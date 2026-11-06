import AppKit
import CraCEF

/// Bounded CDP calls shared by page inspection and native input. No DevTools port is opened.
@MainActor
final class MCPCDP {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    let browser: CraBrowser
    let canContinue: () -> Bool
    init(_ browser: CraBrowser, canContinue: @escaping () -> Bool) {
        self.browser = browser; self.canContinue = canContinue
    }
    func check() throws {
        guard !Task.isCancelled, canContinue() else { throw Failure(message: "Operation cancelled: tab, connection or server changed.") }
    }
    func call(_ method: String, _ params: [String: Any] = [:], timeout: Double = 2, cleanup: Bool = false) async throws -> [String: Any] {
        if !cleanup { try check() }
        let data = try JSONSerialization.data(withJSONObject: params)
        let result: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            let reply = Reply(continuation)
            reply.timer = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                    reply.finish(.failure(Failure(message: "Chromium did not acknowledge \(method). Outcome may be unknown; inspect before repeating an action.")))
                } catch {}
            }
            browser.sendDevToolsMethod(method, params: String(decoding: data, as: UTF8.self)) { value, error in
                Task { @MainActor in
                    if let error { reply.finish(.failure(Failure(message: error))); return }
                    guard let data = value?.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                        reply.finish(.failure(Failure(message: "Invalid Chromium response."))); return
                    }
                    if reply.continuation == nil {
                        self.discardResource(method, result: object)
                        return
                    }
                    if let exception = object["exceptionDetails"] as? [String: Any] {
                        let detail = exception["exception"] as? [String: Any]
                        reply.finish(.failure(Failure(message: detail?["description"] as? String ?? "Page inspection failed.")))
                    } else { reply.finish(.success(object)) }
                }
            }
        }
        if !cleanup {
            do { try check() }
            catch { discardResource(method, result: result); throw error }
        }
        return result
    }
    /// A timed-out or cancelled print can still create a Chromium stream later.
    /// Release that orphan even though no caller remains to consume the response.
    private func discardResource(_ method: String, result: [String: Any]) {
        guard method == "Page.printToPDF", let stream = result["stream"] as? String,
              let data = try? JSONSerialization.data(withJSONObject: ["handle": stream]) else { return }
        browser.sendDevToolsMethod("IO.close", params: String(decoding: data, as: UTF8.self)) { _, _ in }
    }
    func frame() async throws -> [String: Any] {
        let tree = try await call("Page.getFrameTree")
        guard let tree = tree["frameTree"] as? [String: Any], var frame = tree["frame"] as? [String: Any] else {
            throw Failure(message: "Main document unavailable.")
        }
        // CDP splits the fragment from Frame.url. Preserve it for reads and same-document waits.
        if let fragment = frame["urlFragment"] as? String, let url = frame["url"] as? String {
            frame["url"] = url + fragment
        }
        return frame
    }
    func context() async throws -> Int {
        let frame = try await frame()
        let world = try await call("Page.createIsolatedWorld", ["frameId": frame["id"] ?? "", "worldName": "cra-mcp-input"])
        guard let context = world["executionContextId"] as? Int else { throw Failure(message: "Inspection context unavailable.") }
        return context
    }
    func inspect(_ expression: String) async throws -> Any {
        let context = try await context()
        let response = try await call("Runtime.evaluate", ["expression": expression, "contextId": context, "returnByValue": true, "timeout": 1000])
        guard let result = response["result"] as? [String: Any], let value = result["value"] else {
            throw Failure(message: "Inspection returned no value.")
        }
        return value
    }
    static func content(_ value: Any) throws -> [String: Any] {
        MCPProtocol.content(String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self))
    }
    @MainActor
    private final class Reply {
        var continuation: CheckedContinuation<[String: Any], Error>?
        var timer: Task<Void, Never>?
        init(_ continuation: CheckedContinuation<[String: Any], Error>) { self.continuation = continuation }
        func finish(_ result: Result<[String: Any], Error>) {
            guard let continuation else { return }
            self.continuation = nil; timer?.cancel(); timer = nil
            continuation.resume(with: result)
        }
    }
}

