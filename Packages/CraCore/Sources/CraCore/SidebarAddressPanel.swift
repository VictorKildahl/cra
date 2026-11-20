import Foundation

/// Arc's address panel (GitHub #663): a click on the sidebar's address opens a compact command bar
/// over the top of the sidebar, its top left on the address field's, not the centred bar. Measured
/// in offline Arc 1.174 (20 Nov 2026, the address in the sidebar, the toolbar hidden; AX frames and
/// 2x captures): the field is the address's width in 13 pt medium, at least 240 and at most 610 pt,
/// and the panel is 110 pt wider (the glyph, the ⓘ and the margins), 350 to 720 pt. The input row is
/// 45 pt and the rows hang under it on the full bar's 50 pt pitch, titles only (13 pt semibold).
/// With no tab the empty field gets the narrowest panel, "Search or Enter URL…". ⌘L is not this
/// panel: Arc's opens across the top of the page instead.
public enum SidebarAddressPanel {
    /// The typed text's width: at least this, at most `fieldMax`, plus room for the caret.
    public static let fieldMin = 240.0
    public static let fieldMax = 610.0
    public static let caretRoom = 2.0
    /// The panel less its field: the 53 pt before it (glyph) and the 57 after (ⓘ and margin).
    public static let chrome = 110.0
    /// Kept from the window's edge when the window is too narrow for the whole panel.
    public static let windowMargin = 8.0
    public static let inputHeight = 45.0
    public static let rowHeight = 46.0
    public static let rowGap = 4.0
    /// From the input row to the first row, and from the last row to the panel's bottom.
    public static let rowsTop = 6.0
    public static let bottomPadding = 10.5
    public static let cornerRadius = 10.0
    /// The address and the rows' titles.
    public static let fontSize = 13.0

    /// The panel's width for an address `textWidth` wide (13 pt medium), in a window that leaves
    /// `available` points to its right.
    public static func width(textWidth: Double, available: Double) -> Double {
        let field = min(max(textWidth + caretRoom, fieldMin), fieldMax)
        return max(0, min(field + chrome, available - windowMargin))
    }

    /// The panel's height with `rows` rows (the banner counts as one).
    public static func height(rows: Int) -> Double {
        guard rows > 0 else { return inputHeight }
        let n = Double(rows)
        return inputHeight + rowsTop + n * rowHeight + (n - 1) * rowGap + bottomPadding
    }
}
