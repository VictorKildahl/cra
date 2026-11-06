import CraCore
import Testing

/// Shipped issues about Peek, the Little Window, Picture in Picture, split view, windows and
/// Capture whose decisions have no test of their own type to sit beside. The rest of the area's
/// promises are marked where they live: PeekTriggerTests (#202), PeekLayoutTests (#204),
/// GlobalShortcutTests, ActionSearchScopeTests and HiddenFrameReleaseTests (#195),
/// PictureInPictureGestureTests (#134), ToolbarCompositionTests and ToolbarRoomTests (#178),
/// ConnectionSecurityTests (#90).
struct ShippedWindowsTests {
    /// ⌥⌘N from any app is on unless turned off, as Arc's "Open Little Arc when I press ⌥⌘N" is
    /// (#195): every settings.json written before the switch existed loads with it on, and Off
    /// stays off through a save.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195"),
          arguments: ["settings.json", "settings-legacy.json", "settings-empty.json", "settings-bad-routes.json"])
    func littleWindowShortcutWorksFromAnyAppUnlessTurnedOff(name: String) throws {
        #expect(AppSettings().littleWindowShortcutEverywhere)
        var settings = try ModelFixtureTests.loadSettings(name).loaded
        #expect(settings.littleWindowShortcutEverywhere)
        settings.littleWindowShortcutEverywhere = false
        let saved = try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(settings))
        #expect(!saved.littleWindowShortcutEverywhere)
    }

    /// The ring round the focused split pane is the space's shadedDark (#178). An Auto space's
    /// ring is the same in both halves: it comes from the light half's colour, whatever macOS
    /// shows and whatever colour the dark half has.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178"), arguments: ["#F8D558", "#2861B3", "#F25E6B"])
    func anAutoSpaceRingsTheFocusedPaneInOneColour(hex: String) {
        let dark = SpaceTheme.Variant(colors: ["#2C273B", "#32263A"], intensity: 1, noise: 0, accent: "#010220")
        let auto = SpaceTheme(colors: [hex], intensity: 0.5, noise: 0, appearance: "auto", accent: hex, dark: dark)
        let oneHalf = SpaceTheme(colors: [hex], intensity: 0.5, noise: 0, appearance: "auto", accent: hex)
        #expect(auto.shadedDark == SpaceTheme.shadedDark(hex))
        #expect(auto.shadedDark == oneHalf.shadedDark)
        #expect(auto.resolved(systemDark: false).shadedDark == auto.shadedDark)
    }
}
