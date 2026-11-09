/// What a click on a favorite's tile does (issue #264). The first click opens the favorite as
/// always; the second click of a double-click on one away from its pinned page takes it back
/// there, as the tile menu's Back to Pinned Page does, the way Arc users go home on a favorite.
/// A favorite on its pinned page has nowhere to go back to, so its double-click only opens it.
public enum FavoriteClick: Equatable, Sendable {
    case select
    case backToPinnedPage

    /// `clickCount` is AppKit's for the release (2 for the second click of a double-click).
    public static func action(clickCount: Int, navigatedAway: Bool) -> FavoriteClick {
        clickCount == 2 && navigatedAway ? .backToPinnedPage : .select
    }
}
