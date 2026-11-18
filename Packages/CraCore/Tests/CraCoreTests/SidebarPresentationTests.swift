import CraCore
import Testing

/// A window with no tab holds its hidden sidebar open, as Arc does (GitHub #483); with a tab the
/// sidebar is as it always was.
struct SidebarPresentationTests {
    /// The report: with the sidebar hidden and no tab open, the sidebar went in whenever the pointer
    /// left it, so picking the next tab meant bringing it out again. Arc keeps it out until a tab opens.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/483"))
    func aWindowWithNoTabHoldsItsHiddenSidebarOpen() {
        let empty = SidebarPresentation(sidebarVisible: false, hasSelectedTab: false)
        #expect(empty.mode == .heldOpen)
        #expect(!empty.mayRetract)
    }

    /// Selecting a tab ends the hold: the hidden sidebar goes on its own again, as before #483.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/483"))
    func aSelectedTabEndsTheHold() {
        let withTab = SidebarPresentation(sidebarVisible: false, hasSelectedTab: true)
        #expect(withTab.mode == .hidden)
        #expect(withTab.mayRetract)
    }

    /// A docked sidebar is docked with or without a tab, and one floating over a full-screen page goes
    /// as it did.
    @Test func aDockedSidebarStaysDocked() {
        for hasSelectedTab in [false, true] {
            let docked = SidebarPresentation(sidebarVisible: true, hasSelectedTab: hasSelectedTab)
            #expect(docked.mode == .docked)
            #expect(docked.mayRetract)
        }
    }

    /// Over a page in full screen the docked sidebar is out of sight and the window's edge brings it out
    /// over the page, as before #483 (#315): it is hidden there, and goes on its own.
    @Test func aSidebarOverAFullscreenPageIsHidden() {
        let overPage = SidebarPresentation(sidebarVisible: true, hasSelectedTab: true, pageFullscreen: true)
        #expect(overPage.mode == .hidden)
        #expect(overPage.mayRetract)
    }

    /// A folder's preview keeps the sidebar out whatever the window shows, as it did before #483.
    @Test func aFolderPreviewKeepsItOut() {
        for sidebarVisible in [false, true] {
            for hasSelectedTab in [false, true] {
                let previewing = SidebarPresentation(sidebarVisible: sidebarVisible, hasSelectedTab: hasSelectedTab,
                                                     folderPreviewOpen: true)
                #expect(!previewing.mayRetract)
            }
        }
    }
}
