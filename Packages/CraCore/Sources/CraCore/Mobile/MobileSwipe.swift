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

    /// What a drag on the bottom bar does, decided as it starts.
    public enum BarDrag: Equatable {
        /// Along the bar: the neighbouring tab in the row.
        case neighbour
        /// Upwards: the tab row.
        case tabRow
        /// Upwards from the tab button's zone (`MobileBottomBar.previousTabZone`): the tab
        /// looked at before this one (#537).
        case previousTab
        /// Upwards from the pill (`MobileBottomBar.searchPullZone`): the search sheet, pulled
        /// out under the finger (#623).
        case searchSheet
    }

    /// Sideways goes to the neighbouring tab and upwards opens the tab row. From the tab
    /// button's zone, upwards brings the previous tab, and a thumb's flick that leans towards
    /// the middle of the screen still counts as upwards: anything steeper than a third of the
    /// way up from flat, since a swipe along the bar is close to flat.
    public static func barDrag(velocity: CGPoint, startsInPreviousTabZone: Bool, hasPreviousTab: Bool,
                               startsInSearchPullZone: Bool = false) -> BarDrag {
        let up = -velocity.y
        if startsInPreviousTabZone, hasPreviousTab, up > 0, abs(velocity.x) <= 1.5 * up { return .previousTab }
        if startsInSearchPullZone, up > abs(velocity.x) { return .searchSheet }
        return abs(velocity.y) > abs(velocity.x) ? .tabRow : .neighbour
    }

    /// The search sheet pulled up out of the pill (#623) follows the finger; a pull of this
    /// many points has it fully out, its field grown from the pill.
    public static let searchPullSpan: CGFloat = 260

    /// How far out the pulled sheet is, 0 in the bar to 1 open.
    public static func searchPullProgress(dragUp distance: CGFloat) -> CGFloat {
        min(1, max(0, distance / searchPullSpan))
    }

    /// Whether letting go of the pull opens the sheet: far enough, or flicked upwards, and not
    /// being pulled back down. Otherwise it sinks back into the pill.
    public static func searchPullOpens(dragUp distance: CGFloat, velocityUp: CGFloat) -> Bool {
        guard velocityUp > -200 else { return false }
        return distance > 90 || (distance > 20 && velocityUp > 500)
    }

    /// Whether a drag down on the open search sheet takes the sheet down with it (#623): from
    /// anywhere on it, the suggestions included, unless they are scrolled down and the drag
    /// should scroll them back first.
    public static func sheetDragStarts(velocity: CGPoint, onList: Bool, listOffset: CGFloat) -> Bool {
        guard velocity.y > abs(velocity.x) else { return false }
        return !onList || listOffset <= 0.5
    }

    /// The open sheet dragged down goes back the way a pull brought it up (#655): the keyboard goes as the drag
    /// starts and the sheet's top stays under the finger, this far above the bar (`searchPull`), its field shrinking
    /// back into the pill. Before, the sheet slid down under the keyboard, out of sight until the finger lifted.
    /// `startPull` is how far above the bar the sheet's top was when the drag started.
    public static func sheetDragDownPull(startPull: CGFloat, dragDown: CGFloat) -> CGFloat {
        max(0, startPull - dragDown)
    }

    /// Whether letting go of that drag puts the sheet away: dragged far enough down, or flicked down. Otherwise it
    /// rises back open with the keyboard.
    public static func sheetDragDownCloses(dragDown: CGFloat, velocityDown: CGFloat) -> Bool {
        dragDown > 70 || velocityDown > 700
    }

    /// Whether the sheet is out of sight under the keyboard: its top at or below the keyboard's.
    /// `keyboardTop` is nil with no keyboard up.
    public static func sheetUnderKeyboard(sheetTop: CGFloat, keyboardTop: CGFloat?) -> Bool {
        keyboardTop.map { sheetTop >= $0 - 1 } ?? false
    }

    /// A drag up that starts on the tab button brings the previous tab (`MobileTabsDocument.previousTab`)
    /// out of the button under the finger (#537). Its card is the whole page at this share of
    /// the way: a 500 pt drag would get there, so mid-screen it is about half grown, as in Arc Search.
    public static func previousTabProgress(dragUp distance: CGFloat, to startY: CGFloat = 400) -> CGFloat {
        min(1, max(0, distance / max(startY, 1)))
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
        mode == .fromAnywhere || startsAtEdge(x, width: width)
    }

    /// The strip along each side where a swipe is always Back or Forward.
    static func startsAtEdge(_ x: CGFloat, width: CGFloat) -> Bool {
        x < 24 || x > width - 24
    }

    /// How far a scroll view can still move its content sideways: `left` towards the content's
    /// left end (what a finger moving right does), `right` towards its right end.
    public struct ScrollRoom: Equatable, Sendable {
        public var left: CGFloat
        public var right: CGFloat

        public init(left: CGFloat, right: CGFloat) {
            self.left = left
            self.right = right
        }

        /// From a scroll view's numbers: its offset, the content's width, its own width and the
        /// insets it adds on either side.
        public init(offsetX: CGFloat, contentWidth: CGFloat, width: CGFloat, insetLeft: CGFloat = 0, insetRight: CGFloat = 0) {
            left = max(0, offsetX + insetLeft)
            right = max(0, contentWidth + insetRight - width - offsetX)
        }
    }

    /// Whether a drag across a page goes Back or Forward, decided as it starts. Only a one-finger
    /// drag that is clearly sideways does: two fingers are a pinch, and the page zooms (#628).
    /// It also leaves the drag to the page wherever something under the finger can still scroll
    /// that way, such as a carousel, a wide table or the page itself when zoomed in (#627), so
    /// that only its end goes on to navigate. A drag from the screen's edge always navigates.
    /// `scrollers` are the scroll views under the finger, `velocity` the finger's as it starts.
    public static func pageSwipeStarts(at x: CGFloat, width: CGFloat, mode: MobileSwipeToNavigate, touches: Int,
                                       velocity: CGPoint, scrollers: [ScrollRoom]) -> Bool {
        guard touches == 1, abs(velocity.x) > 1.5 * abs(velocity.y), mayStart(at: x, width: width, mode: mode) else { return false }
        if startsAtEdge(x, width: width) { return true }
        // A finger moving right pulls content in from the left.
        let scrolls = scrollers.contains { velocity.x > 0 ? $0.left > 0.5 : $0.right > 0.5 }
        return !scrolls
    }

    /// How far the page must be pulled down, and held there at release, to reload.
    public static let pullToRefreshDistance: CGFloat = 128

    /// Pull to refresh acts on release, so dragging back up before letting go cancels it.
    public static func refreshes(pullAtRelease: CGFloat) -> Bool {
        pullAtRelease >= pullToRefreshDistance
    }

    /// Whether pushing a pull back to the top hands the rest of the drag to the page's own
    /// scrolling, rather than waiting for the finger to lift first.
    public static func pullHandsOff(pull: CGFloat) -> Bool {
        pull <= 0
    }
}
