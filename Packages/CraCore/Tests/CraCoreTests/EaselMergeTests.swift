import CraCore
import Foundation
import Testing

/// One easel on two Macs put together for sync: what changed on either since the bundle both were
/// written from is kept, the other Mac wins where both changed the same thing, and an easel or
/// item gone on either stays gone, as with the sidebar (SidebarMerge).
struct EaselMergeTests {
    let picture = Easel.Item(kind: .image(file: "D0D0D0D0-0000-4000-8000-000000000000.png"), frame: .init(x: 0, y: 0, width: 100, height: 100))
    let box = Easel.Item(kind: .rectangle, frame: .init(x: 200, y: 0, width: 50, height: 50))
    let note = Easel.Item(kind: .text("Note", size: 22), frame: .init(x: 0, y: 200, width: 80, height: 30))

    let id = UUID()
    /// A picture under a box under a note, with the picture as its thumbnail.
    var base: Easel {
        var e = Easel(id: id, title: "Board", items: [picture, box, note])
        e.thumbnail = picture.id
        return e
    }

    func moved(_ item: Easel.Item, in easel: Easel) -> Easel {
        var e = easel
        e.items = e.items.map { $0.id == item.id ? $0.moved(by: .init(10, 10)) : $0 }
        return e
    }

    func without(_ item: Easel.Item, _ easel: Easel) -> Easel {
        var e = easel
        e.items.removeAll { $0.id == item.id }
        return e
    }

    // MARK: The table

    @Test func anEaselMadeHereOnlyIsKept() {
        #expect(Easel.merge(base: nil, local: base, remote: nil) == base)
    }

    @Test func withNoBaseTheOtherMacsEaselIsAddedOrOverwrites() {
        var other = base
        other.title = "Theirs"
        #expect(Easel.merge(base: nil, local: nil, remote: other) == other)
        #expect(Easel.merge(base: nil, local: base, remote: other) == other, "Import and Use That Sidebar overwrite")
    }

    /// Every released Cra saves `Easel(id:)` when a tab opens an easel row whose file it lacks.
    @Test func withNoBaseABlankCopyNeverReplacesAnEaselHere() {
        #expect(Easel.merge(base: nil, local: base, remote: Easel(id: id)) == base)
    }

    @Test func withNoBaseABlankCopyIsAddedWhereThereIsNone() {
        #expect(Easel.merge(base: nil, local: nil, remote: Easel(id: id)) == Easel(id: id))
    }

    @Test func withABaseABlankedEaselIsAChangeLikeAnyOther() {
        #expect(Easel.merge(base: base, local: base, remote: Easel(id: id)) == Easel(id: id))
    }

    @Test func anEaselDeletedOnEitherMacStaysDeleted() {
        var edited = base
        edited.title = "Edited"
        #expect(Easel.merge(base: base, local: nil, remote: edited) == nil, "deleted here, edited there")
        #expect(Easel.merge(base: base, local: edited, remote: nil) == nil, "deleted there, edited here")
        #expect(Easel.merge(base: base, local: nil, remote: nil) == nil)
        #expect(Easel.merge(base: nil, local: nil, remote: nil) == nil)
    }

    @Test func anEaselChangedOnOneMacTakesThatChange() {
        var edited = base
        edited.title = "Edited"
        edited.items.append(Easel.Item(kind: .ellipse, frame: .init(x: 0, y: 0, width: 5, height: 5)))
        #expect(Easel.merge(base: base, local: base, remote: edited) == edited)
        #expect(Easel.merge(base: base, local: edited, remote: base) == edited)
    }

    // MARK: Both Macs changed it

