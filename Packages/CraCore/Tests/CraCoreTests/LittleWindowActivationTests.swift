import CraCore
import Testing

/// GitHub #581: a Little Window on a desktop is an ordinary panel, so picking it in Mission Control keeps Cra in front.
struct LittleWindowActivationTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/581")) func onADesktopItActivatesCra() {
        #expect(LittleWindowActivation.space(types: [0]) == .desktop)
        #expect(!LittleWindowActivation.staysNonActivating(on: .desktop))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/186")) func overAnotherAppsFullScreenItStaysNonActivating() {
        #expect(LittleWindowActivation.space(types: [4]) == .fullScreen)
        #expect(LittleWindowActivation.staysNonActivating(on: .fullScreen))
    }

    @Test func whenTheWindowServerDoesntSayItStaysAsItOpened() {
        #expect(LittleWindowActivation.space(types: []) == .unknown)
        #expect(LittleWindowActivation.space(types: [0, 0]) == .unknown)
        #expect(LittleWindowActivation.space(types: [2]) == .unknown)
        #expect(LittleWindowActivation.staysNonActivating(on: .unknown))
    }
}
