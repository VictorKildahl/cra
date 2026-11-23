import CoreGraphics
import Foundation

/// How the page sits behind the search sheet: pushed back as a card, the way Arc Search shows it.
public enum MobilePageBehindSearch {
    /// The card's distance from each side of the screen.
    public static let sideInset: CGFloat = 10
    public static let cornerRadius: CGFloat = 12
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
}
