import CoreGraphics
import CraCore
import Testing

/// Arc's theme editor slider and dial (Arc 1.173.1, 18 Nov 2026).
struct SpaceStyleControlsTests {
    @Test func aValueTicksAsItCrossesAStep() {
        #expect(SpaceStyleControls.ticks(from: 0.08, to: 0.12, step: 0.1))
        #expect(SpaceStyleControls.ticks(from: 0.12, to: 0.08, step: 0.1))
        #expect(!SpaceStyleControls.ticks(from: 0.12, to: 0.18, step: 0.1))
        // The dial's steps are twice as far apart.
        #expect(!SpaceStyleControls.ticks(from: 0.25, to: 0.35, step: 0.2))
        #expect(SpaceStyleControls.ticks(from: 0.35, to: 0.45, step: 0.2))
        // Both ends are steps.
        #expect(SpaceStyleControls.ticks(from: 0.03, to: 0, step: 0.1))
        #expect(SpaceStyleControls.ticks(from: 0.97, to: 1, step: 0.2))
    }

    @Test func nothingTicksWithoutAMoveOrAStep() {
        #expect(!SpaceStyleControls.ticks(from: 0.5, to: 0.5, step: 0.1))
        #expect(!SpaceStyleControls.ticks(from: 0.1, to: 0.9, step: 0))
    }

    @Test func aFastDragOverSeveralStepsTicksOnce() {
        #expect(SpaceStyleControls.ticks(from: 0.05, to: 0.95, step: 0.1))
    }

    @Test func theWaveIsFlatAtNothingAndFullAtOne() {
        #expect(SpaceStyleControls.waveAmplitude(value: 0) == 0)
        #expect(SpaceStyleControls.waveAmplitude(value: 1) == 14.25)
        // Measured 20 pt from trough to crest at 0.54, 5 pt of it the line.
        #expect(abs(2 * SpaceStyleControls.waveAmplitude(value: 0.54) + 5 - 20) < 0.5)
        #expect(SpaceStyleControls.waveAmplitude(value: 3) == 14.25)
    }

    @Test func theThumbGrowsWithTheValue() {
        let none = SpaceStyleControls.thumbSize(value: 0, held: false)
        let full = SpaceStyleControls.thumbSize(value: 1, held: false)
        #expect(none.width == 11.5 && none.height == 40.5)
        #expect(full.width == 25.5 && abs(full.height - 53.2) < 0.001)
        // Held it is a tenth larger: 12.5 × 44.5 pt and 28 × 58.5 pt in the recording.
        let heldNone = SpaceStyleControls.thumbSize(value: 0, held: true)
        let heldFull = SpaceStyleControls.thumbSize(value: 1, held: true)
        #expect(abs(heldNone.width - 12.5) < 0.2 && abs(heldNone.height - 44.5) < 0.2)
        #expect(abs(heldFull.width - 28) < 0.1 && abs(heldFull.height - 58.5) < 0.1)
        // At rest at 0.8 it was 22 × 50.5 pt.
        let rest = SpaceStyleControls.thumbSize(value: 0.8, held: false)
        #expect(abs(rest.width - 22) < 0.8 && abs(rest.height - 50.5) < 0.3)
    }
}
