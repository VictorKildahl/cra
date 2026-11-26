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

    /// #822: the menu takes the half of the space's palette that matches the Mac's appearance, as Arc 1.174.2 does
    /// (26 Nov 2026: the gold space captured with the Mac in Dark mode, then in Light mode; the reporter's Arc showed it
    /// light). The 9 Nov measurement above ran in Dark mode only, which is where "always dark" came from.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/822")) func inLightModeTheMenuTakesTheLightPalette() {
        let light = ArcMenuTones(shadedDark: Self.rgb(0x6F5600), shaded: Self.rgb(0xE9B300), midTone: Self.rgb(0xE9B300),
                                 tintedLight: Self.rgb(0xFCEDBC), dark: false)
        #expect(Self.gap(light.fill, (254, 253, 252)) <= 2, "fill = light.backgroundExtra: \(light.fill)")
        #expect(Self.gap(light.separator, (226, 221, 200)) <= 3, "separators = light.hover: \(light.separator)")
        #expect(Self.gap(light.shortcut, (198, 187, 145)) <= 3, "shortcuts = light.subtitle: \(light.shortcut)")
        #expect(light.disabled == ArcMenuTones.disabledInkLight)
        #expect(light.ink == RGB(0, 0, 0), "black titles")
        // A plain grey space in Light mode (the reporter's) is light too.
        let grey = ArcMenuTones(theme: SpaceTheme(colors: ["#D1D1D6"], intensity: 0, noise: 0, appearance: "light"), dark: false)
        #expect(min(grey.fill.r, grey.fill.g, grey.fill.b) > 0.9, "light fill: \(grey.fill)")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/822")) func inDarkModeTheMenuStaysDarkOnEverySpace() {
        let grey = ArcMenuTones(theme: SpaceTheme(colors: ["#D1D1D6"], intensity: 0, noise: 0, appearance: "light"), dark: true)
        #expect(max(grey.fill.r, grey.fill.g, grey.fill.b) < 0.12, "dark fill, as in Arc: \(grey.fill)")
        #expect(grey.shortcut.r > grey.fill.r + 0.2, "shortcuts read on the dark fill: \(grey.shortcut)")
        #expect(grey.disabled == ArcMenuTones.disabledInk && grey.ink == RGB(1, 1, 1))
        let pale = ArcMenuTones(theme: SpaceTheme(colors: ["#FFF6D8"], intensity: 0.2, noise: 0, appearance: "light"), dark: true)
        #expect(pale.fill.r < 0.1 && pale.fill.g < 0.1 && pale.fill.b < 0.1, "dark on a light space in Dark mode: \(pale.fill)")
    }
}
