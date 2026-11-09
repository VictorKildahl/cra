import CraCore
import Foundation
import Testing

/// Back on a tab a link opened (GitHub #273, Arc's canNavigateBack and navigateBackToReferrer).
struct BackToReferrerTests {
    private let tab = UUID(), source = UUID()

    /// The reporter's case: a link opened a tab, Back on it closes it and shows the tab it came from.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func backOnTheFirstPageReturnsToTheTabTheLinkCameFrom() {
        #expect(BackToReferrer.step(canGoBack: false, tab: tab, referrer: source, inSplit: false, pinned: false) == .close(returnTo: source))
        #expect(BackToReferrer.canNavigateBack(canGoBack: false, tab: tab, referrer: source, inSplit: false, pinned: false))
    }

    /// Pages the tab went on to come first: Back walks them, as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func theTabsOwnHistoryComesFirst() {
        #expect(BackToReferrer.step(canGoBack: true, tab: tab, referrer: source, inSplit: false, pinned: false) == .history)
        #expect(BackToReferrer.step(canGoBack: true, tab: tab, referrer: nil, inSplit: true, pinned: true) == .history)
    }

    /// Nowhere to return to, or a tab Back shouldn't close: a split's pane, a pinned tab.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func backStaysOffWithNothingToReturnTo() {
        #expect(BackToReferrer.step(canGoBack: false, tab: tab, referrer: nil, inSplit: false, pinned: false) == .none)
        #expect(BackToReferrer.step(canGoBack: false, tab: tab, referrer: tab, inSplit: false, pinned: false) == .none)
        #expect(BackToReferrer.step(canGoBack: false, tab: tab, referrer: source, inSplit: true, pinned: false) == .none)
        #expect(BackToReferrer.step(canGoBack: false, tab: tab, referrer: source, inSplit: false, pinned: true) == .none)
        #expect(!BackToReferrer.canNavigateBack(canGoBack: false, tab: tab, referrer: nil, inSplit: false, pinned: false))
    }
}
