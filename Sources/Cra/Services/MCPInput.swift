import AppKit
import CraCEF

/// Performs input through Chromium. JavaScript in an isolated world only locates targets
/// and observes delivered events; it never clicks, focuses, selects or edits the page.
@MainActor
final class MCPInput {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private let browser: CraBrowser
    private let canContinue: () -> Bool
    private let reference: (node: Int, document: String)?
    private let discardUploads: (([String]) -> Void)?
    private let stageUploads: (([String]) async throws -> [String])?
    private let group = "cra-input-" + UUID().uuidString
    private var object: String?
    private var node: String?
    private var loader = ""
    private var expired = false
    private var dispatched = false
    private var dragIntercepted = false
    private var mouseDown = false
    private var heldKey: [String: Any]?
    private(set) var position: CGPoint

    /// Mouse button, click count and modifiers of a page_click.
    private var button = "left"
    private var clickCount = 1
    private var mouseModifiers = 0
    /// Image pixels per CSS pixel of the tab's last screenshot (x/y arguments use them).
    private let screenshotScale: Double

    init(browser: CraBrowser, position: CGPoint, reference: (node: Int, document: String)? = nil, screenshotScale: Double = 1,
         stageUploads: (([String]) async throws -> [String])? = nil, discardUploads: (([String]) -> Void)? = nil, canContinue: @escaping () -> Bool) {
        self.browser = browser
        self.reference = reference
        self.screenshotScale = screenshotScale
        self.stageUploads = stageUploads
        self.discardUploads = discardUploads
        self.position = position
        self.canContinue = canContinue
    }

    /// A ref outside the main document (a same-site iframe): it is acted on by its box.
    private struct OutsideDocument: Error {}

