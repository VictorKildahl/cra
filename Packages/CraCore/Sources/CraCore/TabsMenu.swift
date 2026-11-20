import Foundation

/// The head of the menu bar's Tabs menu and its "Open in <space>" row, as Arc 1.172.2 has them
/// (read over Accessibility in Victor's Arc, with and without a Little Arc in front, plus a capture
/// of the open menu, 11 Nov 2026):
///
///     New Tab…  ⌘T
///     Pin Tab  ⌘D
///     🧑‍🌾 Open in Victor  ⌘O     ← only while a Little Arc or Peek is in front
///     New Folder…
///
/// Arc's MainMenu.nib names the row "Open Little Arc or Peek in" (`openTabIn`), which is also its
/// name in Settings ▸ Shortcuts. In the menu it reads "Open in" and the space the Little Arc's own
/// "Open in <space> ⌘O" button names, with that space's icon, and moves the page there straight
/// away (no space picker: that is ⇧⌘O). It is not in the Window menu, and with no Little Arc in
/// front it is gone from the menu altogether.
///
/// The rest of the menu is Arc 1.173.1's too (read over Accessibility, 19 Nov 2026, GitHub #622),
/// three groups with a divider between them:
///
///     New Tab…, Pin Tab, (Open in <space>), New Folder…
///     ──
///     Next Tab, Previous Tab, Reveal Tab in Sidebar
///     ──
///     Clear Today, Reset all tabs in this Space
///
/// Arc has no Go to Tab rows, not even hidden ones: ⌘1–⌘9 work without a row. Cra's menu bar
/// carries the shortcuts of the actions it shows, so the Tabs actions that had rows before stay in
/// the menu as hidden rows (`hidden`).
public enum TabsMenu {
    /// Rows are key-action identifiers.
    public static let head = ["newTab", "pinTab", openIn, "newFolder"]

    /// The rows the menu draws, in Arc's groups.
    public static let sections: [[String]] = [
        head,
        ["nextTab", "previousTab", "revealTab"],
        ["clearToday", "resetSpaceTabs"],
    ]

    /// The Tabs actions that had rows in Cra's menu and that Arc keeps out of its own. They stay as
    /// hidden rows, so their shortcuts (⌃⇥, ⌘1–⌘9 and any set in Settings ▸ Shortcuts) still reach them
    /// through the menu bar. Other Tabs actions, such as the all-spaces recent tab, never had a row:
    /// the shortcut registry reaches them directly.
    public static let hidden = ["recentTab", "favoriteTab", "renameTab", "duplicateTab", "resetTab", "muteTab"]
        + (1...9).map { "item\($0)" }

    /// The "Open in <space>" row's action.
    public static let openIn = "promoteLittleWindow"

    /// Its name in Settings ▸ Shortcuts (Arc: "Open Little Arc or Peek in…").
    public static let openInName = "Open Little Window or Peek in…"

    /// Its title in the menu: the space the page would go to.
    public static func openInTitle(space: String) -> String { "Open in \(space)" }

    /// The row shows only while a Little Window or Peek with a page is in front.
    public static func showsOpenIn(littleWindowWithPage: Bool) -> Bool { littleWindowWithPage }
}

/// Whether the visible Tabs rows can act, and what Pin Tab says (GitHub #622). A row is enabled only
/// when choosing it would do something, and its shortcut follows the same answer, so a dimmed row's
/// key does nothing either. Arc leaves Next Tab, Clear Today and others enabled with nothing to act
/// on; Cra dims them. Only the rows in `decided` are worked out here: the hidden extras and
/// Open in <space> keep their own checks.
extension TabsMenu {
    /// What the focused browser window shows, for its focused space only.
    public struct Facts: Equatable, Sendable {
        public enum Selection: Equatable, Sendable { case none, today, pinned, favorite }
        public enum Window: Equatable, Sendable { case normal, blank, incognito }

        /// The selected tab and where it lives (a tab in a folder or split counts where its row is).
        public var selection: Selection
        /// The tabs Next and Previous Tab step through: Favorites, pinned and Today, with folders'
        /// and splits' tabs. The rules only look at 0, 1 and more, so the app counts no further than 2.
        public var tabs: Int
        /// Clear Today would archive something (TodayClear: selected and playing rows stay whole).
        public var clearableToday: Bool
        /// A tab in the pinned section (folders included, Favorites not) is away from its saved page.
        public var resettablePinned: Bool
        public var window: Window
        /// A Little Window or Peek has the keyboard; it takes these commands and does nothing.
        public var littleWindowInFront: Bool
        /// The Create a Space page covers the space it was opened from: nothing acts on that space
        /// behind it (Next Tab would change its selection unseen).
        public var makingSpace: Bool

        public init(selection: Selection = .none, tabs: Int = 0, clearableToday: Bool = false,
                    resettablePinned: Bool = false, window: Window = .normal, littleWindowInFront: Bool = false,
                    makingSpace: Bool = false) {
            self.selection = selection
            self.tabs = tabs
            self.clearableToday = clearableToday
            self.resettablePinned = resettablePinned
            self.window = window
            self.littleWindowInFront = littleWindowInFront
            self.makingSpace = makingSpace
        }
    }

    /// A row's state: whether it can act, and its title where the rule sets one.
    public struct RowState: Equatable, Sendable {
        public let enabled: Bool
        public let title: String?
        public init(enabled: Bool, title: String? = nil) { (self.enabled, self.title) = (enabled, title) }
    }

    /// The rows worked out here.
    public static let decided: Set<String> = ["newTab", "pinTab", "newFolder", "nextTab", "previousTab", "revealTab",
                                              "clearToday", "resetSpaceTabs"]

    public static func decides(_ id: String) -> Bool { decided.contains(id) }

    public static func state(of id: String, _ f: Facts) -> RowState {
        // The browser window's space is in front: no Little Window or Peek, no Create a Space page.
        let tabWindow = !f.littleWindowInFront && !f.makingSpace
        switch id {
        case "newTab":
            return RowState(enabled: true)
        case "pinTab":
            // A Favorite comes out of Favorites with ⌘D, as a pinned tab comes out of Pinned.
            let unpins = f.selection == .pinned || f.selection == .favorite
            return RowState(enabled: tabWindow && f.selection != .none && f.window != .blank,
                            title: unpins ? "Unpin Tab" : "Pin Tab")
        case "newFolder":
            return RowState(enabled: f.window != .blank && !f.makingSpace)
        case "nextTab", "previousTab":
            // Somewhere to go: any tab with none selected, another tab with one selected.
            let elsewhere = f.selection == .none ? f.tabs > 0 : f.tabs > 1
            return RowState(enabled: tabWindow && elsewhere)
        case "revealTab":
            return RowState(enabled: tabWindow && f.selection != .none)
        case "clearToday":
            return RowState(enabled: tabWindow && f.clearableToday)
        case "resetSpaceTabs":
            return RowState(enabled: tabWindow && f.window == .normal && f.resettablePinned)
        default:
            return RowState(enabled: true)
        }
    }
}
