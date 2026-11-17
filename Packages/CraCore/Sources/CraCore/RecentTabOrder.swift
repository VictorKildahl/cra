import Foundation

/// The order the tab switcher lists tabs in (Arc's ⌃Tab, ModalItemSwitcher): the tab on screen
/// first, then the others by when each was last on screen, newest first. A tab never shown since
/// it opened has no time and stays out.
///
/// "Next Recent Tab in All Spaces" (⌃⌥Tab, #467, not in Arc) lists every space's tabs in the same
/// order. Picking another space's tab shows it, so it becomes the newest and the tab left behind
/// the next newest: a second tap goes back to where it started.
public enum RecentTabOrder {
    public struct Entry: Equatable, Sendable {
        public var id: UUID
        public var lastActive: Date?

        public init(id: UUID, lastActive: Date?) {
            self.id = id
            self.lastActive = lastActive
        }
    }

    /// `entries` in sidebar order (spaces in their order, each one's favorites, pinned, Today).
    /// A tab listed twice (a favorite shared by several spaces, #154) counts once; tabs shown at the
    /// same moment keep the sidebar's order.
    public static func ordered(_ entries: [Entry], current: UUID?) -> [UUID] {
        var seen = Set<UUID>()
        let listed = entries.compactMap { e -> (id: UUID, at: Date)? in
            guard let at = e.lastActive, seen.insert(e.id).inserted else { return nil }
            return (e.id, at)
        }
        return listed.enumerated().sorted { a, b in
            if (a.element.id == current) != (b.element.id == current) { return a.element.id == current }
            if a.element.at != b.element.at { return a.element.at > b.element.at }
            return a.offset < b.offset
        }.map(\.element.id)
    }
}
