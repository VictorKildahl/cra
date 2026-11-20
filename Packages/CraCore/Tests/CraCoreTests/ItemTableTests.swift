import CraCore
import Foundation
import Observation
import Testing

@MainActor
struct ItemTableTests {
    final class Fired: @unchecked Sendable { var value = false }

    /// Why ItemTable exists: a row that read one item doesn't redraw when another changes.
    @Test func readersOfOneItemIgnoreOthers() {
        let table = ItemTable()
        let a = SidebarItem.tab("https://a.test", parent: nil), b = SidebarItem.tab("https://b.test", parent: nil)
        table[a.id] = a
        table[b.id] = b
        let fired = Fired()
        _ = withObservationTracking { table[a.id] } onChange: { fired.value = true }
        var changed = b
        changed.title = "B"
        table[b.id] = changed
        #expect(!fired.value)
        var changedA = a
        changedA.title = "A"
        table[a.id] = changedA
        #expect(fired.value)
    }

    /// Sync encodes the sidebar again only when this count moved (#615): every write that changes an
    /// item moves it, a write of the same value doesn't, and reading it is observed by nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/615"))
    func changeCountMovesWithEveryChange() {
        let table = ItemTable()
        let a = SidebarItem.tab("https://a.test", parent: nil)
        let start = table.changeCount
        table[a.id] = a
        #expect(table.changeCount != start)
        var count = table.changeCount
        table[a.id] = a
        #expect(table.changeCount == count, "the same value is no change")
        var titled = a
        titled.title = "A"
        table[a.id] = titled
        #expect(table.changeCount != count, "a title")
        count = table.changeCount
        var favicon = titled
        if case .tab(var t) = favicon.data { t.faviconKey = "other.test"; favicon.data = .tab(t) }
        table[a.id] = favicon
        #expect(table.changeCount != count, "a favicon")
        count = table.changeCount
        table[a.id] = nil
        #expect(table.changeCount != count, "a removal")

        let fired = Fired()
        withObservationTracking { _ = table.changeCount } onChange: { fired.value = true }
        table[a.id] = a
        #expect(!fired.value)
    }

    @Test func walksSeeEveryChange() {
        let table = ItemTable()
        let a = SidebarItem.folder("A", parent: nil)
        let fired = Fired()
        _ = withObservationTracking { table.values.count } onChange: { fired.value = true }
        table[a.id] = a
        #expect(fired.value && table.all.count == 1 && table[a.id] == a)
    }

    @Test func writingTheSameItemNotifiesNobody() {
        let table = ItemTable()
        let a = SidebarItem.folder("A", parent: nil)
        table[a.id] = a
        let fired = Fired()
        _ = withObservationTracking { table[a.id] } onChange: { fired.value = true }
        table[a.id] = a
        #expect(!fired.value)
        table[a.id] = nil
        #expect(fired.value && table[a.id] == nil)
    }

    /// State kept beside the item (expansion, selection) invalidates its readers through notify.
    @Test func observeAndNotify() {
        let table = ItemTable()
        let id = UUID(), fired = Fired()
        _ = withObservationTracking { table.observe(id) } onChange: { fired.value = true }
        table.notify(UUID())
        #expect(!fired.value)
        table.notify(id)
        #expect(fired.value)
        #expect(ItemSignal().version == 0)
    }

    /// The recorder's tab count, kept as items change instead of counted every sample (#214).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/214")) func tabCountFollowsWrites() {
        let table = ItemTable()
        let folder = SidebarItem.folder("F", parent: nil)
        var tabs = (0..<3).map { SidebarItem.tab("https://example.com/\($0)", parent: folder.id) }
        table[folder.id] = folder
        for t in tabs { table[t.id] = t }
        #expect(table.tabCount == 3)
        tabs[0].title = "renamed"
        table[tabs[0].id] = tabs[0]
        table[tabs[1].id] = tabs[1]
        #expect(table.tabCount == 3, "a tab written again is still one tab")
        table[tabs[2].id] = nil
        table[UUID()] = nil
        #expect(table.tabCount == 2)
        table[tabs[1].id] = SidebarItem(id: tabs[1].id, parentID: nil, title: "F2", children: [], isUnread: false,
                                        createdAt: folder.createdAt, data: folder.data)
        #expect(table.tabCount == 1, "a tab turned folder stops counting")
        #expect(table.tabCount == table.values.filter(\.isTab).count)
    }
}
