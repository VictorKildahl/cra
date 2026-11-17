import Foundation

/// Back on a tab a link opened (GitHub #273). Arc keeps the tab the link came from as the new
/// tab's `referrerID`; its toolbar enables Back on `canNavigateBack` rather than the page's own
/// `canGoBack`, and a Back with no page left behind closes the tab (close reason
/// `navigateBackToReferrer`) and shows the one it came from.
///
/// Arc saves the referrer with the tab (TabData.referrerID) and the page's history with it
/// (PageHistory), so after a relaunch Back still steps through the pages and then closes the tab.
public enum BackToReferrer {
    public enum Step: Equatable {
        /// The page goes back in its own history.
        case history
        /// The tab closes and the tab it was opened from is shown.
        case close(returnTo: UUID)
        /// Nothing to go back to.
        case none
    }

    /// - Parameters:
    ///   - canGoBack: the page has an entry behind the current one.
    ///   - referrer: the tab the link was clicked in, while that tab is still in the sidebar.
    ///   - tab: the tab Back was pressed on.
    ///   - inSplit: the tab is a pane of a split; closing a pane isn't what Back means there.
    ///   - pinned: the tab is pinned or a favorite; closing one unloads it and resets its page.
    public static func step(canGoBack: Bool, tab: UUID, referrer: UUID?, inSplit: Bool, pinned: Bool) -> Step {
        if canGoBack { return .history }
        guard let referrer, referrer != tab, !inSplit, !pinned else { return .none }
        return .close(returnTo: referrer)
    }

    /// Whether Back is enabled (Arc: `canNavigateBack`).
    public static func canNavigateBack(canGoBack: Bool, tab: UUID, referrer: UUID?, inSplit: Bool, pinned: Bool) -> Bool {
        step(canGoBack: canGoBack, tab: tab, referrer: referrer, inSplit: inSplit, pinned: pinned) != .none
    }

    /// A two-finger swipe back over the page, or a Magic Mouse's (GitHub #370). Chromium's history
    /// swipe starts only when the page itself can go back (`canNavigateInDirection:onWindow:`,
    /// `pageCanGoBack`) and then moves the page, so on a tab a link opened it never started. Arc's
    /// Chromium asks the app when the page can't (`WebContentsUIDelegate::CanExternallyNavigate`,
    /// then `WillExternallyNavigate`), and the swipe does what Back does: `.none` means no swipe,
    /// `.history` leaves it to Chromium, `.close` closes the tab to its referrer. The mouse's back
    /// button doesn't ask: it stays the page's own history, in Arc and in Cra.
    public static func swipeBack(pageCanGoBack: Bool, tab: UUID, referrer: UUID?, inSplit: Bool, pinned: Bool) -> Step {
        step(canGoBack: pageCanGoBack, tab: tab, referrer: referrer, inSplit: inSplit, pinned: pinned)
    }
}

/// Back in a Little Window, and a two-finger swipe back over its page (GitHub #495). A Little Window
/// is one page that came from somewhere else, so Arc treats it as a link's tab: when the page has
/// nothing behind it, Back, and the swipe that goes where Back goes (CanExternallyNavigate), close
/// the window. A Peek keeps its page's own history only; Escape and its close button end it.
public enum LittleWindowBack {
    public enum Step: Equatable {
        /// The page goes back in its own history.
        case history
        /// The window closes (its page is archived, as any close of it does).
        case close
        /// Nothing to go back to.
        case none
    }

    /// - Parameters:
    ///   - pageCanGoBack: the page has an entry behind the current one.
    ///   - hasPage: the window shows a page (not just its command bar, before anything was opened).
    ///   - peek: the window is a Peek over a browser window.
    public static func step(pageCanGoBack: Bool, hasPage: Bool, peek: Bool) -> Step {
        if pageCanGoBack { return .history }
        return hasPage && !peek ? .close : .none
    }
}

/// A two-finger swipe over a Little Window's address bar (GitHub #495, bensk). The bar isn't the
/// page, so Chromium's history swipe never sees it; this one goes where Back and Forward go
/// (Back on the first page closes the window, `LittleWindowBack`) when the fingers let go far enough
/// sideways. A swipe that starts up or down is left alone, and so is one taken back before release.
public struct LittleBarSwipe: Sendable {
    public enum Direction: Equatable, Sendable { case back, forward }

    /// Sideways finger travel (points) a swipe needs when it ends.
    public static let distance: CGFloat = 60
    /// Travel before the swipe decides whether it is sideways (the space swipe's 6 pt and 1.2×).
    static let slop: CGFloat = 6

    enum Axis: Sendable { case idle, undecided, sideways, other }
    private var axis: Axis = .idle
    /// Finger travel since the swipe began, + to the right.
    public private(set) var travelX: CGFloat = 0
    private var travelY: CGFloat = 0

    public init() {}

    /// Two fingers touched (the scroll's `.mayBegin` or `.began`).
    public mutating func begin() {
        axis = .undecided
        travelX = 0
        travelY = 0
    }

    /// One scroll event of the swipe. `inverted` is the event's `isDirectionInvertedFromDevice`
    /// (natural scrolling), which gives the fingers' own direction back: fingers to the right go
    /// back whatever the scroll direction setting, as Chromium's swipe does. Returns whether the
    /// swipe is sideways, so the bar keeps the event.
    public mutating func move(dx: CGFloat, dy: CGFloat, inverted: Bool) -> Bool {
        guard axis == .undecided || axis == .sideways else { return false }
        let sign: CGFloat = inverted ? 1 : -1
        travelX += dx * sign
        travelY += dy * sign
        if axis == .undecided {
            guard max(abs(travelX), abs(travelY)) > Self.slop else { return false }
            axis = abs(travelX) > abs(travelY) * 1.2 ? .sideways : .other
        }
        return axis == .sideways
    }

    /// The fingers let go (`cancelled`: the system took the gesture). Where the swipe goes, if anywhere.
    public mutating func end(cancelled: Bool = false) -> Direction? {
        defer { axis = .idle }
        guard axis == .sideways, !cancelled, abs(travelX) >= Self.distance else { return nil }
        return travelX > 0 ? .back : .forward
    }
}
