import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's "+" past the last space (Arc 1.173.1's EdgeFeedbackView, 18 Nov 2026).
struct NewSpaceSwipeTests {
    private let strip = CGSize(width: 82, height: 1000)

    @Test func fifteenPointsOfOverscrollBringTheFeedbackOut() {
        #expect(NewSpaceSwipe.shown(overscroll: 0) == 0)
        #expect(NewSpaceSwipe.shown(overscroll: 7.5) == 0.5)
        #expect(NewSpaceSwipe.shown(overscroll: 15) == 1)
        #expect(NewSpaceSwipe.shown(overscroll: 60) == 1)
        #expect(NewSpaceSwipe.shown(overscroll: -3) == 0)
    }

    /// Arc's rubber band past its last page: 300 px of fingers (150 pt at its half speed) moved a
    /// 215 pt page 20.5 pt.
    @Test func theListGivesLikeArcsPastTheLastSpace() {
        #expect(abs(NewSpaceSwipe.overscroll(travel: 300, page: 215) - 20.4) < 0.2)
        #expect(NewSpaceSwipe.overscroll(travel: 0, page: 254) == 0)
        #expect(NewSpaceSwipe.overscroll(travel: -40, page: 254) == 0)
        // Nearly even at first, 0.075 pt for a point of fingers, then less and less.
        #expect(abs(NewSpaceSwipe.overscroll(travel: 20, page: 254) - 1.5) < 0.02)
        let near = NewSpaceSwipe.overscroll(travel: 400, page: 254) - NewSpaceSwipe.overscroll(travel: 380, page: 254)
        #expect(near < 1.5 && near > 0.9)
        // The ring is full after about 330 pt of fingers in a 254 pt sidebar, the feedback out after about 212.
        #expect(abs(NewSpaceSwipe.overscroll(travel: 330, page: 254) - NewSpaceSwipe.fillDistance) < 0.3)
        #expect(abs(NewSpaceSwipe.overscroll(travel: 212, page: 254) - NewSpaceSwipe.showDistance) < 0.3)
    }

    @Test func theRingIsFullAtTwentyTwoAndAHalf() {
        #expect(NewSpaceSwipe.progress(overscroll: 0) == 0)
        // Read from the recording: about 0.64 with the list 14.5 pt out.
        #expect(abs(NewSpaceSwipe.progress(overscroll: 14.5) - 0.644) < 0.001)
        #expect(NewSpaceSwipe.progress(overscroll: 22.5) == 1)
        #expect(NewSpaceSwipe.progress(overscroll: 40) == 1)
        #expect(!NewSpaceSwipe.isActivated(overscroll: 22.4))
        #expect(NewSpaceSwipe.isActivated(overscroll: 22.5))
    }

    @Test func aLiftMakesASpaceOnlyOnceTheRingHasBeenFullATenthOfASecond() {
        #expect(!NewSpaceSwipe.createsOnLift(fullFor: nil))
        #expect(!NewSpaceSwipe.createsOnLift(fullFor: 0.02))
        #expect(!NewSpaceSwipe.createsOnLift(fullFor: 0.1))
        #expect(NewSpaceSwipe.createsOnLift(fullFor: 0.11))
        #expect(NewSpaceSwipe.createsOnLift(fullFor: 3))
    }

    @Test func aWindowWithoutSpacesOfItsOwnIsNotOfferedOne() {
        #expect(NewSpaceSwipe.isOffered(standalone: false))
        #expect(!NewSpaceSwipe.isOffered(standalone: true))
    }

    @Test func theDiscComesFromPastTheEdgeToTwelvePointsInside() {
        let out = NewSpaceSwipe.discFrame(shown: 0, strip: strip)
        let start: CGFloat = 87
        #expect(out.minX == start)
        let rest = NewSpaceSwipe.discFrame(shown: 1, strip: strip)
        let expected = CGRect(x: 40, y: 485, width: 30, height: 30)
        #expect(rest == expected)
        #expect(strip.width - rest.maxX == 12)
        // The spring's swing past 1 doesn't carry the disc further in.
        #expect(NewSpaceSwipe.discFrame(shown: 1.2, strip: strip) == rest)
        let half = NewSpaceSwipe.discFrame(shown: 0.5, strip: strip)
        #expect(half.minX == 63.5)
    }

