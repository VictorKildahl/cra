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
    @Test(arguments: [
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

    /// An appearance-based theme with one half shows that half whatever macOS shows.
    @Test func appearanceBasedWithOneHalfKeepsIt() throws {
        var space = Self.spaces["gradientAppearanceBasedDark"]!
        var info = space["customInfo"] as! [String: Any], wt = info["windowTheme"] as! [String: Any]
        var bg = wt["background"] as! [String: Any], ab = bg["appearanceBased"] as! [String: Any]
        ab["light"] = nil
        bg["appearanceBased"] = ab; wt["background"] = bg; info["windowTheme"] = wt; space["customInfo"] = info
        let theme = try #require(ArcThemeImport.theme(from: space))
        #expect(theme == SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0, appearance: "dark", accent: "#010220"))
    }

    /// A style Cra can't read falls back to the mid tone of Arc's derived palette, which keeps the hue.
    @Test func unknownStyleFallsBackToThePalettesMidTone() throws {
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

    @Test func autoShowsTheHalfMacOSAsksFor() {
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

    /// An Auto theme saved before 0.1.29 (one set of colours) looks as it did on the side its colours
    /// suit and gets a derived half on the other.
    @Test(arguments: ["#F8D558", "#2861B3"])
    func olderAutoThemeKeepsItsSideAndDerivesTheOther(hex: String) {
        let theme = SpaceTheme(colors: [hex, hex], intensity: 0.8, noise: 0.1, appearance: "auto")
        let own = theme.resolved(systemDark: theme.isDark)
        #expect(own.colors == theme.colors && own.isDark == theme.isDark)
        let other = theme.resolved(systemDark: !theme.isDark)
        #expect(other.isDark != theme.isDark && other.colors != theme.colors)
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
        let theme = SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "auto")
        #expect(theme.followsSystem && theme.key == ["#8389FF"])
        let light = theme.resolved(systemDark: false), dark = theme.resolved(systemDark: true)
        #expect(light.colors == ["#8389FF"] && !light.isDark)
        #expect(close(dark.accent, "#01021F") && dark.isDark)
        #expect(SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.5, noise: 0, appearance: "dark").dark == nil)
        // A colour too dark for a light theme is lifted to Arc's default light half.
        let lifted = SpaceThemeVariants.light(key: ["#0000F2"], intensity: 0.5, noise: 0)
        #expect(!lifted.isDark && close(lifted.colors.first, "#CCCCFF"))
    }
}
