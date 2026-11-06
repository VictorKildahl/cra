/// A collapsed pinned section (a click on the space's name) keeps the pinned row you were last on
/// in sight, also once you pick a favorite or a Today tab, so a glance at the sidebar still says
/// which pinned tab is open. Arc 1.171 keeps one such row per window's sidebar,
/// `peekedPinnedSidebarItemID` beside `pinnedSectionExpansionState`, and doesn't save it with the
/// window. Cra listed only the open tab's row, which vanished the moment you picked another tab
/// (X DM, 6 Nov 2026).
public enum PinnedPeek {
    /// The peeked row once a tab comes on screen: its pinned row (the tab, or the split holding
    /// it) when it has one. A favorite or a Today tab leaves the one before in sight.
    public static func showing<ID>(pinnedRow: ID?, peek: ID?) -> ID? {
        pinnedRow ?? peek
    }

    /// The peeked row as the section collapses: only the open tab's, as a closed folder keeps.
    public static func collapsing<ID>(openPinnedRow: ID?) -> ID? {
        openPinnedRow
    }

    /// The peek once the tab `closed` (or the split `rowOfClosed` holding it) closes (⌘W).
    public static func closing<ID: Equatable>(_ closed: ID, rowOfClosed: ID?, peek: ID?) -> ID? {
        peek == closed || (rowOfClosed != nil && peek == rowOfClosed) ? nil : peek
    }

    /// The rows a collapsed section lists, in sidebar order (`pinnedRows`): the open tab's and the
    /// peeked one, while they are still pinned.
    public static func listed<ID: Hashable>(open: ID?, peek: ID?, pinnedRows: [ID]) -> [ID] {
        let wanted = Set([open, peek].compactMap { $0 })
        return wanted.isEmpty ? [] : pinnedRows.filter(wanted.contains)
    }
}
