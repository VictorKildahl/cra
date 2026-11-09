import CraCore
import Testing

/// A double-click on a favorite away from its pinned page takes it back there (issue #264).
struct FavoriteClickTests {
    /// The first click opens the favorite as always; the second of a double-click is Back to Pinned Page.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/264"))
    func doubleClickAwayFromItsPageGoesBack() {
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: true) == .select)
        #expect(FavoriteClick.action(clickCount: 2, navigatedAway: true) == .backToPinnedPage)
    }

    /// On its pinned page there is nowhere to go back to, and a third click doesn't load it again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/264"))
    func otherwiseAClickOnlyOpensIt() {
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false) == .select)
        #expect(FavoriteClick.action(clickCount: 2, navigatedAway: false) == .select)
        #expect(FavoriteClick.action(clickCount: 3, navigatedAway: true) == .select)
    }
}
