import Foundation

/// Auto-archive with two Macs in sync. A tab looked at on one Mac is in use on both, but the other Mac's archive pass
/// can run before that look reaches it (at launch, after waking, iCloud still downloading): it archived the tab, and
/// as a tab gone on either Mac stays gone (SidebarMerge), the first Mac lost it too, in neither Archive there (Victor,
/// 25 Nov 2026, after Chris Coyier's report on X). Such a pass is undone when the look arrives: on the Mac that ran it,
/// when the other Mac's bundle brings the look, and on the Mac that looked, when a bundle lists the tab among its Mac's
/// auto-archives (`SyncManifest.autoArchived`).
public enum SyncAutoArchive {
    /// How long a bundle lists a tab its Mac's pass took: the other Mac can be away this long and still keep one it
    /// had looked at within its timer.
    public static let listedFor: TimeInterval = 30 * 86400

    /// The auto-archives a bundle lists, from the Archive's (id, when) for reason `.auto`.
    public static func listed(_ autoArchived: [(id: UUID, at: Date)], now: Date) -> [UUID: Date] {
        var out: [UUID: Date] = [:]
        for e in autoArchived where now.timeIntervalSince(e.at) < listedFor { out[e.id] = max(out[e.id] ?? e.at, e.at) }
        return out
    }

    /// The tabs a pass took (`archived`, id → when) that the other Mac had looked at (`seen`, id → its last look) within
    /// the tab's timer before the pass, so they were in use. A tab whose timer is Never on this Mac is kept too.
    public static func undone(archived: [UUID: Date], seen: [UUID: Date], limit: (UUID) -> AutoArchiveChoice) -> Set<UUID> {
        Set(archived.compactMap { id, at in
            guard let look = seen[id] else { return nil }
            switch limit(id) {
            case .never: return id
            case .after(let t): return look > at.addingTimeInterval(-t.seconds) ? id : nil
            }
        })
    }
}

public extension SidebarDocument {
    /// The document without these items, taken out of their lists too: a base that forgets a tab lets SidebarMerge
    /// keep the copy one Mac still has, as an item made since.
    func removing(_ ids: Set<UUID>) -> SidebarDocument {
        guard !ids.isEmpty else { return self }
        var d = self
        d.items = d.items.filter { !ids.contains($0.id) }.map { it in
            var it = it
            it.children.removeAll { ids.contains($0) }
            return it
        }
        return d
    }

    /// When each tab was last looked at, for the tabs that have a time.
    var lastActive: [UUID: Date] {
        var out: [UUID: Date] = [:]
        for it in items { if let at = it.tab?.timeLastActiveAt { out[it.id] = at } }
        return out
    }
}
