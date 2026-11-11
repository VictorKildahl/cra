import Foundation

/// The sidebar's menu for several tabs picked with ⌘/⇧-click (GitHub #356), row for row as Arc
/// draws it. Read over Accessibility in Arc 1.17x on 11 Nov 2026, two Today tabs picked, then a
/// pinned tab added (the issue's screenshot was an older Arc, with Copy URLs ⇧⌘C and the actions
/// first):
///
///     Today tabs                          A pinned tab among them
///     Copy Links, Share 2 Items…          Copy Links, Share 3 Items…
///     ──                                  ──
///     Change Icon… (dimmed), Mute         Open in Split View, Move to ▸, New Folder with 3 Items
///     ──                                  ──
///     Open in Split View, Duplicate,      Archive Items
///     Move to ▸, New Folder with 2 Items
///     ──
///     Archive Tabs, Archive Tabs Below (dimmed)
///
/// Move to ▸ lists the spaces, the picks' own one checked, then New Space…. Mute was dimmed with
/// nothing playing; Cra lets it act once a pick plays sound or is muted. Share 2 Items… copies a
/// link anyone can open, as Arc's did ("Copied Shared URL"): Arc kept the selection on arc.net,
/// Cra's link carries it after its # (FolderShareLink.picked). Copy Links copies what ⇧⌘C does with
/// tabs picked, every link one per line (#322). Rows are identifiers; `title` names them.
public enum PickedTabsMenu {
    public static let sections: [[String]] = [
        ["copyLinks", "share"],
        ["changeIcon", "mute"],
        ["openInSplitView", "duplicate", "moveTo", "newFolder"],
        ["archive", "archiveBelow"],
    ]

    /// A split holds at most four panes, so Open in Split View shows for two to four picks.
    public static let maxPanes = 4

    /// What the menu is opened on.
    public struct Picks: Equatable, Sendable {
        public var count: Int
        /// Whether a pick is pinned (or in a pinned folder): Arc then leaves out the tab-only rows.
        public var anyPinned: Bool
        /// Whether every pick is muted already, so the row unmutes them.
        public var allMuted: Bool
        /// Whether a pick plays sound or is muted, so Mute has something to do.
        public var anySound: Bool
        /// Whether a pick is in a split already (a split doesn't nest).
        public var anyInSplit: Bool

        public init(count: Int, anyPinned: Bool = false, allMuted: Bool = false, anySound: Bool = false, anyInSplit: Bool = false) {
            self.count = count
            self.anyPinned = anyPinned
            self.allMuted = allMuted
            self.anySound = anySound
            self.anyInSplit = anyInSplit
        }
    }

    public static func shows(_ id: String, for picks: Picks) -> Bool {
        switch id {
        case "changeIcon", "mute", "duplicate", "archiveBelow": !picks.anyPinned
        case "openInSplitView": (2...maxPanes).contains(picks.count) && !picks.anyInSplit
        default: true
        }
    }

    /// Arc dims Change Icon… and Archive Tabs Below for several tabs, and Mute with nothing to mute.
    public static func isEnabled(_ id: String, for picks: Picks) -> Bool {
        switch id {
        case "changeIcon", "archiveBelow": false
        case "mute": picks.anySound || picks.allMuted
        default: true
        }
    }

    public static func title(_ id: String, for picks: Picks) -> String {
        let n = picks.count
        return switch id {
        case "copyLinks": "Copy Links"
        case "share": "Share \(n) Items…"
        case "changeIcon": "Change Icon…"
        case "mute": picks.allMuted ? "Unmute" : "Mute"
        case "openInSplitView": "Open in Split View"
        case "duplicate": "Duplicate"
        case "moveTo": "Move to"
        case "newFolder": "New Folder with \(n) Items"
        case "archive": picks.anyPinned ? "Archive Items" : "Archive Tabs"
        case "archiveBelow": "Archive Tabs Below"
        default: id
        }
    }

    /// The rows that show, in sections, as the menu draws them.
    public static func shown(for picks: Picks) -> [[String]] {
        sections.map { $0.filter { shows($0, for: picks) } }.filter { !$0.isEmpty }
    }
}
