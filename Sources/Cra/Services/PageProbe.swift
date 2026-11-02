import AppKit
import CraCEF

/// What a page holds, asked from the page itself: a blank tab tells apart a navigation that
/// never committed (about:blank), a page Chromium thinks is hidden, one that has content but
/// never painted it, and one that is simply empty.
///
/// `frameRate` counts animation frames for half a second. A visible page gets one per display
/// refresh; 0 means Chromium's compositor never asked it to draw. Frames without `painted`
/// mean they were drawn but never reached the screen (#80).
@MainActor
enum PageProbe {
    private static let script = """
        new Promise(done => {
          let frames = 0, counting = true;
          const tick = () => { if (counting) { frames++; requestAnimationFrame(tick); } };
          requestAnimationFrame(tick);
          setTimeout(() => { counting = false;
            done(JSON.stringify({blank: location.href === 'about:blank', ready: document.readyState, visibility: document.visibilityState,
              viewport: innerWidth + 'x' + innerHeight + '@' + devicePixelRatio,
              scrollHeight: document.documentElement ? document.documentElement.scrollHeight : 0,
              elements: document.getElementsByTagName('*').length,
              text: document.body ? document.body.textContent.length : -1,
              painted: performance.getEntriesByName('first-contentful-paint').length > 0,
              frameRate: frames * 2})); }, 500);
        })
        """

    /// One line ("ready=complete visibility=visible …"), or why there is none.
    static func run(_ browser: CraBrowser, completion: @escaping (String) -> Void) {
        guard browser.isCreated, !browser.isClosed else { completion("no browser yet"); return }
        let body = try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true, "awaitPromise": true])
        var answered = false
        let finish: (String) -> Void = { line in
            guard !answered else { return }
            answered = true
            completion(line)
        }
        // A hung renderer never answers; that is an answer too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish("no answer in 3 s (renderer busy or gone)") }
        browser.sendDevToolsMethod("Runtime.evaluate", params: body.flatMap { String(data: $0, encoding: .utf8) } ?? "{}") { result, error in
            DispatchQueue.main.async {
                guard let data = result?.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let value = (json["result"] as? [String: Any])?["value"] as? String,
                      let fields = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] else {
                    finish("probe failed: \(error ?? "no result")")
                    return
                }
                finish(["blank", "ready", "visibility", "viewport", "scrollHeight", "elements", "text", "painted", "frameRate"]
                    .map { "\($0)=\(fields[$0].map { "\($0)" } ?? "?")" }.joined(separator: " "))
            }
        }
    }

    /// Where Cra put the page: its view's size and whether anything hides it.
    static func viewState(_ rt: TabRuntime) -> String {
        var views = [rt.browser.containerView]
        if let host = rt.hostWindow {
            views = EmbeddedPages.pageViews(of: host) ?? [host.contentView].compactMap { $0 }
        }
        let shown = views.map { v -> String in
            let hidden = sequence(first: v, next: \.superview).contains { $0.isHidden }
            return "\(Int(v.frame.width))x\(Int(v.frame.height))\(hidden ? " hidden" : "")\(v.window == nil ? " no-window" : "")"
        }
        var s = "view=\(shown.joined(separator: ","))"
        if let host = rt.hostWindow {
            s += " pageWindow=\(host.isVisible ? "visible" : "not visible")\(EmbeddedPages.isHost(host) ? " embedded" : "") alpha=\(host.alphaValue)"
        }
        // Chromium reports a page in a covered window as hidden (visibility=hidden), which is
        // fine; hidden in a window on screen is not.
        if let w = views.first?.window {
            s += " window=\(w.occlusionState.contains(.visible) ? "on screen" : "covered")\(NSApp.isActive ? "" : " app=inactive")"
            // Chromium times the page's frames to the display its own window is on.
            s += " display=\(refreshRate(w.screen))"
            if let host = rt.hostWindow, host.screen != w.screen { s += " pageDisplay=\(refreshRate(host.screen))" }
        }
        return s
    }

    static func refreshRate(_ screen: NSScreen?) -> String {
        screen.map { "\($0.maximumFramesPerSecond)Hz" } ?? "none"
    }
}
