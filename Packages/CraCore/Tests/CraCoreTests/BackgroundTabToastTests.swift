import CraCore
import Foundation
import Testing

/// Arc's "New Tab Created" toast for every tab opened behind the page while the sidebar is hidden
/// (GitHub #543), not only ⌘Return in the command bar (#85).
struct BackgroundTabToastTests {
    let shown = UUID(), other = UUID()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func hiddenSidebarSaysSo() {
        #expect(BackgroundTabToast.text(sidebarVisible: false, tabSpace: shown, shownSpace: shown, tabSpaceTitle: "Work")
                == "New Tab Created")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func sidebarOutShowsTheRowInstead() {
        #expect(BackgroundTabToast.text(sidebarVisible: true, tabSpace: shown, shownSpace: shown, tabSpaceTitle: "Work") == nil)
        #expect(BackgroundTabToast.text(sidebarVisible: true, tabSpace: other, shownSpace: shown, tabSpaceTitle: "Home") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func anotherSpaceIsNamed() {
        #expect(BackgroundTabToast.text(sidebarVisible: false, tabSpace: other, shownSpace: shown, tabSpaceTitle: "Home")
                == "New Tab Created in Home")
        // No name to give, or no space known: the plain toast.
        #expect(BackgroundTabToast.text(sidebarVisible: false, tabSpace: other, shownSpace: shown, tabSpaceTitle: "")
                == "New Tab Created")
        #expect(BackgroundTabToast.text(sidebarVisible: false, tabSpace: nil, shownSpace: shown, tabSpaceTitle: nil)
                == "New Tab Created")
    }
}

/// Arc's "New Tab Created" toast is a button (GitHub #543, gxcodes): a click opens the tab it announced.
/// Arc's BackgroundTabNotificationContent carries the window and the tab (`windowID`, `itemID`), and
/// another background tab while the toast is up replaces it, so the click opens the newest one.
struct BackgroundTabToastClickTests {
    let first = UUID(), second = UUID()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func clickOpensTheAnnouncedTab() {
        #expect(BackgroundTabToast.clickOpens(announced: [first], isOpen: { _ in true }) == first)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func clickOpensTheNewestOfSeveral() {
        #expect(BackgroundTabToast.clickOpens(announced: [first, second], isOpen: { _ in true }) == second)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/543"))
    func aClosedTabOpensNothing() {
        // Closed (or archived) before the click: nothing opens, not the one before it.
        #expect(BackgroundTabToast.clickOpens(announced: [first, second], isOpen: { $0 == first }) == nil)
        #expect(BackgroundTabToast.clickOpens(announced: [], isOpen: { _ in true }) == nil)
    }
}
