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
}