    func run(name: String, arguments: [String: Any]) async -> [String: Any] {
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(MCPInputPlan.durationBudget(text: arguments["text"] as? String ?? ""))); expired = true } catch {}
        }
        defer { deadline.cancel() }
        humanize = arguments["humanize"] as? Bool == true
        button = arguments["button"] as? String ?? "left"
        clickCount = arguments["clickCount"] as? Int ?? 1
        if name == "page_click" { mouseModifiers = (arguments["modifiers"] as? String).flatMap(MCPProtocol.modifierFlags) ?? 0 }
        let result: [String: Any]
        do {
            if let x = (arguments["x"] as? NSNumber)?.doubleValue, let y = (arguments["y"] as? NSNumber)?.doubleValue {
                result = try await atPoint(name, CGPoint(x: x / screenshotScale, y: y / screenshotScale), arguments: arguments)
            } else if name == "page_scroll", arguments["ref"] == nil, arguments["selector"] == nil {
                let metrics = try await call("Page.getLayoutMetrics")
                let viewport = metrics["cssVisualViewport"] as? [String: Any] ?? [:]
                let middle = CGPoint(x: (viewport["clientWidth"] as? Double ?? 800) / 2, y: (viewport["clientHeight"] as? Double ?? 600) / 2)
                result = try await atPoint(name, middle, arguments: arguments)
            } else {
                do {
                    try await prepare(selector: arguments["selector"] as? String, scroll: name != "page_upload")
                    result = try await onTarget(name, arguments: arguments)
                } catch is OutsideDocument {
                    await cleanup()
                    if name == "page_upload" {
                        // A file input has no point to click: find the ref's same-site frame instead.
                        try await prepareInChildFrame()
                        result = try await upload(arguments["paths"] as! [String])
                    } else {
                        result = try await atPoint(name, try await referencePoint(), arguments: arguments)
                    }
                }
            }
        } catch {
            if dispatched, let dialog = (error as? MCPCDP.Failure)?.dialog {
                // The input went in and the page answered with alert(), confirm() or prompt().
                result = content(["status": "dialog_opened", "dialog": dialog,
                                  "next": "The page opened a JavaScript dialog and waits for it. Answer it with page_dialog."])
            } else {
                let suffix = dispatched ? " Input may be partial; inspect the page before retrying." : " No input was sent."
                result = MCPProtocol.content(error.localizedDescription + suffix, failed: true)
            }
        }
        await cleanup()
        return result
    }

    /// Input on an element of the main document (or the focused one), checked before and after.
    private func onTarget(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        if name == "page_upload" { return try await upload(arguments["paths"] as! [String]) }
        if name == "page_drag" { return try await drag(to: arguments["targetSelector"] as! String) }
        let editing = name == "page_fill" || name == "page_type"
        let initial = try await inspect(editing: editing)
        if initial["kind"] as? String == "frame", let src = initial["src"] as? String, !src.isEmpty, !Self.isWeb(src) { throw Self.notWeb }
        if name == "page_hover" || name == "page_scroll" {
            // A hovered element may grow or move (a menu opens): that's the point of hovering.
            try await move(editing: false, settle: false)
            if name == "page_scroll" {
                try await wheel(dx: arguments["dx"] as? Int ?? 0, dy: arguments["dy"] as? Int ?? 0)
                let observed = try await function("function(){return this.counts.wheel || 0}")
                guard ((observed["result"] as? [String: Any])?["value"] as? Int ?? 0) > 0 else { throw Failure(message: "The page did not confirm trusted wheel events.") }
            }
            return try await finish(.none, mouse: false)
        }
        if name == "page_select" { return try await select(value: arguments["value"] as? String, label: arguments["label"] as? String) }
        if editing, initial["kind"] as? String == "typed" {
            return try await setTypedValue(arguments["text"] as! String, type: initial["inputType"] as? String ?? "")
        }
        let untargeted = arguments["ref"] == nil && arguments["selector"] == nil
        let clicked = name == "page_click" || name == "page_fill" || !untargeted && initial["focused"] as? Bool != true
        if name == "page_press", clicked, initial["editable"] as? Bool != true {
            throw Failure(message: "An unfocused non-editable target would be activated by clicking. Use page_press without a target for current focus, or focus it explicitly first.")
        }
        if clicked { try await click(editing: editing) }
        if editing, clicked, try await followReplacement() { retargeted = true }
        if name == "page_click" { return try await finish(.none) }
        if name == "page_press" {
            if !untargeted { _ = try await inspect(focused: true) }
            let modifiers = (arguments["modifiers"] as? String).flatMap(MCPProtocol.modifierFlags) ?? 0
            try await press(arguments["key"] as! String, modifiers: modifiers)
            return try await finish(.none, keyboard: initial["kind"] as? String != "frame", mouse: clicked)
        }
        // page_type and page_fill.
        let kind = initial["kind"] as? String ?? "none"
        var state = try await inspect(editing: true, focused: true)
        if name == "page_type", clicked, kind != "frame" {
            try await key(key: "End", code: "End", virtual: 35, modifiers: 4, commands: ["moveToEndOfDocument"])
            state = try await inspect(editing: true, focused: true)
        }
        let text = arguments["text"] as! String
        // In a one-line field a newline is the Enter key: "query\n" searches, as typing it would.
        let submits = text.contains("\n") && kind == "field" && state["multiline"] as? Bool != true
        if name == "page_fill" {
            try await key(key: "a", code: "KeyA", virtual: 65, modifiers: 4, commands: ["selectAll"])
            state = try await inspect(editing: true, focused: true)
            if kind == "field" {
                let count = (state["value"] as? String ?? "").utf16.count
                if let selectionStart = state["start"] as? Int, selectionStart != 0 || state["end"] as? Int != count {
                    throw Failure(message: "Chromium did not select the entire field. Nothing will be erased.")
                }
            }
            try await press("Backspace")
            state = try await inspect(editing: true, focused: true)
            guard (state["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure(message: "The field did not clear.") }
        }
        if name == "page_type", kind == "field", !(state["start"] is Int), state["value"] as? String != "" {
            throw Failure(message: "This field does not expose its caret. Use page_fill to replace its content.")
        }
        let verify: Verify
        switch kind {
        case "field" where submits: verify = .none
        case "field":
            let old = state["value"] as? String ?? ""
            let start = state["start"] as? Int ?? old.utf16.count
            let end = state["end"] as? Int ?? start
            let original = old as NSString
            verify = .exact(original.substring(to: start) + text + original.substring(from: end))
        case "rich": verify = .contains(text)
        default: verify = .none
        }
        let keys: Bool
        do { keys = try await typeText(text) }
        catch let error where text.contains("\n") && dispatched {
            // Enter submitted the page while text went in: the old document's world is gone.
            if let navigated = await navigated() { return navigated }
            throw error
        }
        return try await finish(verify, keyboard: keys && kind != "frame" && !text.isEmpty, inserted: !keys && kind != "frame", mouse: clicked && !retargeted)
    }

    /// The focused field took the replaced one's place (state.retarget): input goes there now.
    private var retargeted = false
    private func followReplacement() async throws -> Bool {
        let response = try await function("function(){return this.retarget()}")
        guard (response["result"] as? [String: Any])?["value"] as? Bool == true else { return false }
        let element = try await function("function(){return this.node}", value: false)
        node = (element["result"] as? [String: Any])?["objectId"] as? String
        return true
    }

    /// Date, time, month, week, colour and range inputs can't be typed into (a segmented date
    /// field stores the wrong date): the value's format is checked, the field focused natively,
    /// the value set and read back, then input and change fire, as Playwright's fill does.
    private func setTypedValue(_ text: String, type: String) async throws -> [String: Any] {
        guard let value = MCPFieldValue.normalized(type: type, value: text) else {
            let formats = ["date": "2026-11-09", "time": "14:30 or 2:30 PM", "datetime-local": "2026-11-09T14:30",
                           "month": "2026-11", "week": "2026-W45", "color": "#3b82f6", "range": "a number"]
            throw Failure(message: "A \(type) input takes \(formats[type] ?? "its own format"), not \"\(text.prefix(60))\". Nothing was changed.")
        }
        guard let node else { throw Failure(message: "No target node.") }
        dispatched = true
        _ = try await call("DOM.focus", ["objectId": node])
        let response = try await function("""
        function(value) {
          const n = this.node, old = n.value;
          n.value = value;
          if (value !== '' && n.value !== value && n.type !== 'range' && n.type !== 'color') { n.value = old; return {ok: false, value: n.value}; }
          n.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
          n.dispatchEvent(new Event('change', {bubbles: true}));
          return {ok: true, value: n.value};
        }
        """, arguments: [value])
        let state = (response["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
        guard state["ok"] as? Bool == true else { throw Failure(message: "The \(type) input refused \"\(value)\" (min, max or step?). It was put back.") }
        var result: [String: Any] = ["status": "completed", "input": "value", "value": state["value"] ?? value]
        if let held = state["value"] as? String, held != value { result["note"] = "The input holds \(held) (it rounds or snaps values)." }
        return content(result)
    }

    /// A point of the viewport in CSS pixels: anything at all, iframes and canvas included. The
    /// main document's trusted events are counted; a cross-site frame's aren't visible to Cra.
    private func atPoint(_ name: String, _ point: CGPoint, arguments: [String: Any]) async throws -> [String: Any] {
        guard ["page_click", "page_hover", "page_scroll", "page_type", "page_fill", "page_press", "page_upload"].contains(name) else {
            throw Failure(message: "\(name) needs a ref or selector of the main document.")
        }
        let metrics = try await call("Page.getLayoutMetrics")
        let viewport = metrics["cssVisualViewport"] as? [String: Any] ?? [:]
        let width = viewport["clientWidth"] as? Double ?? 0, height = viewport["clientHeight"] as? Double ?? 0
        guard point.x >= 0, point.y >= 0, point.x < width, point.y < height else {
            throw Failure(message: "x/y is outside the viewport (\(Int(width * screenshotScale))×\(Int(height * screenshotScale)) screenshot pixels). Scroll first or take a new screenshot.")
        }
        try await prepare(selector: "html", scroll: false)
        let hit = await describe(point)
        if let frame = hit["frame"] as? String, !Self.isWeb(frame) { throw Self.notWeb }
        if name == "page_upload" {
            // No pointer input: the element at the point (through open shadow roots) is the target.
            if hit["frame"] != nil { throw Failure(message: "That point is in a frame. Pass the ref of its uploader from page_snapshot.") }
            _ = try await function("""
            function(x, y) {
              let el = document.elementFromPoint(x, y);
              while (el && el.shadowRoot) { const inner = el.shadowRoot.elementFromPoint(x, y); if (!inner || inner === el) break; el = inner; }
              if (!el) throw Error('Nothing is at that point.');
              this.node = el;
              this.watch(el);
              return true;
            }
            """, arguments: [point.x, point.y])
            let element = try await function("function(){return this.node}", value: false)
            node = (element["result"] as? [String: Any])?["objectId"] as? String
            return try await upload(arguments["paths"] as! [String])
        }
        if hit["tag"] as? String == "SELECT", name == "page_click" {
            throw Failure(message: "That is a <select>. Use page_select with its ref (page_snapshot) so no native menu opens.")
        }
        for step in path(to: point) {
            try await pace(step.delay)
            dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseMoved", "x": step.point.x, "y": step.point.y, "buttons": 0])
            position = step.point
        }
        switch name {
        case "page_hover": break
        case "page_scroll": try await wheel(dx: arguments["dx"] as? Int ?? 0, dy: arguments["dy"] as? Int ?? 0)
        default:
            try await pressMouse(at: point)
            if name == "page_type" || name == "page_fill" {
                try await pause(0.05)
                if name == "page_fill" {
                    try await key(key: "a", code: "KeyA", virtual: 65, modifiers: 4, commands: ["selectAll"])
                    try await press("Backspace")
                }
                _ = try await typeText(arguments["text"] as! String)
            } else if name == "page_press" {
                try await press(arguments["key"] as! String, modifiers: (arguments["modifiers"] as? String).flatMap(MCPProtocol.modifierFlags) ?? 0)
            }
        }
        let response = try await function("function(){return this.counts}")
        let counts = (response["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
        var result: [String: Any] = ["status": "completed", "input": "chromium", "at": ["x": point.x * screenshotScale, "y": point.y * screenshotScale],
                                     "target": hit, "trustedEvents": counts]
        if name != "page_hover", name != "page_scroll", (counts["mousedown"] ?? 0) == 0 {
            result["note"] = "The point is inside a frame, whose events Cra doesn't count. Check the result with page_screenshot or page_snapshot."
        }
        return content(result)
    }

    /// The middle of a ref's box (a node in a same-site iframe), scrolled into view first.
    private func referencePoint() async throws -> CGPoint {
        guard let reference else { throw Failure(message: "Target is unavailable.") }
        _ = try? await call("DOM.scrollIntoViewIfNeeded", ["backendNodeId": reference.node])
        let quads = try await call("DOM.getContentQuads", ["backendNodeId": reference.node])
        guard let quad = (quads["quads"] as? [[Double]])?.first, quad.count == 8 else {
            throw Failure(message: "Stale ref or the element has no box. Take a new snapshot.")
        }
        return CGPoint(x: (quad[0] + quad[2] + quad[4] + quad[6]) / 4, y: (quad[1] + quad[3] + quad[5] + quad[7]) / 4)
    }

    /// What is at a point, for the result: a short description, never a field's value.
    private func describe(_ point: CGPoint) async -> [String: Any] {
        let response = try? await function("""
        function(x, y) {
          let el = document.elementFromPoint(x, y);
          while (el && el.shadowRoot) { const inner = el.shadowRoot.elementFromPoint(x, y); if (!inner || inner === el) break; el = inner; }
          if (!el) return {};
          const out = {tag: el.tagName};
          for (const name of ['id', 'role', 'aria-label', 'name', 'type', 'title']) { const v = el.getAttribute(name); if (v) out[name] = v.slice(0, 200); }
          if (el instanceof HTMLIFrameElement) { try { out.frame = new URL(el.src, location.href).origin; } catch (e) {} }
          else if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el.isContentEditable)) {
            const text = (el.innerText || '').trim().replace(/\\s+/g, ' ');
            if (text) out.text = text.slice(0, 80);
          }
          return out;
        }
        """, arguments: [point.x, point.y])
        return (response?["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
    }

    private func cdp() -> MCPCDP { MCPCDP(browser, canContinue: canContinue) }

    /// Frames agents may act in: web pages, and the blank frames pages write into themselves.
    private static func isWeb(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("about:") || lower.hasPrefix("data:") || lower.hasPrefix("blob:http")
    }
    private static let notWeb = Failure(message: "That is an extension's or the browser's own frame (a password manager's menu, say). Agents can't use those; the user can.")

    /// Types at the focus: key by key up to MCPInputPlan.keyTypingLimit pieces, else committed
    /// text per line with Enter between. Returns whether keys were used.
    private func typeText(_ text: String) async throws -> Bool {
        if MCPInputPlan.typesKeys(text) {
            for piece in MCPInputPlan.textPieces(text) {
                try await inspectFocusStays()
                if piece == "\n" {
                    try await press("Enter")
                } else {
                    let identity = piece.unicodeScalars.count == 1 ? piece.first.flatMap(MCPInputPlan.textKey) : nil
                    try await key(key: piece, code: identity?.code, virtual: identity?.virtual,
                                  text: piece, modifiers: identity?.modifiers ?? 0, unmodified: identity?.unmodified)
                }
                try await pace(MCPInputPlan.keyGap(Double.random(in: 0...1)))
            }
            return true
        }
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if index > 0 { try await press("Enter") }
            guard !line.isEmpty else { continue }
            try await inspectFocusStays()
            dispatched = true
            _ = try await call("Input.insertText", ["text": line])
        }
        return false
    }

    /// Typing stops when focus leaves the element it started in (a page moved it, or a dialog).
    private var focusAtStart: String?
    private func inspectFocusStays() async throws {
        let world = try await context()
        let response = try await call("Runtime.evaluate", ["expression": Self.focusProbe, "returnByValue": true, "contextId": world])
        let now = (response["result"] as? [String: Any])?["value"] as? String ?? ""
        if let focusAtStart, focusAtStart != now { throw Failure(message: "Focus moved while typing; stopped so nothing lands in another field.") }
        focusAtStart = now
    }
    /// The focused element, through open shadow roots, as a token that changes when focus moves.
    private static let focusProbe = """
    (() => { let a = document.activeElement; while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
      if (!a) return ''; if (!a.__craFocusToken) Object.defineProperty(a, '__craFocusToken', {value: Math.random().toString(36).slice(2)});
      return a.__craFocusToken; })()
    """
    private var isolatedContext: Int?
    private func context() async throws -> Int {
        if let isolatedContext { return isolatedContext }
        let value = try await cdp().context()
        isolatedContext = value
        return value
    }

    private func wheel(dx: Int, dy: Int) async throws {
        // Notches of about 40 px, at most 8: a few-pixel scroll is one whole event, not eight fractions Chromium drops.
        let steps = max(1, min(8, max(abs(dx), abs(dy)) / 40))
        for _ in 0..<steps {
            dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseWheel", "x": position.x, "y": position.y,
                                                           "deltaX": Double(dx) / Double(steps), "deltaY": Double(dy) / Double(steps)])
            try await pace(0.012 + Double.random(in: 0...0.012))
        }
        // Chromium scrolls a wheel step over a few frames; let it land before the result reads it.
        try await pause(0.2)
    }

    private func check() throws {
        guard !Task.isCancelled, !expired, canContinue() else {
            throw Failure(message: "Input cancelled: connection, tab or server is no longer available, or the action timed out.")
        }
    }

    /// Paced, human-like input (humanize=true); otherwise input goes in at once, like Playwright's.
    private var humanize = false

    /// A pause that only paced input takes.
    private func pace(_ seconds: Double) async throws {
        if humanize { try await pause(seconds) } else { try check() }
    }

    /// The pointer's way to `end`: a curved, eased path when humanized, else one move.
    private func path(to end: CGPoint) -> [MCPInputPlan.Move] {
        humanize ? MCPInputPlan.movement(from: position, to: end, variation: Double.random(in: 0...1))
            : Array(MCPInputPlan.movement(from: position, to: end, variation: 0.5).suffix(1))
    }

    private func pause(_ seconds: Double) async throws {
        try check()
        try await Task.sleep(for: .seconds(seconds))
        try check()
    }

    private func call(_ method: String, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
        try check()
        let value = try await rawCall(method, parameters)
        try check()
        return value
    }

    private func rawCall(_ method: String, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
        // A busy renderer can take a moment to acknowledge input; other calls answer within 2 s.
        try await MCPCDP(browser, canContinue: canContinue).call(method, parameters, timeout: method.hasPrefix("Input.") ? 5 : 2, cleanup: true)
    }

    /// Locates the target in the main document, or with `frame` the ref's node in that child frame.
    private func prepare(selector: String?, scroll: Bool = true, frame child: String? = nil) async throws {
        let tree = try await call("Page.getFrameTree")
        guard let frameTree = tree["frameTree"] as? [String: Any], let frame = frameTree["frame"] as? [String: Any],
              let frameID = frame["id"] as? String, let loaderID = frame["loaderId"] as? String else {
            throw Failure(message: "The main document is unavailable.")
        }
        loader = loaderID
        if let reference, reference.document != loaderID { throw Failure(message: "Stale ref: document changed. Take a new snapshot.") }
        // A child frame gets a world of its own name: the main frame's attempt already wrapped the
        // node in "cra-mcp-input", and that wrapper (another realm's) fails every instanceof there.
        let world = try await call("Page.createIsolatedWorld", ["frameId": child ?? frameID, "worldName": child.map { "cra-mcp-input-" + $0 } ?? "cra-mcp-input"])
        guard let context = world["executionContextId"] as? Int else { throw Failure(message: "No isolated inspection world.") }
        isolatedContext = context
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [selector ?? ""]), as: UTF8.self)
        var retained: String?
        if let reference, selector != "html" {
            do {
                let resolved = try await call("DOM.resolveNode", ["backendNodeId": reference.node, "executionContextId": context, "objectGroup": group])
                retained = (resolved["object"] as? [String: Any])?["objectId"] as? String
            } catch let failure as MCPCDP.Failure where failure.dialog == nil {
                // Nodes of another frame can't be resolved in the main document's world.
                if (try? await call("DOM.describeNode", ["backendNodeId": reference.node])) != nil { throw OutsideDocument() }
                throw Failure(message: "Stale ref: node unavailable. Take a new snapshot.")
            }
            guard retained != nil else { throw Failure(message: "Stale ref: node unavailable. Take a new snapshot.") }
        }
        let script = """
        (function(target) {
          const selector = \(literal)[0];
          let active = document.activeElement;
          while (active && active.shadowRoot && active.shadowRoot.activeElement) active = active.shadowRoot.activeElement;
          const matches = target ? [target] : selector ? document.querySelectorAll(selector) : [active || document.body];
          if (matches.length !== 1) throw Error('Selector must match exactly one element; found ' + matches.length);
          const node = matches[0];
          if (!(node instanceof Element) || node.ownerDocument !== document || !node.isConnected) {
            if (node && node.ownerDocument && node.ownerDocument !== document) throw Error('OUTSIDE_DOCUMENT');
            throw Error('Stale or unsupported target; take a new snapshot.');
          }
          const state = {node, counts:{}, downKeys:new Set()};
          const types = ['mousemove','mousedown','mouseup','click','dblclick','auxclick','contextmenu','keydown','keyup','beforeinput','input','wheel','change','dragstart','dragover','drop','pointermove','pointerup'];
          // An event that isn't composed (change) stops at the shadow root it started in, so the
          // target's root is watched too; an event both see counts once.
          const seen = new WeakSet(), roots = new Set();
          const observe = event => {
            if (!event.isTrusted || seen.has(event)) return;
            seen.add(event);
            const target = event.composedPath().includes(state.node);
            if (event.type === 'keyup' && state.downKeys.has(event.key)) {
              state.counts.keyup = (state.counts.keyup || 0) + 1; state.downKeys.delete(event.key); return;
            }
            if (!target) return;
            if (event.type === 'keydown') state.downKeys.add(event.key);
            state.counts[event.type] = (state.counts[event.type] || 0) + 1;
          };
          for (const type of types) window.addEventListener(type, observe, true);
          state.watch = el => {
            const root = el.getRootNode();
            if (!(root instanceof ShadowRoot) || roots.has(root)) return;
            roots.add(root);
            for (const type of types) root.addEventListener(type, observe, true);
          };
          state.watch(node);
          state.stop = () => { for (const type of types) { window.removeEventListener(type, observe, true); for (const root of roots) root.removeEventListener(type, observe, true); } };
          // A page that swaps a field for a new one on focus (Wikipedia's search box): follow focus
          // only to an editable field of the same kind that shares an id, name, placeholder,
          // label or title with the old one. Anything else stays an error; nothing is typed.
          state.retarget = () => {
            const old = state.node;
            if (old.isConnected) return false;
            let a = document.activeElement;
            while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
            const editable = a && (a instanceof HTMLInputElement || a instanceof HTMLTextAreaElement || a.isContentEditable);
            const same = editable && a.tagName === old.tagName && (a.type || '') === (old.type || '')
              && ['id', 'name', 'placeholder', 'aria-label', 'title'].some(k => old.getAttribute(k) && old.getAttribute(k) === a.getAttribute(k));
            if (!same) throw Error('The page replaced the field when it was clicked, and focus is not on a matching one. Take a new snapshot; nothing was typed.');
            state.node = a;
            state.watch(a);
            return true;
          };
          return state;
        })
        """
        let made: [String: Any]
        do {
            if let retained {
                made = try await call("Runtime.callFunctionOn", ["objectId": retained, "functionDeclaration": "function(){return (" + script + ")(this)}", "objectGroup": group])
            } else {
                made = try await call("Runtime.evaluate", ["expression": script + "()", "contextId": context, "objectGroup": group])
            }
        } catch let failure as MCPCDP.Failure where failure.message.contains("OUTSIDE_DOCUMENT") { throw OutsideDocument() }
        object = (made["result"] as? [String: Any])?["objectId"] as? String
        guard object != nil else { throw Failure(message: "Could not retain target identity.") }
        let element = try await function("function(){return this.node}", value: false)
        node = (element["result"] as? [String: Any])?["objectId"] as? String
        guard let node else { throw Failure(message: "No target node.") }
        if scroll {
            _ = try await inspect()
            do { _ = try await call("DOM.scrollIntoViewIfNeeded", ["objectId": node]) }
            catch let failure as MCPCDP.Failure where failure.message.contains("layout object") {
                throw Failure(message: "That element isn't shown on the page (it has no box): something may reveal it, like a menu or a search icon. Take a screenshot or snapshot.")
            }
            // The compositor applies a scroll a frame later; input sent sooner hits what was there.
            _ = try? await call("Runtime.evaluate", ["expression": "new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(1))))",
                                                    "awaitPromise": true, "contextId": context, "timeout": 500])
        }
    }

    /// For a ref in a same-site iframe (page_snapshot lists their elements): the child frame
    /// whose isolated world resolves the node to an element of its own document.
    private func prepareInChildFrame() async throws {
        let tree = try await call("Page.getFrameTree")
        var frames: [String] = []
        var pending = [tree["frameTree"] as? [String: Any] ?? [:]]
        while let next = pending.popLast(), frames.count < 20 {
            for child in next["childFrames"] as? [[String: Any]] ?? [] {
                if let id = (child["frame"] as? [String: Any])?["id"] as? String { frames.append(id) }
                pending.append(child)
            }
        }
        for frame in frames {
            do { try await prepare(selector: nil, scroll: false, frame: frame); return }
            catch is OutsideDocument { continue }
            catch let failure as MCPCDP.Failure where failure.dialog == nil { continue }  // another site's frame
        }
        throw Failure(message: "That ref is in another site's frame, which page_upload can't reach.")
    }

    private func function(_ declaration: String, arguments: [Any] = [], value: Bool = true) async throws -> [String: Any] {
        guard let object else { throw Failure(message: "Target is unavailable.") }
        return try await call("Runtime.callFunctionOn", ["objectId": object, "functionDeclaration": declaration,
                            "arguments": arguments.map { ["value": $0] }, "returnByValue": value, "objectGroup": group])
    }

    private func inspect(editing: Bool = false, focused: Bool = false, hit: Bool = false) async throws -> [String: Any] {
        let response = try await function("""
        function(editing, focused, hit) {
          const n = this.node;
          let active = document.activeElement;
          while (active && active.shadowRoot && active.shadowRoot.activeElement) active = active.shadowRoot.activeElement;
          if (!n.isConnected || n.ownerDocument !== document) throw Error('Target was detached or replaced. Resolve it again.');
          if (n.matches(':disabled') || n.closest('[inert],button:disabled,[aria-disabled="true"]')) throw Error('Target is disabled or inert.');
          for (let a = n; a; a = a.parentElement || (a.getRootNode() instanceof ShadowRoot ? a.getRootNode().host : null)) {
            const style = getComputedStyle(a);
            if (style.visibility !== 'visible' || Number(style.opacity) === 0) throw Error('Target is not visible.');
          }
          const plain = n.isContentEditable && Array.from(n.children).every(c => c.tagName === 'BR');
          const field = plain || n instanceof HTMLTextAreaElement || n instanceof HTMLInputElement && ['text','search','email','url','tel','password','number'].includes(n.type);
          const typed = n instanceof HTMLInputElement && ['date','time','datetime-local','month','week','color','range'].includes(n.type);
          const kind = field ? 'field' : typed ? 'typed' : n.isContentEditable ? 'rich' : (n instanceof HTMLIFrameElement || n instanceof HTMLFrameElement) ? 'frame' : 'none';
          if (editing && kind === 'none') throw Error('Nothing editable here. Click a field or editor first, or pass its ref or selector.');
          if (editing && n.readOnly) throw Error('Target is read-only.');
          if (focused && active !== n) throw Error('Focus changed; refusing to type into another element.');
          const rects = Array.from(n.getClientRects()).map(r => ({left:Math.max(0,r.left),top:Math.max(0,r.top),right:Math.min(innerWidth,r.right),bottom:Math.min(innerHeight,r.bottom)}));
          const r = rects.filter(r => r.right > r.left && r.bottom > r.top).sort((a,b) => (b.right-b.left)*(b.bottom-b.top)-(a.right-a.left)*(a.bottom-a.top))[0];
          if (hit && !r) throw Error('Target has no visible hit area.');
          const x = r ? (r.left+r.right)/2 : 0, y = r ? (r.top+r.bottom)/2 : 0;
          let top = r && document.elementFromPoint(x,y);
          while (top && top.shadowRoot) { const inner = top.shadowRoot.elementFromPoint(x,y); if (!inner || inner === top) break; top = inner; }
          const inside = (outer, inner) => { for (let p = inner; p; p = p.parentNode || p.host) if (p === outer) return true; return false; };
          if (hit && !inside(n, top)) throw Error('Target is covered by another element.');
          let start = n.selectionStart, end = n.selectionEnd;
          if (plain) {
            const selection = getSelection();
            if (selection.rangeCount && n.contains(selection.anchorNode) && n.contains(selection.focusNode)) {
              const a = document.createRange(), b = document.createRange();
              a.selectNodeContents(n); a.setEnd(selection.anchorNode, selection.anchorOffset);
              b.selectNodeContents(n); b.setEnd(selection.focusNode, selection.focusOffset);
              start = Math.min(a.toString().length, b.toString().length); end = Math.max(a.toString().length, b.toString().length);
            } else if (!n.textContent) { start = 0; end = 0; }
          }
          const value = plain ? n.textContent.replace(/\\u00a0/g,' ') : field ? n.value || '' : kind === 'rich' ? n.innerText : '';
          return {x,y,kind,editable:kind !== 'none',value,start,end,multiline:n instanceof HTMLTextAreaElement || kind === 'rich',focused:active === n,src:kind === 'frame' ? n.src : '',inputType:n instanceof HTMLInputElement ? n.type : ''};
        }
        """, arguments: [editing, focused, hit])
        guard let value = (response["result"] as? [String: Any])?["value"] as? [String: Any] else {
            throw Failure(message: "Target inspection returned no value.")
        }
        return value
    }

    private func move(editing: Bool, settle: Bool = true) async throws {
        let target = try await inspect(editing: editing, hit: true)
        let end = CGPoint(x: target["x"] as? Double ?? 0, y: target["y"] as? Double ?? 0)
        for move in path(to: end) {
            try await pace(move.delay)
            dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseMoved", "x": move.point.x, "y": move.point.y, "buttons": 0])
            position = move.point
        }
        guard settle else { return }
        let current = try await inspect(editing: editing, hit: true)
        guard abs((current["x"] as? Double ?? -100) - end.x) < 2,
              abs((current["y"] as? Double ?? -100) - end.y) < 2 else {
            throw Failure(message: "Target moved during pointer movement. No click was sent.")
        }
    }

    private func click(editing: Bool) async throws {
        try await move(editing: editing)
        try await pressMouse(at: position) { [self] in
            // The press can run page code. Never release over a newly substituted target. A field
            // the page replaced on focus is released where it was (followReplacement() then checks).
            if editing, let gone = try? await function("function(){return !this.node.isConnected}"),
               (gone["result"] as? [String: Any])?["value"] as? Bool == true { return }
            let released = try await inspect(editing: editing, hit: true)
            guard abs((released["x"] as? Double ?? -100) - position.x) < 2,
                  abs((released["y"] as? Double ?? -100) - position.y) < 2 else {
                throw Failure(message: "Target moved while the mouse button was held.")
            }
        }
    }

    /// Press and release `button` clickCount times at a point; `between` runs while it is held.
    private func pressMouse(at point: CGPoint, between: (() async throws -> Void)? = nil) async throws {
        let buttons = ["left": 1, "right": 2, "middle": 4][button] ?? 1
        if button == "right" { browser.suppressesContextMenu = true }
        for count in 1...clickCount {
            mouseDown = true
            dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mousePressed", "x": point.x, "y": point.y, "modifiers": mouseModifiers,
                                                           "button": button, "buttons": buttons, "clickCount": count])
            try await pace(count < clickCount ? 0.03 : MCPInputPlan.clickHold(Double.random(in: 0...1)))
            if count == clickCount { try await between?() }
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseReleased", "x": point.x, "y": point.y, "modifiers": mouseModifiers,
                                                           "button": button, "buttons": 0, "clickCount": count])
            mouseDown = false
            if count < clickCount { try await pause(0.04) }
        }
    }

    private func select(value: String?, label: String?) async throws -> [String: Any] {
        let isNative = try await function("function(){return this.node instanceof HTMLSelectElement}")
        if (isNative["result"] as? [String: Any])?["value"] as? Bool != true {
            return try await customSelect(value ?? label ?? "")
        }
        // Type-ahead with the shortest prefix of the option's label that no other enabled option
        // starts with; a label that is the start of another needs all of it.
        let response = try await function("""
        function(value, label) {
          const n = this.node;
          if (!(n instanceof HTMLSelectElement) || n.multiple) throw Error('Only single HTML select controls are supported. For a custom dropdown, click it open and click the option.');
          const norm = s => s.trim().replace(/\\s+/g, ' ').toLocaleLowerCase();
          const options = Array.from(n.options).filter(o => !o.disabled && !(o.parentElement instanceof HTMLOptGroupElement && o.parentElement.disabled));
          const matches = options.filter(o => value !== null ? o.value === value : norm(o.label) === norm(label));
          if (matches.length !== 1) throw Error((value !== null ? 'value' : 'label') + ' must match one enabled option; options: ' + options.slice(0, 30).map(o => JSON.stringify(o.label.trim()) + '=' + JSON.stringify(o.value)).join(', '));
          const option = matches[0], text = option.label.trim().replace(/\\s+/g, ' ');
          if (n.value === option.value) return {done:true, value:option.value};
          let prefix = null;
          for (let i = 1; i <= text.length && !prefix; i++) {
            const p = norm(text.slice(0, i));
            if (options.filter(o => norm(o.label).startsWith(p)).length === 1) prefix = text.slice(0, i);
          }
          if (!prefix) {
            const first = options.find(o => norm(o.label).startsWith(norm(text)));
            if (first !== option) throw Error('Another option starts with the same label; it cannot be reached by typing. Use the keyboard (page_press ArrowDown) instead.');
            prefix = text;
          }
          return {done:false, prefix, value:option.value};
        }
        """, arguments: [value ?? NSNull(), label ?? NSNull()])
        guard let state = (response["result"] as? [String: Any])?["value"] as? [String: Any], let target = state["value"] as? String, let node else {
            throw Failure(message: "Select options unavailable.")
        }
        if state["done"] as? Bool == true { return content(["status": "completed", "input": "chromium", "note": "Already selected."]) }
        guard let prefix = state["prefix"] as? String else { throw Failure(message: "Select label unavailable.") }
        // macOS' native popup consumes arrow keys differently. Native focus plus the select's
        // built-in type-ahead avoids the popup and still emits trusted input/change events.
        dispatched = true
        _ = try await call("DOM.focus", ["objectId": node])
        _ = try await inspect(focused: true)
        try await press("Escape")
        // Blink keeps select type-ahead for one second, including between tool calls.
        try await pause(1.1)
        for piece in MCPInputPlan.textPieces(prefix) {
            _ = try await inspect(focused: true)
            let identity = piece.unicodeScalars.count == 1 ? piece.first.flatMap(MCPInputPlan.textKey) : nil
            try await key(key: piece, code: identity?.code, virtual: identity?.virtual, text: piece,
                          modifiers: identity?.modifiers ?? 0, unmodified: identity?.unmodified)
            try await pace(MCPInputPlan.keyGap(Double.random(in: 0...1)))
        }
        let final = try await function("function(){return this.node.value}")
        guard (final["result"] as? [String: Any])?["value"] as? String == target else { throw Failure(message: "Select did not reach the requested option.") }
        let observed = try await function("function(){return this.counts}")
        let counts = (observed["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
        if (counts["input"] ?? 0) == 0 || (counts["change"] ?? 0) == 0 {
            throw Failure(message: "Select did not confirm trusted input/change events.")
        }
        var result = try await finish(.none, keyboard: true, mouse: false)
        if (counts["change"] ?? 0) > 1 {
            // Typing "Deu" passes "Denmark" first: the page saw a change event for each.
            result = content(["status": "completed", "input": "chromium", "trustedEvents": counts,
                              "note": "Type-ahead passed through \((counts["change"] ?? 1) - 1) other option(s) on the way, each with a change event."])
        }
        return result
    }

    /// A dropdown that isn't a <select>: a typeahead is typed into, anything else clicked open;
    /// then the option the control owns (aria-controls, aria-owns, aria-activedescendant, or the
    /// one listbox inside its component, else the one listbox on screen) whose text, label or
    /// value matches is clicked. Several or no matches are refused with what's showing.
    private func customSelect(_ wanted: String) async throws -> [String: Any] {
        let kind = try await function("""
        function() {
          const n = this.node;
          const typeable = n instanceof HTMLInputElement && ['text','search','email','url','tel',''].includes(n.type) || n.isContentEditable;
          return typeable ? 'type' : 'click';
        }
        """)
        let typeable = (kind["result"] as? [String: Any])?["value"] as? String == "type"
        try await click(editing: typeable)
        if typeable {
            try await key(key: "a", code: "KeyA", virtual: 65, modifiers: 4, commands: ["selectAll"])
            _ = try await typeText(wanted)
        }
        let finder = """
        function(wanted) {
          const n = this.node, norm = s => (s || '').trim().replace(/\\s+/g, ' ').toLocaleLowerCase();
          const shown = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
          const ids = [n.getAttribute('aria-controls'), n.getAttribute('aria-owns')].join(' ').split(/\\s+/).filter(Boolean);
          let popups = ids.map(id => document.getElementById(id)).filter(Boolean);
          const active = n.getAttribute('aria-activedescendant') && document.getElementById(n.getAttribute('aria-activedescendant'));
          if (active) popups.push(active.closest('[role=listbox],[role=menu],[role=tree],[role=grid]') || active.parentElement);
          if (!popups.length) {
            for (let a = n.parentElement, i = 0; a && i < 4 && !popups.length; a = a.parentElement, i++) {
              const lists = Array.from(a.querySelectorAll('[role=listbox],[role=menu]')).filter(shown);
              if (lists.length === 1) popups = lists;
            }
          }
          if (!popups.length) { const lists = Array.from(document.querySelectorAll('[role=listbox],[role=menu]')).filter(shown); if (lists.length === 1) popups = lists; }
          const options = popups.flatMap(p => Array.from(p.querySelectorAll('[role=option],[role=menuitem],[role=menuitemradio],[role=treeitem],li'))).filter(shown);
          if (!options.length) return {found: 0, showing: []};
          const label = o => [o.innerText, o.getAttribute('aria-label'), o.getAttribute('data-value'), o.getAttribute('value')];
          const w = norm(wanted);
          let hits = options.filter(o => label(o).some(t => norm(t) === w));
          if (!hits.length) hits = options.filter(o => norm(o.innerText).includes(w));
          const showing = options.slice(0, 20).map(o => (o.innerText || o.getAttribute('aria-label') || '').trim().slice(0, 60));
          if (hits.length !== 1) return {found: hits.length, showing};
          hits[0].scrollIntoView({block: 'nearest'});
          const r = hits[0].getBoundingClientRect();
          return {found: 1, x: r.left + r.width / 2, y: r.top + r.height / 2, text: (hits[0].innerText || '').trim().slice(0, 80)};
        }
        """
        var state: [String: Any] = [:]
        for _ in 0..<27 {
            try await pause(0.15)
            let response = try await function(finder, arguments: [wanted])
            state = (response["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
            if state["found"] as? Int == 1 { break }
        }
        guard state["found"] as? Int == 1, let x = state["x"] as? Double, let y = state["y"] as? Double else {
            let showing = (state["showing"] as? [String] ?? []).joined(separator: " | ")
            throw Failure(message: (state["found"] as? Int ?? 0) > 1
                ? "Several options match \"\(wanted)\": \(showing). Use a fuller label, or page_click the option."
                : showing.isEmpty ? "No options appeared for this control. Open it with page_click and click the option." : "No option matches \"\(wanted)\". Showing: \(showing).")
        }
        let point = CGPoint(x: x, y: y)
        for step in path(to: point) {
            try await pace(step.delay)
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseMoved", "x": step.point.x, "y": step.point.y, "buttons": 0])
            position = step.point
        }
        button = "left"; clickCount = 1
        try await pressMouse(at: point)
        return content(["status": "completed", "input": "chromium", "picked": state["text"] ?? wanted])
    }

    private func press(_ name: String, modifiers: Int = 0) async throws {
        if let definition = MCPInputPlan.keys[name] {
            let commands = MCPInputPlan.editingCommands(key: name, modifiers: modifiers)
            let text: String? = name == "Enter" && modifiers & 7 == 0 ? "\r" : name == "Space" && modifiers & 7 == 0 ? " " : nil
            try await key(key: name == "Space" ? " " : name, code: definition.code, virtual: definition.virtual, text: text, modifiers: modifiers, commands: commands)
            return
        }
        guard let character = name.first, name.count == 1, let identity = MCPInputPlan.textKey(character) else { throw Failure(message: "Unsupported key.") }
        // With Meta or Control a character is a shortcut (⌘K), so no text goes in with it.
        let shortcut = modifiers & 6 != 0
        let all = modifiers | identity.modifiers
        try await key(key: shortcut ? identity.unmodified : name, code: identity.code, virtual: identity.virtual,
                      text: shortcut ? nil : name, modifiers: all,
                      commands: MCPInputPlan.editingCommands(key: identity.unmodified, modifiers: all), unmodified: identity.unmodified)
    }

    private func key(key: String, code: String? = nil, virtual: Int? = nil, text: String? = nil,
                     modifiers: Int = 0, commands: [String] = [], unmodified: String? = nil) async throws {
        var down: [String: Any] = ["type": text == nil ? "rawKeyDown" : "keyDown", "key": key, "modifiers": modifiers]
        if let code { down["code"] = code }
        if let virtual { down["windowsVirtualKeyCode"] = virtual }
        if let text { down["text"] = text; down["unmodifiedText"] = unmodified ?? text }
        if !commands.isEmpty { down["commands"] = commands }
        var up = down
        up["type"] = "keyUp"; up["modifiers"] = 0
        up.removeValue(forKey: "text"); up.removeValue(forKey: "unmodifiedText"); up.removeValue(forKey: "commands")
        try check()
        heldKey = up
        dispatched = true
        _ = try await call("Input.dispatchKeyEvent", down)
        try await pace(MCPInputPlan.keyHold(Double.random(in: 0...1)))
        _ = try await call("Input.dispatchKeyEvent", up)
        heldKey = nil
    }

    private enum Verify { case none, exact(String), contains(String) }

    private func finish(_ verify: Verify, keyboard: Bool = false, inserted: Bool = false, mouse: Bool = true) async throws -> [String: Any] {
        do {
            switch verify {
            case .none: break
            case .exact(let expected):
                let state = try await inspect(editing: true, focused: true)
                guard state["value"] as? String == expected else {
                    throw Failure(message: "The field value differs from the requested edit (the page may have transformed or rejected input).")
                }
            case .contains(let text):
                let state = try await inspect(editing: true)
                let squash = { (s: String) in s.replacingOccurrences(of: "\u{a0}", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                guard squash(state["value"] as? String ?? "").contains(squash(text)) else {
                    throw Failure(message: "The editor doesn't show the typed text (the page may have transformed or rejected input).")
                }
            }
            // Instant input can be read back before the page has handled all of it: wait up to
            // half a second for the events to arrive (a dialog opening meanwhile ends the wait).
            var counts: [String: Int] = [:]
            var confirmed = false
            for attempt in 0..<11 {
                if attempt > 0 { try await pause(0.05) }
                let response = try await function("function(){return this.counts}")
                counts = (response["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
                let clicked = button == "right" ? (counts["contextmenu"] ?? 0) > 0 : button == "middle" ? true : (counts["click"] ?? 0) > 0
                confirmed = (!mouse || (counts["mousedown"] ?? 0) > 0 && (counts["mouseup"] ?? 0) > 0 && clicked)
                    && (!mouse || clickCount < 2 || (counts["dblclick"] ?? 0) > 0)
                    && (!keyboard || (counts["keydown"] ?? 0) > 0 && counts["keydown"] == counts["keyup"])
                    && (!inserted || (counts["input"] ?? 0) > 0)
                if confirmed { break }
            }
            guard confirmed else { throw Failure(message: "The page did not confirm the expected trusted input events.") }
            var result: [String: Any] = ["status": "completed", "input": "chromium", "trustedEvents": counts]
            if retargeted { result["retargeted"] = "The page replaced the field when it was clicked; the text went into its replacement." }
            return content(result)
        } catch {
            // A committed navigation destroys the observer. Report that explicitly, never replay.
            if dispatched, !mouseDown, heldKey == nil, let navigated = await navigated() { return navigated }
            throw error
        }
    }

    /// The navigation_observed result when the main document changed since prepare(), else nil.
    private func navigated() async -> [String: Any]? {
        guard let tree = try? await rawCall("Page.getFrameTree"), let frameTree = tree["frameTree"] as? [String: Any],
              let frame = frameTree["frame"] as? [String: Any], let current = frame["loaderId"] as? String, current != loader else { return nil }
        return content(["status": "navigation_observed", "input": "chromium",
                        "eventVerification": "The document navigated (Enter or a click submitted it); the old event observer is gone. Read the new page to check."])
    }

    /// The file input for the target an agent passed: itself, its label's, the one inside it, or
    /// the one in its shadow-root component (MCPUploadTarget decides). Becomes this.node.
    private func uploadTarget() async throws -> MCPUploadTarget.Choice {
        let response = try await function("""
        function() {
          const n = this.node;
          const isFile = el => el instanceof HTMLInputElement && el.type === 'file';
          const isField = el => el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement || el.isContentEditable;
          // File inputs under an element or shadow root, through open shadow roots.
          const inputs = scope => {
            const found = [];
            const walk = root => { for (const el of root.querySelectorAll('*')) { if (isFile(el)) found.push(el); if (el.shadowRoot) walk(el.shadowRoot); } };
            walk(scope);
            if (scope instanceof Element && scope.shadowRoot) walk(scope.shadowRoot);
            return found;
          };
          const label = n.closest('label'), control = label ? label.control : null;
          // The shadow components around n, nearest first: the root it is in (then its host's),
          // or a host it is slotted into. The document itself is not one.
          const scopes = [];
          for (let a = n; scopes.length < 12;) {
            const up = a.parentNode;
            if (!up || up.nodeType === Node.DOCUMENT_NODE) break;
            if (up instanceof ShadowRoot) { scopes.push(up); a = up.host; continue; }
            if (up.shadowRoot) scopes.push(up);
            a = up;
          }
          this.uploadCandidates = {label: control, inside: inputs(n), components: scopes.map(inputs)};
          return {isFileInput: isFile(n), labelsFileInput: isFile(control), isOtherField: isField(n) && !isFile(n) || !!control && !isFile(control),
                  inside: this.uploadCandidates.inside.length, components: this.uploadCandidates.components.map(c => c.length)};
        }
        """)
        let seen = (response["result"] as? [String: Any])?["value"] as? [String: Any] ?? [:]
        let choice = MCPUploadTarget.choose(.init(
            isFileInput: seen["isFileInput"] as? Bool == true, labelsFileInput: seen["labelsFileInput"] as? Bool == true,
            isOtherField: seen["isOtherField"] as? Bool == true, inside: seen["inside"] as? Int ?? 0, components: seen["components"] as? [Int] ?? []))
        let level: Int
        switch choice {
        case .refused(let message): throw Failure(message: message)
        case .itself: return choice
        case .component(let index): level = index
        case .label, .inside: level = 0
        }
        _ = try await function("""
        function(via, level) {
          const c = this.uploadCandidates;
          this.node = via === 'label' ? c.label : via === 'inside' ? c.inside[0] : c.components[level][0];
          this.watch(this.node);
          delete this.uploadCandidates;
          return true;
        }
        """, arguments: [choice.via ?? "", level])
        let element = try await function("function(){return this.node}", value: false)
        node = (element["result"] as? [String: Any])?["objectId"] as? String
        return choice
    }

    private func upload(_ paths: [String]) async throws -> [String: Any] {
        let choice = try await uploadTarget()
        guard let node else { throw Failure(message: "Upload target is unavailable.") }
        _ = try await function("""
        function(count) {
          const n=this.node;
          if (!n.isConnected || n.ownerDocument !== document || !(n instanceof HTMLInputElement) || n.type !== 'file' || n.disabled || n.closest('[inert]')) throw Error('Upload requires a live, enabled file input.');
          if (count > 1 && !n.multiple) throw Error('This file input does not accept multiple files.');
          return true;
        }
        """, arguments: [paths.count])
        try check()
        guard let stageUploads else { throw Failure(message: "Upload staging is unavailable.") }
        let files = try await stageUploads(paths)
        do {
            try check()
            _ = try await function("function(){if(!this.node.isConnected || this.node.ownerDocument!==document || this.node.disabled || this.node.type!=='file')throw Error('Upload target changed while staging');return true}")
            try check()
        } catch { discardUploads?(files); throw error }
        dispatched = true
        // From this point a timeout/cancellation can hide a successful selection. Preserve
        // its files conservatively; deleting them could break a File already held by the page.
        _ = try await rawCall("DOM.setFileInputFiles", ["objectId": node, "files": files])
        try check()
        let observed = try await function("""
        function() { if (!this.node.isConnected) throw Error('Upload target was replaced. Inspect the page before retrying.');
          return {files:Array.from(this.node.files, f=>({name:f.name,size:f.size})),counts:this.counts}; }
        """)
        guard let value = (observed["result"] as? [String: Any])?["value"] as? [String: Any],
              let files = value["files"] as? [[String: Any]], files.count == paths.count,
              let counts = value["counts"] as? [String: Int], (counts["change"] ?? 0) > 0 else {
            throw Failure(message: "Chromium did not confirm the file selection and trusted change event.")
        }
        var result: [String: Any] = ["status": "completed", "input": "chromium", "files": files, "trustedEvents": counts]
        if let via = choice.via {
            result["fileInput"] = ["label": "The file input this label is for.", "inside": "The file input inside this element.",
                                   "component": "The file input of this element's shadow-root component."][via]
        }
        return content(result)
    }

    private func drag(to selector: String) async throws -> [String: Any] {
        let target = MCPInput(browser: browser, position: position, canContinue: canContinue)
        do {
            try await target.prepare(selector: selector, scroll: false)
            try await move(editing: false)
            let destination = try await target.inspect(hit: true)
            let end = CGPoint(x: destination["x"] as? Double ?? 0, y: destination["y"] as? Double ?? 0)
            guard hypot(position.x - end.x, position.y - end.y) > 8 else { throw Failure(message: "Drag targets must have distinct hit areas.") }
            browser.interceptedDragData = nil
            dragIntercepted = true
            _ = try await call("Input.setInterceptDrags", ["enabled": true])
            mouseDown = true; dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mousePressed", "x": position.x, "y": position.y, "button": "left", "buttons": 1, "clickCount": 1])
            try await pace(MCPInputPlan.clickHold(Double.random(in: 0...1)))
            var dragData: [String: Any]?
            for step in MCPInputPlan.movement(from: position, to: end, variation: Double.random(in: 0...1)) {
                try await pace(step.delay)
                let current = try await target.inspect(hit: true)
                guard abs((current["x"] as? Double ?? -100) - end.x) < 2, abs((current["y"] as? Double ?? -100) - end.y) < 2 else {
                    throw Failure(message: "Drop target moved. Drag aborted; cleanup sends Escape and releases the button.")
                }
                if dragData == nil, let text = browser.interceptedDragData, let bytes = text.data(using: .utf8) {
                    dragData = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
                    guard let dragData, dragData["oversized"] as? Bool != true else { throw Failure(message: "Native drag payload exceeds 64 KiB. Drag cancelled.") }
                    guard (dragData["files"] as? [String] ?? []).isEmpty else { throw Failure(message: "Dragging local files is unsupported; use page_upload.") }
                    _ = try await call("Input.dispatchDragEvent", ["type": "dragEnter", "x": step.point.x, "y": step.point.y, "data": dragData])
                }
                if let dragData {
                    _ = try await call("Input.dispatchDragEvent", ["type": "dragOver", "x": step.point.x, "y": step.point.y, "data": dragData])
                } else {
                    _ = try await call("Input.dispatchMouseEvent", ["type": "mouseMoved", "x": step.point.x, "y": step.point.y, "button": "left", "buttons": 1])
                }
                position = step.point
            }
            // A short drag can cross the threshold on its final move; allow the event to arrive.
            try await pause(0.08)
            if dragData == nil, let text = browser.interceptedDragData, let bytes = text.data(using: .utf8) {
                dragData = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
                guard let dragData, dragData["oversized"] as? Bool != true else { throw Failure(message: "Native drag payload exceeds 64 KiB. Drag cancelled.") }
                    guard (dragData["files"] as? [String] ?? []).isEmpty else { throw Failure(message: "Dragging local files is unsupported; use page_upload.") }
                _ = try await call("Input.dispatchDragEvent", ["type": "dragEnter", "x": end.x, "y": end.y, "data": dragData])
                _ = try await call("Input.dispatchDragEvent", ["type": "dragOver", "x": end.x, "y": end.y, "data": dragData])
            }
            _ = try await target.inspect(hit: true)
            if let dragData { _ = try await call("Input.dispatchDragEvent", ["type": "drop", "x": end.x, "y": end.y, "data": dragData]) }
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseReleased", "x": end.x, "y": end.y, "button": "left", "buttons": 0, "clickCount": 1])
            mouseDown = false
            let response = try await target.function("function(){return this.counts}")
            let counts = (response["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
            let source = try await function("function(){return this.counts}")
            let sourceCounts = (source["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
            guard dragData != nil ? (counts["drop"] ?? 0) > 0 : (counts["mouseup"] ?? 0) + (sourceCounts["mouseup"] ?? 0) > 0 else {
                throw Failure(message: "The page did not confirm the native drop/release. Inspect its result before retrying.")
            }
            await target.cleanup()
            return content(["status": "completed", "input": "chromium", "humanized": true, "kind": dragData == nil ? "pointer" : "html", "trustedEvents": counts])
        } catch { await target.cleanup(); throw error }
    }

    private func cleanup() async {
        if browser.suppressesContextMenu {
            // Chromium asks for the menu just after the press; keep refusing it a little longer.
            let browser = browser
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(600)); browser.suppressesContextMenu = false }
        }
        if dragIntercepted {
            _ = try? await rawCall("Input.cancelDragging")
            _ = try? await rawCall("Input.setInterceptDrags", ["enabled": false])
            browser.interceptedDragData = nil
        }
        if mouseDown {
            // Tell drag libraries to cancel before releasing. Pointer capture may still deliver
            // release/click to its owner; cleanup is not a rollback of already delivered input.
            _ = try? await rawCall("Input.dispatchKeyEvent", ["type": "rawKeyDown", "key": "Escape", "code": "Escape", "windowsVirtualKeyCode": 27])
            _ = try? await rawCall("Input.dispatchKeyEvent", ["type": "keyUp", "key": "Escape", "code": "Escape", "windowsVirtualKeyCode": 27])
            _ = try? await rawCall("Input.dispatchMouseEvent", ["type": "mouseReleased", "x": -1, "y": -1,
                                                               "button": "left", "buttons": 0, "clickCount": 1])
        }
        if let heldKey { _ = try? await rawCall("Input.dispatchKeyEvent", heldKey) }
        if let object {
            _ = try? await rawCall("Runtime.callFunctionOn", ["objectId": object, "functionDeclaration": "function(){this.stop()}"])
        }
        _ = try? await rawCall("Runtime.releaseObjectGroup", ["objectGroup": group])
    }

    private func content(_ value: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return MCPProtocol.content(String(decoding: data, as: UTF8.self))
    }
}
