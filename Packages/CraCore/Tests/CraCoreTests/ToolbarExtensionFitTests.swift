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

/// What a narrow split pane drops, in Arc 1.171's order (GitHub #178).
struct ToolbarRoomTests {
    private let pins: [CGFloat] = [34, 34]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func everythingStaysWhileTheAddressFits() {
        #expect(ToolbarRoom.plan(pins: pins, reload: 37, settings: 34, needed: 150, room: 200) == .init())
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func pinsGoBeforeRefresh() {
        // 120 + one pin = 154 ≥ 150.
        #expect(ToolbarRoom.plan(pins: pins, reload: 37, settings: 34, needed: 150, room: 120) == .init(hiddenPins: 1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func refreshGoesOnceThePinsAreNotEnough() {
        // 40 + 68 = 108 < 150: ↻ goes too, and the address, cut short, keeps the sliders.
        #expect(ToolbarRoom.plan(pins: pins, reload: 37, settings: 34, needed: 150, room: 40)
                == .init(hiddenPins: 2, hidesReload: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func theSlidersGoOnlyWhenTheAddressWouldBeSqueezed() {
        // A 215 pt pane (Arc 1.170): ← → · options · ✕ and the address only.
        #expect(ToolbarRoom.plan(pins: [], reload: 37, settings: 34, needed: 150, room: 0)
                == .init(hidesReload: true, hidesSettings: true))
        #expect(ToolbarRoom.plan(pins: [], reload: 37, settings: 34, needed: 150, room: 70)
                == .init(hidesReload: true))
        // Arc's 3-pane split: a 325 pt pane keeps the sliders (114 pt of address room in Cra's
        // bar), a 292 pt one doesn't (82 pt).
        #expect(!ToolbarRoom.plan(pins: [], reload: 37, settings: 34, needed: 150, room: 114 - 37).hidesSettings)
        #expect(ToolbarRoom.plan(pins: [], reload: 37, settings: 34, needed: 150, room: 82 - 37).hidesSettings)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func aShortAddressNeverCostsTheSliders() {
        // Needs 60: ↻ makes room (30 + 37 = 67), nothing else goes.
        #expect(ToolbarRoom.plan(pins: [], reload: 37, settings: 34, needed: 60, room: 30) == .init(hidesReload: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func missingButtonsAreNotHidden() {
        #expect(ToolbarRoom.plan(pins: [], reload: nil, settings: nil, needed: 150, room: 0) == .init())
    }
}
