import Foundation

/// ⌥⌘I on a page, as in Chrome: open DevTools, or close them when open. CEF's HasDevTools()
/// stays true until the DevTools frontend has gone, so deciding from it made a second press
/// while they closed close them again (nothing happened). This follows the page's DevTools
/// from Cra's requests and CEF's callbacks instead, and remembers a press made mid-close.
struct DevToolsToggle: Equatable {
    enum State: Equatable { case closed, opening, open, closing(reopen: Bool) }
    enum Effect: Equatable { case show, close, none }

    private(set) var state = State.closed

    /// The shortcut, the developer bar's button, the menu item.
    mutating func toggle() -> Effect {
        switch state {
        case .closed:
            state = .opening
            return .show
        case .opening, .open:
            state = .closing(reopen: false)
            return .close
        case .closing(let reopen):
            state = .closing(reopen: !reopen)
            return .none
        }
    }

    /// Inspect Element: DevTools must end up open (and CEF moves them to the element).
    mutating func show() -> Effect {
        switch state {
        case .closed, .opening, .open:
            if state == .closed { state = .opening }
            return .show
        case .closing:
            state = .closing(reopen: true)
            return .none
        }
    }

    /// CEF made the DevTools view, also for DevTools opened from Chromium's own menu.
    mutating func didOpen() {
        if case .closing = state { return }
        state = .open
    }

    /// CEF reports them gone; a press made while they closed opens them again now.
    mutating func didClose() -> Effect {
        if case .closing(reopen: true) = state {
            state = .opening
            return .show
        }
        state = .closed
        return .none
    }
}
