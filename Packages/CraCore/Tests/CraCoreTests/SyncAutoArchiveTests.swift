import CraCore
import Foundation
import Testing

/// A tab looked at on one Mac is in use on both: an archive pass on the other Mac that ran before it knew of that look
/// (at launch, after waking, iCloud still downloading) is undone (Victor, 25 Nov 2026, after Chris Coyier's report).
struct SyncAutoArchiveTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let tab = UUID(), other = UUID()

    @Test func aLookWithinTheLimitBeforeThePassUndoesIt() {
        let archivedAt = t0.addingTimeInterval(26 * 3600)
        let undone = SyncAutoArchive.undone(
            archived: [tab: archivedAt, other: archivedAt],
            seen: [tab: archivedAt.addingTimeInterval(-60), other: archivedAt.addingTimeInterval(-13 * 3600)],
            limit: { _ in .after(.twelveHours) })
        #expect(undone == [tab], "looked at a minute before the pass is kept; 13 hours before, it was idle on both Macs")
    }

    @Test func aTabLookedAtOnlyLongAgoOrNeverStaysArchived() {
        let archivedAt = t0
        #expect(SyncAutoArchive.undone(archived: [tab: archivedAt], seen: [:], limit: { _ in .after(.twelveHours) }).isEmpty)
        #expect(SyncAutoArchive.undone(archived: [tab: archivedAt], seen: [tab: archivedAt.addingTimeInterval(-12 * 3600 - 1)],
                                       limit: { _ in .after(.twelveHours) }).isEmpty)
    }

    @Test func eachTabByItsOwnProfilesTimerAndNeverKeepsIt() {
        let archivedAt = t0
        let seen = [tab: archivedAt.addingTimeInterval(-3 * 86400), other: archivedAt.addingTimeInterval(-3 * 86400)]
        let undone = SyncAutoArchive.undone(archived: [tab: archivedAt, other: archivedAt], seen: seen,
                                            limit: { $0 == tab ? .after(.sevenDays) : .after(.twentyFourHours) })
        #expect(undone == [tab])
        #expect(SyncAutoArchive.undone(archived: [other: archivedAt], seen: seen, limit: { _ in .never }) == [other])
    }

    @Test func aBundleListsItsRecentAutoArchivesOnly() {
        let now = t0
        let listed = SyncAutoArchive.listed([(tab, now.addingTimeInterval(-3600)), (other, now.addingTimeInterval(-SyncAutoArchive.listedFor - 1))], now: now)
        #expect(listed == [tab: now.addingTimeInterval(-3600)])
    }

    @Test func forgettingTabsInTheBaseLetsTheMergeKeepThem() {
        // Base and this Mac had the tab; the other Mac's pass took it. Forgotten in the base, it stays.
        var doc = SidebarDocument.fresh()
        let today = doc.spaces[0].todayContainerID
        let item = SidebarItem.tab("https://example.com/seen", title: "Seen", parent: today)
        doc.items.append(item)
        doc.items = doc.items.map { var it = $0; if it.id == today { it.children = [item.id] }; return it }
        let remote = doc.removing([item.id])
        #expect(SidebarMerge.merge(base: doc, local: doc, remote: remote).items.contains { $0.id == item.id } == false, "gone on either stays gone")
        let kept = SidebarMerge.merge(base: doc.removing([item.id]), local: doc, remote: remote)
        #expect(kept.items.contains { $0.id == item.id })
        #expect(kept.items.first { $0.id == today }?.children == [item.id])
        // This Mac's pass took it and the other Mac's bundle still has it: it comes back.
        let back = SidebarMerge.merge(base: doc.removing([item.id]), local: remote, remote: doc)
        #expect(back.items.first { $0.id == today }?.children == [item.id])
    }

    @Test func aTabLookedAtOnBothKeepsTheLaterLook() {
        var doc = SidebarDocument.fresh()
        let today = doc.spaces[0].todayContainerID
        let item = SidebarItem.tab("https://example.com/both", title: "Both", parent: today)
        doc.items.append(item)
        func seen(_ at: Date) -> SidebarDocument {
            var d = doc
            d.items = d.items.map { it in
                guard it.id == item.id, var t = it.tab else { return it }
                t.timeLastActiveAt = at
                var it = it
                it.data = .tab(t)
                return it
            }
            return d
        }
        let later = t0.addingTimeInterval(3600)
        let merged = SidebarMerge.merge(base: doc, local: seen(later), remote: seen(t0))
        #expect(merged.lastActive[item.id] == later, "the other Mac's copy wins the rest, not an older look")
    }
}
