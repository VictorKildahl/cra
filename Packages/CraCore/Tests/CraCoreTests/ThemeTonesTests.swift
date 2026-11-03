import CraCore
import Foundation
import Testing

/// Arc's tooltip tones against Arc's own palettes: Victor's space and Arc's default theme from
/// StorableSidebar.json (semanticColorPalette), and the two spaces measured in GitHub #152.
struct ThemeTonesTests {
    struct Space: Sendable, CustomTestStringConvertible {
        let name: String
        /// primaryColorPalette.shadedDark, 0...255 (Arc's extended sRGB can leave the range).
        let shadedDark: (Double, Double, Double)
        /// dark.background, dark.title, light.hover, light.maxContrastColor.
        let fill, title, badge, ink: (Double, Double, Double)
        var testDescription: String { name }
    }

    static let spaces = [
        Space(name: "Victor", shadedDark: (111.42, 85.74, -20.46),
              fill: (33.42, 25.72, -6.14), title: (233.46, 229.61, 213.68), badge: (226.29, 221.15, 199.91), ink: (111.42, 85.74, -20.46)),
        Space(name: "Arc default", shadedDark: (31.06, 42.36, 261.65),
              fill: (9.31, 12.70, 78.49), title: (221.42, 223.11, 255.99), badge: (210.27, 212.48, 256.08), ink: (31.06, 42.36, 261.65)),
        // GitHub #152's token table (CloudDev red, RM blue).
        Space(name: "CloudDev", shadedDark: (183, 0, 33), fill: (55, 0, 10), title: (244, 217, 222), badge: (241, 204, 211), ink: (183, 0, 33)),
        Space(name: "RM", shadedDark: (36, 86, 159), fill: (11, 26, 48), title: (222, 230, 241), badge: (211, 221, 236), ink: (36, 86, 159)),
    ]

    static func close(_ c: RGB, _ e: (Double, Double, Double), within: Double) -> Bool {
        abs(c.r * 255 - e.0) <= within && abs(c.g * 255 - e.1) <= within && abs(c.b * 255 - e.2) <= within
    }

    /// Every tone is a mix of shadedDark: what Arc stores lands within rounding.
    @Test(arguments: spaces)
    func tonesAreArcsPaletteSlots(space: Space) {
        let sd = RGB(space.shadedDark.0 / 255, space.shadedDark.1 / 255, space.shadedDark.2 / 255)
        let t = TooltipTones(shadedDark: sd)
        #expect(Self.close(t.fill, space.fill, within: 1))
        #expect(Self.close(t.title, space.title, within: 1))
        #expect(Self.close(t.badge, space.badge, within: 1))
        #expect(Self.close(t.ink, space.ink, within: 1))
    }

    /// Cra rebuilds shadedDark from the theme colour: Victor's #F8D558 lands next to Arc's
    /// (which runs below 0 in blue, so the screen shows 0), and so does its tip's fill.
    @Test func victorsThemeRebuildsArcsShade() {
        let theme = SpaceTheme(colors: ["#F8D558", "#A4F554"], intensity: 0.25, noise: 0.35, appearance: "light", vibrant: true, accent: "#F8D558")
        #expect(Self.close(theme.shadedDark, (111.42, 85.74, 0), within: 8))
        #expect(Self.close(TooltipTones(theme: theme).fill, (33.42, 25.72, 0), within: 3))
    }

    /// Arc's shadedDark sits at 10 % luminance in the theme's hue; greys stay grey.
    @Test(arguments: ["#F8D558", "#E63333", "#2861B3", "#3A8F5C", "#808080"])
    func shadedDarkKeepsTheHueAtTenPercentLuminance(hex: String) {
        let c = SpaceTheme.shadedDark(hex)
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        #expect(abs(0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) - 0.1) < 0.002)
        let src = HexColor.components(hex)!
        let a = SpaceTheme.hsb(src.r, src.g, src.b), b = SpaceTheme.hsb(c.r, c.g, c.b)
        if a.s < 0.05 { #expect(b.s < 0.001) } else { #expect(abs(a.h - b.h) < 0.002) }
    }

    @Test func themeWithoutAccentUsesItsFirstColour() {
        let theme = SpaceTheme(colors: ["#2861B3", "#FFFFFF"], intensity: 1, noise: 0, appearance: "dark")
        #expect(theme.shadedDark == SpaceTheme.shadedDark("#2861B3"))
    }
}
