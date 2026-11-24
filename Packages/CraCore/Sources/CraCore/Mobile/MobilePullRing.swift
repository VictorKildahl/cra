import CoreGraphics

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
}
