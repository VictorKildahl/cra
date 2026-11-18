import CoreGraphics
import Foundation

/// What the iPhone app's swipes decide when the finger lifts.
public enum MobileSwipe {
    /// A drag commits once it has gone this share of the screen's width...
    public static let commitFraction: CGFloat = 0.35
    /// ...or is moving this fast (points a second) after at least `flickDistance`.
    public static let flickVelocity: CGFloat = 500
    public static let flickDistance: CGFloat = 30

    /// -1 for a committed drag to the left, 1 to the right, 0 when it falls back.
    public static func direction(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Int {
        let far = abs(translation) > width * commitFraction
        let flicked = abs(translation) > flickDistance && abs(velocity) > flickVelocity && translation * velocity > 0
        guard far || flicked else { return 0 }
        return translation > 0 ? 1 : -1
    }

    /// A swipe along the bottom bar moves between tabs as the tab row has them: a drag to the
    /// right brings the older tab in from the left, a drag to the left the newer one. Returns the
    /// step in the row (-1 older, 1 newer, 0 stay).
    public static func tabStep(translation: CGFloat, velocity: CGFloat, width: CGFloat, hasOlder: Bool, hasNewer: Bool) -> Int {
        switch direction(translation: translation, velocity: velocity, width: width) {
        case 1: return hasOlder ? -1 : 0
        case -1: return hasNewer ? 1 : 0
        default: return 0
        }
    }

    /// A drag up that starts on the tab button brings the previous tab (`MobileTabsDocument.previousTab`)
    /// out of the button under the finger (#537). Its card is the whole page at this share of
    /// the way: a 500 pt drag would get there, so mid-screen it is about half grown, as in Arc Search.
    public static func previousTabProgress(dragUp distance: CGFloat) -> CGFloat {
        min(1, max(0, distance / 500))
    }

    /// Whether letting go of that drag switches: far enough or flicked upwards, and not being
    /// pulled back down.
    public static func switchesToPreviousTab(dragUp distance: CGFloat, velocityUp: CGFloat) -> Bool {
        guard velocityUp > -200 else { return false }
        return distance > 90 || (distance > 20 && velocityUp > 500)
    }

    public enum Navigation: Equatable {
        case none, back, forward
        /// Back on a tab's first page: the tab goes to the archive and the one before it shows.
        case archiveTab
        /// Forward with nowhere to go, right after that: the archived tab comes back.
        case reopenTab
    }

    /// A swipe across the page: right is back, left is forward.
    public static func navigation(translation: CGFloat, velocity: CGFloat, width: CGFloat, canGoBack: Bool, canGoForward: Bool,
                                  hasOtherTab: Bool, canReopenTab: Bool) -> Navigation {
        switch direction(translation: translation, velocity: velocity, width: width) {
        case 1: return canGoBack ? .back : hasOtherTab ? .archiveTab : .none
        case -1: return canGoForward ? .forward : canReopenTab ? .reopenTab : .none
        default: return .none
        }
    }

    /// Whether a swipe across the page may start at `x` in a page `width` wide.
    public static func mayStart(at x: CGFloat, width: CGFloat, mode: MobileSwipeToNavigate) -> Bool {
        mode == .fromAnywhere || x < 24 || x > width - 24
    }

    /// How far the page must be pulled down, and held there at release, to reload.
    public static let pullToRefreshDistance: CGFloat = 96

    /// Pull to refresh acts on release, so dragging back up before letting go cancels it.
    public static func refreshes(pullAtRelease: CGFloat) -> Bool {
        pullAtRelease >= pullToRefreshDistance
    }
}
