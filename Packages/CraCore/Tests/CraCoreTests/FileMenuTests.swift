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

    @Test func spaceAndFolderLiveElsewhere() {
        // Arc: Spaces ▸ New Space…, Tabs ▸ New Folder….
        #expect(!FileMenu.sections.joined().contains("newSpace"))
        #expect(!FileMenu.sections.joined().contains("newFolder"))
    }
}
