import CraCore
import Testing

/// A dialog's card never rounds past its sheet, so no white rim shows in its corners (GitHub #753).
struct DialogCornerTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/753"))
    func onMacOS15TheCardRoundsNoMoreThanItsSheet() {
        #expect(DialogCorner.radius(16, macOSMajor: 15) == 10)
        #expect(DialogCorner.radius(24, macOSMajor: 14) == 10)
        #expect(DialogCorner.radius(8, macOSMajor: 15) == 8)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/753"))
    func onMacOS26TheCardKeepsArcsCorners() {
        #expect(DialogCorner.radius(16, macOSMajor: 26) == 16)
        #expect(DialogCorner.radius(24, macOSMajor: 27) == 24)
    }
}
