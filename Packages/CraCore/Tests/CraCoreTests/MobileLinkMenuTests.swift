import Foundation
import Testing
@testable import CraCore

struct MobileLinkMenuTests {
    /// Arc Search's help centre: touch and hold a link, "Open in New Tab" or "Open in Background Tab".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aLinkOpensInANewOrABackgroundTab() {
        let titles = MobileLinkMenu.items(incognito: false).map(\.title)
        #expect(titles == ["Open", "Open in New Tab", "Open in Background Tab", "Copy Link", "Share..."])
    }

    /// An incognito tab closes once it is off screen, so an incognito page has no background row.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func anIncognitoPageHasNoBackgroundTab() {
        let items = MobileLinkMenu.items(incognito: true)
        #expect(!items.contains(.openInBackgroundTab))
        #expect(items.contains(.openInNewTab))
    }

    /// A tab opened in the background joins the end of the row and the page on screen stays.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aBackgroundTabJoinsTheRowUnseen() {
        let shown = MobileTab(url: "https://one.example/", lastActive: .distantPast)
        var document = MobileTabsDocument(tabs: [shown], selected: shown.id)
        let later = MobileTab(url: "https://two.example/", lastActive: .distantPast)
        document.add(later)
        #expect(document.selected == shown.id)
        #expect(document.rowTabs.map(\.id) == [shown.id, later.id])
        #expect(document.closeIncognitoTabsLeftBehind().isEmpty)
    }
}
