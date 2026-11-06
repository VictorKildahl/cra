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

    init(browser: CraBrowser, position: CGPoint, reference: (node: Int, document: String)? = nil, stageUploads: (([String]) async throws -> [String])? = nil, discardUploads: (([String]) -> Void)? = nil, canContinue: @escaping () -> Bool) {
        self.browser = browser
        self.reference = reference
        self.stageUploads = stageUploads
        self.discardUploads = discardUploads
        self.position = position
        self.canContinue = canContinue
    }

    func run(name: String, arguments: [String: Any]) async -> [String: Any] {
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(MCPInputPlan.durationBudget(text: arguments["text"] as? String ?? ""))); expired = true } catch {}
        }
        defer { deadline.cancel() }
        let result: [String: Any]
        do {
            try await prepare(selector: arguments["selector"] as? String, scroll: name != "page_upload")
            if name == "page_upload" {
                result = try await upload(arguments["paths"] as! [String])
                await cleanup(); return result
            }
            if name == "page_drag" {
                result = try await drag(to: arguments["targetSelector"] as! String)
                await cleanup(); return result
            }
            let editing = name == "page_fill" || name == "page_type"
            let initial = try await inspect(editing: editing)
            if editing, let text = arguments["text"] as? String, text.contains("\n"), initial["multiline"] as? Bool != true {
                throw Failure(message: "Newlines require a textarea. Use page_press Enter to submit a form explicitly.")
            }
            if name == "page_hover" || name == "page_scroll" {
                try await move(editing: false)
                if name == "page_scroll" {
                    let dy = arguments["dy"] as! Int
                    for _ in 0..<8 {
                        _ = try await inspect(hit: true)
                        dispatched = true
                        _ = try await call("Input.dispatchMouseEvent", ["type": "mouseWheel", "x": position.x, "y": position.y, "deltaX": 0, "deltaY": Double(dy) / 8])
                        try await pause(0.025 + Double.random(in: 0...0.025))
                    }
                    let observed = try await function("function(){return this.counts.wheel || 0}")
                    guard ((observed["result"] as? [String: Any])?["value"] as? Int ?? 0) > 0 else { throw Failure(message: "The page did not confirm trusted wheel events.") }
                }
                result = try await finish(verifyValue: nil, mouse: false)
                await cleanup()
                return result
            }
            if name == "page_select" {
                result = try await select(arguments["value"] as! String)
                await cleanup()
                return result
            }
            let clicked = name == "page_click" || name == "page_fill" || initial["focused"] as? Bool != true
            if name == "page_press", initial["focused"] as? Bool != true, initial["editable"] as? Bool != true {
                throw Failure(message: "An unfocused non-editable target would be activated by clicking. Use page_press without a target for current focus, or focus it explicitly first.")
            }
            if clicked { try await click(editing: editing) }
            if name == "page_type", clicked {
                _ = try await inspect(editing: true, focused: true)
                try await key(key: "End", code: "End", virtual: 35, modifiers: 4, commands: ["moveToEndOfDocument"])
            }
            if name == "page_click" {
                result = try await finish(verifyValue: nil)
            } else if name == "page_press" {
                _ = try await inspect(focused: true)
                try await press(arguments["key"] as! String, modifiers: (arguments["modifiers"] as? String).flatMap(MCPProtocol.modifierFlags) ?? 0)
                result = try await finish(verifyValue: nil, keyboard: true, mouse: clicked)
            } else {
                var state = try await inspect(editing: true, focused: true)
                let text = arguments["text"] as! String
                if name == "page_fill" {
                    try await key(key: "a", code: "KeyA", virtual: 65, modifiers: 4, commands: ["selectAll"])
                    state = try await inspect(editing: true, focused: true)
                    let count = (state["value"] as? String ?? "").utf16.count
                    if let selectionStart = state["start"] as? Int,
                       selectionStart != 0 || state["end"] as? Int != count {
                        throw Failure(message: "Chromium did not select the entire field. Nothing will be erased.")
                    }
                    try await press("Backspace")
                    state = try await inspect(editing: true, focused: true)
                    guard state["value"] as? String == "" else { throw Failure(message: "The field did not clear.") }
                }
                if name == "page_type", !(state["start"] is Int), state["value"] as? String != "" {
                    throw Failure(message: "This field does not expose its caret. Use page_fill to replace its content.")
                }
                let old = state["value"] as? String ?? ""
                let start = state["start"] as? Int ?? 0
                let end = state["end"] as? Int ?? start
                let original = old as NSString
                let expected = original.substring(to: start) + text + original.substring(from: end)
                for piece in MCPInputPlan.textPieces(text) {
                    _ = try await inspect(editing: true, focused: true)
                    if piece == "\n" {
                        try await press("Enter")
                    } else {
                        let identity = piece.unicodeScalars.count == 1 ? piece.first.flatMap(MCPInputPlan.textKey) : nil
                        try await key(key: piece, code: identity?.code, virtual: identity?.virtual,
                                      text: piece, modifiers: identity?.modifiers ?? 0,
                                      unmodified: identity?.unmodified)
                    }
                    try await pause(MCPInputPlan.keyGap(Double.random(in: 0...1)))
                }
                result = try await finish(verifyValue: expected, keyboard: !text.isEmpty || name == "page_fill", mouse: clicked)
            }
        } catch {
            let suffix = dispatched ? " Input may be partial; inspect the page before retrying." : " No input was sent."
            result = MCPProtocol.content(error.localizedDescription + suffix, failed: true)
        }
        await cleanup()
        return result
    }

    private func check() throws {
        guard !Task.isCancelled, !expired, canContinue() else {
            throw Failure(message: "Input cancelled: connection, tab or server is no longer available, or the action timed out.")
        }
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
        try await MCPCDP(browser, canContinue: canContinue).call(method, parameters, cleanup: true)
    }

    private func prepare(selector: String?, scroll: Bool = true) async throws {
        let tree = try await call("Page.getFrameTree")
        guard let frameTree = tree["frameTree"] as? [String: Any], let frame = frameTree["frame"] as? [String: Any],
              let frameID = frame["id"] as? String, let loaderID = frame["loaderId"] as? String else {
            throw Failure(message: "The main document is unavailable.")
        }
        loader = loaderID
        if let reference, reference.document != loaderID { throw Failure(message: "Stale ref: document changed. Take a new snapshot.") }
        let world = try await call("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "cra-mcp-input"])
        guard let context = world["executionContextId"] as? Int else { throw Failure(message: "No isolated inspection world.") }
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [selector ?? ""]), as: UTF8.self)
        var retained: String?
        if let reference {
            let resolved = try await call("DOM.resolveNode", ["backendNodeId": reference.node, "executionContextId": context, "objectGroup": group])
            retained = (resolved["object"] as? [String: Any])?["objectId"] as? String
            guard retained != nil else { throw Failure(message: "Stale ref: node unavailable. Take a new snapshot.") }
        }
        let script = """
        (function(target) {
          const selector = \(literal)[0];
          const matches = target ? [target] : selector ? document.querySelectorAll(selector) : [document.activeElement];
          if (matches.length !== 1) throw Error('Selector must match exactly one element; found ' + matches.length);
          const node = matches[0];
          if (!(node instanceof Element) || node.ownerDocument !== document || !node.isConnected) throw Error('Stale or unsupported target; take a new snapshot.');
          const state = {node, counts:{}, downKeys:new Set()};
          const types = ['mousemove','mousedown','mouseup','click','keydown','keyup','beforeinput','input','wheel','change','dragstart','dragover','drop','pointermove','pointerup'];
          const observe = event => {
            if (!event.isTrusted) return;
            const target = event.composedPath().includes(node);
            if (event.type === 'keyup' && state.downKeys.has(event.key)) {
              state.counts.keyup = (state.counts.keyup || 0) + 1; state.downKeys.delete(event.key); return;
            }
            if (!target) return;
            if (event.type === 'keydown') state.downKeys.add(event.key);
            state.counts[event.type] = (state.counts[event.type] || 0) + 1;
          };
          for (const type of types) document.addEventListener(type, observe, true);
          state.stop = () => { for (const type of types) document.removeEventListener(type, observe, true); };
          return state;
        })
        """
        let made: [String: Any]
        if let retained {
            made = try await call("Runtime.callFunctionOn", ["objectId": retained, "functionDeclaration": "function(){return (" + script + ")(this)}", "objectGroup": group])
        } else {
            made = try await call("Runtime.evaluate", ["expression": script + "()", "contextId": context, "objectGroup": group])
        }
        object = (made["result"] as? [String: Any])?["objectId"] as? String
        guard object != nil else { throw Failure(message: "Could not retain target identity.") }
        let element = try await function("function(){return this.node}", value: false)
        node = (element["result"] as? [String: Any])?["objectId"] as? String
        guard let node else { throw Failure(message: "No target node.") }
        if scroll {
            _ = try await inspect()
            _ = try await call("DOM.scrollIntoViewIfNeeded", ["objectId": node])
        }
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
          if (!n.isConnected || n.ownerDocument !== document) throw Error('Target was detached or replaced. Resolve it again.');
          if (document.visibilityState !== 'visible') throw Error('Tab is hidden. Select it in Cra before sending input.');
          if (n.matches(':disabled') || n.closest('[inert],button:disabled,[aria-disabled="true"]')) throw Error('Target is disabled or inert.');
          for (let ancestor = n; ancestor; ancestor = ancestor.parentElement) {
            const style = getComputedStyle(ancestor);
            if (style.visibility !== 'visible' || Number(style.opacity) === 0) throw Error('Target is not visible.');
          }
          const rich = n.isContentEditable && Array.from(n.children).every(c => c.tagName === 'BR');
          if (editing && !(rich || n instanceof HTMLTextAreaElement || n instanceof HTMLInputElement && ['text','search','email','url','tel','password'].includes(n.type))) throw Error('Typing supports text inputs and textareas only.');
          if (editing && n.readOnly) throw Error('Target is read-only.');
          if (focused && document.activeElement !== n) throw Error('Focus changed; refusing to type into another element.');
          const rects = Array.from(n.getClientRects()).map(r => ({left:Math.max(0,r.left),top:Math.max(0,r.top),right:Math.min(innerWidth,r.right),bottom:Math.min(innerHeight,r.bottom)}));
          const r = rects.filter(r => r.right > r.left && r.bottom > r.top).sort((a,b) => (b.right-b.left)*(b.bottom-b.top)-(a.right-a.left)*(a.bottom-a.top))[0];
          if (hit && !r) throw Error('Target has no visible hit area.');
          const x = r ? (r.left+r.right)/2 : 0, y = r ? (r.top+r.bottom)/2 : 0;
          const top = r && document.elementFromPoint(x,y);
          if (hit && top !== n && !n.contains(top)) throw Error('Target is covered by another element.');
          let start = n.selectionStart, end = n.selectionEnd;
          if (rich) {
            const selection = getSelection();
            if (selection.rangeCount && n.contains(selection.anchorNode) && n.contains(selection.focusNode)) {
              const a = document.createRange(), b = document.createRange();
              a.selectNodeContents(n); a.setEnd(selection.anchorNode, selection.anchorOffset);
              b.selectNodeContents(n); b.setEnd(selection.focusNode, selection.focusOffset);
              start = Math.min(a.toString().length, b.toString().length); end = Math.max(a.toString().length, b.toString().length);
            } else if (!n.textContent) { start = 0; end = 0; }
          }
          return {x,y,editable:rich || n instanceof HTMLTextAreaElement || n instanceof HTMLInputElement && ['text','search','email','url','tel','password'].includes(n.type),value:rich ? n.textContent.replace(/\\u00a0/g,' ') : n.value || '',start,end,multiline:n instanceof HTMLTextAreaElement,focused:document.activeElement === n};
        }
        """, arguments: [editing, focused, hit])
        guard let value = (response["result"] as? [String: Any])?["value"] as? [String: Any] else {
            throw Failure(message: "Target inspection returned no value.")
        }
        return value
    }

    private func move(editing: Bool) async throws {
        let target = try await inspect(editing: editing, hit: true)
        let end = CGPoint(x: target["x"] as? Double ?? 0, y: target["y"] as? Double ?? 0)
        for move in MCPInputPlan.movement(from: position, to: end, variation: Double.random(in: 0...1)) {
            try await pause(move.delay)
            _ = try await inspect(editing: editing)
            dispatched = true
            _ = try await call("Input.dispatchMouseEvent", ["type": "mouseMoved", "x": move.point.x, "y": move.point.y, "buttons": 0])
            position = move.point
        }
        let current = try await inspect(editing: editing, hit: true)
        guard abs((current["x"] as? Double ?? -100) - end.x) < 2,
              abs((current["y"] as? Double ?? -100) - end.y) < 2 else {
            throw Failure(message: "Target moved during pointer movement. No click was sent.")
        }
    }

    private func click(editing: Bool) async throws {
        try await move(editing: editing)
        let end = position
        mouseDown = true
        _ = try await call("Input.dispatchMouseEvent", ["type": "mousePressed", "x": end.x, "y": end.y,
                                                       "button": "left", "buttons": 1, "clickCount": 1])
        try await pause(MCPInputPlan.clickHold(Double.random(in: 0...1)))
        // The press can run page code. Never release over a newly substituted target.
        let released = try await inspect(editing: editing, hit: true)
        guard abs((released["x"] as? Double ?? -100) - end.x) < 2,
              abs((released["y"] as? Double ?? -100) - end.y) < 2 else {
            throw Failure(message: "Target moved while the mouse button was held.")
        }
        _ = try await call("Input.dispatchMouseEvent", ["type": "mouseReleased", "x": end.x, "y": end.y,
                                                       "button": "left", "buttons": 0, "clickCount": 1])
        mouseDown = false
    }

    private func select(_ value: String) async throws -> [String: Any] {
        let response = try await function("""
        function(value) {
          const n = this.node;
          if (!(n instanceof HTMLSelectElement) || n.multiple) throw Error('Only single HTML select controls are supported.');
          const options = Array.from(n.options).filter(o => !o.disabled && !o.parentElement.disabled);
          const matches = options.filter(o => o.value === value);
          if (matches.length !== 1) throw Error('Value must match one enabled option.');
          const label = matches[0].label.trim().replace(/\\s+/g, ' ');
          const initial = Array.from(label)[0];
          if (!initial || !/^[A-Za-z]$/.test(initial) || options.filter(o => o.label.trim().toLocaleLowerCase().startsWith(initial.toLocaleLowerCase())).length !== 1) throw Error('Native selection requires a unique first character; refusing intermediate option changes.');
          if (options.length > 100) throw Error('Select exceeds 100 enabled options.');
          return {label:initial,value:n.value};
        }
        """, arguments: [value])
        guard let state = (response["result"] as? [String: Any])?["value"] as? [String: Any], let label = state["label"] as? String,
              MCPInputPlan.validText(label), let node else { throw Failure(message: "Select label unavailable or too long.") }
        // macOS' native popup consumes arrow keys differently. Native focus plus the select's
        // built-in type-ahead avoids the popup and still emits trusted input/change events.
        dispatched = true
        _ = try await call("DOM.focus", ["objectId": node])
        _ = try await inspect(focused: true)
        try await press("Escape")
        // Blink retains select type-ahead for one second, including between tool calls.
        // Expire that buffer before one unambiguous initial, avoiding intermediate selections.
        try await pause(1.1)
        for piece in MCPInputPlan.textPieces(label) {
            _ = try await inspect(focused: true)
            let identity = piece.unicodeScalars.count == 1 ? piece.first.flatMap(MCPInputPlan.textKey) : nil
            try await key(key: piece, code: identity?.code, virtual: identity?.virtual, text: piece,
                          modifiers: identity?.modifiers ?? 0, unmodified: identity?.unmodified)
            try await pause(MCPInputPlan.keyGap(Double.random(in: 0...1)))
        }
        let final = try await function("function(){return this.node.value}")
        guard (final["result"] as? [String: Any])?["value"] as? String == value else { throw Failure(message: "Select did not reach the requested option.") }
        let observed = try await function("function(){return this.counts}")
        let counts = (observed["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
        if state["value"] as? String != value, (counts["input"] ?? 0) == 0 || (counts["change"] ?? 0) == 0 {
            throw Failure(message: "Select did not confirm trusted input/change events.")
        }
        return try await finish(verifyValue: nil, keyboard: true, mouse: false)
    }

    private func press(_ name: String, modifiers: Int = 0) async throws {
        guard let definition = MCPInputPlan.keys[name] else { throw Failure(message: "Unsupported key.") }
        try await key(key: name, code: definition.code, virtual: definition.virtual, text: name == "Enter" ? "\r" : nil, modifiers: modifiers)
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
        try await pause(MCPInputPlan.keyHold(Double.random(in: 0...1)))
        _ = try await call("Input.dispatchKeyEvent", up)
        heldKey = nil
    }

    private func finish(verifyValue: String?, keyboard: Bool = false, mouse: Bool = true) async throws -> [String: Any] {
        do {
            if let expected = verifyValue {
                let state = try await inspect(editing: true, focused: true)
                guard state["value"] as? String == expected else {
                    throw Failure(message: "The field value differs from the requested edit (the page may have transformed or rejected input).")
                }
            }
            let response = try await function("function(){return this.counts}")
            let counts = (response["result"] as? [String: Any])?["value"] as? [String: Int] ?? [:]
            guard !mouse || (counts["mousedown"] ?? 0) > 0 && (counts["mouseup"] ?? 0) > 0 && (counts["click"] ?? 0) > 0,
                  !keyboard || (counts["keydown"] ?? 0) > 0 && counts["keydown"] == counts["keyup"],
                  verifyValue == nil || verifyValue == "" || (counts["input"] ?? 0) > 0 else {
                throw Failure(message: "The page did not confirm the expected trusted input events.")
            }
            return content(["status": "completed", "input": "chromium", "humanized": true, "trustedEvents": counts])
        } catch {
            // A committed navigation destroys the observer. Report that explicitly, never replay.
            if verifyValue == nil, dispatched, !mouseDown, heldKey == nil,
               let tree = try? await call("Page.getFrameTree"), let frameTree = tree["frameTree"] as? [String: Any],
               let frame = frameTree["frame"] as? [String: Any], let current = frame["loaderId"] as? String, current != loader {
                return content(["status": "navigation_observed", "input": "chromium", "humanized": true,
                                "eventVerification": "The document navigated; the old event observer is no longer available."])
            }
            throw error
        }
    }

    private func upload(_ paths: [String]) async throws -> [String: Any] {
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
        return content(["status": "completed", "input": "chromium", "files": files, "trustedEvents": counts])
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
            try await pause(MCPInputPlan.clickHold(Double.random(in: 0...1)))
            var dragData: [String: Any]?
            for step in MCPInputPlan.movement(from: position, to: end, variation: Double.random(in: 0...1)) {
                try await pause(step.delay)
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
