import CraCore
import Testing

struct LittleBarRowsTests {
    /// GitHub #599: picking a page in a Little Window's address bar sometimes brought the browser
    /// window forward instead: the row was an open tab's ("Switch to Tab") or an archived page's
    /// ("Restore"). In a Little Window both load their page in the window.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/599"))
    func littleWindowLoadsOpenTabsAndArchivedPagesInPlace() {
        #expect(LittleBarRows.action(for: .openTab, in: .littleWindow, tabsScope: false) == .loadInWindow)
        #expect(LittleBarRows.action(for: .archivedPage, in: .littleWindow, tabsScope: false) == .loadInWindow)
    }

    /// Scoped to a space's tabs ("%" then Tab), the bar was asked for a tab: that still switches.
    @Test func tabsScopeStillSwitches() {
        #expect(LittleBarRows.action(for: .openTab, in: .littleWindow, tabsScope: true) == .browserWindow)
    }

    /// The browser window's bar and a Peek's switch and restore as before (#379).
    @Test func browserWindowAndPeekKeepTheirRows() {
        for window in [CommandBarOpening.Window.browser, .peek] {
            for row in [LittleBarRows.Row.openTab, .archivedPage] {
                #expect(LittleBarRows.action(for: row, in: window, tabsScope: false) == .browserWindow)
                #expect(LittleBarRows.action(for: row, in: window, tabsScope: true) == .browserWindow)
            }
        }
    }
}
