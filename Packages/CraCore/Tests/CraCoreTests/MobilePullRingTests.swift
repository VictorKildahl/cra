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
        // The safe top, half the 27 pt ring, and 8 pt below. Typed outside the macro: CI's
        // compiler cannot type-check the literals inside #expect in time.
        let expectedY: CGFloat = 59 + 13.5 + 8
        #expect(center.y == expectedY)
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

/// The ring's ink and the spring of its second lap at the refresh line.
struct MobilePullRingMotionTests {
    @Test func theRingTakesTheStatusBarsInk() {
        #expect(MobilePullRing.ink(statusBarFill: "#1C1C1E", darkMode: false) == "#FFFFFF", "white over a dark band")
        #expect(MobilePullRing.ink(statusBarFill: "#FFFFFF", darkMode: true) == "#404040", "dark grey over a light one")
        #expect(MobilePullRing.ink(statusBarFill: nil, darkMode: true) == "#FFFFFF", "no band: the system's look")
        #expect(MobilePullRing.ink(statusBarFill: nil, darkMode: false) == "#404040")
    }

    /// The faster the pull reaches the line, the further and bouncier the lap springs out.
    @Test func aFasterPullBumpsFurtherAndBouncier() {
        let slow = MobilePullRing.bump(speed: 0)
        let fast = MobilePullRing.bump(speed: 2000)
        let degree: CGFloat = .pi / 180
        let slowGap: CGFloat = abs(slow.peak - degree)
        let fastGap: CGFloat = abs(fast.peak - 30 * degree)
        #expect(slowGap < 1e-9, "a slow pull barely nudges it: 1°")
        #expect(fastGap < 1e-9, "30° at most")
        #expect(MobilePullRing.bump(speed: 5000) == fast)
        #expect(MobilePullRing.bump(speed: -100) == slow)
        #expect(MobilePullRing.bump(speed: .infinity) == slow, "a broken measurement is a slow pull")
        #expect(fast.decay < slow.decay, "a fast pull's spring swings again")
        #expect(MobilePullRing.bump(speed: 1000).peak > slow.peak)
        #expect(MobilePullRing.bump(speed: 1000).peak < fast.peak)
    }

    @Test func theLapSpringsOutToItsPeakAndDiesAway() {
        let bump = MobilePullRing.bump(speed: 1200)
        #expect(MobilePullRing.lap(bump, at: 0) == 0)
        #expect(abs(MobilePullRing.lap(bump, at: 0.25) - bump.peak) < 1e-9, "a quarter through, the lap is the peak")
        #expect(MobilePullRing.lap(bump, at: 0.5) < 1e-9)
        #expect(MobilePullRing.lap(bump, at: 0.75) < MobilePullRing.lap(bump, at: 0.25) / 2, "the next swing is smaller")
        #expect(MobilePullRing.lap(bump, at: 1) < 1e-9, "it ends at rest")
        for speed in [0, 1200, 2000] as [CGFloat] {
            let bump = MobilePullRing.bump(speed: speed)
            #expect((0...100).allSatisfy { MobilePullRing.lap(bump, at: CGFloat($0) / 100) <= 2 * bump.peak },
                    "the decay never swings it past twice its peak")
        }
    }

    /// A full pull's lap turns 108° in 0.3 s as the ring fades, as docs/ios-parity.md says.
    @Test func aFullPullsLapTurnsAsItFades() {
        let degrees: CGFloat = MobilePullRing.successTurn * 180 / .pi
        #expect(abs(degrees - 108) < 1e-9)
        #expect(MobilePullRing.successDuration == 0.3)
    }
}
