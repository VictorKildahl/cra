/// The tab Arc shows after the selected one closes (GitHub #105). Arc 1.171, offline copy driven
/// through its menus, 2 Nov 2026:
/// - It goes back to the tab shown just before, if that one still has a page: not when it was
///   closed (a pinned tab ⌘W unloaded) or hasn't loaded since launch. Only that one tab counts;
///   Arc doesn't walk further back, nor to the tab the closed one was opened from.
/// - Otherwise an unpinned tab hands over to its neighbour in the list, the one above first,
///   loaded or not. A pinned tab or favorite hands over to nothing, and so does the last tab.
public enum CloseSuccessor {
    /// - Parameters:
    ///   - previous: the tab shown in this window just before `closing`, if it is still in the
    ///     same space.
    ///   - hasPage: whether a tab's page is loaded.
    ///   - list: the unpinned tabs top to bottom, `closing` among them; empty for a pinned tab.
    public static func next<ID: Equatable>(closing: ID, previous: ID?, hasPage: (ID) -> Bool, list: [ID]) -> ID? {
        if let previous, previous != closing, hasPage(previous) { return previous }
        guard let i = list.firstIndex(of: closing) else { return nil }
        if i > 0 { return list[i - 1] }
        return i + 1 < list.count ? list[i + 1] : nil
    }
}
