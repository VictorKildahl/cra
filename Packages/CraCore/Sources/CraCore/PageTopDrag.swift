import Foundation

/// Arc's Settings ▸ Advanced "Allow window dragging from the top of webpages" (on by default; Arc
/// 1.172.1, measured with real drags on 7 Nov 2026): with the toolbar hidden, a drag that starts in
/// the top 56 pt of the page moves the window (58 pt in it no longer does). Arc's WindowContentGrabber
/// only takes drags with the ordinary arrow cursor; the page receives the press immediately.
public enum PageTopDrag {
    /// How far into the page the band reaches (Arc: 56 pt drags, 58 pt doesn't).
    public static let band: Double = 56
    /// How much of the page's right edge stays out of the band, for the scrollbar (Arc's grabber is
    /// the content's width less 14 pt).
    public static let trailingInset: Double = 14
    /// How far the pointer moves before a press is a drag (AppKit's and Cra's window-drag slop).
    public static let slop: Double = 3

    /// Whether a press can start a window drag: a plain single left click in the
    /// band of a page that has no bar above it, with the setting on.
    public static func holds(enabled: Bool, barAbovePage: Bool, depthIntoPage: Double, clickCount: Int, modifiers: Bool,
                             distanceFromRight: Double = .infinity) -> Bool {
        enabled && !barAbovePage && clickCount == 1 && !modifiers
            && depthIntoPage >= 0 && depthIntoPage < band && distanceFromRight > trailingInset
    }

    /// Whether the pointer has moved far enough from the press to move the window.
    public static func isDrag(dx: Double, dy: Double) -> Bool { (dx * dx + dy * dy).squareRoot() > slop }
}