@MainActor
final class MCPPage {
    let browser: CraBrowser
    var references = MCPReferences()
    var pendingNavigation: (document: String, url: String)?
    init(_ browser: CraBrowser) { self.browser = browser }

    func resolve(_ ref: String, cdp: MCPCDP) async throws -> (node: Int, document: String) {
        let frame = try await cdp.frame()
        guard let document = frame["loaderId"] as? String, let node = references.resolve(ref, document: document) else {
            throw MCPCDP.Failure(message: "Stale or unknown element ref. Run page_snapshot again; refs never retarget another node.")
        }
        return (node, document)
    }

    func run(_ name: String, arguments: [String: Any], cdp: MCPCDP) async throws -> [String: Any] {
        switch name {
        case "page_read":
            let before = try await cdp.frame()
            let offset = arguments["offset"] as? Int ?? 0
            var value = try await cdp.inspect("""
            (() => {
              const cut = (s,n) => { let end=Math.min(s.length,n); if (end<s.length && /[\\uD800-\\uDBFF]/.test(s[end-1])) end--; return s.slice(0,end); };
              const text = document.body?.innerText || '';
              let offset = \(offset);
              if (offset > 0 && /[\\uDC00-\\uDFFF]/.test(text[offset]) && /[\\uD800-\\uDBFF]/.test(text[offset-1])) offset++;

              let end = Math.min(text.length, offset + 20000);
              if (end < text.length && /[\\uD800-\\uDBFF]/.test(text[end-1])) end--;
              return {title:cut(document.title,500),url:location.href,text:text.slice(offset,end),
                nextOffset:end<text.length?end:null,
                links:Array.from(document.querySelectorAll('a[href]')).filter(a=>a instanceof HTMLAnchorElement).slice(0,50).map(a=>({text:cut(a.innerText,150),url:cut(a.href,1000)})),
                contentTrust:'untrusted'};
            })()
            """) as? [String: Any] ?? [:]
            let after = try await cdp.frame()
            guard before["loaderId"] as? String == after["loaderId"] as? String else { throw MCPCDP.Failure(message: "Document changed during read. Read again from offset zero.") }
            value["url"] = String((after["url"] as? String ?? browser.currentURL).prefix(4000))
            value["title"] = String(browser.currentTitle.prefix(500))
            return try MCPCDP.content(value)
        case "page_navigate":
            guard let url = arguments["url"] as? String, MCPProtocol.navigable(url) else { throw MCPCDP.Failure(message: "Only HTTP and HTTPS URLs are accepted.") }
            let before = try await cdp.frame()
            pendingNavigation = (before["loaderId"] as? String ?? "", before["url"] as? String ?? "")
            do {
                let result = try await cdp.call("Page.navigate", ["url": url], timeout: 10)
                if let error = result["errorText"] as? String { throw MCPCDP.Failure(message: error) }
            } catch { pendingNavigation = nil; throw error }
            return try MCPCDP.content(["status": "navigation_requested"])
        case "page_snapshot": return try await snapshot(cdp)
        case "page_wait": return try await wait(arguments, cdp: cdp)
        case "page_screenshot":
            let view = try await cdp.inspect("({visible:document.visibilityState === 'visible',scale:devicePixelRatio})") as? [String: Any] ?? [:]
            guard view["visible"] as? Bool == true else { throw MCPCDP.Failure(message: "Show the tab before capturing a screenshot.") }
            let metrics = try await cdp.call("Page.getLayoutMetrics")
            guard let viewport = metrics["cssVisualViewport"] as? [String: Any],
                  let width = viewport["clientWidth"] as? Double, let height = viewport["clientHeight"] as? Double,
                  width > 0, height > 0 else { throw MCPCDP.Failure(message: "Viewport unavailable.") }
            let shot = try await cdp.call("Page.captureScreenshot", ["format": "jpeg", "quality": 75, "captureBeyondViewport": false,
                "clip": ["x": viewport["pageX"] ?? 0, "y": viewport["pageY"] ?? 0, "width": width, "height": height,
                         "scale": min(1, 1280 / (max(width, height) * (view["scale"] as? Double ?? 1)))]], timeout: 10)
            guard let data = shot["data"] as? String, data.utf8.count < 750_000 else { throw MCPCDP.Failure(message: "Screenshot exceeds the response limit.") }
            return ["content": [["type": "image", "mimeType": "image/jpeg", "data": data]], "isError": false]
        case "page_pdf":
            let result = try await cdp.call("Page.printToPDF", ["printBackground": true, "transferMode": "ReturnAsStream"], timeout: 30)
            guard let stream = result["stream"] as? String else { throw MCPCDP.Failure(message: "PDF stream unavailable.") }
            do {
                var pdf = Data()
                while true {
                    let chunk = try await cdp.call("IO.read", ["handle": stream, "size": 65536])
                    guard let text = chunk["data"] as? String else { throw MCPCDP.Failure(message: "Invalid PDF chunk.") }
                    let bytes = chunk["base64Encoded"] as? Bool == true ? Data(base64Encoded: text) : text.data(using: .utf8)
                    guard let bytes, pdf.count + bytes.count <= 16_777_216 else { throw MCPCDP.Failure(message: "PDF exceeds 16 MiB.") }
                    pdf.append(bytes)
                    if chunk["eof"] as? Bool == true { break }
                }
                _ = try await cdp.call("IO.close", ["handle": stream], cleanup: true)
                try cdp.check()
                let folder = AppPaths.file("mcp-exports")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let directoryFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard directoryFD >= 0 else { throw MCPCDP.Failure(message: "Unsafe export directory.") }
                defer { close(directoryFD) }
                var info = stat()
                guard fstat(directoryFD, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw MCPCDP.Failure(message: "Export directory must be private to this user.") }
                let filename = UUID().uuidString + ".pdf"
                let path = folder.appendingPathComponent(filename)
                let fd = openat(directoryFD, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard fd >= 0 else { throw MCPCDP.Failure(message: "Could not create PDF.") }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                do { try handle.write(contentsOf: pdf); try handle.close() }
                catch { try? handle.close(); _ = unlinkat(directoryFD, filename, 0); throw error }
                return try MCPCDP.content(["path": path.path, "bytes": pdf.count, "mimeType": "application/pdf"])
            } catch {
                _ = try? await cdp.call("IO.close", ["handle": stream], cleanup: true)
                throw error
            }
        case "page_history":
            let action = arguments["action"] as! String
            let before = try await cdp.frame()
            pendingNavigation = (before["loaderId"] as? String ?? "", before["url"] as? String ?? "")
            do {
                if action == "reload" { browser.reload() }
                else {
                    let history = try await cdp.call("Page.getNavigationHistory")
                    guard let entries = history["entries"] as? [[String: Any]], let current = history["currentIndex"] as? Int else {
                        throw MCPCDP.Failure(message: "History unavailable.")
                    }
                    let index = current + (action == "back" ? -1 : 1)
                    guard entries.indices.contains(index), let entry = entries[index]["id"] as? Int else { pendingNavigation = nil; throw MCPCDP.Failure(message: "No history entry in that direction.") }
                    _ = try await cdp.call("Page.navigateToHistoryEntry", ["entryId": entry])
                }
            } catch { pendingNavigation = nil; throw error }
            return try MCPCDP.content(["status": "navigation_requested"])
        default: throw MCPCDP.Failure(message: "Unsupported page operation.")
        }
    }

    private func snapshot(_ cdp: MCPCDP) async throws -> [String: Any] {
        let frame = try await cdp.frame()
        guard let document = frame["loaderId"] as? String else { throw MCPCDP.Failure(message: "No document identity.") }
        let tree = try await cdp.call("Accessibility.getFullAXTree", ["frameId": frame["id"] ?? ""], timeout: 10)
        let nodes = tree["nodes"] as? [[String: Any]] ?? []
        references.retain(nodes: Set(nodes.compactMap { $0["backendDOMNodeId"] as? Int }), document: document)
        let byID = Dictionary(nodes.compactMap { node -> (String, [String: Any])? in
            guard let id = node["nodeId"] as? String else { return nil }; return (id, node)
        }, uniquingKeysWith: { first, _ in first })
        var suppressed: Set<String> = []
        var descendants: [String] = []
        for node in nodes {
            let role = (node["role"] as? [String: Any])?["value"] as? String ?? ""
            let editable = (node["properties"] as? [[String: Any]] ?? []).contains { $0["name"] as? String == "editable" }
            if editable || ["textbox", "searchbox", "combobox"].contains(role) { descendants += node["childIds"] as? [String] ?? [] }
        }
        while let id = descendants.popLast() {
            if suppressed.insert(id).inserted { descendants += byID[id]?["childIds"] as? [String] ?? [] }
        }
        var elements: [[String: Any]] = []
        var bytes = 0
        var truncated = false
        for node in nodes where node["ignored"] as? Bool != true {
            if let id = node["nodeId"] as? String, suppressed.contains(id) { continue }
            let role = (node["role"] as? [String: Any])?["value"] as? String ?? ""
            if ["InlineTextBox", "generic", "none"].contains(role) { continue }
            let name = (node["name"] as? [String: Any])?["value"] as? String ?? ""
            var row: [String: Any] = ["role": role, "name": String(name.prefix(500)), "node": node["nodeId"] ?? ""]
            for property in node["properties"] as? [[String: Any]] ?? [] {
                if let key = property["name"] as? String, ["checked", "selected", "expanded", "disabled", "focused", "required", "level"].contains(key),
                   let value = (property["value"] as? [String: Any])?["value"] { row[key] = value }
            }
            if !["StaticText", "LineBreak"].contains(role), let backend = node["backendDOMNodeId"] as? Int, let ref = references.reference(node: backend, document: document) { row["ref"] = ref }
            bytes += try JSONSerialization.data(withJSONObject: row).count
            if elements.count >= 500 || bytes > 100_000 { truncated = true; break }
            elements.append(row)
        }
        let after = try await cdp.frame()
        guard after["loaderId"] as? String == document else { throw MCPCDP.Failure(message: "Document changed during snapshot. Take a new snapshot.") }
        return try MCPCDP.content(["url": frame["url"] ?? "", "elements": elements, "truncated": truncated,
                                   "scope": "main-frame", "contentTrust": "untrusted"])
    }

    private func wait(_ arguments: [String: Any], cdp: MCPCDP) async throws -> [String: Any] {
        // A failed/cancelled wait must not permanently fence subsequent inspection of this tab.
        defer { pendingNavigation = nil }
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        let expression = """
        (() => {
          const a = \(literal);
          if (document.readyState !== 'complete' || a.url && location.href !== a.url || a.text && !document.body?.innerText.includes(a.text)) return false;
          if (!a.selector) return true;
          const n = document.querySelector(a.selector), state = a.state || 'visible';
          if (state === 'attached') return !!n;
          if (state === 'detached') return !n;
          let visible = !!n && !!n.getClientRects().length;
          for (let p = n; p && visible; p = p.parentElement) { const s=getComputedStyle(p); visible=s.visibility==='visible' && Number(s.opacity)!==0; }
          return state === 'hidden' ? !visible : visible;
        })()
        """
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds((arguments["timeoutMs"] as? Int) ?? 10000))
        repeat {
            try cdp.check()
            do {
                let current = try await cdp.frame()
                let navigationReady = pendingNavigation.map { current["loaderId"] as? String != $0.document || current["url"] as? String != $0.url } ?? true
                if navigationReady, try await cdp.inspect(expression) as? Bool == true {
                    pendingNavigation = nil
                    return try MCPCDP.content(["status": "matched"])
                }
            } catch {
                // Read-only observation may race a navigation; never retry a mutating command.
                let changing = ["Cannot find context", "Execution context was destroyed", "Cannot find default execution context", "Cannot find frame", "Main document unavailable"]
                guard changing.contains(where: error.localizedDescription.contains) else { throw error }
            }
            if clock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < deadline
        throw MCPCDP.Failure(message: "Wait timed out; the requested page condition was not observed.")
    }
}
