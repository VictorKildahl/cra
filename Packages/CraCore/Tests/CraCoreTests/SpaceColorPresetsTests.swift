import Foundation
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

    /// Five pages of nine as in Arc: Brand, Brand sets, Pastel, Drab, Greyscale. A page-2 swatch is
    /// three colours, as Arc saves it (#632; before, Cra's had two).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func pages() {
        #expect(SpaceColorPresets.pages.map(\.group) == ["Brand", "Brand", "Pastel", "Drab", "Greyscale"])
        #expect(SpaceColorPresets.pages.map { $0.seconds != nil } == [false, true, false, false, false])
        for page in SpaceColorPresets.pages {
            #expect(page.swatches.count == 9)
            #expect(page.swatches.allSatisfy { $0.count == (page.seconds == nil ? 1 : 3) })
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
    /// (#155): the colour, flat, while macOS is light (a pastel of it when it reads dark), and the colour
    /// itself over the dark material while macOS is dark, as Arc keeps it (#677).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: 0..<9)
    func newSpaceIsOneColourOnAuto(index: Int) {
        let hex = SpaceColorPresets.brand[index]
        let theme = SpaceColorPresets.newSpaceTheme(index: index)
        #expect(theme.key == [hex] && theme.appearance == "auto" && theme.dark != nil)
        let light = theme.resolved(systemDark: false), dark = theme.resolved(systemDark: true)
        #expect(light.solid && light.colors.count == 2 && light.colors[0] == light.colors[1] && !light.isDark)
        #expect(dark.colors == [hex.uppercased(), hex.uppercased()] && dark.solid && !dark.usesLightMaterial(systemDark: true))
    }

    /// Arc's page-2 sets: each Brand colour with the second and third colours Arc saved for it, at
    /// its P3 brightness and 40° either side round the P3 hue wheel (#632; the 29–46° Cra read before
    /// was the same turn measured in sRGB).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"), arguments: 0..<9)
    func brandPairs(index: Int) {
        let swatch = SpaceColorPresets.pages[1].swatches[index]
        #expect(swatch == [SpaceColorPresets.brand[index], SpaceColorPresets.brandPairs[index], SpaceColorPresets.brandThirds[index]])
        #expect(SpaceColorPresets.brandPairs[3] == "#EAAF5A" && SpaceColorPresets.brandThirds[3] == "#F25EC3")
        // The set is the first colour turned on the wheel: within a byte of Arc's (whose saturated
        // ones run a little past sRGB, so they can't be compared by brightness alone).
        let a = SpaceColorWheel.padHSB(swatch[0])
        for (colour, turn) in zip(swatch.dropFirst(), [40.0, -40]) {
            #expect(Self.near(colour, SpaceColorWheel.padHex(hue: a.hue + turn, saturation: a.saturation, brightness: a.brightness)))
        }
    }

    static func turn(from a: Double, to b: Double, is turn: Double, within slack: Double) -> Bool {
        let d = (b - a - turn).truncatingRemainder(dividingBy: 360)
        return min(abs(d), 360 - abs(d)) <= slack
    }

    /// Whether two colours are the same to within one step of a byte in each channel.
    static func near(_ a: String, _ b: String) -> Bool {
        guard let x = HexColor.components(a), let y = HexColor.components(b) else { return false }
        return max(abs(x.r - y.r), abs(x.g - y.g), abs(x.b - y.b)) <= 1.01 / 255
    }

    /// What Arc 1.174 saved (offline, 20 Nov 2026, StorableSidebar.json read after each run): a
    /// swatch from a page, then + pressed `adds` times. Pages 1, 3, 4 and 5 give one colour that +
    /// takes across the wheel (`complimentary`: 180°, then 150° and 210°); page 2 gives three
    /// colours 40° either side (`analogous`). Before #632 every + went 40° on in sRGB, so Brand red
    /// got an orange where Arc gives a cyan, and three colours never reached the other side.
    static let arcSets: [(page: Int, swatch: Int, adds: Int, wheel: SpaceColorWheel.Wheel, colours: [String])] = [
        (0, 3, 1, .complimentary, ["#F25E6B", "#01E4DB"]),
        (0, 3, 2, .complimentary, ["#F25E6B", "#01E497", "#4FADE6"]),
        (0, 1, 1, .complimentary, ["#F29BBB", "#88E8C9"]),
        (0, 1, 2, .complimentary, ["#F29BBB", "#88E8A1", "#8CE0E8"]),
        (0, 2, 2, .complimentary, ["#A6729D", "#7F9F70", "#68A08C"]),
        (0, 4, 1, .complimentary, ["#FF8558", "#2AC9F4"]),
        (0, 4, 2, .complimentary, ["#FF8558", "#00F3D1", "#5A80F7"]),
        (0, 5, 2, .complimentary, ["#F8D558", "#41CFF7", "#9B6BFA"]),
        (0, 6, 1, .complimentary, ["#34E895", "#F66BBF"]),
        (0, 6, 2, .complimentary, ["#34E895", "#E46CEB", "#F66B81"]),
        (0, 7, 1, .complimentary, ["#6CBAD9", "#E09979"]),
        (0, 7, 2, .complimentary, ["#6CBAD9", "#E4798B", "#D9C773"]),
        (0, 8, 2, .complimentary, ["#666789", "#8A7564", "#738763"]),
        (1, 3, 0, .analogous, ["#F25E6B", "#EAAF5A", "#F25EC3"]),
        (1, 7, 0, .analogous, ["#6CBAD9", "#7F7EDC", "#5CD8B8"]),
        (2, 0, 1, .complimentary, ["#FEFBFA", "#FAFDFE"]),
        (2, 3, 2, .complimentary, ["#FFCBD1", "#C2F8DB", "#C7E8F9"]),
        (2, 4, 1, .complimentary, ["#FFE0D3", "#CEEFFB"]),
        (2, 8, 1, .complimentary, ["#C5C6E5", "#E3E2C2"]),
        (3, 0, 2, .complimentary, ["#4E3A5A", "#565837", "#32593A"]),
        (3, 2, 2, .complimentary, ["#8F4042", "#258762", "#3A6688"]),
        (3, 4, 1, .complimentary, ["#D7B35D", "#6288D7"]),
        (3, 4, 2, .complimentary, ["#D7B35D", "#48BDD4", "#8569D8"]),
        (3, 8, 1, .complimentary, ["#26456B", "#6C5026"]),
        (3, 8, 2, .complimentary, ["#26456B", "#70302A", "#606821"]),
    ]

    /// Every page places + where Arc's does, with Arc's wheel: the reporter's "each page of presets
    /// had different behaviour" (#632).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/632"), arguments: arcSets.indices)
    func eachPageAddsColoursOnArcsWheel(i: Int) {
        let arc = Self.arcSets[i]
        let page = SpaceColorPresets.pages[arc.page]
        var key = page.swatches[arc.swatch], wheel = page.wheel
        for _ in 0..<arc.adds { (key, wheel) = SpaceColorWheel.adding(to: key, wheel: wheel) }
        #expect(wheel == arc.wheel)
        #expect(key.count == arc.colours.count && zip(key, arc.colours).allSatisfy(Self.near), "\(key) vs Arc \(arc.colours)")
    }

    /// − keeps the wheel and puts the rest where it places that many: a complimentary three goes back
    /// to a pair across the wheel, an analogous three to the colour and the one 40° on, and + after −
    /// on an analogous pair brings Arc's third back. Down to one colour, + goes complimentary
    /// whatever page it came from (Arc 1.174, the same runs, #632).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/632"))
    func removeAndAddFollowArcsWheel() {
        let red = SpaceColorPresets.pages[0].swatches[3]
        var (key, wheel) = SpaceColorWheel.adding(to: red, wheel: .complimentary)
        (key, wheel) = SpaceColorWheel.adding(to: key, wheel: wheel)
        let pair = SpaceColorWheel.removing(from: key, wheel: wheel)
        #expect(zip(pair, ["#F25E6B", "#01E4DB"]).allSatisfy(Self.near) && pair.count == 2)

        let set = SpaceColorPresets.pages[1].swatches[3]
        let two = SpaceColorWheel.removing(from: set, wheel: .analogous)
        #expect(two.count == 2 && zip(two, ["#F25E6B", "#EAAF5A"]).allSatisfy(Self.near))
        let back = SpaceColorWheel.adding(to: two, wheel: .analogous)
        #expect(back.wheel == .analogous && zip(back.key, set).allSatisfy(Self.near))
        let one = SpaceColorWheel.removing(from: two, wheel: .analogous)
        #expect(one == ["#F25E6B"])
        let again = SpaceColorWheel.adding(to: one, wheel: .analogous)
        #expect(again.wheel == .complimentary && zip(again.key, ["#F25E6B", "#01E4DB"]).allSatisfy(Self.near))
        #expect(SpaceColorWheel.removing(from: one, wheel: .complimentary).isEmpty)
    }

    /// Dragging any handle turns the set on its wheel: the others keep their turn from the first.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/632"), arguments: SpaceColorWheel.Wheel.allCases, 2...3)
    func dragKeepsTheWheel(wheel: SpaceColorWheel.Wheel, count: Int) {
        let turns = SpaceColorWheel.offsets(wheel, count: count)
        let key = SpaceColorWheel.placed(Array(repeating: "#6CBAD9", count: count), handle: count - 1, hue: 100, saturation: 0.3, wheel: wheel)
        let first = SpaceColorWheel.padHSB(key[0])
        #expect(Self.turn(from: 100 - turns[count - 1], to: first.hue, is: 0, within: 1.5))
        for (colour, turn) in zip(key, turns) {
            #expect(Self.turn(from: first.hue, to: SpaceColorWheel.padHSB(colour).hue, is: turn, within: 1.5))
        }
    }

    /// The wheel is saved with two or three colours and read back, so the editor reopens on it; one
    /// colour saves none. A theme saved before 0.1.53 has none and gets its preset's wheel, else Cra's
    /// old 40° one; a wheel this Cra doesn't know is dropped, not the theme (#632).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/632"))
    func wheelIsSaved() throws {
        let three = SpaceThemeVariants.theme(key: ["#F25E6B", "#01E497", "#4FADE6"], intensity: 0.8, noise: 0, appearance: "light", wheel: .complimentary)
        let saved = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(three))
        #expect(saved.wheel == .complimentary && saved == three)
        let threeJSON = String(decoding: try JSONEncoder().encode(three), as: UTF8.self)
        #expect(threeJSON.contains("\"wheel\":\"complimentary\""))
        let one = SpaceThemeVariants.theme(key: ["#F25E6B"], intensity: 0.8, noise: 0, appearance: "light", wheel: .complimentary)
        let oneJSON = String(decoding: try JSONEncoder().encode(one), as: UTF8.self)
        #expect(one.wheel == nil && !oneJSON.contains("wheel"))
        let odd = ##"{"colors":["#F25E6B","#01E4DB"],"intensity":0.8,"noise":0,"appearance":"light","key":["#F25E6B","#01E4DB"],"wheel":"triad"}"##
        let read = try JSONDecoder().decode(SpaceTheme.self, from: Data(odd.utf8))
        #expect(read.wheel == nil && read.key?.count == 2)
        #expect(SpaceColorPresets.wheel(of: SpaceColorPresets.pages[1].swatches[0]) == .analogous)
        #expect(SpaceColorPresets.wheel(of: ["#F25E6B"]) == .complimentary)
        #expect(SpaceColorPresets.wheel(of: ["#123456", "#345612"]) == .analogous)
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
        // The pad's model is Arc's Display P3 HSB since #632.
        let b = SpaceColorWheel.padHSB(hex).brightness
        for hue in stride(from: 0.0, to: 360, by: 45) {
            let moved = SpaceColorWheel.placed([hex], handle: 0, hue: hue, saturation: 0.5, wheel: .complimentary)
            #expect(moved.count == 1)
            #expect(abs(SpaceColorWheel.padHSB(moved[0]).brightness - b) < 0.01)
            #expect(Self.turn(from: hue, to: SpaceColorWheel.padHSB(moved[0]).hue, is: 0, within: 2))
        }
        let pair = SpaceColorWheel.adding(to: [hex], wheel: .complimentary).key
        let set = SpaceColorWheel.placed(pair, handle: 1, hue: 200, saturation: 0.5, wheel: .complimentary)
        #expect(set.count == 2 && set.allSatisfy { abs(SpaceColorWheel.padHSB($0).brightness - b) < 0.01 })
        #expect(Self.turn(from: 200, to: SpaceColorWheel.padHSB(set[1]).hue, is: 0, within: 2))
        #expect(Self.turn(from: 20, to: SpaceColorWheel.padHSB(set[0]).hue, is: 0, within: 2))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func emptyPadAndGreysOnTheDrag() {
        let first = SpaceColorWheel.placed([], handle: 0, hue: 220, saturation: 0.6, wheel: .complimentary)
        #expect(first.count == 1 && abs(SpaceColorWheel.padHSB(first[0]).brightness - SpaceColorWheel.padBrightness) < 0.01)
        let fromBlack = SpaceColorWheel.placed(["#000000"], handle: 0, hue: 220, saturation: 0.8, wheel: .complimentary)[0]
        #expect(fromBlack != "#000000" && !SpaceColorWheel.isGreyscale(fromBlack))
        #expect(SpaceColorWheel.padHSB(fromBlack).brightness < 0.25)
        let fromGrey = SpaceColorWheel.placed(["#808080"], handle: 0, hue: 220, saturation: 0.8, wheel: .complimentary)[0]
        #expect(abs(SpaceColorWheel.padHSB(fromGrey).brightness - SpaceColorWheel.padHSB("#808080").brightness) < 0.01)
    }

    /// + is off while the first colour is a grey, as Arc's is on its black and white swatches; on
    /// black it added white, a gradient no handle could fix (#455). A coloured one gets a companion
    /// at its own brightness, so a dark colour's is dark too.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func plusIsOffOnGreys() {
        for grey in SpaceColorPresets.greyscale {
            #expect(!SpaceColorWheel.canAdd([grey]))
            #expect(SpaceColorWheel.adding(to: [grey], wheel: .complimentary).key == [grey])
        }
        for hex in SpaceColorPresets.brand + SpaceColorPresets.drab where !SpaceColorWheel.isGreyscale(hex) {
            #expect(SpaceColorWheel.canAdd([hex]))
            let pair = SpaceColorWheel.adding(to: [hex], wheel: .complimentary).key
            #expect(pair.count == 2 && pair[0] == hex)
            #expect(abs(SpaceColorWheel.padHSB(pair[1]).brightness - SpaceColorWheel.padHSB(hex).brightness) < 0.01)
        }
        #expect(!SpaceColorWheel.canAdd([]) && !SpaceColorWheel.canAdd(["#F25E6B", "#EAAF5A", "#A6729D"]))
    }

    /// hsb and hex are inverse to the byte, and so are the pad's P3 padHSB and padHex.
    @Test(arguments: SpaceColorPresets.brand + SpaceColorPresets.pastel + SpaceColorPresets.drab + SpaceColorPresets.greyscale)
    func wheelRoundTrips(hex: String) {
        let w = SpaceColorWheel.hsb(hex)
        #expect(SpaceColorWheel.hex(hue: w.hue, saturation: w.saturation, brightness: w.brightness) == hex)
        let p = SpaceColorWheel.padHSB(hex)
        #expect(SpaceColorWheel.padHex(hue: p.hue, saturation: p.saturation, brightness: p.brightness) == hex)
    }
}
