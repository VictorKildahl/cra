import CraCore
import Foundation
import Testing

/// Two Macs' sidebars put together for sync: what changed on either since the bundle both were
/// written from is kept, and an item gone on either stays gone.
struct SidebarMergeTests {
    /// A space with a folder in Pinned that holds two tabs, and one tab in Today.
    struct Fixture {
        var doc = SidebarDocument.fresh()
        let folder: SidebarItem
        let first: SidebarItem
        let second: SidebarItem
        let today: SidebarItem

        init() {
            let space = doc.spaces[0]
            var folder = SidebarItem.folder("Work", parent: space.pinnedContainerID)
            let first = SidebarItem.tab("https://example.com/first", title: "First", parent: folder.id)
            let second = SidebarItem.tab("https://example.com/second", title: "Second", parent: folder.id)
            let today = SidebarItem.tab("https://example.com/today", title: "Today", parent: space.todayContainerID)
            folder.children = [first.id, second.id]
            doc.items += [folder, first, second, today]
            doc.items = doc.items.map { it in
                var it = it
                if it.id == space.pinnedContainerID { it.children = [folder.id] }
                if it.id == space.todayContainerID { it.children = [today.id] }
                return it
            }
            self.folder = folder
            self.first = first
            self.second = second
            self.today = today
        }
    }

    func ids(_ doc: SidebarDocument) -> Set<UUID> { Set(doc.items.map(\.id)) }
    func item(_ id: UUID, in doc: SidebarDocument) -> SidebarItem? { doc.items.first { $0.id == id } }
    func without(_ id: UUID, _ doc: SidebarDocument) -> SidebarDocument {
        var d = doc
        d.items = d.items.filter { $0.id != id }.map { it in
            var it = it
            it.children.removeAll { $0 == id }
            return it
        }
        return d
    }
    func retitled(_ id: UUID, _ title: String, _ doc: SidebarDocument) -> SidebarDocument {
        var d = doc
        d.items = d.items.map { it in
            guard it.id == id, var tab = it.tab else { return it }
            tab.savedTitle = title
            var it = it
            it.data = .tab(tab)
            return it
        }
        return d
    }
    func added(_ tab: SidebarItem, under parentID: UUID, _ doc: SidebarDocument) -> SidebarDocument {
        var d = doc
        d.items.append(tab)
        d.items = d.items.map { it in
            guard it.id == parentID else { return it }
            var it = it
            it.children.append(tab.id)
            return it
        }
        return d
    }

    /// The bug: a tab closed here, and the other Mac wrote from the bundle before the close.
    @Test func aTabClosedHereStaysClosed() {
        let f = Fixture()
        let local = without(f.second.id, f.doc)
        let remote = retitled(f.today.id, "Today, renamed", f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(f.second.id, in: merged) == nil)
        #expect(item(f.folder.id, in: merged)?.children == [f.first.id])
        #expect(item(f.today.id, in: merged)?.tab?.savedTitle == "Today, renamed")
    }

    @Test func aTabClosedThereGoesHereToo() {
        let f = Fixture()
        let local = retitled(f.first.id, "First, renamed", f.doc)
        let remote = without(f.first.id, f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(f.first.id, in: merged) == nil)
        #expect(item(f.folder.id, in: merged)?.children == [f.second.id])
    }

    @Test func tabsOpenedOnBothMacsAreOnBoth() {
        let f = Fixture()
        let here = SidebarItem.tab("https://example.com/here", title: "Here", parent: f.doc.spaces[0].todayContainerID)
        let there = SidebarItem.tab("https://example.com/there", title: "There", parent: f.doc.spaces[0].todayContainerID)
        let local = added(here, under: f.doc.spaces[0].todayContainerID, f.doc)
        let remote = added(there, under: f.doc.spaces[0].todayContainerID, f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(here.id, in: merged) != nil && item(there.id, in: merged) != nil)
        let children = item(f.doc.spaces[0].todayContainerID, in: merged)?.children ?? []
        #expect(Set(children) == [f.today.id, here.id, there.id] && children.count == 3)
    }

    /// Both Macs changed the same tab: the other Mac's bundle, the later one, wins.
    @Test func theOtherMacWinsAnItemBothChanged() {
        let f = Fixture()
        let local = retitled(f.first.id, "Mine", f.doc)
        let remote = retitled(f.first.id, "Theirs", f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(f.first.id, in: merged)?.tab?.savedTitle == "Theirs")
    }

    /// A folder both Macs put a tab into keeps both, and a tab taken out here stays out.
    @Test func aFolderChangedOnBothMacsKeepsBothChanges() {
        let f = Fixture()
        let here = SidebarItem.tab("https://example.com/here", title: "Here", parent: f.folder.id)
        let there = SidebarItem.tab("https://example.com/there", title: "There", parent: f.folder.id)
        let local = without(f.first.id, added(here, under: f.folder.id, f.doc))
        let remote = added(there, under: f.folder.id, f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(f.folder.id, in: merged)?.children == [f.second.id, here.id, there.id])
        #expect(item(f.first.id, in: merged) == nil)
    }

    @Test func nothingChangedHereTakesTheOtherMacsBundleAsItIs() {
        let f = Fixture()
        let remote = without(f.today.id, retitled(f.first.id, "Theirs", f.doc))
        #expect(SidebarMerge.merge(base: f.doc, local: f.doc, remote: remote) == remote)
    }

