import CoreGraphics
import Foundation

/// Arc's Library ▸ Easels tile under the pointer (Arc 1.173.1, a 120 Hz screen recording read
/// frame by frame at 2x, 17 Nov 2026): the tile grows about its centre from 257.2 to 272.6 px
/// (128.6 to 136.3 pt, × 1.06) in a tenth of a second, fast first with no overshoot, and its
/// backing brightens with it. It goes back the same way when the pointer leaves. The edges
/// were read at half height, which leaves about ± 0.5 px: 1.06 fits, 1.0625 nearly does.
public enum EaselTileHover {
    public static let scale: CGFloat = 1.06
    public static let duration: Double = 0.1
    /// The tile's backing, the space's ink at this alpha: Arc's backing stands twice as far from
    /// the sidebar under the pointer as at rest.
    public static let restFill: CGFloat = 0.04
    public static let hoverFill: CGFloat = 0.08

    public static func scale(hovering: Bool) -> CGFloat { hovering ? scale : 1 }
    public static func fill(hovering: Bool) -> CGFloat { hovering ? hoverFill : restFill }

    /// How far a grown tile of that side reaches past its frame, a point to spare: the room the
    /// list leaves above its first row.
    public static func overhang(side: CGFloat) -> CGFloat { (side * (scale - 1) / 2).rounded(.up) + 1 }

    /// Where the tile is drawn: its own frame, or that frame grown about its centre.
    public static func frame(_ rect: CGRect, hovering: Bool) -> CGRect {
        let s = scale(hovering: hovering)
        return rect.insetBy(dx: -rect.width * (s - 1) / 2, dy: -rect.height * (s - 1) / 2)
    }
}
