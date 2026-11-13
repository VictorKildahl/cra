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

    /// Arc skips the second press of a double-click on tabs and splits only.
    public static func pushesIn(_ row: Row, clickCount: Int) -> Bool {
        switch row {
        case .tab, .split: return clickCount == 1
        case .newTab, .favorite: return true
        case .other: return false
        }
    }
}
