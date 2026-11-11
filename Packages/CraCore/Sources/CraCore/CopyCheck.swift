import CoreGraphics
import Foundation

/// Arc's confirmation on the Copy URL glyph (GitHub #361), measured on Arc 1.172.2 (11 Nov 2026) at
/// ~115 fps, on the toolbar's 12 pt "Copy Current URL" glyph and the sidebar URL field's 14 pt Copy
/// Link: the link shrinks away, a checkmark draws itself in, holds, un-draws, and the link springs
/// back. Only a click on that glyph plays it. ⇧⌘C, Edit ▸ Copy URL, a Little Arc's link icon and the
/// developer bar's Copy Link leave the glyph alone, and every one of them (the glyph too) shows the
/// "Copied Current URL" toast. Times are seconds from the click.
public enum CopyCheck {
    /// The link fades and shrinks to `linkOutScale` about its centre, easing in.
    public static let linkOutDuration: TimeInterval = 0.11
    public static let linkOutScale: CGFloat = 0.3

    /// The checkmark's stroke draws from the short leg's end to the long leg's tip while it fades in.
    public static let checkInStart: TimeInterval = 0.17
    public static let checkDrawDuration: TimeInterval = 0.15
    public static let checkFadeInDuration: TimeInterval = 0.21

    /// Fully drawn, it stays until `holdUntil`, then un-draws back to `checkOutEnd` of its length
    /// (the short leg), easing in and out.
    public static let holdUntil: TimeInterval = 1.10
    public static let checkUndrawDuration: TimeInterval = 0.16
    public static let checkOutEnd: CGFloat = 0.3

    /// The link comes back from `linkInScale` on an underdamped spring (peak ~1.15 at +0.125 s,
    /// settled by ~+0.45 s) while that short leg fades out.
    public static let linkInStart: TimeInterval = 1.25
    public static let linkInScale: CGFloat = 0.5
    public static let linkInFadeDuration: TimeInterval = 0.06
    public static let springStiffness: CGFloat = 724
    public static let springDamping: CGFloat = 19.4

    /// The checkmark's ink is a square 0.83 times the link glyph's point size, centred on the glyph,
    /// its stroke 0.15 of that square, round caps and join.
    public static func side(glyphSize: CGFloat) -> CGFloat { glyphSize * 0.83 }
    public static func lineWidth(glyphSize: CGFloat) -> CGFloat { side(glyphSize: glyphSize) * 0.15 }

    /// The stroke's three points relative to the glyph's centre, y growing downwards: the short
    /// leg's end, the vertex, the long leg's tip.
    public static func points(glyphSize: CGFloat) -> [CGPoint] {
        let s = side(glyphSize: glyphSize)
        return [CGPoint(x: -0.425 * s, y: 0.075 * s), CGPoint(x: -0.17 * s, y: 0.425 * s), CGPoint(x: 0.425 * s, y: -0.425 * s)]
    }
}
