import Foundation

/// Arc's Settings ▸ Advanced "Allow window dragging from the top of webpages" (on by default; Arc
/// 1.172.1, measured with real drags on 7 Nov 2026): with the toolbar hidden, a drag that starts in
/// the top 56 pt of the page moves the window (58 pt in it no longer does). A press there waits: if
/// the pointer moves past the drag slop the window moves; if it lifts first, the page gets the click.
public enum PageTopDrag {
    /// How far into the page the band reaches (Arc: 56 pt drags, 58 pt doesn't).
    public static let band: Double = 56
    /// How far the pointer moves before a press is a drag (AppKit's and Cra's window-drag slop).
    public static let slop: Double = 3

    /// Whether a press is held back as a possible window drag: a plain single left click in the
    /// band of a page that has no bar above it, with the setting on.
    public static func holds(enabled: Bool, barAbovePage: Bool, depthIntoPage: Double, clickCount: Int, modifiers: Bool) -> Bool {
        enabled && !barAbovePage && clickCount == 1 && !modifiers && depthIntoPage >= 0 && depthIntoPage < band
    }

    /// Whether the pointer has moved far enough from the press to move the window.
    public static func isDrag(dx: Double, dy: Double) -> Bool { (dx * dx + dy * dy).squareRoot() > slop }
}
