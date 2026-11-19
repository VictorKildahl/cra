/// Edit ▸ Find's commands (⌘F, ⌘G, ⇧⌘G, ⌘E) and what each does to the find bar of the window in
/// front. A Little Window and a Peek have a bar of their own over their page, as a browser window
/// has over its tab: before #577 they dropped these commands, so ⌘F did nothing there.
public enum FindCommand: Equatable, Sendable {
    /// Find… (⌘F): the bar opens, or takes the keys again.
    case show
    /// Find Next (⌘G) and Find Previous (⇧⌘G).
    case step(forward: Bool)
    /// Use Selection for Find (⌘E): the page's selection becomes the search.
    case useSelection

    /// The command an action id (KeyBindings) names; nil for any other action.
    public init?(action: String) {
        switch action {
        case "find": self = .show
        case "findNext": self = .step(forward: true)
        case "findPrevious": self = .step(forward: false)
        case "useSelectionForFind": self = .useSelection
        default: return nil
        }
    }

    /// What the window does for it.
    public enum Effect: Equatable, Sendable {
        /// Show the bar (with the last search, all of it selected) and give it the keys.
        case showBar
        /// Search the bar's text again, to the next or previous match.
        case search(forward: Bool)
        /// Read the page's selection, then show the bar searching it.
        case searchSelection
    }

    /// `barShown`: the window's bar is up. ⌘G with no bar opens it, as Chrome's and Arc's do,
    /// rather than searching for text no one can see.
    public func effect(barShown: Bool) -> Effect {
        switch self {
        case .show: return .showBar
        case .step(let forward): return barShown ? .search(forward: forward) : .showBar
        case .useSelection: return .searchSelection
        }
    }
}
