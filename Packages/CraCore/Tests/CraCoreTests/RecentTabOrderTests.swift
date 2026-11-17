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
