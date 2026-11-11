/// What a click on the favicon of a pinned tab's sidebar row does (Arc's icon region, GitHub #139).
/// Away from its pinned page, a click there goes back and, with ⌘, moves the page out to a new
/// Today tab first. A double-click there goes back too (#345): its first click already did, so
/// the second, which lands on a tab now at home, does nothing. Otherwise it would count as a
/// double-click on the row and start a rename.
public enum PinnedIconClick: Equatable, Sendable {
    case backToPinnedPage
    case separateFromPinnedTab
    /// The second click of a double-click whose first click went back.
    case nothing
    /// A click anywhere else on the row: select, pick or rename as usual.
    case row

    /// `clickCount` is AppKit's (2 for the second click of a double-click); `previousWentBack`
    /// says whether this row's last click went back or separated.
    public static func action(clickCount: Int, onIcon: Bool, navigatedAway: Bool, command: Bool,
                              previousWentBack: Bool) -> PinnedIconClick {
        if clickCount >= 2 && previousWentBack { return .nothing }
        guard onIcon && navigatedAway else { return .row }
        return command ? .separateFromPinnedTab : .backToPinnedPage
    }

    public var wentBack: Bool { self == .backToPinnedPage || self == .separateFromPinnedTab }
}
