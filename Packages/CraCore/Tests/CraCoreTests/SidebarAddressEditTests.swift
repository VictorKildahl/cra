import CraCore
import Foundation
import Testing

/// The sidebar URL field edited in place (#344): what a click does and where Return goes.
struct SidebarAddressEditTests {
    let search: (String) -> String = { "https://search.test/?q=" + $0.replacingOccurrences(of: " ", with: "+") }

    /// Off is Arc's field (the command bar); on, a click edits in place. With no tab there is no
    /// address to edit, so the bar makes a new tab either way.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/344"))
    func clickEditsInPlaceOnlyWhenTurnedOnAndATabIsSelected() {
        #expect(SidebarAddressEdit.click(editInPlace: true, hasTab: true) == .editInPlace)
        #expect(SidebarAddressEdit.click(editInPlace: false, hasTab: true) == .commandBarEditURL)
        #expect(SidebarAddressEdit.click(editInPlace: true, hasTab: false) == .commandBarNewTab)
        #expect(SidebarAddressEdit.click(editInPlace: false, hasTab: false) == .commandBarNewTab)
    }

    /// Return loads an address, or searches for anything else, in the tab; an empty field loads nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/344"))
    func returnLoadsAnAddressOrASearchInTheTab() {
        let page = "https://example.org/a"
        #expect(SidebarAddressEdit.commit(typed: "example.org/b", currentURL: page, pinned: false, searchURL: search) == .load("https://example.org/b"))
        #expect(SidebarAddressEdit.commit(typed: "  other.test  ", currentURL: page, pinned: false, searchURL: search) == .load("https://other.test"))
        #expect(SidebarAddressEdit.commit(typed: "cra browser", currentURL: page, pinned: false, searchURL: search) == .load("https://search.test/?q=cra+browser"))
        #expect(SidebarAddressEdit.commit(typed: page, currentURL: page, pinned: false, searchURL: search) == .load(page))
        #expect(SidebarAddressEdit.commit(typed: " \n", currentURL: page, pinned: false, searchURL: search) == SidebarAddressEdit.Commit.none)
    }

    /// A pinned tab keeps to its host, as with ⌘L: another host opens in a new Today tab.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/344"))
    func aPinnedTabSendsAnotherHostToANewTab() {
        let page = "https://example.org/a"
        #expect(SidebarAddressEdit.commit(typed: "example.org/b", currentURL: page, pinned: true, searchURL: search) == .load("https://example.org/b"))
        #expect(SidebarAddressEdit.commit(typed: "other.test", currentURL: page, pinned: true, searchURL: search) == .newTab("https://other.test"))
        #expect(SidebarAddressEdit.commit(typed: "cra browser", currentURL: page, pinned: true, searchURL: search) == .newTab("https://search.test/?q=cra+browser"))
    }

    /// Off in a settings.json written before #344, and it survives a save.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/344"))
    func settingDefaultsOffAndRoundTrips() throws {
        let decoder = JSONDecoder()
        let older = try decoder.decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!older.editAddressInPlace)
        var on = older
        on.editAddressInPlace = true
        #expect(try decoder.decode(AppSettings.self, from: JSONEncoder().encode(on)).editAddressInPlace)
    }
}
