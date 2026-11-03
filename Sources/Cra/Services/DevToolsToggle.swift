import Foundation

/// ⌥⌘I on a page, as in Chrome: open DevTools, or close them when open. CEF's HasDevTools()
/// stays true until the DevTools frontend has gone, so deciding from it made a second press
/// while they closed close them again (nothing happened). This follows the page's DevTools
/// from Cra's requests and CEF's callbacks instead, and remembers a press made mid-close.
struct DevToolsToggle: Equatable {
    enum State: Equatable { case closed, opening, open, closing(reopen: Bool) }
    /// `frontend`: DevTools stay as they are and the open frontend takes the action now.
    enum Effect: Equatable { case show, close, frontend, none }

    private(set) var state = State.closed
    /// The panel the frontend shows ("console", "network", "elements", …) as it last reported
    /// it, nil while closed or before it reports one.
    private(set) var panel: String?

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

    /// The DevTools commands of Arc 1.170's developer bar and menu (GitHub #88): ⌥⌘I toggles;
    /// Console (⌥⌘J) and Network open on their panel, switch to it when DevTools show another,
    /// and close them only when it already shows (#138); Inspect (⌥⌘C) always ends open, with
    /// the element picker armed.
    enum Command: Equatable { case toggle, console, network, inspect }

    /// The effect, and what the frontend is asked (CraBrowser.devToolsAction).
    mutating func run(_ command: Command) -> (effect: Effect, frontend: String?) {
        switch command {
        case .toggle: return (toggle(), nil)
        case .inspect: return (show(), "inspect")
        case .console, .network:
            let name = command == .console ? "console" : "network"
            switch state {
            case .closed, .closing:
                let effect = toggle()
                return (effect, state == .closing(reopen: false) ? nil : name)
            case .opening:
                // The frontend still loading takes the panel once it is up.
                return (.none, name)
            case .open:
                if panel == name {
                    state = .closing(reopen: false)
                    return (.close, nil)
                }
                // Until the frontend reports the switch, a second press already closes.
                panel = name
                return (.frontend, name)
            }
        }
    }

    /// The frontend selected a panel, from these commands or its own tab bar.
    mutating func didShowPanel(_ name: String) {
        if state == .open || state == .opening { panel = name }
    }

    /// CEF made the DevTools view, also for DevTools opened from Chromium's own menu.
    mutating func didOpen() {
        if case .closing = state { return }
        state = .open
    }

    /// CEF reports them gone; a press made while they closed opens them again now.
    mutating func didClose() -> Effect {
        panel = nil
        if case .closing(reopen: true) = state {
            state = .opening
            return .show
        }
        state = .closed
        return .none
    }
}
