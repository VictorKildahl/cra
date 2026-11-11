import CoreGraphics
import Foundation

/// Arc's Little Arc as ⌥⌘N opens it: a compact card that is only the command bar, at the top right
/// of the screen. Picking a row turns the same window into the full Little Arc, its top-right corner
/// where the card's was.
///
/// Arc 1.172.1 (build 90370), 10 Nov 2026, ScreenCaptureKit at 120 fps on a 1728 × 1117 pt display
/// (GitHub #337): the card is 490 × 329 pt, 20 pt in from the right edge of the screen and 20 pt
/// below the menu bar. The command bar fills it edge to edge: a 64 pt field row with a 24 pt ✕ tile
/// at its end, a hairline 12 pt in from either side, then the rows. With nothing typed the rows fill
/// the card; typing shrinks the bar to its rows and the window shows below it. Enter on a row sets
/// the window to its full size in one frame, keeping the card's top-right corner. Esc, ⌘W and losing
/// focus fade the card out in 190 ms. Cra's frames are AppKit's (y up).
public enum LittleCard {
    public static let size = CGSize(width: 490, height: 329)
    /// From the visible area's right edge and its top (the menu bar's bottom) to the card's.
    public static let margin: CGFloat = 20
    /// The ✕ tile at the end of the field row: 24 pt with 6 pt corners, 22.5 pt from the card's edge.
    public static let closeSize: CGFloat = 24
    public static let closeRadius: CGFloat = 6
    public static let closeTrailing: CGFloat = 22.5
    /// The hairline under the field row, in from either side of the card.
    public static let dividerInset: CGFloat = 12
    /// The bar's lower corners while it is shorter than the card.
    public static let barBottomRadius: CGFloat = 9
    /// Esc, ⌘W and losing focus fade the card out over this long.
    public static let fadeDuration: TimeInterval = 0.19

    /// The card's frame in a screen's visible area (the screen less the menu bar and the Dock).
    public static func frame(in visible: CGRect) -> CGRect {
        let w = min(size.width, visible.width), h = min(size.height, visible.height)
        let x = max(visible.minX, visible.maxX - margin - w)
        let y = max(visible.minY, visible.maxY - margin - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The full Little Window grown out of `card`: `size` (kept 20 pt inside the visible area, as a
    /// Little Window is), its top-right corner on the card's, moved only as far as the screen needs.
    public static func expanded(from card: CGRect, to size: CGSize, in visible: CGRect) -> CGRect {
        let w = max(0, min(size.width, visible.width - 2 * margin))
        let h = max(0, min(size.height, visible.height - 2 * margin))
        var f = CGRect(x: card.maxX - w, y: card.maxY - h, width: w, height: h)
        f.origin.x = max(visible.minX, min(f.minX, visible.maxX - w))
        f.origin.y = max(visible.minY, min(f.minY, visible.maxY - h))
        return f
    }

    /// The bar in a card: inside the window's rim (`inset`) on three sides, from the top down to
    /// `height` or the card's bottom rim, whichever comes first. `fills` when it reaches the bottom,
    /// where its lower corners follow the window's.
    public static func barFrame(height: CGFloat, in card: CGRect, inset: CGFloat) -> (frame: CGRect, fills: Bool) {
        let room = max(0, card.height - 2 * inset)
        let h = min(height, room)
        let frame = CGRect(x: card.minX + inset, y: card.maxY - inset - h, width: max(0, card.width - 2 * inset), height: h)
        return (frame, height >= room)
    }
}
