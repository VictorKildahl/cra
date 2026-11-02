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

    /// A pinned tab or favorite closing (it unloads): back to the previous tab while it has a
    /// page, else nothing. A pinned split hands over to nothing even then (Arc 1.171).
    public static func afterPinned<ID: Equatable>(closing: ID, isSplit: Bool, previous: ID?, hasPage: (ID) -> Bool) -> ID? {
        isSplit ? nil : next(closing: closing, previous: previous, hasPage: hasPage, list: [])
    }
}
