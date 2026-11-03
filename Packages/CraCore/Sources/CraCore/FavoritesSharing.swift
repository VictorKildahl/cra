import Foundation

/// Settings ▸ Tabs ▸ "Share Favorites across Spaces with the same profile" (GitHub #154). Arc
/// keeps one favorites container per profile (topApps{profile}) that every space on that profile
/// shows. Cra keeps a container per space; with sharing on, the spaces of a profile point at
/// one of them, the first space's in sidebar order, which takes in the others' favorites.
/// Turning it off gives every space its own copy again (SidebarStore).
public enum FavoritesSharing {
    /// A space's favorites as the store holds them.
    public struct SpaceFavorites: Equatable {
        public var spaceID: UUID
        public var profileID: UUID?
        public var containerID: UUID
        /// The container's items in order, with `key(of:children:)` for each.
        public var items: [Entry]

        public init(spaceID: UUID, profileID: UUID?, containerID: UUID, items: [Entry]) {
            self.spaceID = spaceID
            self.profileID = profileID
            self.containerID = containerID
            self.items = items
        }
    }

    public struct Entry: Equatable {
        public var id: UUID
        public var key: String?

        public init(id: UUID, key: String?) {
            self.id = id
            self.key = key
        }
    }

    public struct Move: Equatable {
        public var item: UUID
        public var container: UUID

        public init(item: UUID, container: UUID) {
            self.item = item
            self.container = container
        }
    }

    public struct Plan: Equatable {
        /// The favorites container each space shows.
        public var containers: [UUID: UUID] = [:]
        /// The space each shown container names in its kind: the first space that shows it.
        public var owners: [UUID: UUID] = [:]
        /// Containers to make, empty, for a profile whose first space's container another
        /// profile already shows.
        public var created: [UUID] = []
        /// Favorites that join the end of another container, in this order.
        public var moves: [Move] = []
        /// Favorites of the same page as one already in the list they would join: they go, and
        /// a window that had one open shows the kept one.
        public var duplicates: [UUID: UUID] = [:]
        /// Containers no space shows any more, emptied by `moves` and `duplicates`.
        public var dropped: [UUID] = []

        public init() {}
    }

    /// Spaces in sidebar order (incognito ones left out). A container several spaces already
    /// show is taken in once.
    public static func share(_ spaces: [SpaceFavorites], newID: () -> UUID = UUID.init) -> Plan {
        var plan = Plan()
        var target: [UUID?: UUID] = [:]
        var keys: [UUID: [String: UUID]] = [:]
        var taken: Set<UUID> = []
        func index(_ items: [Entry]) -> [String: UUID] {
            var out: [String: UUID] = [:]
            for e in items { if let k = e.key, out[k] == nil { out[k] = e.id } }
            return out
        }
        for s in spaces {
            if let t = target[s.profileID] {
                plan.containers[s.spaceID] = t
                guard taken.insert(s.containerID).inserted else { continue }
                for e in s.items {
                    if let k = e.key, let kept = keys[t]?[k] {
                        plan.duplicates[e.id] = kept
                    } else {
                        plan.moves.append(Move(item: e.id, container: t))
                        if let k = e.key { keys[t, default: [:]][k] = e.id }
                    }
                }
                plan.dropped.append(s.containerID)
            } else if taken.insert(s.containerID).inserted {
                target[s.profileID] = s.containerID
                plan.containers[s.spaceID] = s.containerID
                plan.owners[s.containerID] = s.spaceID
                keys[s.containerID] = index(s.items)
            } else {
                // Another profile's list: this profile starts its own, empty.
                let c = newID()
                target[s.profileID] = c
                plan.created.append(c)
                plan.containers[s.spaceID] = c
                plan.owners[c] = s.spaceID
            }
        }
        return plan
    }

    /// Turning sharing off: every space after the first that shows a container gets a copy of
    /// it (space → container to copy). The first keeps the favorites themselves, open pages too.
    public static func unshare(_ spaces: [SpaceFavorites]) -> [UUID: UUID] {
        var seen: Set<UUID> = []
        var copies: [UUID: UUID] = [:]
        for s in spaces where !seen.insert(s.containerID).inserted { copies[s.spaceID] = s.containerID }
        return copies
    }

    /// What makes two favorites the same when lists merge: a tab's pinned home, a split's panes'
    /// homes in order. Nil never matches (an empty pane, anything else).
    public static func key(of item: SidebarItem, children: [SidebarItem]) -> String? {
        if let t = item.tab { return t.savedURL.isEmpty ? nil : "tab " + t.savedURL }
        guard item.isSplit else { return nil }
        let homes = children.compactMap { $0.tab?.savedURL }
        guard !homes.isEmpty, !homes.contains(where: \.isEmpty) else { return nil }
        return "split " + homes.joined(separator: " ")
    }
}
