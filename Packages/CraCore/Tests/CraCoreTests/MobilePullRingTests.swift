import CoreGraphics
import CraCore
import Testing

/// The ring in the status band, which fills through a pull down to reload.
struct MobilePullRingTests {
    @Test func theRingGetsBiggerWithTheStatusBar() {
        #expect(MobilePullRing.side(safeTop: 20) == 20, "a phone with no island keeps a small ring")
        #expect(MobilePullRing.side(safeTop: 47) == 20, "the smallest phone with an island")
        #expect(MobilePullRing.side(safeTop: 59) == 27)
        #expect(MobilePullRing.side(safeTop: 80) == 28, "28 pt is as large as it gets")
    }

    @Test func theRingSitsCentredBelowTheBar() {
        let center = MobilePullRing.center(safeTop: 59, screenWidth: 440)
        #expect(center.x == 220)
        #expect(center.y == 59 + 27.0 / 2 + 8)
        #expect(center.y - MobilePullRing.side(safeTop: 59) / 2 > 0, "all of it is on screen")
    }

    @Test func theRingIsWholeAtTheRefreshLine() {
        #expect(MobilePullRing.progress(pull: 0) == 0)
        #expect(MobilePullRing.progress(pull: 64) == 0.5)
        #expect(MobilePullRing.progress(pull: MobileSwipe.pullToRefreshDistance) == 1)
        #expect(MobilePullRing.progress(pull: 400) == 1, "past the line it stays whole")
        #expect(MobilePullRing.progress(pull: -4) == 0)
        #expect(MobilePullRing.progress(pull: .infinity) == 0, "a broken measurement draws nothing")
    }
}
