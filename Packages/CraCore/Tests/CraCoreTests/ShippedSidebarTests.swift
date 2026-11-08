import CraCore
import Foundation
import Testing

/// What closed sidebar issues shipped, where no test of the same type held it already. The
/// settings files are the made-up ones in Fixtures/Model/input.
struct ShippedSidebarTests {
    static func settings(_ name: String) throws -> AppSettings {
        try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.data("input", name))
    }

    static func reloaded(_ settings: AppSettings) throws -> AppSettings {
        try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(settings))
    }

    /// The New Tab row leads Today, where Arc has it (#47): on a new Mac, and once for settings
    /// 0.1.15–0.1.23 saved with the row below Today. Moved back below after that, it stays there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/47"))
    func newTabRowLeadsToday() throws {
        #expect(AppSettings().newTabButtonAtTop, "a first launch has the row above Today")
        let legacy = try Self.settings("settings-legacy.json")
        #expect(legacy.newTabButtonAtTop && legacy.newTabButtonDefaultMigrated,
                "settings saved before the move, with the row below Today, get it above once")
        let chosen = try Self.settings("settings.json")
        #expect(!chosen.newTabButtonAtTop, "settings saved since keep the row where the user put it")
        #expect(try !Self.reloaded(chosen).newTabButtonAtTop && Self.reloaded(legacy).newTabButtonAtTop,
                "and a save and a relaunch keep it there")
    }

    /// Settings ▸ Tabs ▸ Links ▸ "Open links in new tabs in the background" (#183) is off unless
    /// turned on, and survives a restart once on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/183"))
    func backgroundLinksSettingIsKept() throws {
        #expect(!AppSettings().openLinksInBackground)
        let on = try Self.settings("settings.json")
        #expect(try on.openLinksInBackground && Self.reloaded(on).openLinksInBackground)
    }

    /// Peek (#12): links to other sites peek from Favorites and Pinned tabs and Shift-click peeks
    /// from any tab, both on by default as in Arc; "In every tab" is off unless turned on. Settings
    /// saved before these existed get the same.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/12"))
    func peekOptionsDefaultToArcs() throws {
        for s in [AppSettings(), try ModelFixtureTests.decoder.decode(AppSettings.self, from: Data("{}".utf8))] {
            #expect(s.peekLinksToOtherSites && s.peekOnShiftClick && !s.peekInEveryTab)
        }
        let changed = try Self.reloaded(Self.settings("settings.json"))
        #expect(!changed.peekLinksToOtherSites && !changed.peekOnShiftClick && changed.peekInEveryTab, "a choice is kept")
    }
}
