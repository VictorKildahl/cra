import Testing
import CraCore
import Foundation

@Suite struct LinkMenuTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/183"))
    func defaultSwitchesToTheNewTabLikeArc() {
        let items = LinkMenu.items(openLinksInBackground: false)
        #expect(items.map(\.title) == ["Open Link in New Tab", "Open Link in Background Tab"])
        #expect(items.map(\.opensInBackground) == [false, true])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/183"))
    func settingOnKeepsThePageInFrontAndOffersTheSwitch() {
        let items = LinkMenu.items(openLinksInBackground: true)
        #expect(items.map(\.title) == ["Open Link in New Tab", "Open Link in Foreground Tab"])
        #expect(items.map(\.opensInBackground) == [true, false])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/183"))
    func settingIsOffForSettingsWithoutIt() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!s.openLinksInBackground)
    }
}
