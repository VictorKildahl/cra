import CraCore
import Foundation
import Testing

/// Fixtures/arc-window-themes.json holds `customInfo.windowTheme` as Arc writes it (background and
/// primaryColorPalette only). The solid ones are the 22 test spaces Arc was measured with for #30;
/// the gradients come from a real Arc profile.
struct ArcThemeImportTests {
    static let spaces: [String: [String: Any]] = {
        let url = Bundle.module.url(forResource: "arc-window-themes", withExtension: "json", subdirectory: "Fixtures")!
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: [String: Any]]
    }()

    static func theme(_ name: String) -> SpaceTheme? {
        ArcThemeImport.theme(from: spaces[name]!)
    }

    /// A one-colour Arc theme (blendedSingleColor) stays that colour, flat, whatever its vibrancy
    /// and text appearance (0.1.22 imported it as a gradient of another colour, #30).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/30"), arguments: [
        ("solidRedDark", "#E63333", 1.0, "dark"),
        ("solidWhiteDark", "#FFFFFF", 1.0, "dark"),
        ("solidWhiteLight", "#FFFFFF", 1.0, "light"),
        ("solidBlueDark", "#2861B3", 1.0, "dark"),
        ("solidBlueHalfIntensity", "#2861B3", 0.5, "dark"),
        ("solidBlueZeroIntensity", "#2861B3", 0.0, "dark"),
        ("solidBlueVibrantLight", "#2861B3", 1.0, "light"),
    ])
    func solidThemeKeepsItsColour(name: String, hex: String, intensity: Double, appearance: String) throws {
        let theme = try #require(Self.theme(name))
        #expect(theme.solid)
        #expect(theme.colors == [hex, hex])
        #expect(theme.accent == hex)
        #expect(theme.intensity == intensity)
        #expect(theme.appearance == appearance)
        #expect(!theme.vibrant, "Arc draws a solid colour the same with or without vibrancy")
    }

    /// Fitted to Arc's rendering in 0.1.23; a change here changes how imported spaces look.
    @Test func vibrantLightGradient() throws {
        let theme = try #require(Self.theme("gradientVibrantLight"))
        #expect(theme == SpaceTheme(colors: ["#F1E58A", "#FBC67D"], intensity: 0.25217215013901756, noise: 0.35,
                                    appearance: "light", vibrant: true, accent: "#F8D558"))
    }

    /// Arc's Auto theme keeps both halves and follows macOS (#155; until 0.1.28 only the dark half came over).
    @Test func appearanceBasedGradientKeepsBothHalves() throws {
        let theme = try #require(Self.theme("gradientAppearanceBasedDark"))
        #expect(theme.appearance == "auto" && theme.followsSystem)
        #expect(theme.resolved(systemDark: true) == SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0,
                                                               appearance: "dark", accent: "#010220"))
        #expect(theme.resolved(systemDark: false) == SpaceTheme(colors: ["#CDCDFC", "#FFE5E5"], intensity: 0.5, noise: 0,
                                                                appearance: "light", accent: "#C8CAFF"))
    }

    /// Arc's `single` theme never follows macOS: one without `contentOverBackgroundAppearance` takes
    /// the side its colours suit instead of Auto, so it is never swapped for a derived half (#171).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/171"), arguments: [("solidRedDark", "dark"), ("solidWhiteLight", "light"), ("gradientVibrantLight", "light")])
    func singleWithoutAppearanceKeepsItsSide(name: String, appearance: String) throws {
        let theme = try #require(ArcThemeImport.theme(from: Self.withoutAppearanceKey(Self.spaces[name]!)))
        #expect(theme.appearance == appearance && !theme.followsSystem)
        #expect(theme.resolved(systemDark: true) == theme && theme.resolved(systemDark: false) == theme)
    }

    static func withoutAppearanceKey(_ space: [String: Any]) -> [String: Any] {
        var space = space
        var info = space["customInfo"] as! [String: Any], wt = info["windowTheme"] as! [String: Any]
        var bg = wt["background"] as! [String: Any], single = bg["single"] as! [String: Any]
        var v = single["_0"] as! [String: Any]
        v["contentOverBackgroundAppearance"] = nil
        single["_0"] = v; bg["single"] = single; wt["background"] = bg; info["windowTheme"] = wt; space["customInfo"] = info
        return space
    }

    /// An appearance-based theme with one half shows that half whatever macOS shows.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/171"))
    func appearanceBasedWithOneHalfKeepsIt() throws {
        var space = Self.spaces["gradientAppearanceBasedDark"]!
        var info = space["customInfo"] as! [String: Any], wt = info["windowTheme"] as! [String: Any]
        var bg = wt["background"] as! [String: Any], ab = bg["appearanceBased"] as! [String: Any]
        ab["light"] = nil
        bg["appearanceBased"] = ab; wt["background"] = bg; info["windowTheme"] = wt; space["customInfo"] = info
        let theme = try #require(ArcThemeImport.theme(from: space))
        #expect(theme == SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0, appearance: "dark", accent: "#010220"))
    }

    /// A style Cra can't read falls back to the mid tone of Arc's derived palette, which keeps the hue.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/30"))
    func unknownStyleFallsBackToThePalettesMidTone() throws {
        let theme = try #require(Self.theme("unknownStyleWithPalette"))
        #expect(theme.solid && theme.colors == ["#8389FF", "#8389FF"])
    }

    @Test func spaceWithoutAThemeImportsNone() {
        #expect(Self.theme("noWindowTheme") == nil)
    }

    /// A fixture space with its background variant (single, or an appearance-based theme's dark
    /// half) changed: the same file, one field different. Returns the half that changed.
    static func theme(_ name: String, changing change: (inout [String: Any]) -> Void) -> SpaceTheme? {
        var space = spaces[name]!
        var systemDark = false
        var info = space["customInfo"] as! [String: Any]
        var wt = info["windowTheme"] as! [String: Any]
        var bg = wt["background"] as! [String: Any]
        if var single = bg["single"] as? [String: Any] {
            var v = single["_0"] as! [String: Any]
            change(&v)
            single["_0"] = v
            bg["single"] = single
        } else {
            var ab = bg["appearanceBased"] as! [String: Any]
            let key = ab["dark"] != nil ? "dark" : "light"
            systemDark = key == "dark"
            var v = ab[key] as! [String: Any]
            change(&v)
            ab[key] = v
            bg["appearanceBased"] = ab
        }
        wt["background"] = bg
        info["windowTheme"] = wt
        space["customInfo"] = info
        return ArcThemeImport.theme(from: space)?.resolved(systemDark: systemDark)
    }

    static func gradient(_ v: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var style = v["style"] as! [String: Any], color = style["color"] as! [String: Any], c0 = color["_0"] as! [String: Any]
        var bg = c0["blendedGradient"] as! [String: Any], g = bg["_0"] as! [String: Any]
        change(&g)
        bg["_0"] = g; c0["blendedGradient"] = bg; color["_0"] = c0; style["color"] = color; v["style"] = style
    }

    /// Arc lets a gradient have one base colour; both stops then come from it.
    @Test(arguments: ["gradientVibrantLight", "gradientAppearanceBasedDark"])
    func oneBaseColourGradient(name: String) throws {
        let full = try #require(Self.theme(name) { _ in })
        let theme = try #require(Self.theme(name) { v in
            Self.gradient(&v) { g in g["baseColors"] = [(g["baseColors"] as! [[String: Any]])[0]] }
        })
        #expect(theme.colors.count == 2 && theme.accent == full.accent, "the first base colour stays the accent")
    }

    /// Only a vibrant light theme gets the over-the-desktop fit; the same gradient opaque keeps its stops.
    @Test func opaqueLightGradientSkipsTheVibrantFit() throws {
        let vibrant = try #require(Self.theme("gradientVibrantLight"))
        let opaque = try #require(Self.theme("gradientVibrantLight") { $0["isVibrant"] = false })
        #expect(!opaque.vibrant && opaque.colors != vibrant.colors && opaque.intensity == vibrant.intensity)
    }

    /// Only an opaque dark theme is darkened over Arc's #2B2632; a vibrant dark one keeps its stops.
    @Test func vibrantDarkGradientIsNotDarkened() throws {
        let opaque = try #require(Self.theme("gradientAppearanceBasedDark") { _ in })
        let vibrant = try #require(Self.theme("gradientAppearanceBasedDark") { $0["isVibrant"] = true })
        #expect(vibrant.vibrant && vibrant.colors != opaque.colors && vibrant.intensity != 1)
    }
}

