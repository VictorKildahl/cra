import Foundation

/// Two Macs' sidebars put together for sync (SettingsSyncService). `base` is the bundle both
/// were written from, `local` this Mac's sidebar now, `remote` the bundle the other Mac wrote.
/// What changed on one Mac since `base` is kept. Where both changed one item, each of its fields
/// is the other Mac's (the later bundle's) unless only this Mac changed it, with the children of a
/// folder put together. An item gone
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
        // An item whose folder (or space's list) is gone on the other Mac, made or moved into it
        // here: it goes to the nearest folder up the chain still there, not to the first space.
        for (id, var it) in out {
            guard let p = it.parentID, out[p] == nil else { continue }
            var up: UUID? = p
            var steps = 0
            while let cur = up, out[cur] == nil, steps < 64 {
                up = (l[cur] ?? r[cur] ?? b[cur])?.parentID
                steps += 1
            }
            guard let found = up, out[found] != nil else { continue }
            it.parentID = found
            out[id] = it
        }
        for (id, var it) in out {
            var kept = Set<UUID>()
            it.children = it.children.filter { out[$0]?.parentID == id && kept.insert($0).inserted }
            out[id] = it
        }
        // Sets, not `children.contains`: Today can hold thousands of tabs.
        var listed = out.mapValues { Set($0.children) }
        for id in ids {
            guard let it = out[id], let parentID = it.parentID, var parent = out[parentID], listed[parentID]?.contains(id) == false else { continue }
            parent.children.append(id)
            out[parentID] = parent
            listed[parentID]?.insert(id)
        }
        // Each Mac closed a different pane of one split: the pane left takes the split's place.
        ThinSplits.collapse(&out)
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
            // Changed on both Macs: field by field. The whole item was the other Mac's, parent and all,
            // so tabs made into a split here while the other Mac only looked at them went back to Today
            // and left the split with no panes (#921, reported on X).
            var m = r
            func keepLocal<V: Equatable>(_ key: WritableKeyPath<SidebarItem, V>) {
                if l[keyPath: key] != b[keyPath: key], r[keyPath: key] == b[keyPath: key] { m[keyPath: key] = l[keyPath: key] }
            }
            keepLocal(\.parentID)
            keepLocal(\.title)
            keepLocal(\.isUnread)
            keepLocal(\.folderIcon)
            keepLocal(\.folderSymbol)
            keepLocal(\.liveFolder)
            keepLocal(\.tabGroup)
            m.children = mergeList(base: b.children, local: l.children, remote: r.children)
            m.data = mergeData(base: b.data, local: l.data, remote: r.data)
            return m
        }
    }

    /// A tab's or a split's data changed on both Macs: the other Mac's, unless all it changed is when
    /// it was looked at (and which pane had focus), as a Mac does with every look; then this Mac's. The
    /// later look either way, or this Mac's would read as idle to the archive pass.
    static func mergeData(base: ItemData, local: ItemData, remote: ItemData) -> ItemData {
        if local == base { return remote }
        if remote == base { return local }
        func later(_ a: Date?, _ b: Date?) -> Date? {
            guard let a else { return b }
            guard let b else { return a }
            return max(a, b)
        }
        switch (base, local, remote) {
        case (.tab(let b), .tab(let l), .tab(let r)):
            func page(_ t: TabData) -> TabData { var t = t; t.timeLastActiveAt = nil; return t }
            var t = page(r) == page(b) ? l : r
            t.timeLastActiveAt = later(l.timeLastActiveAt, r.timeLastActiveAt)
            return .tab(t)
        case (.split(let b), .split(let l), .split(let r)):
            func layout(_ s: SplitData) -> SplitData { var s = s; s.timeLastActiveAt = nil; s.focusTabID = nil; return s }
            var s = layout(r) == layout(b) ? l : r
            s.focusTabID = l.focusTabID != b.focusTabID && r.focusTabID == b.focusTabID ? l.focusTabID : r.focusTabID
            s.timeLastActiveAt = later(l.timeLastActiveAt, r.timeLastActiveAt)
            return .split(s)
        default:
            return remote
        }
    }

    /// The other Mac's in its order, then the ones made here; one gone on either Mac is left out,
    /// and one both changed is the other Mac's, as with items.
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
            case (let b?, let l?, let r?): return l != b && r == b ? l : r
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
        var inResult = Set(result)
        for (i, id) in local.enumerated() where !baseSet.contains(id) && !inResult.contains(id) {
            if let before = local[..<i].last(where: { inResult.contains($0) }), let at = result.firstIndex(of: before) {
                result.insert(id, at: at + 1)
            } else {
                result.insert(id, at: 0)
            }
            inResult.insert(id)
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
        /// The bundle's settings, what SettingsMerge merges against. Nil in a history an older Cra wrote: that bundle's
        /// settings replace this Mac's whole, as before.
        public var settings: AppSettings?
        /// The bundle's easels without their pictures, what Easel.merge merges against. Nil for a bundle without
        /// easels and in a history an older Cra wrote: then no easel is deleted.
        public var easels: [Easel]?

        public init(id: UUID, document: SidebarDocument, settings: AppSettings? = nil, easels: [Easel]? = nil) {
            self.id = id
            self.document = document
            self.settings = settings
            self.easels = easels
        }
    }

    public static let limit = 8

    public var entries: [Entry] = []

    public init() {}

    public mutating func remember(_ id: UUID, _ document: SidebarDocument, settings: AppSettings? = nil, easels: [Easel]? = nil) {
        entries.removeAll { $0.id == id }
        entries.insert(Entry(id: id, document: document, settings: settings, easels: easels), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public func document(for id: UUID?) -> SidebarDocument? {
        guard let id else { return nil }
        return entries.first { $0.id == id }?.document
    }

    /// What to merge a bundle against: the newest of the bundles its writer had (`parentIDs`,
    /// newest first) that this Mac has too. Nil, so the bundle is applied whole, for a bundle from
    /// an older Cra or one written from bundles all gone from here.
    public func base(for manifest: SyncManifest) -> SidebarDocument? {
        baseEntry(for: manifest)?.document
    }

    /// The settings of the same bundle `base(for:)` picks; nil when it has none (written by an older Cra).
    public func baseSettings(for manifest: SyncManifest) -> AppSettings? {
        baseEntry(for: manifest)?.settings
    }

    /// The easels of the newest of the manifest's `easelParentIDs` remembered with easels; nil when there is none.
    public func baseEasels(for manifest: SyncManifest) -> [Easel]? {
        for id in manifest.easelParentIDs ?? [] { if let easels = entries.first(where: { $0.id == id })?.easels { return easels } }
        return nil
    }

    private func baseEntry(for manifest: SyncManifest) -> Entry? {
        for id in manifest.parentIDs ?? [] { if let e = entries.first(where: { $0.id == id }) { return e } }
        return nil
    }

    /// The ids a bundle written now names as its parents (`SyncManifest.parentIDs`).
    public var ids: [UUID] { entries.map(\.id) }
    /// Whether a remembered bundle held the easel, so a Mac may merge against it.
    public func remembers(easel id: UUID) -> Bool { entries.contains { $0.easels?.contains { $0.id == id } == true } }
    /// The bundles remembered with their easels, newest first: a manifest's `easelParentIDs`.
    public var easelIDs: [UUID] { entries.filter { $0.easels != nil }.map(\.id) }
}
