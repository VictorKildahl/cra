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
