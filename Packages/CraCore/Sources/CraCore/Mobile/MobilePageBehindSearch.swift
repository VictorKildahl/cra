import CoreGraphics
import Foundation

/// How the page sits behind the search sheet: pushed back as a card whose top edge is under the
/// status bar. The status band shrinks to nothing above it, so the card's rounded top hugs the
/// page's content.
public enum MobilePageBehindSearch {
    /// The card's distance from each side of the screen.
    public static let sideInset: CGFloat = 10
    /// The card's rounded top, half the device's own corner.
    public static let cornerRadius: CGFloat = 22
    /// How dark the page gets: black at 0.2 over it, which turns a white page #cccccc as in the
    /// TidBITS screenshot.
    public static let dim: CGFloat = 0.2

    /// The page's scale and its shift down, for a screen of `size` whose status bar ends at `safeTop`:
    /// the card's top edge sits right under the status bar.
    public static func transform(in size: CGSize, safeTop: CGFloat) -> (scale: CGFloat, shiftDown: CGFloat) {
        guard size.width > 0 else { return (1, 0) }
        let scale = (size.width - 2 * sideInset) / size.width
        return (scale, safeTop - size.height * (1 - scale) / 2)
    }

    /// The same, `progress` of the way from the page as it is (0) to the card (1): the page
    /// follows the search drawer, its top from the screen's edge to under the status bar.
    public static func transform(in size: CGSize, safeTop: CGFloat, progress: CGFloat)
        -> (scale: CGFloat, shiftDown: CGFloat) {
        guard size.width > 0 else { return (1, 0) }
        let final = transform(in: size, safeTop: safeTop)
        let p = min(1, max(0, progress))
        return (1 + (final.scale - 1) * p, final.shiftDown * p)
    }
}
