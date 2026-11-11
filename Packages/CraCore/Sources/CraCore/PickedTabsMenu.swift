import Foundation

/// The sidebar's menu for several tabs picked with ⌘/⇧-click (GitHub #356), in Arc's sections.
/// Arc 1.17x, from the issue's screenshot of two picked Today tabs:
///
///     Open in Split View, Duplicate
///     ──
///     Copy URLs ⇧⌘C, Share 2 Items…
///     ──
///     Move to ▸, New Folder with 2 Items
///     ──
///     Change Icon ▸ (dimmed), Mute
///     ──
///     Archive Tabs
///
/// Cra keeps its single-tab menu's Move to Space ▸ and Move to Folder ▸ for Arc's one Move to ▸,
/// and its own last section, Close N Tabs and Deselect All, since closing a picked pinned tab keeps
/// it pinned, as ⌘W does. Share is the Mac's share services in a submenu (Messages, Mail, AirDrop,
/// Notes, Reminders) as on a single tab: Arc's share link goes through arc.net, and nothing leaves
/// the Mac here. Copy URLs copies what ⇧⌘C does with tabs picked: every link, one per line
/// (#322). Rows are identifiers; `title` names them.
public enum PickedTabsMenu {
    public static let sections: [[String]] = [
        ["openInSplitView", "duplicate"],
        ["copyURLs", "share"],
        ["moveToSpace", "moveToFolder", "newFolder"],
        ["changeIcon", "mute"],
        ["closeTabs", "deselectAll"],
    ]

    /// A split holds at most four panes, so Open in Split View shows for two to four picks.
    public static let maxPanes = 4

    /// What the menu is opened on.
    public struct Picks: Equatable, Sendable {
        public var count: Int
        /// Whether every pick is muted already, so the row unmutes them.
        public var allMuted: Bool
        /// Whether the space has a folder to move them into.
        public var hasFolders: Bool
        /// Whether a pick is in a split already (a split doesn't nest).
        public var anyInSplit: Bool

        public init(count: Int, allMuted: Bool = false, hasFolders: Bool = false, anyInSplit: Bool = false) {
            self.count = count
            self.allMuted = allMuted
            self.hasFolders = hasFolders
            self.anyInSplit = anyInSplit
        }
    }

    public static func shows(_ id: String, for picks: Picks) -> Bool {
        switch id {
        case "openInSplitView": (2...maxPanes).contains(picks.count) && !picks.anyInSplit
        case "moveToFolder": picks.hasFolders
        default: true
        }
    }

    /// Arc greys out Change Icon for several tabs; every other row that shows can be picked.
    public static func isEnabled(_ id: String) -> Bool { id != "changeIcon" }

    public static func title(_ id: String, for picks: Picks) -> String {
        let n = picks.count
        return switch id {
        case "openInSplitView": "Open in Split View"
        case "duplicate": "Duplicate"
        case "copyURLs": "Copy URLs"
        case "share": "Share \(n) Items"
        case "moveToSpace": "Move to Space"
        case "moveToFolder": "Move \(n) Tabs to Folder"
        case "newFolder": "New Folder with \(n) Items"
        case "changeIcon": "Change Icon"
        case "mute": picks.allMuted ? "Unmute" : "Mute"
        case "closeTabs": "Close \(n) Tabs"
        case "deselectAll": "Deselect All"
        default: id
        }
    }

    /// The rows that show, in sections, as the menu draws them.
    public static func shown(for picks: Picks) -> [[String]] {
        sections.map { $0.filter { shows($0, for: picks) } }.filter { !$0.isEmpty }
    }
}