struct SpaceThemeTests {
    /// sidebar.json written by older versions lacks the newer keys.
    @Test func decodingFillsMissingKeys() throws {
        let theme = try JSONDecoder().decode(SpaceTheme.self, from: Data(##"{"colors":["#112233","#445566"]}"##.utf8))
        #expect(theme == SpaceTheme(colors: ["#112233", "#445566"], intensity: 0.8, noise: 0.15, appearance: "auto"))
    }

    @Test func roundTrips() throws {
        let theme = SpaceTheme(colors: ["#2861B3", "#2861B3"], intensity: 0.5, noise: 0, appearance: "light",
                               vibrant: true, accent: "#2861B3", solid: true)
        #expect(try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(theme)) == theme)
    }

    /// A theme that says its appearance keeps it, whatever its colours.
    @Test func explicitAppearanceWinsOverTheColours() {
        #expect(SpaceTheme(colors: ["#FFFFFF", "#FFFFFF"], intensity: 1, noise: 0, appearance: "dark").isDark)
        #expect(!SpaceTheme(colors: ["#000000", "#000000"], intensity: 1, noise: 0, appearance: "light").isDark)
    }

    @Test(arguments: [("#000000", true), ("#FFFFFF", false), ("#2861B3", true), ("#F8D558", false)])
    func autoAppearanceFollowsTheFirstColour(hex: String, dark: Bool) {
        #expect(SpaceTheme(colors: [hex, hex], intensity: 1, noise: 0, appearance: "auto").isDark == dark)
    }
}

/// An Auto theme follows macOS (Arc: background.appearanceBased), issue #155.
struct SpaceThemeAppearanceTests {
    static let light = SpaceTheme(colors: ["#CDCDFC", "#FFE5E5"], intensity: 0.5, noise: 0, appearance: "light", accent: "#C8CAFF")
    static let dark = SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0, appearance: "dark", accent: "#010220")

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"))
    func autoShowsTheHalfMacOSAsksFor() {
        let theme = SpaceTheme(light: Self.light, dark: Self.dark)
        #expect(theme.followsSystem)
        #expect(theme.resolved(systemDark: false) == Self.light)
        #expect(theme.resolved(systemDark: true) == Self.dark)
    }

    @Test(arguments: [false, true])
    func lightAndDarkKeepTheirLook(systemDark: Bool) {
        #expect(Self.light.resolved(systemDark: systemDark) == Self.light)
        #expect(Self.dark.resolved(systemDark: systemDark) == Self.dark)
    }

    /// An Auto theme with one set of colours (saved before 0.1.29, or an import that had no second
    /// half) stays on the side its colours suit while macOS changes: no derived half (#171).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/171"), arguments: ["#F8D558", "#2861B3", "#F25E6B"])
    func autoThemeWithOneHalfKeepsItsLook(hex: String) {
        let theme = SpaceTheme(colors: [hex, hex], intensity: 0.8, noise: 0.1, appearance: "auto")
        var own = theme
        own.appearance = theme.isDark ? "dark" : "light"
        #expect(theme.resolved(systemDark: false) == own)
        #expect(theme.resolved(systemDark: true) == own)
    }

    /// Every swatch the editor offers, with one, two or three colours on the pad, picked on Auto
    /// follows macOS: a light half while macOS is light, a dark half while it is dark, both kept
    /// through a save, and the editor reopens on Auto. 0.1.30–0.1.32 saved one colour on Auto (the
    /// editor's default) as a fixed light or dark theme, and the space stopped following macOS (#155).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: SpaceColorPresets.pages.flatMap(\.swatches), 1...3)
    func everySwatchOnAutoFollowsMacOS(swatch: [String], colours: Int) throws {
        // The pad's + adds colours round the wheel from the first (SpaceColorWheel).
        let first = SpaceColorWheel.hsb(swatch[0])
        let key = (0..<colours).map { i in
            swatch.indices.contains(i) ? swatch[i]
                : SpaceColorWheel.hex(hue: (first.hue + SpaceColorWheel.offset(i) + 360).truncatingRemainder(dividingBy: 360),
                                      saturation: first.saturation, brightness: first.brightness)
        }
        let theme = SpaceThemeVariants.theme(key: key, intensity: 0.5, noise: 0.2, appearance: "auto")
        // The editor reads its Auto / Light / Dark back from `appearance` (SpaceStyleEditor).
        #expect(theme.appearance == "auto" && theme.followsSystem && theme.key == key)
        let saved = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(theme))
        #expect(saved == theme)
        let light = saved.resolved(systemDark: false), dark = saved.resolved(systemDark: true)
        #expect(!light.isDark && dark.isDark && light.colors != dark.colors)
    }

