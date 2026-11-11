import Foundation
import CraCore
import Testing

/// The menu on several picked sidebar tabs (GitHub #356): Arc's sections, Copy URLs and Share for
/// all of them at once.
struct PickedTabsMenuTests {
    private func rows(_ picks: PickedTabsMenu.Picks) -> [String] {
        PickedTabsMenu.shown(for: picks).map { $0.map { PickedTabsMenu.title($0, for: picks) }.joined(separator: "|") }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/356"))
    func twoPicksGetArcsRowsWithCopyAndShare() {
        #expect(rows(.init(count: 2, hasFolders: true)) == [
            "Open in Split View|Duplicate",
            "Copy URLs|Share 2 Items",
            "Move to Space|Move 2 Tabs to Folder|New Folder with 2 Items",
            "Change Icon|Mute",
            "Close 2 Tabs|Deselect All",
        ])
    }

    @Test func splitViewTakesTwoToFourTabsNotInASplit() {
        #expect(PickedTabsMenu.shows("openInSplitView", for: .init(count: 4)))
        #expect(!PickedTabsMenu.shows("openInSplitView", for: .init(count: 5)))
        #expect(!PickedTabsMenu.shows("openInSplitView", for: .init(count: 1)))
        #expect(!PickedTabsMenu.shows("openInSplitView", for: .init(count: 3, anyInSplit: true)))
        #expect(rows(.init(count: 5)).first == "Duplicate")
    }

    @Test func noFolderNoMoveToFolder() {
        #expect(rows(.init(count: 3))[2] == "Move to Space|New Folder with 3 Items")
    }

    @Test func allMutedUnmutes() {
        #expect(PickedTabsMenu.title("mute", for: .init(count: 2, allMuted: true)) == "Unmute")
        #expect(PickedTabsMenu.title("mute", for: .init(count: 2, allMuted: false)) == "Mute")
    }

    @Test func onlyChangeIconIsDimmed() {
        let dimmed = PickedTabsMenu.sections.joined().filter { !PickedTabsMenu.isEnabled($0) }
        #expect(dimmed == ["changeIcon"])
    }
}
