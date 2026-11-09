import CoreGraphics
import CraCore
import Testing

/// The trackpad tick of a sidebar swipe between spaces or into the Library (issue #260): Arc's
/// detent while the fingers move, and one tick on release for a page the drag never reached.
struct PageDetentHapticsTests {
    /// Moves the strip through `positions` (pages from the start) and lifts onto `target`;
    /// returns how many ticks the swipe asked for.
    private func ticks(_ positions: [CGFloat], landing target: Int, pages: ClosedRange<Int> = -1...1, from start: Int = 0) -> Int {
        var haptics = PageDetentHaptics(page: start)
        var count = positions.filter { haptics.track(position: $0, pages: pages) }.count
        if haptics.land(on: target) { count += 1 }
        return count
    }

    /// A flick changes the space from a fraction of a page (more than 0.8 pages a second); it
    /// never crossed a detent, so before #260 it changed the space without a tick.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aFlickTicksOnce() {
        #expect(ticks([0.05, 0.1, 0.15], landing: 1) == 1)
        #expect(ticks([-0.05, -0.12], landing: -1) == 1)
    }

    /// A slow drag past half ticks there, as Arc does, and the landing on that page adds none.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aDragPastHalfTicksOnce() {
        #expect(ticks([0.2, 0.4, 0.5, 0.7], landing: 1) == 1)
        // Arc rounds half away from zero: exactly half is the next page.
        var haptics = PageDetentHaptics()
        #expect(haptics.track(position: 0.49, pages: -1...1) == false)
        #expect(haptics.track(position: 0.5, pages: -1...1) == true)
    }

    /// A drag that goes nowhere is silent.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aShortDragBackIsSilent() {
        #expect(ticks([0.1, 0.3, 0.1], landing: 0) == 0)
    }

    /// Out past half and back: a tick at each crossing (Arc's detent), none on landing home.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func outAndBackTicksAtEachCrossing() {
        #expect(ticks([0.3, 0.6, 0.3, 0.1], landing: 0) == 2)
    }

    /// Past half, then a flick back home: the last tick was for the next page, so the landing
    /// home ticks again and the last tick always names the page shown.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aFlickBackFromPastHalfTicksForHome() {
        #expect(ticks([0.3, 0.6], landing: 0) == 2)
    }

    /// The rubber band past the last space is not a page: no tick, and none on settling back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func theRubberBandIsSilent() {
        #expect(ticks([0.2, 0.4, 0.6], landing: 0, pages: -1...0) == 0)
    }

    /// The Library is the page before the first space: pulling it in ticks once, by drag or by
    /// flick, and pushing it out from the Library ticks once.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func theLibraryIsAPage() {
        #expect(ticks([-0.3, -0.6, -0.9], landing: -1, pages: -1...0) == 1)
        #expect(ticks([-0.2], landing: -1, pages: -1...0) == 1)
        #expect(ticks([-0.8, -0.3], landing: 0, pages: -1...0, from: -1) == 1)
    }

    @Test func aBrokenPositionIsSilent() {
        var haptics = PageDetentHaptics()
        #expect(haptics.track(position: .nan, pages: -1...1) == false)
        #expect(haptics.track(position: .infinity, pages: -1...1) == false)
        #expect(haptics.page == 0)
    }
}
