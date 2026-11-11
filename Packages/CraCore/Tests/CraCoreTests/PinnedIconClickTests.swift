import CraCore
import Testing

/// The favicon of a pinned tab away from its page takes it back there, by click or double-click.
struct PinnedIconClickTests {
    /// A double-click on the favicon goes back once and doesn't start renaming the tab (#345).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/345"))
    func doubleClickGoesBackWithoutRenaming() {
        let first = PinnedIconClick.action(clickCount: 1, onIcon: true, navigatedAway: true, command: false, previousWentBack: false)
        #expect(first == .backToPinnedPage)
        // The tab is home now, so the second click finds nothing to go back to.
        #expect(PinnedIconClick.action(clickCount: 2, onIcon: true, navigatedAway: false, command: false,
                                       previousWentBack: first.wentBack) == .nothing)
        // A fast second click before the row updates doesn't load the page twice.
        #expect(PinnedIconClick.action(clickCount: 2, onIcon: true, navigatedAway: true, command: false,
                                       previousWentBack: true) == .nothing)
        // ⌘ double-click: the page moves out once.
        let separated = PinnedIconClick.action(clickCount: 1, onIcon: true, navigatedAway: true, command: true, previousWentBack: false)
        #expect(separated == .separateFromPinnedTab && separated.wentBack)
        #expect(PinnedIconClick.action(clickCount: 2, onIcon: true, navigatedAway: false, command: true,
                                       previousWentBack: true) == .nothing)
    }

    /// A double-click on a pinned tab that didn't go back renames it as before, favicon or not.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/345"))
    func otherClicksAreTheRows() {
        #expect(PinnedIconClick.action(clickCount: 2, onIcon: true, navigatedAway: false, command: false, previousWentBack: false) == .row)
        #expect(PinnedIconClick.action(clickCount: 1, onIcon: false, navigatedAway: true, command: false, previousWentBack: false) == .row)
        #expect(PinnedIconClick.action(clickCount: 2, onIcon: false, navigatedAway: true, command: false, previousWentBack: false) == .row)
        #expect(PinnedIconClick.action(clickCount: 1, onIcon: true, navigatedAway: false, command: false, previousWentBack: true) == .row)
        #expect(!PinnedIconClick.row.wentBack && !PinnedIconClick.nothing.wentBack)
    }
}
