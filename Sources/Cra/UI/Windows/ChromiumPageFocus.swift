import AppKit

/// Tells Chromium which page has Cra's focus, so extensions see it as the active tab.
///
/// An embedded page's views live in Cra's window, so its Chromium host window never becomes key
/// and Chromium never learns that the page was activated. Its browser stays inactive, and
/// `chrome.tabs.query({active: true, currentWindow: true})` and `lastFocusedWindow` answer with
/// whichever page was active last. A password manager then offered the previous site's logins
/// (#414). Chromium's window delegate (`ViewsNSWindowDelegate`) turns `windowDidBecomeKey` into
/// widget activation without checking that the window really is key, and `windowDidResignKey`
/// into deactivation unless the window still is key. So Cra calls them when a page takes or
/// loses focus. Only one host is active at a time. If the engine stops taking these calls at
/// face value (a CEF update, or the move off CEF), the `extension-*-context` scenarios fail.
enum ChromiumPageFocus {
    private static weak var focusedHost: NSWindow?
    private static var changingFocus = false

    static func focus(_ window: NSWindow) {
        guard !changingFocus, focusedHost !== window else { return }
        changingFocus = true
        defer { changingFocus = false }
        if let previous = focusedHost {
            previous.delegate?.windowDidResignKey?(Notification(name: NSWindow.didResignKeyNotification, object: previous))
        }
        focusedHost = window
        // Cra can focus a page while its Chromium host cannot become key, or before
        // AppKit delivers its activation. Extensions must see that page as current now.
        window.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    }

    static func blur(_ window: NSWindow) {
        guard focusedHost === window, !changingFocus else { return }
        changingFocus = true
        defer { changingFocus = false }
        focusedHost = nil
        window.delegate?.windowDidResignKey?(Notification(name: NSWindow.didResignKeyNotification, object: window))
    }
}