    @Test func theDiscFadesInOverTheFirstFifthAndTheBulgeOverTheFirstHalf() {
        #expect(NewSpaceSwipe.discAlpha(shown: 0) == 0)
        #expect(NewSpaceSwipe.discAlpha(shown: 0.1) == 0.5)
        #expect(NewSpaceSwipe.discAlpha(shown: 0.2) == 1)
        #expect(NewSpaceSwipe.bulgeOpacity(shown: 0.25) == 0.5)
        #expect(NewSpaceSwipe.bulgeOpacity(shown: 0.5) == 1)
        #expect(NewSpaceSwipe.bulgeOpacity(shown: 1) == 1)
    }

    @Test func theBulgeIsAnEllipseCentredOnTheEdgeWhenItIsOut() {
        let out = NewSpaceSwipe.bulgeFrame(shown: 1, strip: strip)
        let expected = CGRect(x: 0, y: 0, width: 164, height: 1000)
        #expect(out == expected)
        // Its centre is on the strip's right edge, half way down: the strip shows its left half.
        #expect(out.midX == strip.width && out.midY == strip.height / 2)
        // At rest it sits 10 pt inside the edge, still clear.
        #expect(NewSpaceSwipe.bulgeFrame(shown: 0, strip: strip).minX == 72)
        #expect(NewSpaceSwipe.bulgeFrame(shown: 0.5, strip: strip).minX == 36)
    }

    @Test func theSpringSwingsALittlePastAndSettles() {
        var s = NewSpaceSwipe.Spring()
        var peak = 0.0
        var t = 0.0
        while t < 2 {
            s.advance(toward: 1, by: 1.0 / 120)
            peak = max(peak, s.value)
            t += 1.0 / 120
        }
        // Damped at 0.8 it overshoots by about 1.5 %, and is at rest well inside two seconds.
        #expect(peak > 1.005 && peak < 1.03)
        #expect(s.isSettled(on: 1))
        // A little over half way there after a tenth of a second.
        var h = NewSpaceSwipe.Spring()
        h.advance(toward: 1, by: 0.1)
        #expect(abs(h.value - 0.526) < 0.01)
    }

    @Test func theSpringIsTheSameInOneStepOrMany() {
        var one = NewSpaceSwipe.Spring()
        one.advance(toward: 1, by: 0.25)
        var many = NewSpaceSwipe.Spring()
        for _ in 0..<50 { many.advance(toward: 1, by: 0.005) }
        #expect(abs(one.value - many.value) < 1e-9)
        #expect(abs(one.velocity - many.velocity) < 1e-9)
        // Nothing moves a spring that is where it is headed.
        var still = NewSpaceSwipe.Spring(value: 1)
        still.advance(toward: 1, by: 0.5)
        #expect(still.value == 1 && still.velocity == 0)
    }

    @Test func theDiscTurnsOverWhenTheRingIsFull() {
        let dark = NewSpaceSwipe.look(activated: false, dark: true)
        let darkOn = NewSpaceSwipe.look(activated: true, dark: true)
        #expect(dark.fill == NewSpaceSwipe.Color(0, 0, 0, 0.22))
        #expect(darkOn.fill == dark.ring)
        #expect(darkOn.plus.red == 0 && dark.plus.red == 1)
        let light = NewSpaceSwipe.look(activated: false, dark: false)
        let lightOn = NewSpaceSwipe.look(activated: true, dark: false)
        // AddSpacePlusProgressColor on a light sidebar: #2702C2.
        #expect(light.ring == NewSpaceSwipe.Color(0.153, 0.008, 0.761, 1))
        #expect(light.plus == light.ring)
        #expect(lightOn.fill == light.ring && lightOn.plus == NewSpaceSwipe.Color(1, 1, 1, 1))
    }
}
