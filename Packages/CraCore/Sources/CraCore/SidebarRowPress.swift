import Foundation

/// Arc 1.172.1's sidebar press (SidebarBouncyClickCell, AppTrayItemViewAppKit.isPressed); see
/// "Pressing a sidebar row" in docs/arc-reverse-engineering.md.
public enum SidebarRowPress {
    public enum Row: Sendable {
        case tab, split, newTab, favorite, other
    }

    public static func scale(_ row: Row) -> Double { row == .favorite ? 0.99 : 0.992 }
    public static let dampingRatio = 0.5
    public static let response = 0.2
    public static var stiffness: Double { pow(2 * .pi / response, 2) }
    public static var damping: Double { 4 * .pi * dampingRatio / response }

    /// Arc switches tabs on the press, not the release (Arc 1.173.1, 12 Nov 2026, live: 250 ms into
    /// a held press the window already shows the pressed tab, and a press that becomes a drag has
    /// switched too). A ⌘ or ⇧ press (picking), a double-click's second press (rename) and a press
    /// with ⌃ (the menu) still act on the release, as Arc's ⌘-press does.
    public static func selectsOnPress(_ row: Row, clickCount: Int, modified: Bool) -> Bool {
        row == .tab && clickCount == 1 && !modified
    }

    /// What a click on a tab's row does once released (or pressed, for a plain one).
    public enum TabClick: Equatable, Sendable {
        /// ⌘ picks the tab, ⇧ the range up to it.
        case pick(range: Bool)
        case rename
        /// The tab opens in Split View with the open one, as the tab menu's Open in Split View.
        case openInSplit
        case select
    }

    /// ⌥ on a tab other than the open one splits them: Arc's `alternateClick` way into Split View
    /// (SplitViewEnteredSource, docs/arc-reverse-engineering.md), which Cra had not done ("That was a
    /// core Arc thing", #922). `canSplit` is what the menu row needs: a tab open in
    /// the space the row is in, with a page. Otherwise ⌥ is a plain click. ⌘ and ⇧ pick, as before.
    public static func tabClick(command: Bool, shift: Bool, option: Bool, clickCount: Int, isOpen: Bool, canSplit: Bool) -> TabClick {
        if command || shift { return .pick(range: shift) }
        if clickCount == 2 { return .rename }
        if option, clickCount == 1, !isOpen, canSplit { return .openInSplit }
        return .select
    }

    /// Arc skips the second press of a double-click on tabs and splits only.
    public static func pushesIn(_ row: Row, clickCount: Int) -> Bool {
        switch row {
        case .tab, .split: return clickCount == 1
        case .newTab, .favorite: return true
        case .other: return false
        }
    }
}
