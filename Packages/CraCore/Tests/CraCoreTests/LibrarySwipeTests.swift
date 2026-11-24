import Foundation
import CoreGraphics
import CraCore
import Testing

/// The swipe into the Library moves like a space swipe: the Library is the page before the first space.
struct LibrarySwipeTests {
    /// The Library's right edge moves with the fingers, point for point.
    @Test func followsTheFingersOneToOne() {
        #expect(LibrarySwipe.reveal(from: 0, travel: 208.5, width: 417) == 0.5)
        #expect(LibrarySwipe.reveal(from: 1, travel: -208.5, width: 417) == 0.5)
        #expect(LibrarySwipe.libraryX(reveal: 0.5, base: 347, library: 417) == -208.5)
        #expect(LibrarySwipe.spaceX(reveal: 0.5, base: 347, library: 417) == 208.5)
    }

    /// Like Arc, the sidebar widens with the reveal and lands at the Library's width.
    @Test func sidebarWidensWithTheReveal() {
        #expect(LibrarySwipe.sidebarWidth(reveal: 0, base: 260, library: 330) == 260)
        #expect(LibrarySwipe.sidebarWidth(reveal: 0.5, base: 260, library: 330) == 295)
        #expect(LibrarySwipe.sidebarWidth(reveal: 1, base: 260, library: 1044) == 1044)
        #expect(LibrarySwipe.sidebarWidth(reveal: -0.2, base: 260, library: 330) == 260)
        // Rubber-banding past, it keeps widening and the Library rides its edge.
        let w = LibrarySwipe.sidebarWidth(reveal: 1.1, base: 347, library: 417)
        #expect(w > 417)
        #expect(LibrarySwipe.libraryX(reveal: 1.1, base: 347, library: 417) == w - 417)
    }

    @Test func goingTheOtherWayFromTheSpaceIsASpaceSwipe() {
        #expect(LibrarySwipe.reveal(from: 0, travel: -10, width: 347) == nil)
    }

    /// Swiping out of the Library and on again before it has slid away goes on to the next
    /// space, as two quick space swipes go two pages (Loom report, 9 Nov 2026: the second swipe
    /// rubber-banded on the first space). It counts from the page the slide was headed for.
    @Test func aSwipeThatCatchesTheLibraryLeavingGoesOnToTheNextSpace() {
        #expect(LibrarySwipe.reveal(from: 0.2, travel: -40, width: 400, toward: 0) == 0.1)
        #expect(LibrarySwipe.reveal(from: 0.2, travel: -100, width: 400, toward: 0) == nil)
        // What's left of the fingers' travel once the Library is out pages the spaces.
        #expect(LibrarySwipe.travelPastSpace(from: 0.2, travel: -100, width: 400) == -20)
        // Caught on its way in, or swiped out from rest, it still gives way past the space.
        #expect(LibrarySwipe.reveal(from: 0.8, travel: -400, width: 400, toward: 1)! < 0)
        #expect(LibrarySwipe.reveal(from: 1, travel: -500, width: 400)! < 0)
    }

    /// Past either end it gives way like the space swipe: never more than half a page.
    @Test func rubberBandsPastEitherEnd() {
        let past = LibrarySwipe.reveal(from: 0, travel: 347 * 3, width: 347)!
        #expect(past > 1 && past < 1.5)
        let out = LibrarySwipe.reveal(from: 1, travel: -417 * 3, width: 417)!
        #expect(out < 0 && out > -0.5)
        #expect(LibrarySwipe.reveal(from: 0, travel: 347 * 1.2, width: 347)! < 1.2)
    }

    @Test(arguments: [
        (0.4, 0.0, 0.0), (0.6, 0.0, 1.0),
        (0.2, 1.0, 1.0), (0.8, -1.0, 0.0), (0.4, 0.5, 0.0),
    ])
    func whereItSettles(reveal: Double, velocity: Double, target: Double) {
        #expect(LibrarySwipe.target(reveal: CGFloat(reveal), velocity: CGFloat(velocity)) == CGFloat(target))
    }

    @Test func velocityFromRecentSamples() {
        let samples: [(time: Double, dx: CGFloat)] = [(1.00, 10), (1.02, 10), (1.04, 10)]
        #expect(abs(LibrarySwipe.velocity(samples: samples, width: 375) - 2) < 0.001)
        #expect(LibrarySwipe.velocity(samples: [(1, 5)], width: 375) == 0)
    }

    /// The space swipe's spring: critically damped, so it never overshoots, and it picks up
    /// the release speed.
    @Test func settlesLikeASpaceSwipe() {
        var previous: CGFloat = 0.6
        for i in 1...60 {
            let x = LibrarySwipe.settle(from: 0.6, velocity: 0, to: 1, at: CGFloat(i) / 120)
            #expect(x <= 1 && x >= previous)
            previous = x
        }
        #expect(LibrarySwipe.settle(from: 0.6, velocity: 3, to: 1, at: 0.02) > LibrarySwipe.settle(from: 0.6, velocity: 0, to: 1, at: 0.02))
        #expect(!LibrarySwipe.isSettled(from: 0.6, velocity: 0, to: 1, at: 0.05, width: 347))
        #expect(LibrarySwipe.isSettled(from: 0.6, velocity: 0, to: 1, at: 1, width: 347))
    }

