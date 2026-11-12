/// What the command bar does with its pick.
public enum CommandBarMode: Equatable, Sendable {
    /// ⌘T: commit creates a new tab in the current space.
    case newTab
    /// ⌘L: commit navigates the current tab.
    case editURL
}

/// Which command bar ⌘T and ⌘L open from the window in front, and in which mode.
public struct CommandBarOpening: Equatable, Sendable {
    /// The window the keys came to.
    public enum Window: Equatable, Sendable {
        case browser
        /// A Little Window (Arc's Little Arc).
        case littleWindow
        /// A Peek over a browser window's tab.
        case peek
    }

    /// Whose bar opens: the window's own, or the browser window under a Peek.
    public enum Owner: Equatable, Sendable {
        case ownWindow
        case browserWindow
    }

    public let owner: Owner
    public let mode: CommandBarMode

    public init(owner: Owner, mode: CommandBarMode) {
        self.owner = owner
        self.mode = mode
    }

    /// `shortcut` is .newTab for ⌘T and .editURL for ⌘L; `hasPage` whether a Little Window or Peek
    /// shows a page (an empty Little Window has nothing to edit).
    public static func of(_ shortcut: CommandBarMode, in window: Window, hasPage: Bool) -> CommandBarOpening {
        switch window {
        case .browser:
            return CommandBarOpening(owner: .ownWindow, mode: shortcut)
        // A Peek is a look at a link over a tab: ⌘T is the browser window's New Tab, with its tabs to
        // switch to, the Peek waiting on its tab (#379). ⌘L edits the Peek's address.
        case .peek where shortcut == .newTab:
            return CommandBarOpening(owner: .browserWindow, mode: .newTab)
        case .littleWindow, .peek:
            // Little Arc (Arc 1.168, 24 Oct 2026): ⌘T opens the window's bar as ⌘L does, its address
            // prefilled and selected.
            return CommandBarOpening(owner: .ownWindow, mode: hasPage ? .editURL : .newTab)
        }
    }
}
