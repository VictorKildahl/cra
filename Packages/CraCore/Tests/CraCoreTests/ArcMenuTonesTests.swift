import CraCore
import Testing

/// Arc 1.172.1's sidebar + menu, measured live 9 Nov 2026 (offline Arc, sRGB window captures) on a gold
/// space (primaries shadedDark #6F5600, midTone #E9B300, tintedLight #FCEDBC) and on Arc's default theme
/// (shadedDark #212AFB, shaded #3139FB, midTone #8489FB, tintedLight #ECEDFE).
struct ArcMenuTonesTests {
    static func rgb(_ hex: Int) -> RGB { RGB(Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255, Double(hex & 0xff) / 255) }
    static func gap(_ a: RGB, _ b: (Int, Int, Int)) -> Int {
        [abs(Int((a.r * 255).rounded()) - b.0), abs(Int((a.g * 255).rounded()) - b.1), abs(Int((a.b * 255).rounded()) - b.2)].max()!
    }

    static let gold = ArcMenuTones(shadedDark: rgb(0x6F5600), shaded: rgb(0xE9B300), midTone: rgb(0xE9B300), tintedLight: rgb(0xFCEDBC))
    static let arcDefault = ArcMenuTones(shadedDark: rgb(0x212AFB), shaded: rgb(0x3139FB), midTone: rgb(0x8489FB), tintedLight: rgb(0xECEDFE))

    @Test func fillIsTheDarkBackgroundExtraOfTheSpace() {
        #expect(Self.gap(Self.gold.fill, (17, 13, 0)) <= 1, "gold: \(Self.gold.fill)")
        #expect(Self.gap(Self.arcDefault.fill, (5, 6, 39)) <= 1, "default: \(Self.arcDefault.fill)")
    }

    @Test func hoverAndSeparatorsAreTheDarkHoverOverTheFill() {
        #expect(Self.gap(Self.gold.hover, (81, 70, 26)) <= 4, "gold: \(Self.gold.hover)")
        #expect(Self.gap(Self.arcDefault.hover, (47, 51, 145)) <= 5, "default: \(Self.arcDefault.hover)")
        #expect(Self.gold.separator == Self.gold.hover)
    }

    @Test func shortcutsAreTheDarkSubtitle() {
        #expect(Self.gap(Self.gold.shortcut, (126, 119, 94)) <= 1, "gold: \(Self.gold.shortcut)")
        #expect(Self.gap(Self.arcDefault.shortcut, (118, 119, 128)) <= 2, "default: \(Self.arcDefault.shortcut)")
    }

    @Test func aLightSpaceStillGetsADarkMenu() {
        let pale = ArcMenuTones(theme: SpaceTheme(colors: ["#FFF6D8"], intensity: 0.2, noise: 0, appearance: "light"))
        #expect(pale.fill.r < 0.1 && pale.fill.g < 0.1 && pale.fill.b < 0.1, "Arc's menu is dark on light spaces: \(pale.fill)")
        #expect(pale.disabled == ArcMenuTones.disabledInk)
    }
}
