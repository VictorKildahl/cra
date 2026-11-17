import Testing
@testable import CraCore

/// The theme editor's presets (#170): Arc's catalog colours on five pages, one colour by default.
struct SpaceColorPresetsTests {
    /// Arc's ColorPicker colours as Arc writes them (sRGB): Brand4 is the CloudDev red, Brand8 is
    /// the 0.4236, 0.7286, 0.8512 Arc saved for a picked swatch.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func catalogColours() {
        for group in [SpaceColorPresets.brand, SpaceColorPresets.drab, SpaceColorPresets.pastel, SpaceColorPresets.greyscale] {
            #expect(group.count == 9 && Set(group).count == 9)
            #expect(group.allSatisfy { HexColor.components($0) != nil })
        }
        #expect(SpaceColorPresets.brand[3] == "#F25E6B")
        #expect(SpaceColorPresets.brand[7] == "#6CBAD9")
        #expect(SpaceColorPresets.greyscale.first == "#FFFFFF" && SpaceColorPresets.greyscale.last == "#000000")
    }

    /// Five pages of nine as in Arc: Brand, Brand pairs, Pastel, Drab, Greyscale.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func pages() {
        #expect(SpaceColorPresets.pages.map(\.group) == ["Brand", "Brand", "Pastel", "Drab", "Greyscale"])
        #expect(SpaceColorPresets.pages.map { $0.seconds != nil } == [false, true, false, false, false])
        for page in SpaceColorPresets.pages {
            #expect(page.swatches.count == 9)
            #expect(page.swatches.allSatisfy { $0.count == (page.seconds == nil ? 1 : 2) })
        }
    }

    /// The editor opens on the page holding the space's colours.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func pageOfAKey() {
        for (i, page) in SpaceColorPresets.pages.enumerated() {
            for swatch in page.swatches { #expect(SpaceColorPresets.page(of: swatch) == i) }
        }
        #expect(SpaceColorPresets.page(of: ["#f25e6b"]) == 0)
        #expect(SpaceColorPresets.page(of: ["#123456"]) == nil)
    }

    /// A new space starts on one colour (#170) on Auto, so it follows macOS like every Auto space
    /// (#155): the colour, flat, while macOS is light (a pastel of it when it reads dark) and the
    /// colour's hue, dark, while macOS is dark.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: 0..<9)
    func newSpaceIsOneColourOnAuto(index: Int) {
        let hex = SpaceColorPresets.brand[index]
        let theme = SpaceColorPresets.newSpaceTheme(index: index)
        #expect(theme.key == [hex] && theme.appearance == "auto" && theme.dark != nil)
        let light = theme.resolved(systemDark: false), dark = theme.resolved(systemDark: true)
        #expect(light.solid && light.colors.count == 2 && light.colors[0] == light.colors[1] && !light.isDark)
        #expect(dark.colors.count == 2 && dark.colors[0] == dark.colors[1] && dark.isDark)
    }

    /// Arc's pairs: each Brand colour with the second colour Arc saved for it, which keeps roughly
    /// its brightness and lies 29–46° further round the hue wheel.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"), arguments: 0..<9)
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

    /// The pad's − takes colours off down to none, Arc's colourless theme; + adds a second and third
    /// to a colour on the pad (an empty pad gets its first from a tap or a swatch). Before, − stopped
    /// at one colour, so a space could never go back to no colour (#300).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/300"))
    func padButtons() {
        #expect((0...3).map(SpaceColorWheel.canRemove) == [false, true, true, true])
        #expect((0...3).map(SpaceColorWheel.canAdd) == [false, true, true, false])
    }

    /// Dragging a dark colour round the pad keeps it dark, as Arc's pad does (its dark red stayed at
    /// HSB brightness ≈ 0.4 through navy and teal); before, the first touch jumped to brightness
    /// 0.95, a light colour (#455). The set turns together at the first colour's brightness; an
    /// empty pad starts bright; a grey dragged off the centre shows a dark hue, not black.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"), arguments: SpaceColorPresets.drab)
    func dragKeepsTheColoursBrightness(hex: String) {
        let b = SpaceColorWheel.hsb(hex).brightness
        for hue in stride(from: 0.0, to: 360, by: 45) {
            let moved = SpaceColorWheel.placed([hex], handle: 0, hue: hue, saturation: 0.7)
            #expect(moved.count == 1)
            #expect(abs(SpaceColorWheel.hsb(moved[0]).brightness - b) < 0.01)
            #expect(abs(SpaceColorWheel.hsb(moved[0]).hue - hue) < 2 || abs(SpaceColorWheel.hsb(moved[0]).hue - hue) > 358)
        }
        let pair = SpaceColorWheel.adding(to: [hex])
        let set = SpaceColorWheel.placed(pair, handle: 1, hue: 200, saturation: 0.5)
        #expect(set.count == 2 && set.allSatisfy { abs(SpaceColorWheel.hsb($0).brightness - b) < 0.01 })
        #expect(abs(SpaceColorWheel.hsb(set[1]).hue - 200) < 2 && abs(SpaceColorWheel.hsb(set[0]).hue - 160) < 2)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func emptyPadAndGreysOnTheDrag() {
        let first = SpaceColorWheel.placed([], handle: 0, hue: 120, saturation: 1)
        #expect(first.count == 1 && abs(SpaceColorWheel.hsb(first[0]).brightness - SpaceColorWheel.padBrightness) < 0.01)
        let fromBlack = SpaceColorWheel.placed(["#000000"], handle: 0, hue: 220, saturation: 0.8)[0]
        #expect(fromBlack != "#000000" && !SpaceColorWheel.isGreyscale(fromBlack))
        #expect(SpaceColorWheel.hsb(fromBlack).brightness < 0.25)
        let fromGrey = SpaceColorWheel.placed(["#808080"], handle: 0, hue: 220, saturation: 0.8)[0]
        #expect(abs(SpaceColorWheel.hsb(fromGrey).brightness - SpaceColorWheel.hsb("#808080").brightness) < 0.01)
    }

    /// + is off while the first colour is a grey, as Arc's is on its black and white swatches; on
    /// black it added white, a gradient no handle could fix (#455). A coloured one gets a companion
    /// at its own brightness, so a dark colour's is dark too.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func plusIsOffOnGreys() {
        for grey in SpaceColorPresets.greyscale {
            #expect(!SpaceColorWheel.canAdd([grey]))
            #expect(SpaceColorWheel.adding(to: [grey]) == [grey])
        }
        for hex in SpaceColorPresets.brand + SpaceColorPresets.drab where !SpaceColorWheel.isGreyscale(hex) {
            #expect(SpaceColorWheel.canAdd([hex]))
            let pair = SpaceColorWheel.adding(to: [hex])
            #expect(pair.count == 2 && pair[0] == hex)
            #expect(abs(SpaceColorWheel.hsb(pair[1]).brightness - SpaceColorWheel.hsb(hex).brightness) < 0.01)
        }
        #expect(!SpaceColorWheel.canAdd([]) && !SpaceColorWheel.canAdd(["#F25E6B", "#EAAF5A", "#A6729D"]))
    }

    /// hsb and hex are inverse to the byte.
    @Test(arguments: SpaceColorPresets.brand + SpaceColorPresets.pastel + SpaceColorPresets.greyscale)
    func wheelRoundTrips(hex: String) {
        let w = SpaceColorWheel.hsb(hex)
        #expect(SpaceColorWheel.hex(hue: w.hue, saturation: w.saturation, brightness: w.brightness) == hex)
    }
}
