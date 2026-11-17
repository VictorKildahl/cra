import CraCore
import Foundation
import Testing

/// Settings ▸ Advanced ▸ Command bar ▸ "Fill the command bar with the site’s color" (#457): Tab's
/// site search fills the bar with the site's colour instead of Arc's neutral bar.
struct ScopedSearchFillTests {
    /// #454CDB, a blue space.
    let space = RGB(0x45 / 255.0, 0x4C / 255.0, 0xDB / 255.0)

    private func near(_ c: RGB?, _ r: Double, _ g: Double, _ b: Double, within t: Double = 5) -> Bool {
        guard let c else { return false }
        return abs(c.r * 255 - r) <= t && abs(c.g * 255 - g) <= t && abs(c.b * 255 - b) <= t
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/457"))
    func offByDefaultAndKeptInSettingsJSON() throws {
        #expect(!AppSettings().commandBarSiteColor)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"commandBarCurrentSpaceOnly": true}"#.utf8))
        #expect(!old.commandBarSiteColor)
        var settings = AppSettings()
        settings.commandBarSiteColor = true
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.commandBarSiteColor)
        #expect(saved == settings)
        #expect(UsageStats.unreportedSettings.contains("commandBarSiteColor"))
    }

    /// Off, the bar is Arc's, whatever the site.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/457"))
    func offKeepsArcsBar() {
        #expect(ScopedSearchFill.fill(enabled: false, siteColor: "#FF0000", space: space, dark: true) == nil)
        #expect(ScopedSearchFill.fill(enabled: false, siteColor: nil, space: space, dark: false) == nil)
    }

    /// The fills in #457's video, from the sites' own colours.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/457"))
    func darkBarMatchesTheRequest() {
        #expect(near(ScopedSearchFill.fill(enabled: true, siteColor: "#FF0033", space: space, dark: true), 74, 33, 39))
        #expect(near(ScopedSearchFill.fill(enabled: true, siteColor: "#4285F4", space: space, dark: true), 37, 53, 75))
        // Cra's YouTube pill (#FF0000): the same dark red.
        #expect(near(ScopedSearchFill.fill(enabled: true, siteColor: "#FF0000", space: space, dark: true), 75, 35, 35))
    }

    /// Light, a pale wash of the hue under the dark text.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/457"))
    func lightBarIsAPaleWash() throws {
        let red = try #require(ScopedSearchFill.fill(enabled: true, siteColor: "#FF0000", space: space, dark: false))
        #expect(red.r > 0.95 && red.g > 0.85 && red.g < red.r && red.g == red.b)
        let blue = try #require(ScopedSearchFill.fill(enabled: true, siteColor: "#4285F4", space: space, dark: false))
        #expect(blue.b > blue.g && blue.g > blue.r && blue.r > 0.85)
    }

    /// A site without a colour (Chromium's own engines) takes the space's, as its pill does; grey and
    /// black (X) have no hue, so the bar keeps its own.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/457"))
    func spaceColourAndGreys() {
        let fromSpace = ScopedSearchFill.fill(enabled: true, siteColor: nil, space: space, dark: true)
        #expect(fromSpace == ScopedSearchFill.fill(enabled: true, siteColor: "#454CDB", space: space, dark: true))
        #expect(ScopedSearchFill.fill(enabled: true, siteColor: "#000000", space: space, dark: true) == nil)
        #expect(ScopedSearchFill.fill(enabled: true, siteColor: nil, space: RGB(0.5, 0.5, 0.5), dark: true) == nil)
        // An unreadable colour falls back to the space's.
        #expect(ScopedSearchFill.fill(enabled: true, siteColor: "red", space: space, dark: true) == fromSpace)
    }
}
