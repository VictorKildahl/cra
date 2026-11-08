import CraCore
import Foundation
import Testing

/// What closed theme and window-chrome issues shipped, where no older test pinned it: the theme
/// editor's one-colour default (#170), the tooltip tones on a reporter's space (#152) and the
/// edge-to-edge setting (#24).
struct ShippedThemesTests {
    /// A new space starts on one of Arc's Brand colours, alone on the pad, on Auto (#170: Edit
    /// Space no longer starts every theme with two colours). Index 3 is the CloudDev red.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"), arguments: 0..<9)
    func newSpaceStartsOnOneBrandColour(index: Int) {
        let theme = SpaceColorPresets.newSpaceTheme(index: index)
        #expect(theme.key == [SpaceColorPresets.brand[index]])
        #expect(theme.intensity == 0.8 && theme.noise == 0 && theme.appearance == "auto")
        #expect(SpaceColorPresets.page(of: theme.key ?? []) == 0, "the editor opens on Brand, the page holding it")
        #expect(SpaceColorPresets.newSpaceTheme(index: 3).key == ["#F25E6B"])
    }

    /// One colour picked in Light is saved as a solid theme, the same shape an Arc `single`
    /// (`blendedSingleColor`) import has: the colour twice, flat, as its own accent (#170).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"),
          arguments: SpaceColorPresets.pages.flatMap(\.swatches).filter { $0.count == 1 })
    func oneColourIsSavedLikeAnArcSingleImport(swatch: [String]) {
        let hex = swatch[0]
        // A colour too dark for a light theme is lifted to Arc's default light half (editorHalves).
        guard !SpaceTheme(colors: [hex, hex], intensity: 1, noise: 0, appearance: "auto").isDark else { return }
        let theme = SpaceThemeVariants.theme(key: swatch, intensity: 0.8, noise: 0, appearance: "light")
        var imported = SpaceTheme(colors: [hex, hex], intensity: 0.8, noise: 0, appearance: "light", accent: hex, solid: true)
        imported.key = swatch
        #expect(theme == imported)
    }

    /// Every tip in a window takes the focused space's tones, rebuilt from the space's colour
    /// (#152). For the reporter's CloudDev space (#F25E6B) they land within 4/255 of the token
    /// table Arc stores for it (fill 55,0,10, title 244,217,222, profile pill 241,204,211), which
    /// ThemeTonesTests checks from Arc's own shadedDark; here it comes from the theme alone.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/152"))
    func cloudDevTipTakesArcsTones() {
        let cloudDev = SpaceColorPresets.newSpaceTheme(index: 3).resolved(systemDark: false)
        let tones = TooltipTones(theme: cloudDev)
        func near(_ c: RGB, _ e: (Double, Double, Double)) -> Bool {
            abs(c.r * 255 - e.0) <= 4 && abs(c.g * 255 - e.1) <= 4 && abs(c.b * 255 - e.2) <= 4
        }
        #expect(near(tones.fill, (55, 0, 10)))
        #expect(near(tones.title, (244, 217, 222)))
        #expect(near(tones.badge, (241, 204, 211)))
        // Not Little Arc's fixed navy: a blue space's tip is another colour.
        let blue = TooltipTones(theme: SpaceThemeVariants.theme(key: ["#6CBAD9"], intensity: 0.8, noise: 0, appearance: "light"))
        #expect(blue.fill != tones.fill)
    }

    /// Settings ▸ Tabs ▸ "Pages fill the window edge to edge" is off unless chosen, also in a
    /// settings.json from before it existed, and survives a save (#24).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/24"))
    func edgeToEdgeIsOffUnlessChosen() throws {
        #expect(!AppSettings().edgeToEdgeContent)
        let decode = { (json: String) in try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
        #expect(try !decode("{}").edgeToEdgeContent)
        #expect(try decode(#"{"edgeToEdgeContent": true}"#).edgeToEdgeContent)
        var settings = AppSettings()
        settings.edgeToEdgeContent = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).edgeToEdgeContent)
    }
}
