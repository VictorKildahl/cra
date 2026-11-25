import CoreGraphics
import Foundation

/// The ring that fills as a page is pulled down to reload: it sits in the status band and stays
/// put while the page comes down under it, so the band's bottom is the page's top.
public enum MobilePullRing {
    /// The ring's side: small phones keep a 20 pt ring, a Dynamic Island or notch adds the room
    /// under it, and 28 pt is as large as it gets.
    public static func side(safeTop: CGFloat) -> CGFloat {
        min(28, max(20, safeTop - 32))
    }

    /// The ring's middle, in the screen's coordinates: centred, and low enough in the band that
    /// the whole ring shows below the time and the island.
    public static func center(safeTop: CGFloat, screenWidth: CGFloat) -> CGPoint {
        CGPoint(x: screenWidth / 2, y: safeTop + side(safeTop: safeTop) / 2 + 8)
    }

    /// How much of the ring the pull has drawn, 0 at the page's top to 1 at the refresh line.
    public static func progress(pull: CGFloat) -> CGFloat {
        guard pull.isFinite else { return 0 }
        return min(1, max(0, pull / MobileSwipe.pullToRefreshDistance))
    }

    /// The ring's ink, as hex: the status bar's own, white over a dark band and dark grey over a
    /// light one. With no band (`statusBarFill` nil) the bar follows the system's appearance.
    public static func ink(statusBarFill: String?, darkMode: Bool) -> String {
        let light = statusBarFill.map(MobileStatusBand.lightContent(fill:)) ?? darkMode
        return light ? "#FFFFFF" : "#404040"
    }

    // MARK: The bump at the line

    /// The spring of the solid second lap that starts over the ring's seam at the refresh line.
    public struct Bump: Equatable, Sendable {
        /// The lap's length a quarter of the way through, in radians. The decay makes the first
        /// swing longest a little before then: up to twice this for a slow pull.
        public let peak: CGFloat
        /// How quickly the later swings die away: a slow pull's at once, a fast one's swings again.
        public let decay: CGFloat
    }

    /// How long the bump lasts.
    public static let bumpDuration: TimeInterval = 0.25

    /// The bump for a pull that reached the line at `speed` points a second: a `peak` of 1° for a
    /// slow pull, up to 30° from 2000 pt/s, the faster the bouncier.
    public static func bump(speed: CGFloat) -> Bump {
        let fast = speed.isFinite ? min(1, max(0, speed) / 2000) : 0
        return Bump(peak: (1 + 29 * fast) * .pi / 180, decay: 8 - 5 * fast)
    }

    /// The second lap's length, in radians, `t` (0...1) through the bump: it swings out and back
    /// twice, the second swing smaller, and ends at rest.
    public static func lap(_ bump: Bump, at t: CGFloat) -> CGFloat {
        let t = min(1, max(0, t))
        return bump.peak * exp(-bump.decay * (t - 0.25)) * abs(sin(2 * .pi * t))
    }

    // MARK: Letting go

    /// A pull that reached the line: the second lap's end turns this far as the ring fades.
    public static let successTurn: CGFloat = .pi * 0.6
    /// How long the ring takes to fade after a full pull.
    public static let successDuration: TimeInterval = 0.3
    /// How long a short pull's ring takes to unwind back to the top.
    public static let retractDuration: TimeInterval = 0.3
}
