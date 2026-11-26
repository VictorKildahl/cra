import CraCore
import Testing

/// The site access line in a pinned extension's right-click menu (GitHub #695): Arc's, which is Chromium's
/// extension menu (ExtensionContextMenuModel, the page access items in title case).
struct ExtensionSiteAccessTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func noLineForAnExtensionThatAsksForNoSiteAccess() {
        #expect(ExtensionSiteAccess(engine: nil) == nil)
        #expect(ExtensionSiteAccess(engine: [:]) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func aPageItMayNeverRunOnIsOneGreyLine() {
        let access = ExtensionSiteAccess(engine: ["cantAccess": true])
        #expect(access == .cantAccess)
        #expect(access?.title == "Can't Read or Change Site's Data")
        #expect(access?.rows == [])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func theSubmenuHasChromesThreeChoicesThenLearnMore() {
        // A content script on one site and activeTab: on the site now, "When you click" can be picked, all sites can't.
        let access = ExtensionSiteAccess(engine: ["site": "github.com", "current": "onSite", "enabled": ["onClick", "onSite"]])
        #expect(access == .choices(site: "github.com", current: .onSite, enabled: [.onClick, .onSite]))
        #expect(access?.title == "This Can Read and Change Site Data")
        let rows = access?.rows ?? []
        #expect(rows.map(\.title) == ["When You Click the Extension", "On github.com", "On All Sites", "", "Learn More About Site Access"])
        #expect(rows.map(\.checked) == [false, true, false, false, false])
        #expect(rows.map(\.enabled) == [true, true, false, false, true])
        #expect(rows.map(\.choice) == [.onClick, .onSite, .onAllSites, nil, nil])
        #expect(rows[3].isSeparator)
        #expect(ExtensionSiteAccess.learnMorePage == "https://support.google.com/chrome?p=enable_extensions")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/695"))
    func unknownChoicesFromTheEngineAreLeftOut() {
        let access = ExtensionSiteAccess(engine: ["site": "example.com", "current": "sometimes", "enabled": ["onAllSites", "never"]])
        #expect(access == .choices(site: "example.com", current: nil, enabled: [.onAllSites]))
        #expect(access?.rows.filter(\.checked).isEmpty == true)
    }
}
