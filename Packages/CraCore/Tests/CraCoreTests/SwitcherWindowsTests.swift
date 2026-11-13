import CraCore
import Testing

/// GitHub #401: window switchers (DockDoor, AltTab) listed Cra's Chromium windows as windows of
/// their own, one page made two or three entries, some blank.
struct SwitcherWindowsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/401")) func switchersListWindowsWithButtonsOrAStandardSubrole() {
        // The browser window, and the empty Chrome window its page moved out of, which has buttons.
        #expect(SwitcherWindows.lists(.init(subrole: "AXStandardWindow", hasCloseButton: true, hasMinimizeButton: true)))
        #expect(SwitcherWindows.lists(.init(subrole: "AXDialog", hasCloseButton: true, hasMinimizeButton: true)))
        #expect(SwitcherWindows.lists(.init(subrole: "AXStandardWindow", hasCloseButton: false, hasMinimizeButton: false)))
        #expect(SwitcherWindows.lists(.init(subrole: "AXUnknown", hasCloseButton: true, hasMinimizeButton: false)))
        // Panels (the command bar, the status bubble) are left out.
        #expect(!SwitcherWindows.lists(.init(subrole: "AXSystemDialog", hasCloseButton: false, hasMinimizeButton: false)))
        #expect(!SwitcherWindows.lists(.init(subrole: "AXFloatingWindow", hasCloseButton: false, hasMinimizeButton: false)))
        // A docked window answers as a group inside its parent (#391), whatever buttons it has.
        #expect(!SwitcherWindows.lists(.init(role: "AXGroup", subrole: nil, hasCloseButton: true, hasMinimizeButton: true)))
    }
}
