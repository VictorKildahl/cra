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

/// A two-finger swipe back over the page (GitHub #370): Chromium's history swipe only started
/// when the page had history of its own, so on a tab a link opened the Back button closed the
/// tab and the swipe did nothing. Arc's Chromium asks the app then (canExternallyNavigate), and
/// the swipe does what Back does.
struct SwipeBackTests {
    private let tab = UUID(), source = UUID()

    /// The reporter's case: a link opened a tab; swiping back closes it and shows the tab it came from.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/370"))
    func swipingBackOnALinksTabClosesItLikeBack() {
        #expect(BackToReferrer.swipeBack(pageCanGoBack: false, tab: tab, referrer: source, inSplit: false, pinned: false) == .close(returnTo: source))
        // Pages the tab went on to come first, as for Back.
        #expect(BackToReferrer.swipeBack(pageCanGoBack: true, tab: tab, referrer: source, inSplit: false, pinned: false) == .history)
        // Pinned tabs and split panes keep their own history only: no swipe without it.
        #expect(BackToReferrer.swipeBack(pageCanGoBack: false, tab: tab, referrer: source, inSplit: false, pinned: true) == .none)
        #expect(BackToReferrer.swipeBack(pageCanGoBack: false, tab: tab, referrer: source, inSplit: true, pinned: false) == .none)
        #expect(BackToReferrer.swipeBack(pageCanGoBack: false, tab: tab, referrer: nil, inSplit: false, pinned: false) == .none)
    }
}

/// Back in a Little Window (GitHub #495): Arc closes a Little Arc window when a swipe back (or
/// Back) finds nothing behind its page, as a link's tab closes to the one it came from.
struct LittleWindowBackTests {
    /// The reporter's case: a Little Window on its first page; swiping back closes it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/495"))
    func backOnALittleWindowsFirstPageClosesIt() {
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: true, peek: false) == .close)
    }

    /// Pages the window went on to come first; no page yet (the bar only) or a Peek: nothing closes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/495"))
    func historyComesFirstAndNothingElseCloses() {
        #expect(LittleWindowBack.step(pageCanGoBack: true, hasPage: true, peek: false) == .history)
        #expect(LittleWindowBack.step(pageCanGoBack: true, hasPage: true, peek: true) == .history)
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: false, peek: false) == .none)
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: true, peek: true) == .none)
    }
}

/// A two-finger swipe over a Little Window's address bar goes where Back and Forward go (GitHub
/// #495, bensk: "Could a swipe over the address bar work as well?").
struct LittleBarSwipeTests {
    /// Feeds `steps` scroll events of (dx, dy) and lets go.
    private func swipe(_ steps: [(CGFloat, CGFloat)], inverted: Bool = true, cancelled: Bool = false) -> LittleBarSwipe.Direction? {
        var s = LittleBarSwipe()
        s.begin()
        for (dx, dy) in steps { _ = s.move(dx: dx, dy: dy, inverted: inverted) }
        return s.end(cancelled: cancelled)
    }

    /// The reporter's case: fingers to the right over the bar go back; to the left, forward.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/495"))
    func fingersRightGoBackLeftGoForward() {
        #expect(swipe(Array(repeating: (8, 0), count: 10)) == .back)
        #expect(swipe(Array(repeating: (-8, 0), count: 10)) == .forward)
        // Natural scrolling off reports the deltas the other way round; the fingers still decide.
        #expect(swipe(Array(repeating: (-8, 0), count: 10), inverted: false) == .back)
    }

    /// A short swipe, one taken back, one that started up or down, or one the system took: nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/495"))
    func shortVerticalOrTakenBackSwipesDoNothing() {
        #expect(swipe(Array(repeating: (8, 0), count: 5)) == nil)
        #expect(swipe(Array(repeating: (8, 0), count: 10) + Array(repeating: (-8, 0), count: 8)) == nil)
        #expect(swipe([(1, 8)] + Array(repeating: (12, 0), count: 10)) == nil)
        #expect(swipe(Array(repeating: (8, 0), count: 10), cancelled: true) == nil)
    }

    /// The bar keeps a sideways swipe's events, and leaves an upright one's to the window.
    @Test func keepsOnlySidewaysEvents() {
        var s = LittleBarSwipe()
        s.begin()
        let early = s.move(dx: 3, dy: 0, inverted: true)
        let sideways = s.move(dx: 5, dy: 1, inverted: true)
        #expect(!early && sideways)
        s.begin()
        let upright = s.move(dx: 1, dy: 9, inverted: true)
        let after = s.move(dx: 30, dy: 0, inverted: true)
        #expect(!upright && !after)
        var idle = LittleBarSwipe()
        let untouched = idle.move(dx: 30, dy: 0, inverted: true)
        let ended = idle.end()
        #expect(!untouched && ended == nil)
    }
}
