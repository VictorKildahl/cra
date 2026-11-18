import AppKit
import CraCEF

/// PageHostStrip's AppKit side (CraCore has the rule, GitHub #346). On the engine each profile has
/// one window of Chrome's that holds its pages: never seen (alpha 0, left out of capture), but on
/// screen as a child of the Cra window in use, so Chrome's bubbles anchored to it show. The bridge
/// lays it over that whole window. Screenshot apps that list windows through ScreenCaptureKit see
/// no alpha and no sharing state, so it was the window they took anywhere over Cra, captured
/// blank. Here it shrinks to a strip along the Cra window's top edge, keeping its top left (where
/// Chrome's toolbar, and so its bubbles' anchors, are), each time it or that window changes size.
/// CEF builds keep their page windows: there a page's own window is laid over its card.
@MainActor
enum PageHostWindows {
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard EngineFramework.isChromiumEngine, observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { changed(window) }
            })
        }
        for w in NSApp.windows where CraCEFRuntime.isPageWindow(w) { fit(w) }
    }

    /// The window moved or resized: a page host itself (the bridge just laid it over a Cra window),
    /// or a Cra window with one riding on it.
    private static func changed(_ window: NSWindow) {
        if CraCEFRuntime.isPageWindow(window) {
            fit(window)
        } else {
            for child in window.childWindows ?? [] where CraCEFRuntime.isPageWindow(child) { fit(child) }
        }
    }

    private static func fit(_ host: NSWindow) {
        let target = PageHostStrip.frame(over: host.parent?.frame ?? host.frame)
        guard host.frame != target, !target.isEmpty else { return }
        if host.frame.height > PageHostStrip.height {
            CraLog.note("page host window \(host.windowNumber): \(Int(host.frame.width))x\(Int(host.frame.height)) → strip \(Int(target.width))x\(Int(target.height)) on its window's top edge")
        }
        host.setFrame(target, display: false)
    }
}
