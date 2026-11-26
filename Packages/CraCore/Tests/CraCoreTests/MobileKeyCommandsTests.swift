import Testing
@testable import CraCore

struct MobileKeyCommandsTests {
    /// ⌘T and ⌘L, as on the Mac; Escape needs no modifier.
    @Test func theKeysAreTheMacs() {
        #expect(MobileKeyCommands.Command.newTab.key == .character("t"))
        #expect(MobileKeyCommands.Command.openLocation.key == .character("l"))
        #expect(MobileKeyCommands.Command.closeSearch.key == .escape)
        #expect(MobileKeyCommands.Command.allCases.filter(\.withCommand) == [.newTab, .openLocation])
    }

    /// Over a page: ⌘T searches for a new tab, ⌘L edits the page's address.
    @Test func overAPageTheSearchOpens() {
        #expect(MobileKeyCommands.effect(of: .newTab, searching: false, hasPage: true, covered: false) == .search)
        #expect(MobileKeyCommands.effect(of: .openLocation, searching: false, hasPage: true, covered: false) == .editAddress)
    }

    /// With no page on screen (the empty home, the tab row) there is no address: ⌘L searches.
    @Test func withoutAPageOpenLocationSearches() {
        #expect(MobileKeyCommands.effect(of: .openLocation, searching: false, hasPage: false, covered: false) == .search)
        #expect(MobileKeyCommands.effect(of: .newTab, searching: false, hasPage: false, covered: false) == .search)
    }

    /// Escape only closes the sheet; otherwise it is the page's, which may close its own dialog.
    @Test func escapeIsThePagesUnlessTheSheetIsUp() {
        #expect(MobileKeyCommands.effect(of: .closeSearch, searching: true, hasPage: true, covered: false) == .closeSearch)
        #expect(MobileKeyCommands.effect(of: .closeSearch, searching: false, hasPage: true, covered: false) == nil)
        #expect(MobileKeyCommands.effect(of: .newTab, searching: true, hasPage: true, covered: false) == nil)
        #expect(MobileKeyCommands.effect(of: .openLocation, searching: true, hasPage: true, covered: false) == nil)
    }

    /// Settings, the page menu, onboarding or a summary over the browser: nothing opens under it.
    @Test func nothingHappensUnderAnotherSheet() {
        for command in MobileKeyCommands.Command.allCases {
            for searching in [false, true] {
                #expect(MobileKeyCommands.effect(of: command, searching: searching, hasPage: true, covered: true) == nil)
            }
        }
    }
}
