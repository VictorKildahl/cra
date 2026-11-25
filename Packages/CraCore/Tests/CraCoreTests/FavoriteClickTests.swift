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

    /// ⌘-click on a favorite tile separates its page into a new Today tab and keeps the favorite open
    /// (#801, Arc 1.174.2), at home or navigated away, on every click of a quick run, Caps Lock and Fn
    /// down or not. Other chords (⌘⌥, ⌘⇧, ⌘⌃) stay clear for their own gestures.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/801"))
    func commandClickSeparatesThePage() {
        let cmd = KeyChord.Modifiers.command.rawValue
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: cmd) == .separateFromFavorite, "⌘-click at home (#801)")
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: true, modifiers: cmd) == .separateFromFavorite, "⌘-click away")
        #expect(FavoriteClick.action(clickCount: 2, navigatedAway: true, modifiers: cmd) == .separateFromFavorite, "a quick second ⌘-click separates again")
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: cmd | (1 << 16) | (1 << 23)) == .separateFromFavorite)
        for chord: KeyChord.Modifiers in [[.command, .option], [.command, .shift], [.command, .control]] {
            #expect(FavoriteClick.action(clickCount: 1, navigatedAway: true, modifiers: chord.rawValue) == .select)
        }
    }
}
