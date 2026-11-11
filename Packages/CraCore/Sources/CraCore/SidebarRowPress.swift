import Foundation

/// Arc's press in the sidebar, read from Arc 1.172.1's binary on 11 Nov 2026. A tab, split or
/// New Tab row (SidebarBouncyClickCell, `performBounceAnimation(isPressedIn:)`) pushes in to
/// 99.2 % about its centre while the button is down and springs back on release; folders and the
/// other rows don't. A tab or split row pushes in on the first press of a click only, so the
/// second press of a double-click doesn't dip again; the New Tab row pushes in on every press.
/// A Favorites tile (AppTrayItemViewAppKit, `isPressed`) pushes in further, to 99 %, on every
/// press, with the same spring.
public enum SidebarRowPress {
    public enum Row: Sendable {
        case tab, split, newTab, favorite, other
    }

    /// The scale a pressed row holds (CATransform3DMakeScale(0.992, 0.992, 1); a tile 0.99).
    public static func scale(_ row: Row) -> Double { row == .favorite ? 0.99 : 0.992 }
    /// Arc's spring both ways: damping ratio 0.5, response 0.2 s, mass 1. Underdamped, so it
    /// overshoots a little on the way in and on the way back.
    public static let dampingRatio = 0.5
    public static let response = 0.2
    public static var stiffness: Double { pow(2 * .pi / response, 2) }
    public static var damping: Double { 4 * .pi * dampingRatio / response }

    /// Whether a mouse-down on `row` pushes it in. `clickCount` is AppKit's.
    public static func pushesIn(_ row: Row, clickCount: Int) -> Bool {
        switch row {
        case .tab, .split: return clickCount == 1
        case .newTab, .favorite: return true
        case .other: return false
        }
    }
}
