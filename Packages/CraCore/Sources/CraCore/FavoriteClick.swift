/// What a click on a favorite's tile does (issues #264, #801). A plain click opens the favorite as
/// always; the second click of a double-click on one away from its pinned page takes it back
/// there, as the tile menu's Back to Pinned Page does, the way Arc users go home on a favorite.
/// A favorite on its pinned page has nowhere to go back to, so its double-click only opens it.
///
/// A ⌘-click separates the page from the favorite, as Arc 1.174.2 does (measured 25 Nov 2026, #801):
/// the page moves to a new Today tab at the top, in the background, and the favorite stays open,
/// back on its pinned page if it was away. The same as ⌘ on a pinned tab's icon (#139).
public enum FavoriteClick: Equatable, Sendable {
    case select
    case backToPinnedPage
    case separateFromFavorite

    private static let relevant: KeyChord.Modifiers = [.shift, .control, .option, .command]

    /// `clickCount` is AppKit's for the release (2 for the second click of a double-click).
    /// `modifiers` is AppKit's `NSEvent.ModifierFlags.rawValue` on the release: ⌘ alone (Caps Lock and
    /// Fn don't count) separates, on every click of a quick run of them.
    public static func action(clickCount: Int, navigatedAway: Bool, modifiers: UInt = 0) -> FavoriteClick {
        if KeyChord.Modifiers(rawValue: modifiers).intersection(relevant) == .command {
            return .separateFromFavorite
        }
        return clickCount == 2 && navigatedAway ? .backToPinnedPage : .select
    }
}
