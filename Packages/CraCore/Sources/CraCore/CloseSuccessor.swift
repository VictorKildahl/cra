/// The tab Arc shows after the selected one closes (GitHub #105). Arc 1.171, offline copy driven
/// through its menus, 2 Nov 2026:
/// - It goes back to the tab shown just before, if that one still has a page: not when it was
///   closed (a pinned tab ⌘W unloaded) or hasn't loaded since launch. Only that one tab counts;
///   Arc doesn't walk further back, nor to the tab the closed one was opened from. "Shown just
///   before" is per window and includes a space switch: the tab left in the other space counts,
///   and as it's in another space, nothing goes back to it. Closing one pane of a split keeps
///   the tab shown before the split.
/// - Otherwise an unpinned tab hands over to its neighbour among the Today rows on screen, the one
///   above first, loaded or not: an open folder's tabs count, a closed folder's don't. A pinned
///   tab or favorite hands over to nothing, and so does the last tab.
public enum CloseSuccessor {
    /// - Parameters:
    ///   - previous: the tab shown in this window just before `closing`, if it is still in the
    ///     same space.
    ///   - hasPage: whether a tab's page is loaded.
    ///   - list: the Today tabs shown as rows, top to bottom, `closing` among them; empty for a
    ///     pinned tab.
    public static func next<ID: Equatable>(closing: ID, previous: ID?, hasPage: (ID) -> Bool, list: [ID]) -> ID? {
        if let previous, previous != closing, hasPage(previous) { return previous }
        guard let i = list.firstIndex(of: closing) else { return nil }
        if i > 0 { return list[i - 1] }
        return i + 1 < list.count ? list[i + 1] : nil
    }

    /// What closing a pinned tab or Favorite does: ⌘W, or Close Tab in its own right-click menu.
    public enum PinnedClose: Equatable, Sendable {
        /// Deselected, its page left running: a silent Favorite (Arc 1.173.1, #740: a page's load time and counter carried
        /// on after ⌘W and a click back, and its server saw no second load). Arc's WindowDeselectItemsConfiguration.
        case deselectKeepingPage
        /// Deselected, and taken back to its pinned page in the background, staying loaded: a silent Favorite away from its
        /// pinned page (Arc 1.174.2, #804: the pinned page loaded hidden at the moment of ⌘W, and a click showed that load).
        case deselectGoingHome
        /// Unloaded back to its pinned page: a pinned tab in the list, as in Arc.
        case unloadToPinnedPage
    }

    /// `fromItsMenu`: Close Tab in the Favorite's right-click menu, which closes it in Arc 1.173.1: its page is let go and
    /// a click on the Favorite loads it again. Only ⌘W keeps it running (#740). The menu offers Close Tab only while
    /// the Favorite is shown or loaded, so it is the one way to let a Favorite's page go by hand.
    /// `audible`: the page is making sound. Arc 1.174.2 lets such a Favorite go on ⌘W too, so a video in it stops: the
    /// page got `pagehide` at once and a click loaded it afresh, where a page without sound ran on (#803, 25 Nov 2026).
    /// `awayFromPinnedPage`: the Favorite has moved off its pinned page. Arc 1.174.2 takes a silent one back there on ⌘W,
    /// in the background, so a click on it shows its pinned page without a new load (#804, 25 Nov 2026).
    public static func pinnedClose(isFavorite: Bool, fromItsMenu: Bool = false, audible: Bool = false,
                                   awayFromPinnedPage: Bool = false) -> PinnedClose {
        guard isFavorite, !fromItsMenu, !audible else { return .unloadToPinnedPage }
        return awayFromPinnedPage ? .deselectGoingHome : .deselectKeepingPage
    }

    /// Whether a tab counts as one a close can go back to: its page is loaded and it isn't a Favorite closed with ⌘W. Such a
    /// Favorite keeps its page (#740) but is closed, as Arc's ⌃Tab shows (#784): before 0.1.56 ⌘W unloaded it, so it never
    /// counted, and since then repeated ⌘W on Favorites bounced between the two newest (#870).
    public static func counts(hasPage: Bool, closedWithCmdW: Bool) -> Bool {
        hasPage && !closedWithCmdW
    }

    /// A Favorite ⌘W only deselects (#740, #804): the tab to show instead. Arc goes back through the Favorites visited
    /// before, one further with each ⌘W (Discord report, 26 Nov 2026, #870), so this walks the tabs the window showed
    /// before, newest first (`shownBefore`, ShownTabs), to the first that `counts` (loaded, not closed with ⌘W, in the
    /// same space), else nothing. A Favorite split still hands over to nothing, as a pinned split does (Arc 1.171).
    public static func afterDeselectedFavorite<ID: Equatable>(closing: ID, isSplit: Bool, shownBefore: [ID],
                                                             counts: (ID) -> Bool) -> ID? {
        isSplit ? nil : shownBefore.first { $0 != closing && counts($0) }
    }

    /// A pinned tab or favorite closing (it unloads): back to the previous tab while it has a
    /// page, else nothing. A pinned split hands over to nothing even then (Arc 1.171).
    public static func afterPinned<ID: Equatable>(closing: ID, isSplit: Bool, previous: ID?, hasPage: (ID) -> Bool) -> ID? {
        isSplit ? nil : next(closing: closing, previous: previous, hasPage: hasPage, list: [])
    }
}

/// The tabs a window showed before the one on screen, newest first, each once: where a Favorite's ⌘W walks back to
/// (CloseSuccessor.afterDeselectedFavorite, #870). Not saved: after a relaunch none of them has a page.
public struct ShownTabs<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var newestFirst: [ID] = []
    public let limit: Int

    public init(limit: Int = 50) { self.limit = limit }

    /// The window moved off `id`: it's the newest tab shown before.
    public mutating func left(_ id: ID) {
        newestFirst.removeAll { $0 == id }
        newestFirst.insert(id, at: 0)
        if newestFirst.count > limit { newestFirst.removeLast(newestFirst.count - limit) }
    }

    /// `old` became `new` (a sync merge giving an item another id): it keeps its place.
    public mutating func replace(_ old: ID, with new: ID) {
        guard newestFirst.contains(old) else { return }
        newestFirst.removeAll { $0 == new }
        if let i = newestFirst.firstIndex(of: old) { newestFirst[i] = new }
    }
}
