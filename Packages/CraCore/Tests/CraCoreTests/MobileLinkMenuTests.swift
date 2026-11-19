import Foundation
import Testing
@testable import CraCore

struct MobileLinkMenuTests {
    /// Arc Search's help centre: touch and hold a link, "Open in New Tab" or "Open in Background
    /// Tab"; Victor added "Open in Incognito" (#572). The order is Cra's: Arc Search's was not found.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aLinkOpensInANewABackgroundOrAnIncognitoTab() {
        let titles = MobileLinkMenu.items(incognito: false).map(\.title)
        #expect(titles == ["Open", "Open in New Tab", "Open in Background Tab", "Open in Incognito", "Copy Link", "Share..."])
    }

    /// On a private page every new tab is private already: no "Open in Incognito", and a
    /// background tab waits in the private session (`aPrivateBackgroundTabWaitsUntilSeen`).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func anIncognitoPageOpensLinksPrivately() {
        let titles = MobileLinkMenu.items(incognito: true).map(\.title)
        #expect(titles == ["Open", "Open in New Tab", "Open in Background Tab", "Copy Link", "Share..."])
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

    /// A private tab opened in the background waits, unseen, while the private session goes on,
    /// and shows in the tab row then; once looked at it closes when left, like any private tab,
    /// and leaving private browsing closes it whether seen or not.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aPrivateBackgroundTabWaitsUntilSeen() {
        let normal = MobileTab(url: "https://normal.example/", lastActive: .distantPast)
        let secret = MobileTab(url: "https://secret.example/", lastActive: .distantPast, isIncognito: true)
        var document = MobileTabsDocument(tabs: [normal, secret], selected: secret.id)
        let first = MobileTab(url: "https://later.example/1", lastActive: .distantPast, isIncognito: true)
        let second = MobileTab(url: "https://later.example/2", lastActive: .distantPast, isIncognito: true)
        document.addInBackground(first)
        document.addInBackground(second)
        #expect(document.closeIncognitoTabsLeftBehind().isEmpty)
        #expect(document.switcherTabs.map(\.id) == [normal.id, first.id, second.id])

        // Looked at: the page it came from was seen and left, so it closes; the other still waits.
        document.select(first.id, now: .distantFuture)
        #expect(document.closeIncognitoTabsLeftBehind() == [secret.id])
        #expect(document.switcherTabs.map(\.id) == [normal.id, second.id])

        // Back to a normal tab: the private session ends, the unseen one with it.
        document.select(normal.id, now: .distantFuture)
        #expect(Set(document.closeIncognitoTabsLeftBehind()) == [first.id, second.id])
        #expect(document.tabs.map(\.id) == [normal.id])
        #expect(document.switcherTabs.map(\.id) == [normal.id])
    }

    /// A normal tab opened in the background is in the row like any other, private or not.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aNormalBackgroundTabIsInTheRow() {
        let shown = MobileTab(url: "https://one.example/", lastActive: .distantPast)
        var document = MobileTabsDocument(tabs: [shown], selected: shown.id)
        let later = MobileTab(url: "https://two.example/", lastActive: .distantPast)
        document.addInBackground(later)
        #expect(document.switcherTabs.map(\.id) == [shown.id, later.id])
        #expect(document.rowTabs.map(\.id) == [shown.id, later.id])
    }
}

struct MobileAddressEditTests {
    /// The page menu's address opens the search sheet with the page's address in it (#572).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func theAddressIsThePagesOwn() {
        #expect(MobileAddressEdit.text(tabAddress: "https://example.com/", pageAddress: "https://example.com/a?b=c") == "https://example.com/a?b=c")
        // Not loaded yet: the tab's address.
        #expect(MobileAddressEdit.text(tabAddress: "https://example.com/", pageAddress: nil) == "https://example.com/")
        #expect(MobileAddressEdit.text(tabAddress: "", pageAddress: "about:blank") == "")
    }

    /// A Browse for Me page has no address of its own: its question is what gets edited.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func aBrowseForMePageEditsItsQuestion() {
        let address = MobileBrowseForMe.tabAddress(query: "pizza ovens")
        #expect(MobileAddressEdit.text(tabAddress: address, pageAddress: "about:blank") == "pizza ovens")
    }

    /// Editing the address loads in the same tab; + opens a new one. A sheet switched to the other
    /// side of incognito than the tab can't load there (its private data store is fixed), so it
    /// opens a new tab.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/572")) func anEditedAddressStaysInItsTab() {
        #expect(MobileAddressEdit.target(editing: true, tabIsIncognito: false, sheetIsIncognito: false) == .currentTab)
        #expect(MobileAddressEdit.target(editing: true, tabIsIncognito: true, sheetIsIncognito: true) == .currentTab)
        #expect(MobileAddressEdit.target(editing: false, tabIsIncognito: false, sheetIsIncognito: false) == .newTab)
        #expect(MobileAddressEdit.target(editing: true, tabIsIncognito: false, sheetIsIncognito: true) == .newTab)
        #expect(MobileAddressEdit.target(editing: true, tabIsIncognito: true, sheetIsIncognito: false) == .newTab)
    }
}
