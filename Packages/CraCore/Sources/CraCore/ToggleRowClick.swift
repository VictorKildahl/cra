/// What a click does on a sidebar row whose click opens and closes something: a space header (its
/// pinned tabs; Arc 1.171, a click anywhere but the ••• toggles them) and a folder (Arc: a click
/// opens or closes it). Cra adds a double-click on the name to rename it, as a double-click renames a
/// tab (asked on X, 27 Nov 2026); the menus' Rename stays.
///
/// The first click of a double-click has already toggled, and waiting out the double-click interval
/// made every click feel slow (a 0.2 s wait was tried and dropped, 27 Nov), so the second click puts
/// back what the first changed and opens the name field.
///
/// Folders lost double-click-to-rename in 0.1.18: clicking one fast to open and close it started a
/// rename. Here only the name renames; the icon (the space's chevron, the folder's glyph) keeps
/// toggling however fast the clicks come.
public enum ToggleRowClick: Equatable, Sendable {
    case toggle
    /// Rename; `undoToggle` when the first click of the pair toggled.
    case rename(undoToggle: Bool)

    /// `clickCount` is AppKit's on the release (2 for the second click of a double-click). `onName`:
    /// the click is past the row's icon (the name and the row after it). `firstClickToggled`: this
    /// row's previous click opened or closed it.
    public static func action(clickCount: Int, onName: Bool, firstClickToggled: Bool) -> ToggleRowClick {
        clickCount == 2 && onName ? .rename(undoToggle: firstClickToggled) : .toggle
    }
}
