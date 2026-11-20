import Foundation

/// A container's children with the index each has among its stored ids, in one pass. The sidebar list
/// looked each child's index up with `children.firstIndex(of:)`: at 5,000 tabs in Today, 12.5 million
/// comparisons on every rebuild, and a rebuild runs on every title or favicon a page reports (GitHub #618).
/// Same answer: the stored index, items the lookup doesn't find skipped.
public enum SidebarChildOrder {
    /// `ids` with each one's stored index, for the ones `lookup` finds.
    public static func listed<Item>(_ ids: [UUID], lookup: (UUID) -> Item?) -> [(index: Int, item: Item)] {
        ids.enumerated().compactMap { index, id in lookup(id).map { (index: index, item: $0) } }
    }

    /// Each id's stored index, the first if it is there twice (as `firstIndex(of:)` answered).
    public static func indexes(_ ids: [UUID]) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        out.reserveCapacity(ids.count)
        for (i, id) in ids.enumerated() where out[id] == nil { out[id] = i }
        return out
    }
}
