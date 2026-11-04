import CoreGraphics
import CraCore
import Testing

/// Shift + wheel (or a sideways wheel) over the sidebar switches spaces like Arc 1.171 (issue #93).
struct WheelSpaceSwitchTests {
    /// Feeds `(dx, time)` events and returns the steps they make.
    private func steps(_ events: [(CGFloat, Double)], inverted: Bool = false) -> [Int] {
        var wheel = WheelSpaceSwitch()
        return events.map { wheel.step(dx: $0.0, inverted: inverted, at: $0.1) }
    }

    @Test func oneSlowNotchDoesNothing() {
        #expect(steps([(-1, 10)]) == [0])
        // Notches further apart than the pause never add up.
        #expect(steps([(-1, 10), (-1, 10.065), (-1, 10.13), (-1, 10.2)]) == [0, 0, 0, 0])
    }

    @Test func aFlickSwitches() {
        #expect(steps([(-2, 10)]) == [1])
        #expect(steps([(-1, 10), (-1, 10.035)]) == [0, 1])
        #expect(steps([(-3, 10)]) == [1])
    }

    /// A positive delta (Shift + wheel one way, fingers right on a trackpad) goes back.
    @Test func directionFollowsTheSwipe() {
        #expect(steps([(2, 10)]) == [-1])
        #expect(steps([(1, 10), (1, 10.02)]) == [0, -1])
    }

    /// With natural scrolling (macOS's default) the deltas arrive flipped and the event says so;
    /// the same wheel turn still pages the same way (Arc 1.171 XORs the sign with
    /// isDirectionInvertedFromDevice; issue #93, reversed in Cra 0.1.27).
    @Test func naturalScrollingPagesTheSameWay() {
        #expect(steps([(2, 10)], inverted: true) == [1])
        #expect(steps([(-2, 10)], inverted: true) == [-1])
        #expect(steps([(1, 10), (1, 10.02)], inverted: true) == [0, 1])
    }

    /// A turn subtracts from what had added up rather than starting afresh (Arc keeps one sum).
    @Test func aTurnCancelsOut() {
        #expect(steps([(-1, 10), (1, 10.02), (-1, 10.04)]) == [0, 0, 0])
        #expect(steps([(-0.8, 10), (0.5, 10.02), (-0.8, 10.04)]) == [0, 0, 1])
    }

    /// Arc forgets the sum after 0.05 s without a wheel event.
    @Test func aPauseForgets() {
        #expect(steps([(-1, 10), (-1, 10.045)]) == [0, 1])
        #expect(steps([(-1, 10), (-1, 10.055)]) == [0, 0])
    }

    /// One switch per quarter second, however fast the wheel spins (Arc: a 0.245 s burst of
    /// 3-line events switched once, a 0.254 s burst twice).
    @Test func coolsDownAfterASwitch() {
        let burst = (0..<11).map { (CGFloat(-3), 10 + Double($0) * 0.0245) }
        #expect(steps(burst).filter { $0 != 0 } == [1])
        let longer = (0..<12).map { (CGFloat(-3), 10 + Double($0) * 0.023) }
        #expect(steps(longer).filter { $0 != 0 } == [1, 1])
    }

    /// What adds up during the cooldown is dropped, so the next switch needs a flick of its own.
    @Test func theCooldownDropsWhatItSees() {
        #expect(steps([(-2, 10), (-1, 10.03), (-1, 10.06), (-1, 10.26)]) == [1, 0, 0, 0])
        #expect(steps([(-2, 10), (-1, 10.26), (-1, 10.28)]) == [1, 0, 1])
    }

    @Test func sidewaysDeltaOfZeroIsIgnored() {
        #expect(steps([(-1, 10), (0, 10.02), (-1, 10.04)]) == [0, 0, 1])
    }

    @Test(arguments: [
        // (step, index, count, inLibrary, libraryAllowed, target)
        (1, 0, 3, false, true, WheelSpaceSwitch.Target.space(1)),
        (-1, 2, 3, false, true, .space(1)),
        (1, 2, 3, false, true, nil),
        (-1, 0, 3, false, true, .openLibrary),
        (-1, 0, 3, false, false, nil),
        (-1, 0, 1, false, true, .openLibrary),
        (1, 0, 1, false, true, nil),
        (1, 0, 3, true, true, .closeLibrary),
        (-1, 0, 3, true, true, nil),
        (0, 1, 3, false, true, nil),
    ] as [(Int, Int, Int, Bool, Bool, WheelSpaceSwitch.Target?)])
    func pagesLikeASwipeWithoutWrapping(step: Int, index: Int, count: Int, inLibrary: Bool, libraryAllowed: Bool, target: WheelSpaceSwitch.Target?) {
        #expect(WheelSpaceSwitch.target(step: step, index: index, count: count, inLibrary: inLibrary, libraryAllowed: libraryAllowed) == target)
    }
}
