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

    /// ⌘-click on a favorite tile opens its page in a new Today tab (#801), whether at home or
    /// navigated away, and ignores non-shortcut flags like Caps Lock. Other modifier chords
    /// (⌘⌥, ⌘⇧, ⌘⌃) don't open a new tab.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/801"))
    func commandClickOpensInANewTab() {
        let cmd = KeyChord.Modifiers.command.rawValue
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: cmd) == .openInNewTab, "⌘-click opens a new tab (#801)")
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: true, modifiers: cmd) == .openInNewTab)
        #expect(FavoriteClick.action(clickCount: 2, navigatedAway: true, modifiers: cmd) == .openInNewTab, "rapid ⌘-clicks don't reset the favorite")
        // Caps Lock (bit 16) and Fn (bit 23) don't stop ⌘-click.
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: cmd | (1 << 16) | (1 << 23)) == .openInNewTab)
        // Other modifier chords stay clear for their own gestures.
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: KeyChord.Modifiers([.command, .option]).rawValue) == .select)
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: KeyChord.Modifiers([.command, .shift]).rawValue) == .select)
        #expect(FavoriteClick.action(clickCount: 1, navigatedAway: false, modifiers: KeyChord.Modifiers([.command, .control]).rawValue) == .select)
    }
}
