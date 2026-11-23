import CraCore
import Testing

/// View ▸ Appearance set to Light or Dark (GitHub #700): in Arc that setting is the theme editor's sun
/// and moon, one for the whole browser, and it picks every space's sidebar material without touching
/// its colours (offline Arc 1.172, #455).
struct ForcedAppearanceTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/700"))
    func aForcedAppearancePicksEverySpacesMaterial() {
        // A Dark space on a dark Mac with Cra set to Light: the light material, as for a Light space.
        #expect(SpaceTheme.isLight("dark", systemDark: false, forcedDark: false))
        #expect(!SpaceTheme.isLight("light", systemDark: true, forcedDark: true))
        #expect(SpaceTheme.isLight("auto", systemDark: false, forcedDark: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/700"))
    func automaticLeavesEachSpacesOwn() {
        // View ▸ Appearance ▸ Automatic: a space's Light or Dark as it is, Auto as macOS shows.
        #expect(!SpaceTheme.isLight("dark", systemDark: false, forcedDark: nil))
        #expect(SpaceTheme.isLight("light", systemDark: true, forcedDark: nil))
        #expect(!SpaceTheme.isLight("auto", systemDark: true, forcedDark: nil))
        #expect(SpaceTheme.isLight("light", systemDark: true))
    }
}