    @Test func aSpaceMadeHereAndASpaceDeletedThereBothCount() {
        let f = Fixture()
        var local = f.doc
        let made = SidebarDocument.fresh().spaces[0]
        local.spaces.append(made)
        local.spaceOrder.append(made.id)
        var remote = f.doc
        let other = SidebarDocument.fresh().spaces[0]
        remote.spaces.append(other)
        remote.spaceOrder.insert(other.id, at: 0)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(merged.spaceOrder == [other.id, f.doc.spaces[0].id, made.id])
        #expect(Set(merged.spaces.map(\.id)) == [other.id, f.doc.spaces[0].id, made.id])
    }

    /// A folder closed here while the other Mac put a tab in it: the tab is kept, in the list
    /// the folder was in, not dropped in the first space's Today by the store's repair.
    @Test func aTabPutInAFolderClosedHereGoesWhereTheFolderWas() {
        let f = Fixture()
        let pinned = f.doc.spaces[0].pinnedContainerID
        let local = without(f.second.id, without(f.first.id, without(f.folder.id, f.doc)))
        let there = SidebarItem.tab("https://example.com/there", title: "There", parent: f.folder.id)
        let remote = added(there, under: f.folder.id, f.doc)
        let merged = SidebarMerge.merge(base: f.doc, local: local, remote: remote)
        #expect(item(f.folder.id, in: merged) == nil && item(f.first.id, in: merged) == nil)
        #expect(item(there.id, in: merged)?.parentID == pinned)
        #expect(item(pinned, in: merged)?.children == [there.id])
    }

    /// Both Macs changed one space: the other Mac's, as for an item. One changed only here stays.
    @Test func theOtherMacWinsASpaceBothChanged() {
        let f = Fixture()
        var local = f.doc, remote = f.doc
        local.spaces[0].title = "Mine"
        remote.spaces[0].title = "Theirs"
        #expect(SidebarMerge.merge(base: f.doc, local: local, remote: remote).spaces[0].title == "Theirs")
        #expect(SidebarMerge.merge(base: f.doc, local: local, remote: f.doc).spaces[0].title == "Mine")
    }

    @Test func listsMergeAroundTheItemAnAdditionFollows() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        #expect(SidebarMerge.mergeList(base: [a, b, c], local: [a, d, b, c], remote: [a, b, c, e]) == [a, d, b, c, e])
        #expect(SidebarMerge.mergeList(base: [a, b, c], local: [b, c], remote: [c, b, a]) == [c, b])
        #expect(SidebarMerge.mergeList(base: [a, b, c], local: [d, a, b, c], remote: [b, c]) == [d, b, c])
        #expect(SidebarMerge.mergeList(base: [a, b], local: [a, b], remote: [b, a]) == [b, a])
    }

    @Test func historyKeepsTheLastFewBundlesNewestFirst() throws {
        var history = SyncHistory()
        let docs = (0..<(SyncHistory.limit + 2)).map { _ in SidebarDocument.fresh() }
        let ids = docs.map { _ in UUID() }
        for (id, doc) in zip(ids, docs) { history.remember(id, doc) }
        #expect(history.entries.count == SyncHistory.limit)
        #expect(history.document(for: ids.last!) == docs.last!)
        #expect(history.document(for: ids.first!) == nil && history.document(for: nil) == nil)
        history.remember(ids.last!, docs.first!)
        #expect(history.entries.count == SyncHistory.limit && history.document(for: ids.last!) == docs.first!)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(SyncHistory.self, from: e.encode(history))
        #expect(back.entries.map(\.id) == history.entries.map(\.id) && back.entries[0].document.items.count == history.entries[0].document.items.count)
    }

    /// A manifest names its bundle and the bundles it was written from; one from an older Cra
    /// names neither and is applied whole.
    @Test func aManifestNamesItsBundleAndItsParents() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let parents = [UUID(), UUID()], id = UUID()
        let m = SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: ["sidebar.json": "abc"], id: id, parentIDs: parents)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(SyncManifest.self, from: e.encode(m))
        #expect(back == m && back.id == id && back.parentIDs == parents)
        let old = Data(#"{"version":1,"device":"Studio","deviceID":"id-Studio","writtenAt":"2023-11-14T22:13:20Z","files":{"sidebar.json":"abc"}}"#.utf8)
        let decoded = try d.decode(SyncManifest.self, from: old)
        #expect(decoded.id == nil && decoded.parentIDs == nil && decoded.files == ["sidebar.json": "abc"])
        #expect(SyncHistory().base(for: decoded) == nil)
    }

    /// The other Mac wrote twice before this one looked: its newest bundle names the one before
    /// it first, which never reached here, then one this Mac has. The merge is against that one,
    /// the newest both have.
    @Test func theBaseIsTheNewestParentThisMacHas() {
        var history = SyncHistory()
        let older = SidebarDocument.fresh(), newer = SidebarDocument.fresh()
        let olderID = UUID(), newerID = UUID(), unseen = UUID()
        history.remember(olderID, older)
        history.remember(newerID, newer)
        #expect(history.ids == [newerID, olderID])
        func manifest(_ parents: [UUID]?) -> SyncManifest {
            SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: Date(timeIntervalSince1970: 0), files: [:], id: UUID(), parentIDs: parents)
        }
        #expect(history.base(for: manifest([unseen, olderID, newerID])) == older)
        #expect(history.base(for: manifest([newerID, olderID])) == newer)
        #expect(history.base(for: manifest([unseen])) == nil && history.base(for: manifest(nil)) == nil)
    }
}
