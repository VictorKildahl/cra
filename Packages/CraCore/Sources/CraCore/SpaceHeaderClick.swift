/// What a click on a space header's row does. Arc 1.171: a click anywhere but the ••• collapses or
/// expands the space's pinned tabs. Cra adds a double-click on the name to rename the space, as a
/// double-click renames a tab (asked on X, 27 Nov 2026); right-click ▸ Rename Space… stays.
///
/// The first click of a double-click has already toggled the pinned tabs, and waiting out the
/// double-click interval would slow every single click, so the second click puts them back as they
/// were and opens the name field.
public enum SpaceHeaderClick: Equatable, Sendable {
    case togglePinned
    /// Rename the space; `undoToggle` when the first click of the pair toggled the pinned tabs.
    case rename(undoToggle: Bool)

    /// `clickCount` is AppKit's on the release (2 for the second click of a double-click). `onName`:
    /// the click is past the icon box (the name and the row after it); the icon box keeps its
    /// chevron's job, so a double-click there toggles twice as before. `firstClickToggled`: this
    /// header's previous click collapsed or expanded the pinned tabs.
    public static func action(clickCount: Int, onName: Bool, firstClickToggled: Bool) -> SpaceHeaderClick {
        clickCount == 2 && onName ? .rename(undoToggle: firstClickToggled) : .togglePinned
    }
}
