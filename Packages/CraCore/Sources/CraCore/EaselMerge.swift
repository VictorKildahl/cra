import Foundation

extension Easel {
    /// One easel on two Macs for sync, by SidebarMerge's rules: `base` from the bundle both were written from,
    /// nil when there is none (Import, Use That Sidebar), which adds and overwrites but deletes nothing. Nil: deleted.
    public static func merge(base: Easel?, local: Easel?, remote: Easel?) -> Easel? {
        guard let b = base else {
            // The blank every Cra saves when a tab opens an easel row it has no file for never replaces a real one.
            if let local, let remote, remote == Easel(id: remote.id) { return local }
            return remote ?? local
        }
        guard let l = local, let r = remote else { return nil }
        if l == b { return r }
        if r == b { return l }
        var m = r
        /// A field takes this Mac's change unless the other Mac changed it too.
        func keepLocal<V: Equatable>(_ field: WritableKeyPath<Easel, V>) {
            if l[keyPath: field] != b[keyPath: field], r[keyPath: field] == b[keyPath: field] { m[keyPath: field] = l[keyPath: field] }
        }
        keepLocal(\.title)
        keepLocal(\.titleStyle)
        keepLocal(\.titleSize)
        keepLocal(\.palette)
        keepLocal(\.thumbnail)
        let items = SidebarMerge.mergeByID(base: b.items, local: l.items, remote: r.items)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let order = SidebarMerge.mergeList(base: b.items.map(\.id), local: l.items.map(\.id), remote: r.items.map(\.id))
        var placed = Set<UUID>()
        m.items = (order + items.map(\.id)).compactMap { placed.insert($0).inserted ? byID[$0] : nil }
        if let t = m.thumbnail, byID[t] == nil { m.thumbnail = nil }
        return m
    }
}
