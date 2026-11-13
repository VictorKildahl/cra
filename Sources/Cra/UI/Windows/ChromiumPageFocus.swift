import AppKit

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
