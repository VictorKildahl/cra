import CoreGraphics
import CraCore
import Testing

/// Arc 1.171 drops pinned extensions from the front of the list until the address fits whole
/// (live, 4 Nov 2026: ten pins, the last seven at a 1100 pt window, the last two at 800 pt).
struct ToolbarExtensionFitTests {
    /// A bar with `space` points for the address and the pins, each pin 36 pt.
    private func hidden(pins: Int, space: CGFloat, address: CGFloat) -> Int {
        let widths = Array(repeating: CGFloat(36), count: pins)
        let all = widths.reduce(0, +)
        return ToolbarExtensionFit.hiddenCount(widths: widths, needed: address) { freed in space - (all - freed) }
    }

    @Test func everyPinShowsWhileTheAddressFits() {
        #expect(hidden(pins: 10, space: 600, address: 200) == 0)
    }

    @Test func hidesFromTheFrontUntilTheAddressFits() {
        // 10 × 36 = 360 of 500 leaves 140; the address needs 210: two pins go, leaving 212.
        #expect(hidden(pins: 10, space: 500, address: 210) == 2)
    }

    @Test func allPinsGoWhenEvenThatIsNotEnough() {
        #expect(hidden(pins: 4, space: 100, address: 200) == 4)
    }

    @Test func noPinsNothingHidden() {
        #expect(hidden(pins: 0, space: 10, address: 200) == 0)
    }
}
