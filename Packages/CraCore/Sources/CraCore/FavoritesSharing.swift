import Foundation

/// Settings ▸ Tabs ▸ "Share Favorites across Spaces with the same profile" (GitHub #154), Arc's
/// favorites: one list per profile (StorableSidebar topApps{profile}) that every space on the
/// profile shows. The list belongs to the profile, not to a space: a space that changes profile
/// shows the other profile's list and takes nothing along, and a list nobody shows stays until a
/// space uses the profile again. Off, Cra's favorites are per space; SidebarStore turns one
/// shape into the other.
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

    /// A profile's list and what is in it.
    public struct ProfileList: Equatable {
        public var list: ProfileFavorites
        public var items: [Entry]

        public init(_ list: ProfileFavorites, items: [Entry]) {
            self.list = list
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
        /// Every profile's list afterwards: the ones there were, then new ones.
        public var lists: [ProfileFavorites] = []
        /// Lists to make, empty.
        public var created: [UUID] = []
        /// The list each space shows.
        public var containers: [UUID: UUID] = [:]
        /// Favorites that join the end of a list, in this order.
        public var moves: [Move] = []
        /// Favorites of the same page as one the list already has: they go, and a window
        /// that had one open shows the kept one.
        public var duplicates: [UUID: UUID] = [:]
        /// Space containers emptied into a list.
        public var dropped: [UUID] = []

        public init() {}
    }

    /// Sharing on: each space shows its profile's list, made when the profile has none, and its
    /// own favorites join it in sidebar order. Already shared, nothing changes.
    public static func share(_ spaces: [SpaceFavorites], lists: [ProfileList], newID: () -> UUID = UUID.init) -> Plan {
        var plan = Plan()
        plan.lists = lists.map(\.list)
        var target: [UUID?: UUID] = [:]
        var keys: [UUID: [String: UUID]] = [:]
        var taken: Set<UUID> = []
        for l in lists where target[l.list.profileID] == nil {
            target[l.list.profileID] = l.list.containerID
            keys[l.list.containerID] = index(l.items, into: [:])
        }
        for l in lists { taken.insert(l.list.containerID) }
        for s in spaces {
            let t: UUID
            if let known = target[s.profileID] {
                t = known
            } else {
                t = newID()
                target[s.profileID] = t
                plan.created.append(t)
                plan.lists.append(ProfileFavorites(profileID: s.profileID, containerID: t))
                taken.insert(t)
            }
            plan.containers[s.spaceID] = t
            guard taken.insert(s.containerID).inserted else { continue }
            // A page the list already had goes; two of a page from one space both stay.
            let before = keys[t] ?? [:]
            for e in s.items {
                if let k = e.key, let kept = before[k] {
                    plan.duplicates[e.id] = kept
                } else {
                    plan.moves.append(Move(item: e.id, container: t))
                }
            }
            keys[t] = index(s.items.filter { plan.duplicates[$0.id] == nil }, into: before)
            plan.dropped.append(s.containerID)
        }
        return plan
    }

    /// Sharing off: the spaces showing a list each get a list of their own. The first in sidebar
    /// order takes the favorites themselves, open pages too; the others get copies. Lists no
    /// space shows stay with their profiles.
    public struct Split: Equatable {
        public var spaceID: UUID
        public var from: UUID
        /// True for the space that takes the favorites, false for a copy.
        public var takes: Bool

        public init(spaceID: UUID, from: UUID, takes: Bool) {
            self.spaceID = spaceID
            self.from = from
            self.takes = takes
        }
    }

    public static func unshare(_ spaces: [SpaceFavorites], lists: [ProfileFavorites]) -> [Split] {
        let listIDs = Set(lists.map(\.containerID))
        var seen: Set<UUID> = []
        return spaces.filter { listIDs.contains($0.containerID) }.map {
            Split(spaceID: $0.spaceID, from: $0.containerID, takes: seen.insert($0.containerID).inserted)
        }
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

    private static func index(_ items: [Entry], into start: [String: UUID]) -> [String: UUID] {
        var out = start
        for e in items { if let k = e.key, out[k] == nil { out[k] = e.id } }
        return out
    }
}
