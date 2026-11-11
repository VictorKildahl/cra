import Foundation

/// Arc's space menu (SpaceMenu.swift in Arc 1.171), the same from the space header's ••• and
/// right-click, the Library's Spaces cards and, since GitHub #339, a right-click on a space's
/// icon in the bottom bar (Arc 1.172.2): no Move Left or Move Right there, dragging reorders.
/// "Share Space…" is left out: it publishes the space through Arc's servers. Search Engine is
/// Cra's (#306).
public enum SpaceMenuLayout {
    public enum Item: Equatable, Sendable {
        case changeIcon, rename, editTheme, setProfile, searchEngine
        case newFolder, liveFolders
        case export
        case manageSpaces, hideSpaceHeader
        case delete
    }

    /// Where the menu was opened.
    public enum Origin: Equatable, Sendable {
        case header, library, dock
    }

    /// The menu's groups, a separator between two. Arc offers Hide Space Header only while there
    /// is one space; Show Space Header brings it back.
    public static func sections(spaceCount: Int) -> [[Item]] {
        [
            [.changeIcon, .rename, .editTheme, .setProfile, .searchEngine],
            [.newFolder, .liveFolders],
            [.export],
            spaceCount == 1 ? [.manageSpaces, .hideSpaceHeader] : [.manageSpaces],
            [.delete],
        ]
    }

    /// Whether choosing `item` opens the space first. From the dock on a space that isn't open,
    /// Arc switches to it for Edit Theme Color… (the editor previews on the sidebar). Cra also
    /// switches for Rename Space…, which renames in the header (Arc does nothing there), and New
    /// Folder, whose name field is in the space's list. Change Space Icon… points at the clicked
    /// icon and leaves the open space open, as in Arc.
    public static func opensSpaceFirst(_ item: Item, from origin: Origin, spaceIsOpen: Bool) -> Bool {
        guard origin == .dock, !spaceIsOpen else { return false }
        switch item {
        case .rename, .editTheme, .newFolder: return true
        default: return false
        }
    }
}
