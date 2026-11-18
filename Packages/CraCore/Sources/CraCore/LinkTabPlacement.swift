import Foundation

/// Where a tab a link opens goes in the sidebar, next to the tab it came from.
///
/// Arc puts a link's tab right below its source tab in Today. Cra did that for "Open Link in New Tab",
/// but a ⌘-click or middle click on the engine went to the top of Today with every other new tab.
/// Settings ▸ Links ▸ "Open background tabs below the current tab" (GitHub #532, off by default)
/// sends those below the source too, in the order they were opened.
public enum LinkTabPlacement {
    /// A place in the sidebar: `index` among `parent`'s children.
    public struct Slot: Equatable {
        public let parent: UUID
        public let index: Int
        public init(parent: UUID, index: Int) {
            self.parent = parent
            self.index = index
        }
    }

    /// The slot below `source` for a tab a link in it opened, or nil when the tab goes where new tabs
    /// go (`newTabsAtTop`). Only a tab in Today has a slot: a pinned tab's or a favorite's links open
    /// in Today, and a live folder fills itself.
    ///
    /// A tab in a split gets the slot below the split, never a pane of it. With `afterEarlierLinks` the
    /// slot skips the tabs `source` already opened right below it, so a row of ⌘-clicks reads in the
    /// order they were clicked; without it each new tab goes straight under `source`.
    public static func belowSource(_ source: UUID, afterEarlierLinks: Bool, item: (UUID) -> SidebarItem?) -> Slot? {
        guard let tab = item(source), tab.isTab else { return nil }
        var anchor = tab
        if let p = anchor.parentID, let split = item(p), split.isSplit { anchor = split }
        guard let parentID = anchor.parentID, let parent = item(parentID),
              let at = parent.children.firstIndex(of: anchor.id) else { return nil }
        // Up to the root: Today, outside any live folder.
        var cur: SidebarItem? = parent, hops = 0
        while let c = cur, hops < 64 {
            if c.isLiveFolder { return nil }
            if let kind = c.container {
                guard case .today = kind else { return nil }
                break
            }
            cur = c.parentID.flatMap(item)
            hops += 1
        }
        guard cur?.container != nil else { return nil }
        var index = at + 1
        if afterEarlierLinks {
            while index < parent.children.count, item(parent.children[index])?.tab?.referrerID == source { index += 1 }
        }
        return Slot(parent: parentID, index: index)
    }
}
