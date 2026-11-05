import Testing
import CraCore
import Foundation

@Suite struct LinkMenuTests {
    @Test func defaultSwitchesToTheNewTabLikeArc() {
        let items = LinkMenu.items(openLinksInBackground: false)
        #expect(items.map(\.title) == ["Open Link in New Tab", "Open Link in Background Tab"])
        #expect(items.map(\.opensInBackground) == [false, true])
    }

    @Test func settingOnKeepsThePageInFrontAndOffersTheSwitch() {
        let items = LinkMenu.items(openLinksInBackground: true)
        #expect(items.map(\.title) == ["Open Link in New Tab", "Open Link in Foreground Tab"])
        #expect(items.map(\.opensInBackground) == [true, false])
    }

    @Test func settingIsOffForSettingsWithoutIt() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!s.openLinksInBackground)
    }
}
