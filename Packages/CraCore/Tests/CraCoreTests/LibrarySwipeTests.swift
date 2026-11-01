import CoreGraphics
import CraCore
import Testing

/// The swipe into the Library moves like a space swipe: the Library is the page before the first space.
struct LibrarySwipeTests {
    @Test func followsTheFingersOneToOne() {
        #expect(LibrarySwipe.reveal(from: 0, travel: 173.5, width: 347) == 0.5)
        #expect(LibrarySwipe.reveal(from: 1, travel: -208.5, width: 417) == 0.5)
        #expect(LibrarySwipe.libraryX(reveal: 0.5, width: 347) == -173.5)
        #expect(LibrarySwipe.spaceX(reveal: 0.5, width: 347) == 173.5)
    }

    @Test func goingTheOtherWayFromTheSpaceIsASpaceSwipe() {
        #expect(LibrarySwipe.reveal(from: 0, travel: -10, width: 347) == nil)
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
}
