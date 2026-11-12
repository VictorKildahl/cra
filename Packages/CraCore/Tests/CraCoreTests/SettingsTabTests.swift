import CraCore
import Testing

/// Arc 1.172.2's Settings window: eight tabs in a toolbar, measured on 11 Nov 2026 (Account, General,
/// Profiles, Max, Links, Shortcuts, Icon, Advanced), and where Cra's own panes sit around them.
struct SettingsTabTests {
    @Test func arcsTabsKeepArcsOrderAndTheFirstIsTheAccountsPlace() {
        #expect(SettingsTab.first == .sync, "Cra has no account: the member card and sync take the first place")
        let arc: [SettingsTab] = [.sync, .general, .profiles, .max, .links, .shortcuts, .icon, .advanced]
        let all = SettingsTab.allCases
        #expect(all.filter(arc.contains) == arc, "Arc's eight, in Arc's order")
        #expect(all.prefix(8).map { $0 } == arc, "Cra's own tabs come after Advanced, so Arc's stay where they are")
    }

    @Test func craOwnPanesAreTheTabsAfterAdvanced() {
        #expect(Array(SettingsTab.allCases.dropFirst(8)) == [.privacy, .extensions])
    }

    @Test func everyTabHasATitleAndTheOldPaneNamesStillOpenSomething() {
        #expect(SettingsTab.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(SettingsTab.allCases.map(\.title)).count == SettingsTab.allCases.count)
        // `cra://debug?settingsPane=` and the command bar's "Search Settings…" named the eleven panes of the
        // sidebar window; Tabs, Plugins and Performance now live inside other tabs.
        #expect(SettingsTab(pane: "general") == .general)
        #expect(SettingsTab(pane: "tabs") == .general)
        #expect(SettingsTab(pane: "plugins") == .extensions)
        #expect(SettingsTab(pane: "performance") == .advanced)
        #expect(SettingsTab(pane: "sync") == .sync)
        #expect(SettingsTab(pane: "icon") == .icon)
        #expect(SettingsTab(pane: "advanced") == .advanced)
        #expect(SettingsTab(pane: "nonsense") == nil)
    }

    @Test func eachOldPaneNameIsKnown() {
        for name in ["general", "tabs", "links", "max", "privacy", "profiles", "extensions", "plugins", "shortcuts", "performance", "advanced"] {
            #expect(SettingsTab(pane: name) != nil, "\(name)")
        }
    }

    @Test func theFirstTabCarriesTheUsersFirstNameAsArcsDoes() {
        #expect(SettingsTab.sync.title(fullName: "Victor Kildahl Petersen") == "Victor")
        #expect(SettingsTab.sync.title(fullName: "  Ada  ") == "Ada")
        #expect(SettingsTab.sync.title(fullName: "") == "Cra", "macOS has no name: the app's")
        #expect(SettingsTab.sync.title == "Cra")
        #expect(SettingsTab.general.title(fullName: "Victor") == "General", "the other tabs keep their names")
        #expect(SettingsTab(pane: "sync") == .sync, "links and scenarios still name it sync")
    }
}
