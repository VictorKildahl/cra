/// What a click on a favorite's tile does (issues #264, #801). A plain click opens the favorite as
/// always; the second click of a double-click on one away from its pinned page takes it back
/// there, as the tile menu's Back to Pinned Page does, the way Arc users go home on a favorite.
/// A favorite on its pinned page has nowhere to go back to, so its double-click only opens it.
/// A ⌘-click opens its page in a new Today tab while keeping the original favorite (#801).
public enum FavoriteClick: Equatable, Sendable {
    case select
    case backToPinnedPage
    case openInNewTab

    private static let relevant: KeyChord.Modifiers = [.shift, .control, .option, .command]

    /// `clickCount` is AppKit's for the release (2 for the second click of a double-click).
    /// `modifiers` is AppKit's `NSEvent.ModifierFlags.rawValue` on the release: ⌘ alone (ignoring
    /// Caps Lock, Fn, etc.) opens the favorite's page in a new Today tab (#801).
    public static func action(clickCount: Int, navigatedAway: Bool, modifiers: UInt = 0) -> FavoriteClick {
        if KeyChord.Modifiers(rawValue: modifiers).intersection(relevant) == .command {
            return .openInNewTab
        }
        return clickCount == 2 && navigatedAway ? .backToPinnedPage : .select
    }
}