    /// A swipe settles as fast as Arc's: within 1 % of the way in 0.22 s and not before 0.15 s (Arc's spring,
    /// measured at ω ≈ 30.6). Cra used Dia's 0.4 s spring, still 14 % short at 0.22 s: on #613's side-by-side
    /// recording every Cra swipe took ~330 ms to land and every Arc swipe ~215 ms.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/613"))
    func settlesAsFastAsArcs() {
        let left = { (t: CGFloat) in 1 - LibrarySwipe.settle(from: 0, velocity: 0, to: 1, at: t) }
        #expect(left(0.22) < 0.01)
        #expect(left(0.15) > 0.02)
        #expect(abs(LibrarySwipe.omega - 30.6) < 0.2)
        // At rest within a quarter point of a 347 pt sidebar page by a third of a second (Arc: ~0.27 s to rest).
        #expect(LibrarySwipe.isSettled(from: 0, velocity: 0, to: 1, at: 0.34, width: 347))
    }

    /// The Library button turns a settle around at the speed it is moving.
    @Test func settleVelocityIsTheSlope() {
        #expect(LibrarySwipe.settleVelocity(from: 0, velocity: 2, to: 1, at: 0) == 2)
        for t: CGFloat in [0.02, 0.1, 0.3] {
            let slope = (LibrarySwipe.settle(from: 0, velocity: 0, to: 1, at: t + 0.0005)
                - LibrarySwipe.settle(from: 0, velocity: 0, to: 1, at: t - 0.0005)) / 0.001
            #expect(abs(LibrarySwipe.settleVelocity(from: 0, velocity: 0, to: 1, at: t) - slope) < 0.001)
        }
    }

    // MARK: From a hidden sidebar (Arc 1.173.1, 18 Nov 2026)

    @Test func aFloatingSidebarOnTheFirstSpaceSwipesIntoTheLibrary() {
        #expect(LibrarySwipe.startsFromHiddenSidebar(floatingShown: true, onFirstSpace: true))
        #expect(!LibrarySwipe.startsFromHiddenSidebar(floatingShown: true, onFirstSpace: false))
        #expect(!LibrarySwipe.startsFromHiddenSidebar(floatingShown: false, onFirstSpace: true))
    }

    /// Arc's page had moved 322 px when its floating sidebar had gone back 211 px, and 144 px for 97.
    @Test func theFloatingSidebarGoesBackTwoPointsForThePagesThree() {
        let library: CGFloat = 405
        for r: CGFloat in [0.178, 0.4] {
            let page = LibrarySwipe.pageEdgeFromHidden(reveal: r, library: library, inset: 0)
            let retreat = LibrarySwipe.floatingRetreat(reveal: r, library: library)
            #expect(abs(page / retreat - 1.5) < 0.001)
        }
        #expect(abs(LibrarySwipe.floatingRetreat(reveal: 0.4, library: library) - 108) < 0.001)
        #expect(LibrarySwipe.floatingRetreat(reveal: 0, library: library) == 0)
        #expect(LibrarySwipe.floatingRetreat(reveal: -0.1, library: library) == 0)
        // With the Library in, a 250 pt sidebar 6 pt inside the window is out of sight.
        #expect(LibrarySwipe.floatingRetreat(reveal: 1, library: library) >= 256)
    }

    /// From a hidden sidebar the Library comes in docked at its full width and pushes the page before it, as Arc
    /// 1.173.1's does (a 120 Hz recording, 18 Nov 2026): #679 asked for less of a push, and Arc's is this one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/679"))
    func thePageStaysAgainstTheLibraryFromItsHiddenPlace() {
        let library: CGFloat = 417
        let rest: CGFloat = 10
        #expect(LibrarySwipe.pageEdgeFromHidden(reveal: 0, library: library, inset: rest) == rest)
        #expect(LibrarySwipe.pageEdgeFromHidden(reveal: 0.01, library: library, inset: rest) == rest)
        let half: CGFloat = 208.5
        #expect(LibrarySwipe.pageEdgeFromHidden(reveal: 0.5, library: library, inset: rest) == half)
        #expect(LibrarySwipe.pageEdgeFromHidden(reveal: 1, library: library, inset: rest) == library)
        // The Library under it: its right edge is the page's left one.
        #expect(LibrarySwipe.libraryX(reveal: 0.5, base: 0, library: library) + library == half)
    }
}

