import CoreGraphics

/// The Little Window's "Open in" menu (the ⌄ button, ⇧⌘O): its size and where it hangs. Arc 1.172.1,
/// 10 Nov 2026, window captures at 2x: about 244 pt wide with its 1 pt border, a 46 pt header and 46 pt
/// rows (1.168 had 54 pt ones), starting about 4 pt under the window's top edge and ending about
/// 4.5 pt short of its right one (#331). From Arc's disassembly: the list is `min(rows × 46, 350)` tall
/// and scrolls past that, and a search that matches nothing says "No results" (the ⌄ is hidden with one
/// destination, in LittleToolbarView).
public enum LittlePopupGeometry {
    public static let width: CGFloat = 244
    public static let headerHeight: CGFloat = 46
    public static let rowHeight: CGFloat = 46
    public static let maxListHeight: CGFloat = 350
    public static let topInset: CGFloat = 4
    public static let rightInset: CGFloat = 4.5

    /// The list's height for that many rows; no rows is "No results", which takes a row's height.
    public static func listHeight(rows: Int) -> CGFloat {
        min(CGFloat(max(rows, 1)) * rowHeight, maxListHeight)
    }

    public static func height(rows: Int) -> CGFloat { headerHeight + listHeight(rows: rows) }

    /// The menu's frame for a window frame in AppKit's coordinates (y up), whose top-right corner it hangs from.
    public static func frame(inWindow window: CGRect, rows: Int) -> CGRect {
        let h = height(rows: rows)
        return CGRect(x: window.maxX - rightInset - width, y: window.maxY - topInset - h, width: width, height: h)
    }
}
