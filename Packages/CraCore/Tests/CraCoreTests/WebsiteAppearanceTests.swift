import CraCore
import Foundation
import Testing

/// Arc's View ▸ Appearance (Automatic / Light / Dark for websites) and Settings ▸ Advanced "Play Arc
/// sound effects", added in the Arc parity sweep: settings from before them load as Arc's defaults,
/// and a choice survives a save.
struct WebsiteAppearanceTests {
    @Test func olderSettingsLoadAsArcsDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"httpsOnly": true}"#.utf8))
        #expect(s.websiteAppearance == .automatic)
        #expect(s.soundEffects)
        #expect(s.restoreWindows, "Arc restores windows unless told not to")
        #expect(!s.allowAppleEventsJavaScript, "AppleScript runs no JavaScript until it is turned on, as in Arc")
    }

    @Test func aChoiceSurvivesASave() throws {
        var s = AppSettings()
        s.websiteAppearance = .dark
        s.soundEffects = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.websiteAppearance == .dark && !back.soundEffects)
    }

    @Test func anUnknownValueFallsBackToAutomatic() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"websiteAppearance": "sepia"}"#.utf8))
        #expect(s.websiteAppearance == .automatic)
    }

    @Test func chromiumModes() {
        #expect(WebsiteAppearance.allCases.map(\.chromiumMode) == [0, 1, 2])
    }

    /// Arc's Switch to Light Mode / Dark Mode turn Arc itself, not only its pages; Automatic hands
    /// the browser back to the Mac (#362).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/362"))
    func lightAndDarkTurnTheBrowserToo() {
        #expect(WebsiteAppearance.allCases.map(\.forcesDark) == [nil, false, true])
    }
}
