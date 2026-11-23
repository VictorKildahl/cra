import CraCore
import Testing

/// The fill under the toolbar button the pointer is over (GitHub #694).
struct ToolbarHoverTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/694"))
    func aLightBarGetsADarkHover() {
        // A white bar (no colour yet) and a light page's bar: black 5 %, Arc's toolbar hover on white
        // (242/255, measured live in Arc 1.174). White there didn't show at all.
        #expect(ToolbarColor.isLight(hex: nil))
        #expect(ToolbarColor.isLight(hex: "#F6F8FA"))
        #expect(ToolbarColor.hover(light: true) == .init(white: 0, alpha: 0.05))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/694"))
    func aDarkBarKeepsItsWhiteHover() {
        #expect(!ToolbarColor.isLight(hex: "#0D1117"))
        #expect(!ToolbarColor.isLight(hex: "#2B6CB0"))
        #expect(ToolbarColor.hover(light: false) == .init(white: 1, alpha: 0.1))
    }
}
