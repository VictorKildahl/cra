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

    /// Arc skips the second press of a double-click on tabs and splits only.
    public static func pushesIn(_ row: Row, clickCount: Int) -> Bool {
        switch row {
        case .tab, .split: return clickCount == 1
        case .newTab, .favorite: return true
        case .other: return false
        }
    }
}
