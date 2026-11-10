import CoreGraphics

/// What Arc's ⌥⌘N opens when there is nothing to load (1.172.1, 10 Nov 2026, a 1728 × 1117 pt screen):
/// a 490 × 329 pt card at x 1218, y 53, so its right edge is 20 pt from the screen's and its top 20 pt
/// below the menu bar. Enter grows the same window to 1185 × 832 pt in one frame, its top-right corner
/// where it was (x 523 to 1708, y 53; #337).
public enum LittleCard {
    public static let size = CGSize(width: 490, height: 329)
    public static let margin: CGFloat = 20

    /// The card in `visible`, a screen's visible frame (below the menu bar, y up).
    public static func frame(in visible: CGRect) -> CGRect {
        CGRect(x: visible.maxX - margin - size.width, y: visible.maxY - margin - size.height, width: size.width, height: size.height)
    }

    /// The window the card becomes: `size` (kept off the screen's edges), the card's top-right corner fixed.
    public static func grown(from card: CGRect, to size: CGSize, in visible: CGRect) -> CGRect {
        let w = min(size.width, visible.width - 2 * margin), h = min(size.height, visible.height - 2 * margin)
        return CGRect(x: max(visible.minX, card.maxX - w), y: max(visible.minY, card.maxY - h), width: w, height: h)
    }
}
