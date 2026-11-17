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
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/152"), arguments: spaces)
    func tonesAreArcsPaletteSlots(space: Space) {
        let sd = RGB(space.shadedDark.0 / 255, space.shadedDark.1 / 255, space.shadedDark.2 / 255)
        let t = TooltipTones(shadedDark: sd)
        #expect(Self.close(t.fill, space.fill, within: 1))
        #expect(Self.close(t.title, space.title, within: 1))
        #expect(Self.close(t.badge, space.badge, within: 1))
        #expect(Self.close(t.ink, space.ink, within: 1))
    }

    /// Cra rebuilds shadedDark from the theme colour: Victor's #F8D558 lands next to Arc's, below
    /// 0 in blue as Arc's is (#490: Arc's tones leave sRGB), and so does its tip's fill.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/152"))
    func victorsThemeRebuildsArcsShade() {
        let theme = SpaceTheme(colors: ["#F8D558", "#A4F554"], intensity: 0.25, noise: 0.35, appearance: "light", vibrant: true, accent: "#F8D558")
        #expect(Self.close(theme.shadedDark, (111.42, 85.74, -20.46), within: 8))
        #expect(Self.close(TooltipTones(theme: theme).fill, (33.42, 25.72, -6.14), within: 3))
    }

    /// Arc's shadedDark sits at 10 % luminance in the theme's hue; greys stay grey. Since #490 the hue
    /// and saturation kept are the colour's Display P3 HSL ones, as Arc keeps them (they were sRGB HSB
    /// hue at full saturation, which painted every green the same).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/152"), arguments: ["#F8D558", "#E63333", "#2861B3", "#3A8F5C", "#808080"])
    func shadedDarkKeepsTheHueAtTenPercentLuminance(hex: String) {
        let c = SpaceTheme.shadedDark(hex)
        func lin(_ x: Double) -> Double { (abs(x) <= 0.04045 ? abs(x) / 12.92 : pow((abs(x) + 0.055) / 1.055, 2.4)) * (x < 0 ? -1 : 1) }
        #expect(abs(0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) - 0.1) < 0.002)
        let src = HexColor.components(hex)!
        let a = SpaceTheme.hsl(SpaceTheme.displayP3(RGB(src.r, src.g, src.b))), b = SpaceTheme.hsl(SpaceTheme.displayP3(c))
        if a.s < 0.05 { #expect(b.s < 0.001) } else { #expect(abs(a.h - b.h) < 0.002 && abs(a.s - b.s) < 0.002) }
    }

    /// Arc's primaryColorPalette as offline Arc 1.172.2 wrote it for 18 of its editor's swatches (17 Nov
    /// 2026): source, shadedDark, shaded, midTone, tintedLight, 0...255 in Arc's extended sRGB. Every tone
    /// keeps the colour's saturation, so a sage or a slate stays muted and a dark colour is its own
    /// shadedDark; only a saturated colour (Pastel7 is pale but saturated) gets vivid tones. Cra painted
    /// every colour of a hue at full saturation: Brand9's slate shadedDark came out pure blue (15,22,255)
    /// against Arc's (84,85,113), and every green the same green in ⌘T's selected row (#490).
    static let arcPalettes: [(String, (Double, Double, Double), (Double, Double, Double), (Double, Double, Double), (Double, Double, Double))] = [
        ("#226149", (33.8, 97.2, 73.4), (33.8, 97.2, 73.4), (55.8, 167.6, 126.5), (225.7, 241.1, 234.5)),  // Drab8
        ("#26456B", (37.5, 68.9, 107.0), (37.5, 68.9, 107.0), (116.0, 154.2, 202.6), (233.3, 239.1, 246.9)),  // Drab9
        ("#4E3A5A", (78.1, 58.1, 90.0), (78.1, 58.1, 90.0), (166.3, 140.4, 181.8), (242.7, 239.0, 244.8)),  // Drab1
        ("#666789", (84.5, 85.3, 113.4), (102.1, 103.1, 137.0), (148.9, 149.6, 176.5), (238.8, 238.9, 243.0)),  // Brand9
        ("#6CBAD9", (0.2, 95.5, 125.2), (108.0, 185.8, 217.1), (108.0, 185.8, 217.1), (228.1, 242.0, 247.9)),  // Brand8
        ("#7AA982", (58.9, 96.1, 65.4), (122.1, 169.3, 129.9), (122.1, 169.3, 129.9), (232.2, 240.1, 233.3)),  // Drab7
        ("#8F4042", (143.0, 63.5, 66.0), (143.0, 63.5, 66.0), (204.0, 131.8, 133.6), (247.4, 235.9, 236.1)),  // Drab3
        ("#A6729D", (116.7, 75.3, 109.7), (166.0, 114.0, 157.1), (181.8, 138.5, 174.1), (243.3, 236.2, 242.0)),  // Brand3
        ("#C5C6E5", (77.6, 79.4, 162.5), (183.6, 184.4, 222.8), (183.6, 184.4, 222.8), (238.3, 238.4, 247.5)),  // Pastel9
        ("#CDCCA4", (91.4, 90.0, 46.8), (190.4, 188.7, 136.4), (190.4, 188.7, 136.4), (238.6, 238.2, 225.1)),  // Drab6
        ("#D7B35D", (108.4, 83.1, 18.6), (214.9, 178.7, 93.3), (214.9, 178.7, 93.3), (246.5, 238.6, 221.3)),  // Drab5
        ("#DEFDEB", (-44.0, 103.2, 32.9), (-105.5, 219.7, 67.6), (-105.5, 219.7, 67.6), (222.1, 252.9, 235.0)),  // Pastel7
        ("#F25E6B", (182.7, 0.1, 33.4), (242.0, 94.1, 107.1), (243.8, 108.5, 119.8), (254.4, 234.8, 236.1)),  // Brand4
        ("#F29BBB", (172.9, 24.0, 86.4), (242.3, 155.0, 186.9), (242.3, 155.0, 186.9), (253.0, 235.2, 241.4)),  // Brand2
        ("#F8D558", (111.4, 85.7, -20.5), (233.0, 179.3, -59.0), (233.0, 179.3, -59.0), (252.2, 237.3, 188.1)),  // Brand6
        ("#FFE9F3", (179.8, -7.9, 98.5), (251.6, 160.6, 203.4), (251.6, 160.6, 203.4), (254.9, 233.1, 243.0)),  // Pastel2
        ("#FF8558", (166.4, 46.4, -12.7), (255.0, 133.1, 87.7), (255.0, 133.1, 87.7), (255.9, 234.2, 226.7)),  // Brand5
        ("#FFCBD1", (189.7, -16.5, 37.3), (253.4, 161.4, 172.8), (253.4, 161.4, 172.8), (255.3, 235.0, 237.3)),  // Pastel4
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/490"), arguments: arcPalettes.indices)
    func arcPalettesFollowTheColoursSaturation(index: Int) {
        let (hex, shadedDark, shaded, mid, tinted) = Self.arcPalettes[index]
        #expect(Self.close(SpaceTheme.shadedDark(hex), shadedDark, within: 6), "\(hex) shadedDark")
        #expect(Self.close(SpaceTheme.shaded(hex), shaded, within: 6), "\(hex) shaded")
        #expect(Self.close(SpaceTheme.midTone(hex), mid, within: 6), "\(hex) midTone")
        #expect(Self.close(SpaceTheme.tintedLight(hex), tinted, within: 6), "\(hex) tintedLight")
    }

    /// The issue's case: a sage, a dark green and a vivid green get three different ⌘T rows, as in Arc
    /// (rows measured on Arc's captures: (102,129,110) sage, (0,132,96) vivid).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/490"))
    func greensOfDifferentSaturationGetTheirOwnSelection() {
        let rows = ["#7AA982", "#226149", "#34E895"].map { CommandBarTones(theme: SpaceTheme(colors: [$0], intensity: 1, noise: 0, appearance: "light"), dark: true).selection.rgb }
        #expect(rows[0] != rows[1] && rows[1] != rows[2] && rows[0] != rows[2])
        let sage = SpaceTheme.hsl(rows[0]), vivid = SpaceTheme.hsl(rows[2])
        #expect(sage.s < 0.35 && vivid.s > 0.9)
    }

    /// Arc's colourless default theme keeps the palette Arc stores for it (no colour rebuilds it):
    /// both of Cra's colourless halves and an import of Arc's default dark half.
    @Test(arguments: ["#010220", "#01021F", "#C8CAFF"])
    func colourlessThemeKeepsArcsDefaultPalette(hex: String) {
        #expect(Self.close(SpaceTheme.shadedDark(hex), (31.06, 42.36, 261.65), within: 0.1))
        #expect(Self.close(SpaceTheme.shaded(hex), (47.0, 57.3, 261.1), within: 0.1))
        #expect(Self.close(SpaceTheme.midTone(hex), (131.1, 137.2, 258.7), within: 0.1))
        #expect(Self.close(SpaceTheme.tintedLight(hex), (236.2, 237.1, 255.6), within: 0.1))
        let theme = SpaceThemeVariants.colourless(intensity: 0.5, noise: 0, appearance: "auto")
        #expect(theme.shadedDark == SpaceTheme.shadedDark("#C8CAFF"))
    }

    /// Arc's folder glyph: midTone back on every theme; the front and outline trade tintedLight
    /// and shadedDark between light and dark themes. Dark fronts are opaque (an X report on
    /// 4 Nov: the open folder looked see-through on dark themes only).
    @Test func folderTonesSwapFrontAndOutlineOnDarkThemes() {
        let light = FolderTones(themeColor: "#6CBAD9", dark: false)
        let dark = FolderTones(themeColor: "#010220", dark: true)
        #expect(light.front == SpaceTheme.tintedLight("#6CBAD9"))
        #expect(light.outline == SpaceTheme.shadedDark("#6CBAD9"))
        #expect(dark.front == SpaceTheme.shadedDark("#010220"))
        #expect(dark.outline == SpaceTheme.tintedLight("#010220"))
        #expect(light.back == SpaceTheme.midTone("#6CBAD9") && dark.back == SpaceTheme.midTone("#010220"))
        // Arc's default dark theme, sampled off the glyph: front #1F2AFF, outline #ECEDFF (the
        // front is Arc's stored shadedDark, past sRGB's blue).
        #expect(Self.close(dark.front, (31, 42, 255), within: 7))
        #expect(Self.close(dark.outline, (236, 237, 255), within: 2))
    }

    @Test(arguments: ["#808080", "#202020", "#EEEEEE"])
    func greyTonesStayGrey(hex: String) {
        for c in [SpaceTheme.midTone(hex), SpaceTheme.tintedLight(hex)] {
            #expect(abs(c.r - c.g) < 0.001 && abs(c.g - c.b) < 0.001)
        }
    }

    @Test func themeWithoutAccentUsesItsFirstColour() {
        let theme = SpaceTheme(colors: ["#2861B3", "#FFFFFF"], intensity: 1, noise: 0, appearance: "dark")
        #expect(theme.shadedDark == SpaceTheme.shadedDark("#2861B3"))
    }
}