    @Test func fieldsChangedOnOneMacEachAreBothKept() {
        var local = base, remote = base
        local.title = "Mine"
        local.palette = .vibrant
        remote.titleStyle = .serif
        remote.titleSize = 48
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.title == "Mine" && m?.palette == .vibrant)
        #expect(m?.titleStyle == .serif && m?.titleSize == 48)
    }

    @Test func aFieldBothMacsChangedTakesTheOtherMacs() {
        var local = base, remote = base
        local.title = "Mine"
        local.thumbnail = nil
        remote.title = "Theirs"
        remote.thumbnail = box.id
        #expect(Easel.merge(base: base, local: local, remote: remote)?.title == "Theirs")
        #expect(Easel.merge(base: base, local: local, remote: remote)?.thumbnail == box.id)
        #expect(Easel.merge(base: base, local: remote, remote: local)?.title == "Mine", "whichever Mac is the other")
        #expect(Easel.merge(base: base, local: remote, remote: local)?.thumbnail == nil)
    }

    @Test func itemsAddedOnEitherMacAreBothKept() {
        let mine = Easel.Item(kind: .ellipse, frame: .init(x: 1, y: 1, width: 5, height: 5))
        let theirs = Easel.Item(kind: .arrow(from: .init(0, 0), to: .init(9, 9)), frame: .init(x: 0, y: 0, width: 9, height: 9))
        var local = base, remote = base
        local.items.append(mine)
        remote.items.append(theirs)
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.items.map(\.id) == [picture.id, box.id, note.id, mine.id, theirs.id])
    }

    @Test func anItemDeletedOnEitherMacStaysDeleted() {
        var local = without(box, base), remote = moved(box, in: base)
        remote.title = "Theirs"
        #expect(Easel.merge(base: base, local: local, remote: remote)?.items.map(\.id) == [picture.id, note.id],
                "deleted here, moved there")
        local = moved(note, in: base)
        remote = without(note, base)
        local.title = "Mine"
        #expect(Easel.merge(base: base, local: local, remote: remote)?.items.map(\.id) == [picture.id, box.id],
                "deleted there, moved here")
    }

    @Test func anItemChangedOnOneMacTakesThatChange() {
        var local = moved(box, in: base), remote = base
        remote.title = "Theirs"
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.items == local.items && m?.title == "Theirs")
        local = base
        local.title = "Mine"
        remote = moved(note, in: base)
        let n = Easel.merge(base: base, local: local, remote: remote)
        #expect(n?.items == remote.items && n?.title == "Mine")
    }

    @Test func anItemBothMacsChangedTakesTheOtherMacs() {
        var local = base, remote = base
        local.items[1].shade = .red
        remote.items[1].shade = .purple
        #expect(Easel.merge(base: base, local: local, remote: remote)?.items[1].shade == .purple)
        #expect(Easel.merge(base: base, local: remote, remote: local)?.items[1].shade == .red)
    }

    /// `items` is the stack, bottom first: an item brought forward on one Mac stays forward while the
    /// other Mac's edits come in, and a new item sits above the one it was drawn above.
    @Test func theStackOrderMergesLikeAFolderOfTabs() {
        var local = base, remote = base
        local.items = [box, note, picture]
        remote.items[2].shade = .red
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.items.map(\.id) == [box.id, note.id, picture.id])
        #expect(m?.items[1].shade == .red)

        let added = Easel.Item(kind: .ellipse, frame: .init(x: 1, y: 1, width: 5, height: 5))
        local = base
        local.items.insert(added, at: 1)
        remote = base
        remote.items = [note, picture, box]
        #expect(Easel.merge(base: base, local: local, remote: remote)?.items.map(\.id) == [note.id, picture.id, added.id, box.id])
    }

    /// Every item the merge keeps is in the stack once, even one the order lists miss (an id on both
    /// Macs but in neither's list as the merge sees it).
    @Test func everyKeptItemIsInTheStackOnce() {
        var local = base, remote = base
        local.items.append(note)
        remote.title = "Theirs"
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.items.map(\.id) == [picture.id, box.id, note.id])
    }

    @Test func aThumbnailWhoseItemIsGoneIsCleared() {
        var local = without(picture, base), remote = base
        remote.title = "Theirs"
        let m = Easel.merge(base: base, local: local, remote: remote)
        #expect(m?.thumbnail == nil && m?.items.map(\.id) == [box.id, note.id])
        local = base
        local.thumbnail = box.id
        remote = without(box, base)
        #expect(Easel.merge(base: base, local: local, remote: remote)?.thumbnail == nil, "set here to an item deleted there")
        remote = base
        remote.title = "Theirs"
        #expect(Easel.merge(base: base, local: local, remote: remote)?.thumbnail == box.id)
    }

    // MARK: What it is merged against

    /// The writer names the parents it had with easels, newest first: a bundle an older Cra applied or wrote
    /// vouches for none, so the other Mac never merges against easels this one never had.
    struct Bases {
        let doc = SidebarDocument.fresh()
        let older = UUID(), newer = UUID(), gone = UUID()
        var history = SyncHistory()
        func manifest(_ parents: [UUID]?) -> SyncManifest {
            SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: .now, files: [:], parentIDs: parents, easelParentIDs: parents)
        }
    }

    @Test func theHistoryKeepsEachBundlesEaselsForItsMerge() {
        var b = Bases()
        b.history.remember(b.older, b.doc)
        b.history.remember(b.newer, b.doc, easels: [base])
        #expect(b.history.entries.map(\.easels) == [[base], nil])
    }

    @Test func theNewestEaselParentHeldWithEaselsIsTheBase() {
        var b = Bases()
        var older = base
        older.title = "Older"
        b.history.remember(b.older, b.doc, easels: [older])
        b.history.remember(b.newer, b.doc, easels: [base])
        #expect(b.history.baseEasels(for: b.manifest([b.gone, b.newer, b.older])) == [base])
    }

    @Test func anEaselParentHeldWithoutEaselsIsSkipped() {
        var b = Bases()
        b.history.remember(b.older, b.doc, easels: [base])
        b.history.remember(b.newer, b.doc)
        #expect(b.history.baseEasels(for: b.manifest([b.newer, b.older])) == [base])
    }

    @Test func noEaselParentHeldMeansNoBase() {
        var b = Bases()
        b.history.remember(b.newer, b.doc, easels: [base])
        #expect(b.history.baseEasels(for: b.manifest([b.gone])) == nil)
    }

    @Test func aManifestWithoutEaselParentsHasNoBase() {
        var b = Bases()
        b.history.remember(b.newer, b.doc, easels: [base])
        let m = SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: .now, files: [:], parentIDs: [b.newer])
        #expect(b.history.baseEasels(for: m) == nil, "parentIDs alone vouch for no easels")
    }

    @Test func theWriterNamesOnlyParentsItHoldsWithEasels() {
        var b = Bases()
        b.history.remember(b.older, b.doc, easels: [base])
        b.history.remember(b.gone, b.doc)
        b.history.remember(b.newer, b.doc, easels: [])
        #expect(b.history.easelIDs == [b.newer, b.older])
    }
}
