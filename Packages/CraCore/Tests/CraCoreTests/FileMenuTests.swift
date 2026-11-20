import CraCore
import Testing

/// The File menu has Arc's sections and rows: Share… at the head of the last one, New Profile
/// with New Easel, Close Tab only while a tab is selected (GitHub #279, Arc 1.172.1).
struct FileMenuTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/279"), arguments: [true, false])
    func arcSections(tabSelected: Bool) {
        #expect(FileMenu.shown(tabSelected: tabSelected) == [
            ["newTab", "newWindow", "newBlankWindow", "newIncognitoWindow", "newLittleWindow", "reopenClosedTab"],
            ["editURL"],
            ["newProfile", "newEasel"],
            tabSelected ? ["closeWindow", "closeTab"] : ["closeWindow"],
            ["share", "capturePage", "captureFullPage", "capturePortrait", "savePageAs", "print"],
        ])
    }

    /// ⌘W (Close Tab) closes what is in front. With a tab, the command bar first (#497), then the tab.
    /// A window with no tab, the bar over it or not, closes as a whole, as a new incognito window does
    /// in Arc at once (#644): Close Tab is hidden there, so ⌘W is the window's.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/644"))
    func closeTabClosesWhatIsInFront() {
        #expect(FileMenu.closeTab(commandBarOpen: true, tabSelected: true) == .commandBar)
        #expect(FileMenu.closeTab(commandBarOpen: false, tabSelected: true) == .tab)
        #expect(FileMenu.closeTab(commandBarOpen: true, tabSelected: false) == .window)
        #expect(FileMenu.closeTab(commandBarOpen: false, tabSelected: false) == .window)
    }

    @Test func spaceAndFolderLiveElsewhere() {
        // Arc: Spaces ▸ New Space…, Tabs ▸ New Folder….
        #expect(!FileMenu.sections.joined().contains("newSpace"))
        #expect(!FileMenu.sections.joined().contains("newFolder"))
    }
}
