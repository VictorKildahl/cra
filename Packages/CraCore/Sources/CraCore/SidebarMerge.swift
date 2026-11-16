import Foundation

/// Two Macs' sidebars put together for sync (SettingsSyncService). `base` is the bundle both
/// were written from, `local` this Mac's sidebar now, `remote` the bundle the other Mac wrote.
/// What changed on one Mac since `base` is kept. Where both changed one item, the other Mac's
/// version (the later bundle's) wins, with the children of a folder put together. An item gone
/// on either Mac stays gone: a tab closed on one Mac came back because the other Mac wrote its
/// whole sidebar first (reported by a user, 13 Nov 2026).
public enum SidebarMerge {
    public static func merge(base: SidebarDocument, local: SidebarDocument, remote: SidebarDocument) -> SidebarDocument {
        var result = remote
        result.version = max(local.version, remote.version)
        result.items = mergeItems(base: base.items, local: local.items, remote: remote.items)
        result.spaces = mergeByID(base: base.spaces, local: local.spaces, remote: remote.spaces)
        let spaceIDs = Set(result.spaces.map(\.id))
        var order = mergeList(base: base.spaceOrder, local: local.spaceOrder, remote: remote.spaceOrder).filter { spaceIDs.contains($0) }
        order += result.spaces.map(\.id).filter { !order.contains($0) }
        result.spaceOrder = order
        if local.profiles != base.profiles, remote.profiles == base.profiles { result.profiles = local.profiles }
        if local.profileFavorites != base.profileFavorites, remote.profileFavorites == base.profileFavorites {
            result.profileFavorites = local.profileFavorites
        }
        return result
    }

    /// The other Mac's items in its order, then the ones made here since `base`. Each child list
    /// names only items in the result and each item is under its parent.
    static func mergeItems(base: [SidebarItem], local: [SidebarItem], remote: [SidebarItem]) -> [SidebarItem] {
        let b = table(base), l = table(local), r = table(remote)
        var ids: [UUID] = []
        var seen = Set<UUID>()
        for it in remote + local where seen.insert(it.id).inserted { ids.append(it.id) }
        var out: [UUID: SidebarItem] = [:]
        for id in ids {
            if let merged = mergeItem(base: b[id], local: l[id], remote: r[id]) { out[id] = merged }
        }
        for (id, var it) in out {
            var kept = Set<UUID>()
            it.children = it.children.filter { out[$0]?.parentID == id && kept.insert($0).inserted }
            out[id] = it
        }
        for id in ids {
            guard let it = out[id], let parentID = it.parentID, var parent = out[parentID], !parent.children.contains(id) else { continue }
            parent.children.append(id)
            out[parentID] = parent
        }
        return ids.compactMap { out[$0] }
    }

    static func mergeItem(base: SidebarItem?, local: SidebarItem?, remote: SidebarItem?) -> SidebarItem? {
        switch (base, local, remote) {
        case (nil, nil, nil): return nil
        case (nil, let l?, nil): return l
        case (nil, nil, let r?): return r
        case (nil, _?, let r?): return r
        case (_?, nil, _): return nil
        case (_?, _, nil): return nil
        case (let b?, let l?, let r?):
            if l == b { return r }
            if r == b { return l }
            var m = r
            m.children = mergeList(base: b.children, local: l.children, remote: r.children)
            return m
        }
    }

    /// The other Mac's in its order, then the ones made here; one gone on either Mac is left out.
    static func mergeByID<T: Identifiable & Equatable>(base: [T], local: [T], remote: [T]) -> [T] where T.ID == UUID {
        let b = table(base), l = table(local), r = table(remote)
        var ids: [UUID] = []
        var seen = Set<UUID>()
        for it in remote + local where seen.insert(it.id).inserted { ids.append(it.id) }
        return ids.compactMap { id in
            switch (b[id], l[id], r[id]) {
            case (nil, let l?, nil): return l
            case (nil, _, let r?): return r
            case (_?, nil, _), (_?, _, nil), (nil, nil, nil): return nil
            case (let b?, let l?, let r?): return l == b ? r : l
            }
        }
    }

    /// An ordered list of ids (a folder's children, the space order): the other Mac's list, less
    /// what was taken out here, plus what was added here, each after the item it follows here.
    public static func mergeList(base: [UUID], local: [UUID], remote: [UUID]) -> [UUID] {
        if local == base { return remote }
        if remote == base { return local }
        let baseSet = Set(base), localSet = Set(local)
        var result = remote.filter { !(baseSet.contains($0) && !localSet.contains($0)) }
        for (i, id) in local.enumerated() where !baseSet.contains(id) && !result.contains(id) {
            if let before = local[..<i].last(where: { result.contains($0) }), let at = result.firstIndex(of: before) {
                result.insert(id, at: at + 1)
            } else {
                result.insert(id, at: 0)
            }
        }
        var seen = Set<UUID>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func table<T: Identifiable>(_ items: [T]) -> [UUID: T] where T.ID == UUID {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// The bundles this Mac wrote or applied, newest first (`sync-history.json` in the data folder),
/// so a bundle the other Mac wrote from one of them is merged with what changed here since
/// (SidebarMerge). The last few only: a bundle older than that is applied whole, as before.
public struct SyncHistory: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var id: UUID
        public var document: SidebarDocument

        public init(id: UUID, document: SidebarDocument) {
            self.id = id
            self.document = document
        }
    }

    public static let limit = 8

    public var entries: [Entry] = []

    public init() {}

    public mutating func remember(_ id: UUID, _ document: SidebarDocument) {
        entries.removeAll { $0.id == id }
        entries.insert(Entry(id: id, document: document), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public func document(for id: UUID?) -> SidebarDocument? {
        guard let id else { return nil }
        return entries.first { $0.id == id }?.document
    }
}
