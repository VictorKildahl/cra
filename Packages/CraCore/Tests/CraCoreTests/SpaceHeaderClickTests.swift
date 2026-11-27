import CraCore
import Testing

/// A double-click on a space's name renames it (X request, 27 Nov 2026); a click still collapses or
/// expands its pinned tabs, as in Arc.
struct SpaceHeaderClickTests {
    /// One click anywhere on the row toggles the pinned tabs at once, with no wait for a second click.
    @Test func aClickTogglesThePinnedTabs() {
        #expect(SpaceHeaderClick.action(clickCount: 1, onName: true, firstClickToggled: false) == .togglePinned)
        #expect(SpaceHeaderClick.action(clickCount: 1, onName: false, firstClickToggled: true) == .togglePinned)
    }

    /// The second click of a double-click on the name opens the field and puts back the pinned tabs
    /// the first click collapsed or expanded, so a rename leaves the section as it was.
    @Test func doubleClickOnTheNameRenames() {
        #expect(SpaceHeaderClick.action(clickCount: 2, onName: true, firstClickToggled: true) == .rename(undoToggle: true))
        #expect(SpaceHeaderClick.action(clickCount: 2, onName: true, firstClickToggled: false) == .rename(undoToggle: false))
    }

    /// The icon box is the chevron's: a double-click there collapses and expands as before. A third
    /// click is the field's, and anything past it toggles as a click does.
    @Test func elsewhereADoubleClickStaysTwoToggles() {
        #expect(SpaceHeaderClick.action(clickCount: 2, onName: false, firstClickToggled: true) == .togglePinned)
        #expect(SpaceHeaderClick.action(clickCount: 3, onName: true, firstClickToggled: false) == .togglePinned)
    }
}
