import Testing
@testable import CraCore

/// The theme editor's presets (#170): Arc's catalog colours on five pages, one colour by default.
struct SpaceColorPresetsTests {
    /// Arc's ColorPicker colours as Arc writes them (sRGB): Brand4 is the CloudDev red, Brand8 is
    /// the 0.4236, 0.7286, 0.8512 Arc saved for a picked swatch.
    @Test func catalogColours() {
        for group in [SpaceColorPresets.brand, SpaceColorPresets.drab, SpaceColorPresets.pastel, SpaceColorPresets.greyscale] {
            #expect(group.count == 9 && Set(group).count == 9)
            #expect(group.allSatisfy { HexColor.components($0) != nil })
        }
        #expect(SpaceColorPresets.brand[3] == "#F25E6B")
        #expect(SpaceColorPresets.brand[7] == "#6CBAD9")
        #expect(SpaceColorPresets.greyscale.first == "#FFFFFF" && SpaceColorPresets.greyscale.last == "#000000")
    }

    /// Five pages of nine as in Arc: Brand, Brand pairs, Pastel, Drab, Greyscale.
    @Test func pages() {
        #expect(SpaceColorPresets.pages.map(\.group) == ["Brand", "Brand", "Pastel", "Drab", "Greyscale"])
        #expect(SpaceColorPresets.pages.map { $0.seconds != nil } == [false, true, false, false, false])
        for page in SpaceColorPresets.pages {
            #expect(page.swatches.count == 9)
            #expect(page.swatches.allSatisfy { $0.count == (page.seconds == nil ? 1 : 2) })
        }
    }

    /// The editor opens on the page holding the space's colours.
    @Test func pageOfAKey() {
        for (i, page) in SpaceColorPresets.pages.enumerated() {
            for swatch in page.swatches { #expect(SpaceColorPresets.page(of: swatch) == i) }
        }
        #expect(SpaceColorPresets.page(of: ["#f25e6b"]) == 0)
        #expect(SpaceColorPresets.page(of: ["#123456"]) == nil)
    }

    /// A new space starts on one colour, saved as Arc's one-dot (solid) theme, not a gradient.
    @Test(arguments: 0..<9)
    func newSpaceIsOneColour(index: Int) {
        let theme = SpaceColorPresets.newSpaceTheme(index: index)
        #expect(theme.key == [SpaceColorPresets.brand[index]])
        let hex = SpaceColorPresets.brand[index]
        #expect(theme.solid && theme.colors == [hex, hex] && theme.dark == nil && !theme.followsSystem)
        #expect(theme.isDark == (HexColor.luminance(hex)! < 0.45))
    }

    /// Arc's pairs: each Brand colour with the second colour Arc saved for it, which keeps roughly
    /// its brightness and lies 29–46° further round the hue wheel.
    @Test(arguments: 0..<9)
    func brandPairs(index: Int) {
        let swatch = SpaceColorPresets.pages[1].swatches[index]
        #expect(swatch == [SpaceColorPresets.brand[index], SpaceColorPresets.brandPairs[index]])
        #expect(SpaceColorPresets.brandPairs[3] == "#EAAF5A")
        let a = SpaceColorWheel.hsb(swatch[0]), b = SpaceColorWheel.hsb(swatch[1])
        #expect(abs(a.brightness - b.brightness) < 0.06)
        if a.saturation > 0.05 {
            let turn = (b.hue - a.hue + 360).truncatingRemainder(dividingBy: 360)
            #expect(turn > 25 && turn < 50)
        }
    }

    /// hsb and hex are inverse to the byte.
    @Test(arguments: SpaceColorPresets.brand + SpaceColorPresets.pastel + SpaceColorPresets.greyscale)
    func wheelRoundTrips(hex: String) {
        let w = SpaceColorWheel.hsb(hex)
        #expect(SpaceColorWheel.hex(hue: w.hue, saturation: w.saturation, brightness: w.brightness) == hex)
    }
}
