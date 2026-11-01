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

    @Test func darkVariantOfAnAppearanceBasedGradient() throws {
        let theme = try #require(Self.theme("gradientAppearanceBasedDark"))
        #expect(theme == SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0,
                                    appearance: "dark", accent: "#010220"))
    }

    /// A style Cra can't read falls back to the mid tone of Arc's derived palette, which keeps the hue.
    @Test func unknownStyleFallsBackToThePalettesMidTone() throws {
        let theme = try #require(Self.theme("unknownStyleWithPalette"))
        #expect(theme.solid && theme.colors == ["#8389FF", "#8389FF"])
    }

    @Test func spaceWithoutAThemeImportsNone() {
        #expect(Self.theme("noWindowTheme") == nil)
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

    @Test(arguments: [("#000000", true), ("#FFFFFF", false), ("#2861B3", true), ("#F8D558", false)])
    func autoAppearanceFollowsTheFirstColour(hex: String, dark: Bool) {
        #expect(SpaceTheme(colors: [hex, hex], intensity: 1, noise: 0, appearance: "auto").isDark == dark)
    }
}