/// The settle after a swipe counts its time from the first frame it draws, not from the release (#613).
@Suite struct SettleClockTests {
    /// On #613's side-by-side recording Cra's sidebar stood still for a frame when the fingers lifted, then jumped
    /// 25 to 46 points in one frame, where Arc's picked up speed over three frames. The release switches the space,
    /// which keeps the main thread from drawing for a frame or two, and a spring timed from the release had already
    /// run that long when it first drew. Timed from its first frame it starts with one frame's step, however long
    /// the release took.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/613"))
    func aSlowReleaseDoesNotJumpTheSettle() {
        let frame = 1.0 / 60
        let release = 100.0
        // The release frame takes 50 ms: the first frame drawn is three frames on.
        let firstFrame = release + 3 * frame
        var clock = SettleClock(started: release)
        let t1 = clock.elapsed(atFrame: firstFrame, interval: frame)
        let step = { (t: TimeInterval) in LibrarySwipe.settle(from: 0, velocity: 0.5, to: 1, at: CGFloat(t)) }
        // One frame's way, as if the settle had begun the frame before it drew.
        #expect(abs(t1 - frame) < 1e-9)
        #expect(step(t1) < step(frame) + 1e-9)
        // The next frames follow on from it, a frame apart.
        #expect(abs(clock.elapsed(atFrame: firstFrame + frame, interval: frame) - 2 * frame) < 1e-9)
        #expect(abs(clock.elapsed(atFrame: firstFrame + 2 * frame, interval: frame) - 3 * frame) < 1e-9)
        // Timed from the release, the first frame would have shown three frames' way at once: the jump.
        #expect(step(firstFrame - release) - step(t1) > 0.1)
    }

    /// Before its first frame the settle is where the release left it: a turn-around (the Library button pressed
    /// mid-settle) starts from there, at the release speed.
    @Test func beforeItsFirstFrameTheSettleHasNotMoved() {
        let clock = SettleClock(started: 10)
        #expect(clock.elapsed(now: 10.2) == 0)
        var drawn = clock
        _ = drawn.elapsed(atFrame: 10.05, interval: 1.0 / 120)
        #expect(abs(drawn.elapsed(now: 10.1) - (0.05 + 1.0 / 120)) < 1e-9)
    }

    /// The tint settles with the strip: one response for both, Arc's (ω = 2π / response).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/613"))
    func theTintSettlesOnTheSameSpring() {
        #expect(abs(LibrarySwipe.response - 0.205) < 1e-9)
        #expect(abs(LibrarySwipe.omega - 2 * .pi / LibrarySwipe.response) < 1e-9)
    }

    /// The Library button, ⇧⌘L and the Library's back arrow move it as a swipe does, wherever the sidebar is:
    /// with the sidebar hidden it slides in under the floating sidebar and lands docked, and one that brought a
    /// hidden sidebar out slides back out to it. It appeared at once from a hidden sidebar, and went back with the
    /// tab list showing for a few frames and the page widening in steps (#726).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/726"))
    func theButtonSlidesTheLibraryFromAHiddenSidebarAndBack() {
        // Hidden, out over the page or not: in from the window's edge.
        #expect(LibrarySwipe.buttonMotion(opening: true, sidebar: .hidden, swiping: false) == .slideFromHidden)
        // Docked, it was brought out by the Library or not: the spring, both ways.
        #expect(LibrarySwipe.buttonMotion(opening: false, sidebar: .docked, swiping: false) == .slide(to: 0))
        #expect(LibrarySwipe.buttonMotion(opening: true, sidebar: .docked, swiping: false) == .slide(to: 1))
        // A swipe in progress keeps the fingers in charge; the button lands it at once.
        #expect(LibrarySwipe.buttonMotion(opening: true, sidebar: .docked, swiping: true) == .show)
        #expect(LibrarySwipe.buttonMotion(opening: false, sidebar: .docked, swiping: true) == .close)
        // A page full screen for its own (a video's): nothing to slide beside.
        #expect(LibrarySwipe.buttonMotion(opening: true, sidebar: .none, swiping: false) == .show)
        #expect(LibrarySwipe.buttonMotion(opening: false, sidebar: .none, swiping: false) == .close)
    }

    /// The button's slide is the swipe's settle: eased out, most of it in the first tenth of a second and done in
    /// about a third, as Arc's (#726: 320 ms in the reporter's recording, the biggest step first).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/726"))
    func theButtonsSlideEasesOutInAboutAThirdOfASecond() {
        let w: CGFloat = 417
        let done = stride(from: 0.0, through: 1.0, by: 1.0 / 120).first {
            LibrarySwipe.isSettled(from: 0, velocity: 0, to: 1, at: CGFloat($0), width: w)
        }
        #expect(done.map { $0 > 0.25 && $0 < 0.45 } == true)
        #expect(LibrarySwipe.settle(from: 0, velocity: 0, to: 1, at: 0.1) > 0.6)
    }
}
