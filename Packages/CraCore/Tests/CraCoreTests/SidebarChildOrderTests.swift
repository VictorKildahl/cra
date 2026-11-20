import CraCore
import Foundation
import Testing

struct SidebarChildOrderTests {
    /// GitHub #618: the sidebar's list found each child's index with firstIndex(of:), quadratic in the
    /// children. One pass gives the same indexes: the stored one, with missing items skipped.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/618"))
    func oneStoredIndexPerChildInOnePass() {
        let ids = (0..<6).map { _ in UUID() }
        let missing: Set<UUID> = [ids[1], ids[4]]
        let listed = SidebarChildOrder.listed(ids) { missing.contains($0) ? nil : $0 }
        #expect(listed.map(\.index) == [0, 2, 3, 5])
        #expect(listed.map(\.item) == [ids[0], ids[2], ids[3], ids[5]])
        // The same answer firstIndex(of:) gave, child by child.
        for (index, id) in listed { #expect(ids.firstIndex(of: id) == index) }
        let indexes = SidebarChildOrder.indexes(ids)
        #expect(ids.allSatisfy { indexes[$0] == ids.firstIndex(of: $0) })
    }

    /// An id stored twice (before SidebarIntegrity repairs it) keeps its first index, as before.
    @Test func aRepeatedIdKeepsItsFirstIndex() {
        let a = UUID(), b = UUID()
        #expect(SidebarChildOrder.indexes([a, b, a]) == [a: 0, b: 1])
        #expect(SidebarChildOrder.indexes([]) == [:])
    }

    /// 5,000 children: one pass, not 12.5 million comparisons.
    @Test func fiveThousandChildrenAreListedInOnePass() {
        let ids = (0..<5000).map { _ in UUID() }
        var lookups = 0
        let listed = SidebarChildOrder.listed(ids) { id -> UUID? in lookups += 1; return id }
        #expect(listed.count == 5000 && lookups == 5000 && listed.last?.index == 4999)
    }
}
