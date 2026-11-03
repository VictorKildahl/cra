import Foundation

/// The close button on a sidebar row and what ⌘W does, as in Arc 1.171
/// (TabCellState.closeButtonConfiguration; recorded live and in Arc's code, GitHub #139).
///
/// "Keep" is Arc's `deselect`: the tab unloads, goes back to its pinned page and stays in the
/// sidebar (a minus). "Archive" is `close`: the item leaves the sidebar for the archive (an ✕).
public enum SidebarClose {
    public enum Action: Equatable, Sendable {
        case keep
        case archive
    }

    public struct Button: Equatable, Sendable {
        public let action: Action
        /// The tooltip, with "(⌘W)" when the row is the open one (ArcTooltipLabel turns it into keycaps).
        public let help: String
        public var minus: Bool { action == .keep }

        public init(action: Action, help: String) {
            self.action = action
            self.help = help
        }
    }

    /// A tab's row. A Today tab archives. A pinned tab keeps its place while it is the open tab,
    /// while it is away from its pinned page, or while it shows under a closed folder; otherwise
    /// (in the background on its own page, loaded or not) it archives.
    public static func tab(pinned: Bool, current: Bool, navigatedAway: Bool, peeked: Bool) -> Button {
        let keep = pinned && (current || navigatedAway || peeked)
        return Button(action: keep ? .keep : .archive,
                      help: (keep ? "Close and Keep Pinned" : "Archive this tab") + (current ? " (⌘W)" : ""))
    }

    /// Where a split row's buttons go: a pinned split, or a Today split in the background, has
    /// one at the row's end for the whole split; an open Today split has an ✕ on every pane
    /// (each archives its pane, the split falls apart into the other).
    public enum SplitButtons: Equatable, Sendable {
        case row(Button)
        case perPane(Button)
    }

    public static func split(pinned: Bool, current: Bool) -> SplitButtons {
        if !pinned && current { return .perPane(Button(action: .archive, help: "Archive this item")) }
        let keep = pinned && current
        return .row(Button(action: keep ? .keep : .archive,
                           help: (keep ? "Close this item" : "Archive this item") + (current ? " (⌘W)" : "")))
    }

    /// ⌘W on the open tab, or on every picked tab when it is one of them: if any is a Today tab
    /// they are all archived, pinned ones and favorites too; otherwise they all keep their place.
    public static func commandW(anyToday: Bool) -> Action { anyToday ? .archive : .keep }
}
