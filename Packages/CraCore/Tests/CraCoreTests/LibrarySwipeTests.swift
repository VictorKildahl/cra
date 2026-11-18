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

    @Test func thePageStaysAgainstTheLibraryFromItsHiddenPlace() {
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