    /// Light and Dark keep one look whatever macOS shows, for every swatch (#155).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: SpaceColorPresets.pages.flatMap(\.swatches), ["light", "dark"])
    func everySwatchOnLightOrDarkKeepsOneLook(swatch: [String], appearance: String) {
        let theme = SpaceThemeVariants.theme(key: swatch, intensity: 0.5, noise: 0.2, appearance: appearance)
        #expect(!theme.followsSystem && theme.dark == nil && theme.appearance == appearance)
        #expect(theme.resolved(systemDark: false) == theme.resolved(systemDark: true))
        #expect(theme.isDark == (appearance == "dark"))
    }

    /// A dark half written without its optional fields loads with them off, and one that can't be
    /// read at all is dropped: before, either set the whole sidebar.json aside as corrupt.
    @Test func unreadableDarkHalfDropsOnlyTheHalf() throws {
        let partial = ##"{"colors":["#AA0000","#AA0000"],"intensity":1,"noise":0,"appearance":"auto","dark":{"colors":["#110000","#110000"],"intensity":1}}"##
        let theme = try JSONDecoder().decode(SpaceTheme.self, from: Data(partial.utf8))
        #expect(theme.dark == SpaceTheme.Variant(colors: ["#110000", "#110000"], intensity: 1, noise: 0))
        let broken = ##"{"colors":["#AA0000","#AA0000"],"intensity":1,"noise":0,"appearance":"auto","dark":{"colors":5}}"##
        let kept = try JSONDecoder().decode(SpaceTheme.self, from: Data(broken.utf8))
        #expect(kept.dark == nil && kept.colors == ["#AA0000", "#AA0000"])
    }

