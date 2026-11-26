import Foundation

/// The order the tab switcher lists tabs in (Arc's ⌃Tab, ModalItemSwitcher): the tab on screen
/// first, then the others by when each was last on screen, newest first. A tab never shown since
/// it opened has no time and stays out.
///
/// Arc's switcher lists sidebar items, so a split is one card holding its panes (#554): it counts
/// as recent as its newest pane, and picking it goes back to the pane used last.
///
/// "Next Recent Tab in All Spaces" (⌃⌥Tab, #467, not in Arc) lists every space's tabs in the same
/// order. Picking another space's tab shows it, so it becomes the newest and the tab left behind
/// the next newest: a second tap goes back to where it started.
public enum RecentTabOrder {
    /// Whether ⌃Tab lists a pane: only open tabs. A pinned tab or Favorite counts while its page is loaded, but a
    /// Favorite closed with ⌘W leaves the switcher although its page keeps running (#740), until it's picked again
    /// (Arc 1.174.2, #784). The tab on screen always counts.
    public static func listsPane(selected: Bool, pinned: Bool, loaded: Bool, closedWithCmdW: Bool) -> Bool {
        selected || ((!pinned || loaded) && !closedWithCmdW)
    }

    public struct Entry: Equatable, Sendable {
        public var id: UUID
        public var lastActive: Date?
        /// The split the tab is a pane of.
        public var split: UUID?

        public init(id: UUID, lastActive: Date?, split: UUID? = nil) {
            self.id = id
            self.lastActive = lastActive
            self.split = split
        }
    }

    /// One card in the switcher: a tab, or a split with its panes.
    public struct Card: Equatable, Sendable {
        /// The tab, or the split.
        public var id: UUID
        /// The tabs the card shows, in pane order (just the tab for a tab).
        public var panes: [UUID]
        /// Where picking the card goes: the tab, or the split's pane on screen or used last.
        public var opens: UUID
        public var isSplit: Bool
    }

    /// `entries` in sidebar order (spaces in their order, each one's favorites, pinned, Today; a
    /// split's panes one after another). A tab listed twice (a favorite shared by several spaces,
    /// #154) counts once; cards shown at the same moment keep the sidebar's order.
    public static func cards(_ entries: [Entry], current: UUID?) -> [Card] {
        var seen = Set<UUID>()
        var groups: [(key: UUID, split: Bool, panes: [UUID], newest: (id: UUID, at: Date)?)] = []
        var index: [UUID: Int] = [:]
        for e in entries where seen.insert(e.id).inserted {
            let key = e.split ?? e.id
            let i = index[key] ?? {
                groups.append((key, e.split != nil, [], nil))
                index[key] = groups.count - 1
                return groups.count - 1
            }()
            groups[i].panes.append(e.id)
            if let at = e.lastActive, at > (groups[i].newest?.at ?? .distantPast) { groups[i].newest = (e.id, at) }
        }
        let listed = groups.enumerated().compactMap { offset, g -> (offset: Int, at: Date, card: Card)? in
            guard let newest = g.newest else { return nil }
            let opens = current.flatMap { g.panes.contains($0) ? $0 : nil } ?? newest.id
            return (offset, newest.at, Card(id: g.key, panes: g.panes, opens: opens, isSplit: g.split))
        }
        func holdsCurrent(_ c: Card) -> Bool { current.map(c.panes.contains) ?? false }
        return listed.sorted { a, b in
            if holdsCurrent(a.card) != holdsCurrent(b.card) { return holdsCurrent(a.card) }
            if a.at != b.at { return a.at > b.at }
            return a.offset < b.offset
        }.map(\.card)
    }

    /// The tabs the cards open, one per card.
    public static func ordered(_ entries: [Entry], current: UUID?) -> [UUID] {
        cards(entries, current: current).map(\.opens)
    }
}
