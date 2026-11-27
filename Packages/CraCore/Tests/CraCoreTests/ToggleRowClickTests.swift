import CraCore
import Testing

/// A double-click on a space's or a folder's name renames it (X request, 27 Nov 2026); a click still
/// opens or closes it at once, as in Arc.
struct ToggleRowClickTests {
    /// One click anywhere on the row toggles at once, with no wait for a second click.
    @Test func aClickToggles() {
        #expect(ToggleRowClick.action(clickCount: 1, onName: true, firstClickToggled: false) == .toggle)
        #expect(ToggleRowClick.action(clickCount: 1, onName: false, firstClickToggled: true) == .toggle)
    }

    /// The second click of a double-click on the name opens the field and puts back what the first
    /// click opened or closed, so a rename leaves the row as it was.
    @Test func doubleClickOnTheNameRenames() {
        #expect(ToggleRowClick.action(clickCount: 2, onName: true, firstClickToggled: true) == .rename(undoToggle: true))
        #expect(ToggleRowClick.action(clickCount: 2, onName: true, firstClickToggled: false) == .rename(undoToggle: false))
    }

    /// The icon is the toggle's: fast clicks there open and close and never rename (why folders lost
    /// double-click rename in 0.1.18). A third click is the field's, and past it a click toggles.
    @Test func onTheIconADoubleClickStaysTwoToggles() {
        #expect(ToggleRowClick.action(clickCount: 2, onName: false, firstClickToggled: true) == .toggle)
        #expect(ToggleRowClick.action(clickCount: 3, onName: true, firstClickToggled: false) == .toggle)
    }
}