    /// Both halves and the editor's colours are saved; a theme without them saves as before.
    @Test func roundTripsBothHalves() throws {
        var theme = SpaceTheme(light: Self.light, dark: Self.dark)
        theme.key = ["#8389FF"]
        #expect(try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(theme)) == theme)
        let plain = String(decoding: try JSONEncoder().encode(Self.light), as: UTF8.self)
        #expect(!plain.contains("\"dark\"") && !plain.contains("\"key\""))
    }

    /// The editor's Auto: the light half is the pad's colour (Arc saved the #7FB8D6 swatch picked in
    /// Light as itself); the dark half keeps its hue near Arc's default dark half (key #8389FF → base
    /// #01021F), drawn like an imported dark half.
    @Test func editorHalves() throws {
        func close(_ a: String?, _ b: String) -> Bool {
            guard let a, let x = HexColor.components(a), let y = HexColor.components(b) else { return false }
            return max(abs(x.r - y.r), abs(x.g - y.g), abs(x.b - y.b)) * 255 <= 6
        }
        let theme = SpaceThemeVariants.theme(key: ["#8389FF", "#FF83C8"], intensity: 0.5, noise: 0, appearance: "auto")
        #expect(theme.followsSystem && theme.key == ["#8389FF", "#FF83C8"])
        let light = theme.resolved(systemDark: false), dark = theme.resolved(systemDark: true)
        #expect(light.colors == ["#8389FF", "#FF83C8"] && !light.isDark)
        #expect(close(dark.accent, "#01021F") && dark.isDark)
        // One colour on Auto is a flat fill on both halves: the colour while macOS is light, its hue
        // dark while macOS is dark (#155; not Arc's fixed `single`, see everySwatchOnAutoFollowsMacOS).
        let one = SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "auto")
        #expect(one.followsSystem && one.key == ["#8389FF"])
        #expect(one.resolved(systemDark: false).colors == ["#8389FF", "#8389FF"] && one.resolved(systemDark: false).solid)
        #expect(close(one.resolved(systemDark: true).accent, "#01021F"))
        // In Light it is the same flat colour; in Dark one flat colour keeping its hue.
        #expect(SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "light").solid)
        let darkOne = SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "dark")
        #expect(darkOne.isDark && darkOne.colors.count == 2 && darkOne.colors[0] == darkOne.colors[1])
        #expect(SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "dark").dark == nil)
        // A colour too dark for a light theme is lifted to Arc's default light half.
        let lifted = SpaceThemeVariants.light(key: ["#0000F2"], intensity: 0.5, noise: 0)
        #expect(!lifted.isDark && close(lifted.colors.first, "#CCCCFF"))
    }

    /// A grey or black picked on Auto or Dark stays a neutral grey or black while macOS is dark, as
    /// Arc keeps it (offline Arc 1.172, 12 Nov 2026: black, #1A1A1A and #333333 saved as themselves and
    /// drawn neutral). Cra drew every dark half ~73 % over a purple grey (#2B2632), so black came out
    /// #2F2A36 and nothing could reach a neutral dark shade (#392).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/392"), arguments: SpaceColorPresets.pages[4].swatches, ["auto", "dark"])
    func greysStayNeutralInTheDark(swatch: [String], appearance: String) throws {
        for colours in [swatch, swatch + ["#000000"]] {
            let dark = SpaceThemeVariants.theme(key: colours, intensity: 0.5, noise: 0, appearance: appearance).resolved(systemDark: true)
            #expect(dark.isDark)
            for hex in dark.colors + [try #require(dark.accent)] {
                let c = try #require(HexColor.components(hex))
                #expect(max(c.r, c.g, c.b) - min(c.r, c.g, c.b) < 1.5 / 255, "\(colours) → \(hex)")
            }
        }
    }

    /// A colour that already reads dark is the dark half's colour itself, one dot a flat fill at the
    /// slider's intensity like Arc's: black at full intensity is black over the dark material, and
    /// the slider takes it lighter or darker. Before, the dark half ignored the slider (#392).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/392"), arguments: ["#000000", "#26456B", "#226149", "#4E3A5A"])
    func darkColoursKeepTheirOwnTone(hex: String) {
        for appearance in ["auto", "dark"] {
            let dark = SpaceThemeVariants.theme(key: [hex], intensity: 1, noise: 0, appearance: appearance).resolved(systemDark: true)
            #expect(dark.colors == [hex, hex] && dark.solid && dark.intensity == 1 && dark.accent == hex)
            let faint = SpaceThemeVariants.theme(key: [hex], intensity: 0.2, noise: 0, appearance: appearance).resolved(systemDark: true)
            #expect(faint.intensity == 0.2)
        }
    }

    /// A dark gradient bakes the slider into its stops: more intensity, more of the colour; the
    /// editor reads the slider back from the saved stops (#392).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/392"), arguments: [0.0, 0.3, 0.5, 0.8, 1.0])
    func darkGradientFollowsTheSlider(intensity: Double) throws {
        let key = ["#000000", "#26456B"]
        let theme = SpaceThemeVariants.theme(key: key, intensity: intensity, noise: 0, appearance: "dark")
        #expect(abs(SpaceThemeVariants.padIntensity(of: theme) - intensity) < 0.02)
        let first = try #require(HexColor.components(theme.colors[0]))
        let a = SpaceTheme.solidAlpha(intensity: intensity)
        #expect(abs(first.r * 255 - (1 - a) * 94) <= 1, "black at the slider's opacity over neutral grey")
        let more = SpaceThemeVariants.theme(key: key, intensity: min(1, intensity + 0.2), noise: 0, appearance: "dark")
        if intensity < 1 { #expect((HexColor.luminance(more.colors[0]) ?? 1) < (HexColor.luminance(theme.colors[0]) ?? 0)) }
    }

    /// No colour on the pad (the pad's − took the last one) is Arc's colourless theme: on Auto the
    /// purple light half and the dark half Arc's own default space has, following macOS, as Cra
    /// imports them; Light or Dark keeps that one half. It is saved with an empty pad, so the editor
    /// reopens on "Tap to pick a color for this space". Before, it drew a flat grey (#300).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/300"), arguments: ["auto", "light", "dark"])
    func noColourIsArcsColourlessTheme(appearance: String) throws {
        let arc = try #require(ArcThemeImportTests.theme("gradientAppearanceBasedDark"))
        let theme = SpaceThemeVariants.theme(key: [], intensity: 0.5, noise: 0, appearance: appearance)
        #expect(theme.key == [] && theme.appearance == appearance)
        let saved = try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(theme))
        #expect(saved == theme)
        for systemDark in [false, true] {
            let shownDark = appearance == "auto" ? systemDark : appearance == "dark"
            var shown = saved.resolved(systemDark: systemDark)
            shown.key = nil
            #expect(shown == arc.resolved(systemDark: shownDark))
        }
    }
}
