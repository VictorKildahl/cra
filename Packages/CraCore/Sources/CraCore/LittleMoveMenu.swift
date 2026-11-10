import CoreGraphics
import Foundation

/// Arc's LittleBrowserMoveMenu: the Little Window's "Open in" menu (its ⌄ and ⇧⌘O), a "Search
/// Spaces…" header over one row per space.
///
/// Arc 1.172.1 (offline copy with 1 and 10 spaces, AX frames and 2x window captures, 10 Nov 2026,
/// GitHub #331): 244 pt wide with a hairline border, 4 pt below the window's top edge and 4 pt in
/// from its right edge. A 46 pt header, then 46 pt rows (a 26 pt tile 10 pt in, the name 13 pt
/// semibold 46 pt in) in a list of at most 350 pt that scrolls past that. The space "Open in" names
/// comes first and is highlighted, the others follow in sidebar order. Typing shrinks the menu to
/// the matches; with none it shows "No results" in 64 pt. With one space there's no ⌄ at all.
/// Arc 1.168 (24 Oct) had 54 pt rows, 40 pt tiles, every space in sidebar order, at most six.
public enum LittleMoveMenu {
    public static let width: CGFloat = 244
    public static let border: CGFloat = 0.5
    public static let cornerRadius: CGFloat = 12
    public static let headerHeight: CGFloat = 46
    public static let rowHeight: CGFloat = 46
    public static let maxListHeight: CGFloat = 350
    public static let noResultsHeight: CGFloat = 64
    public static let tileSize: CGFloat = 26
    public static let tileRadius: CGFloat = 6
    public static let tileX: CGFloat = 10
    /// Where the names and the search text start.
    public static let textX: CGFloat = 46
    public static let titleSize: CGFloat = 13
    /// From the window's top edge to the menu's, and from the menu's right edge to the window's.
    public static let topInset: CGFloat = 4
    public static let rightInset: CGFloat = 4

    /// The list under the header: every row up to 350 pt, then it scrolls; "No results" when
    /// nothing matches.
    public static func listHeight(rows: Int) -> CGFloat {
        rows <= 0 ? noResultsHeight : min(CGFloat(rows) * rowHeight, maxListHeight)
    }

    /// The menu's frame for a Little Window's frame (AppKit's y-up screen coordinates).
    public static func frame(rows: Int, in window: CGRect) -> CGRect {
        let h = headerHeight + listHeight(rows: rows)
        return CGRect(x: window.maxX - rightInset - width, y: window.maxY - topInset - h, width: width, height: h)
    }

    /// The ⌄ opens the menu only when there is another space to pick.
    public static func showsChevron(spaces: Int) -> Bool { spaces > 1 }

    /// The rows: the space "Open in" names first, then the rest in sidebar order.
    public static func order<ID: Equatable>(_ spaces: [ID], target: ID) -> [ID] {
        spaces.filter { $0 == target } + spaces.filter { $0 != target }
    }

    /// The list's scroll offset (from its top) that shows `row` whole, moving as little as it can
    /// from `offset`.
    public static func scrollOffset(showing row: Int, from offset: CGFloat, rows: Int) -> CGFloat {
        let visible = listHeight(rows: rows)
        let maxOffset = max(0, CGFloat(rows) * rowHeight - visible)
        let top = CGFloat(max(0, row)) * rowHeight
        var o = offset
        if top < o { o = top }
        if top + rowHeight > o + visible { o = top + rowHeight - visible }
        return min(max(0, o), maxOffset)
    }
}
