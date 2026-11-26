import CraCore
import Foundation
import Testing

/// The tab switcher's order: ⌃Tab within a space (Arc) and ⌃⌥Tab across every space (#467).
struct RecentTabOrderTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)

    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func currentFirstThenNewestFirst() {
        let entries = [RecentTabOrder.Entry(id: a, lastActive: at(1)), .init(id: b, lastActive: at(3)), .init(id: c, lastActive: at(2))]
        #expect(RecentTabOrder.ordered(entries, current: a) == [a, b, c], "the tab on screen leads even when a background tab is newer")
        #expect(RecentTabOrder.ordered(entries, current: nil) == [b, c, a])
    }

    @Test func neverShownTabsStayOut() {
        let entries = [RecentTabOrder.Entry(id: a, lastActive: at(1)), .init(id: b, lastActive: nil)]
        #expect(RecentTabOrder.ordered(entries, current: a) == [a])
    }

    @Test func sharedFavoriteCountsOnceAndTiesKeepSidebarOrder() {
        let entries = [RecentTabOrder.Entry(id: a, lastActive: at(1)), .init(id: c, lastActive: at(1)),
                       .init(id: a, lastActive: at(1)), .init(id: b, lastActive: at(1))]
        #expect(RecentTabOrder.ordered(entries, current: nil) == [a, c, b])
    }

    /// Home's tab a was on screen, then ⌃⌥Tab picked Work's tab c: c is shown now and newest, so the
    /// next tap goes back to a, not to Work's own earlier tab d.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/467"))
    func aSecondTapAcrossSpacesGoesBack() {
        let home = [RecentTabOrder.Entry(id: a, lastActive: at(5)), .init(id: b, lastActive: at(2))]
        let work = [RecentTabOrder.Entry(id: c, lastActive: at(1)), .init(id: d, lastActive: at(4))]
        #expect(RecentTabOrder.ordered(home + work, current: a) == [a, d, b, c])
        let afterJump = [home[0], home[1], .init(id: c, lastActive: at(6)), work[1]]
        #expect(RecentTabOrder.ordered(afterJump, current: c) == [c, a, d, b])
    }
}

/// ⌃Tab lists a split as one card, as Arc's switcher lists sidebar items (#554).
struct RecentTabOrderSplitTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), split = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)

    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// Tab c, then the split of a and b (b used last), then tab d on screen. Before #554 the
    /// switcher showed a and b as two cards; now it is one card holding both panes in pane order.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/554"))
    func aSplitIsOneCardWithItsPanes() {
        let entries = [RecentTabOrder.Entry(id: c, lastActive: at(1)),
                       .init(id: a, lastActive: at(2), split: split), .init(id: b, lastActive: at(3), split: split),
                       .init(id: d, lastActive: at(4))]
        let cards = RecentTabOrder.cards(entries, current: d)
        #expect(cards.map(\.id) == [d, split, c])
        #expect(cards[1].panes == [a, b], "the panes in their order, not by time")
        #expect(cards[1].isSplit && !cards[0].isSplit)
        #expect(cards[1].opens == b, "picking the split goes back to the pane used last")
        #expect(cards[0].panes == [d] && cards[0].opens == d)
    }

    /// The split on screen leads, opening on its current pane, and counts as recent as its newest pane.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/554"))
    func theSplitOnScreenLeadsAndTakesItsNewestPanesTime() {
        let entries = [RecentTabOrder.Entry(id: a, lastActive: at(1), split: split), .init(id: b, lastActive: at(5), split: split),
                       .init(id: c, lastActive: at(3)), .init(id: d, lastActive: at(4))]
        #expect(RecentTabOrder.cards(entries, current: a).map(\.id) == [split, d, c])
        #expect(RecentTabOrder.cards(entries, current: a)[0].opens == a)
        #expect(RecentTabOrder.cards(entries, current: c).map(\.id) == [c, split, d], "b at 5 makes the split newest")
    }

    /// A pane never shown still belongs to its split's card; a split none of whose panes was shown stays out.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/554"))
    func unshownPanesFollowTheirSplit() {
        let other = UUID()
        let entries = [RecentTabOrder.Entry(id: a, lastActive: nil, split: split), .init(id: b, lastActive: at(2), split: split),
                       .init(id: c, lastActive: nil, split: other), .init(id: d, lastActive: nil, split: other)]
        let cards = RecentTabOrder.cards(entries, current: nil)
        #expect(cards.map(\.id) == [split])
        #expect(cards[0].panes == [a, b] && cards[0].opens == b)
    }

    /// The tab list for ⌃Tab without splits is unchanged: one card per tab.
    @Test func tabsAloneKeepTheirOrder() {
        let entries = [RecentTabOrder.Entry(id: a, lastActive: at(1)), .init(id: b, lastActive: at(3)), .init(id: c, lastActive: at(2))]
        #expect(RecentTabOrder.cards(entries, current: a).map(\.id) == RecentTabOrder.ordered(entries, current: a))
    }

    /// ⌃Tab lists open tabs only. A pinned tab or Favorite counts while its page is loaded, but a Favorite closed with ⌘W
    /// leaves the switcher although its page keeps running (#740), until it's picked again: Arc 1.174.2 listed it before
    /// ⌘W and not after (measured 26 Nov 2026, offline copy). isabhiii on #784.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/784")) func aFavoriteClosedWithCmdWLeavesTheSwitcher() {
        #expect(RecentTabOrder.listsPane(selected: false, pinned: true, loaded: true, closedWithCmdW: false))
        #expect(!RecentTabOrder.listsPane(selected: false, pinned: true, loaded: true, closedWithCmdW: true))
        // An unloaded pinned tab isn't open; a Today tab always is; the tab on screen always counts.
        #expect(!RecentTabOrder.listsPane(selected: false, pinned: true, loaded: false, closedWithCmdW: false))
        #expect(RecentTabOrder.listsPane(selected: false, pinned: false, loaded: false, closedWithCmdW: false))
        #expect(RecentTabOrder.listsPane(selected: true, pinned: true, loaded: true, closedWithCmdW: true))
    }
}
