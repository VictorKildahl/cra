import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ Address Bar (GitHub #305): the placement onboarding asks for, kept in
/// settings.json's `showToolbar`.
struct AddressBarPlacementTests {
    /// Off by default like Arc: the address bar starts in the sidebar.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/305")) func startsInTheSidebar() {
        #expect(AppSettings().addressBarPlacement == .sidebar)
    }

    /// Picking a placement is the toolbar switch that ⇧⌘D and View ▸ Show Toolbar flip.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/305")) func placementIsTheToolbarSwitch() {
        var settings = AppSettings()
        settings.addressBarPlacement = .toolbar
        #expect(settings.showToolbar)
        settings.addressBarPlacement = .sidebar
        #expect(!settings.showToolbar)
        settings.showToolbar.toggle()
        #expect(settings.addressBarPlacement == .toolbar)
    }

    /// No new key: a file saved with the toolbar on reads as the toolbar placement, and the
    /// placement is written back as `showToolbar`.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/305")) func settingsFileKeepsShowToolbar() throws {
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showToolbar": true, "toolbarDefaultMigrated": true}"#.utf8))
        #expect(saved.addressBarPlacement == .toolbar)
        var settings = AppSettings()
        settings.addressBarPlacement = .toolbar
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(json["showToolbar"] as? Bool == true)
        #expect(json["addressBarPlacement"] == nil)
    }

    /// Onboarding and Settings show both choices, sidebar first, each with its own words.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/305")) func bothChoicesAreNamed() {
        #expect(AddressBarPlacement.allCases == [.sidebar, .toolbar])
        #expect(Set(AddressBarPlacement.allCases.map(\.title)).count == 2)
        #expect(Set(AddressBarPlacement.allCases.map(\.detail)).count == 2)
    }
}
