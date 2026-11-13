import CraCore
import Testing

/// The space menu: one menu for the header, the Library's cards and the dock's icons (#339).
struct SpaceMenuLayoutTests {
    /// Arc 1.172.2's menu on a dock icon is the header's, item for item: no Edit Space…, Move
    /// Left or Move Right.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/339"))
    func dockShowsArcsWholeSpaceMenu() {
        #expect(SpaceMenuLayout.sections(spaceCount: 3) == [
            [.changeIcon, .rename, .editTheme, .setProfile, .searchEngine],
            [.newFolder, .liveFolders],
            [.export],
            [.manageSpaces],
            [.delete],
        ])
        // With one space Arc adds Hide Space Header after Manage Spaces….
        #expect(SpaceMenuLayout.sections(spaceCount: 1)[3] == [.manageSpaces, .hideSpaceHeader])
    }

    /// An incognito window's space menu leaves out what an incognito space can't do, as Spaces ▸
    /// Change Profile, Delete Space and Manage Spaces… are off in its window: its pages load in
    /// one off-the-record context whatever profile it names, its tabs never move into a saved
    /// space (Export), and live folders aren't made there (#413).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/413"))
    func incognitoSpaceOffersNoProfile() {
        for count in [1, 3] {
            #expect(SpaceMenuLayout.sections(spaceCount: count, incognito: true) == [
                [.changeIcon, .rename, .editTheme, .searchEngine],
                [.newFolder],
            ])
        }
    }

    /// From the dock on another space, Edit Theme Color…, Rename Space… and New Folder open that
    /// space first; Change Space Icon… points at the icon and the open space stays open.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/339"))
    func dockOpensTheSpaceForItsListAndHeader() {
        let switching: [SpaceMenuLayout.Item] = [.rename, .editTheme, .newFolder]
        for item in SpaceMenuLayout.sections(spaceCount: 1).flatMap({ $0 }) {
            #expect(SpaceMenuLayout.opensSpaceFirst(item, from: .dock, spaceIsOpen: false) == switching.contains(item), "\(item)")
            #expect(!SpaceMenuLayout.opensSpaceFirst(item, from: .dock, spaceIsOpen: true), "\(item)")
            #expect(!SpaceMenuLayout.opensSpaceFirst(item, from: .header, spaceIsOpen: false), "\(item)")
            #expect(!SpaceMenuLayout.opensSpaceFirst(item, from: .library, spaceIsOpen: false), "\(item)")
        }
    }
}
