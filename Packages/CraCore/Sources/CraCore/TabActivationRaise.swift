import Foundation

/// What comes forward when a tab asks to be brought to the front: an extension's
/// `chrome.tabs.update(id, {active: true})` (SwitchyOmega's Options focusing its settings tab,
/// GitHub #38), or the page itself (`window.focus()` after a click on its notification).
/// The tab is always selected in the browser window that holds its page; this decides whether
/// that window, and Cra, come forward too.
public enum TabActivationRaise {
    public enum Outcome: Equatable, Sendable {
        /// Only the tab is selected; every window stays where it is.
        case none
        /// The tab's window comes forward and becomes key.
        case window
        /// The window comes forward and Cra becomes the active app.
        case windowAndApp
    }

    /// `appActive`: Cra is the active app. `windowIsKey`: the tab's window (or one of its
    /// panels) has the keyboard. `anotherBrowserWindowIsKey`: a different browser window has it.
    public static func outcome(byPage: Bool, appActive: Bool, windowIsKey: Bool, anotherBrowserWindowIsKey: Bool) -> Outcome {
        if byPage { return .windowAndApp }
        // Another browser window in use keeps its place in front (#239): a window behind it, on
        // another monitor under someone else's app, came up on every tab switch.
        return appActive && !windowIsKey && !anotherBrowserWindowIsKey ? .window : .none
    }
}
