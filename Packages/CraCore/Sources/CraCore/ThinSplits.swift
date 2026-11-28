import Foundation

/// A split holds two panes or more: SidebarStore collapses one that a close or a move leaves with
/// one (collapseSplitIfNeeded). One with fewer can still come from outside the store: a sync merge
/// (SidebarMerge), or a sidebar.json a Cra before the fix wrote. Drawn, an empty split is a row with
/// no panes and only a close button, which has no pane to close, so nothing could remove it, and
/// sync took it to every Mac (#921, reported on X).
public enum ThinSplits {
    /// Every split in `items` with fewer than two tabs goes; what it held takes its place in its
    /// parent's list. Returns the ids of the items changed or removed.
    @discardableResult
    public static func collapse(_ items: inout [UUID: SidebarItem]) -> Set<UUID> {
        let table = items
        let thin = table.values.filter { s in s.isSplit && s.children.filter { table[$0]?.isTab == true }.count < 2 }.map(\.id)
        var changed = Set<UUID>()
        for id in thin {
            guard let split = items[id] else { continue }
            let kids = split.children.filter { items[$0] != nil }
            if let p = split.parentID, var parent = items[p] {
                let at = parent.children.firstIndex(of: id) ?? parent.children.count
                parent.children.removeAll { $0 == id || kids.contains($0) }
                parent.children.insert(contentsOf: kids, at: min(at, parent.children.count))
                items[p] = parent
                changed.insert(p)
            }
            for c in kids {
                items[c]?.parentID = split.parentID
                changed.insert(c)
            }
            items[id] = nil
            changed.insert(id)
        }
        return changed
    }
}
