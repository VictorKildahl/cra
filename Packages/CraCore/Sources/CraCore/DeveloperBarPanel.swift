import Foundation

/// Arc's ⌘L on a page that shows the developer bar (a local page, GitHub #42): the bar's address is edited in place and
/// the command bar's suggestions drop across the page card under it, instead of the centred bar (Arc 1.174.1, measured
/// 22 Nov 2026 on 127.0.0.1 with real ⌘L keystrokes, docs/arc-reverse-engineering.md "The address panel from the
/// sidebar"). The panel is the card's width with its top on the bar's; its field row is the bar's 40 pt, the bar's glyph
/// and monospaced address where the bar draws them, a hairline under it; then the full bar's rows (46 pt, 4 pt apart,
/// inset 10, the first 6 pt under the field row, titles with their addresses) and 11.5 pt under the last one: 303.5 pt
/// for five rows, as Arc's. Its top corners are the card's; ordinary sites keep the centred bar (Arc does too).
public enum DeveloperBarPanel {
    public static let inputHeight: Double = 40
    public static let rowsTop: Double = 6
    public static let rowHeight: Double = 46
    public static let rowGap: Double = 4
    public static let bottomPadding: Double = 11.5
    public static let bottomRadius: Double = 10

    /// The panel's height with `rows` suggestions: the field row alone when there are none.
    public static func height(rows: Int) -> Double {
        guard rows > 0 else { return inputHeight }
        let n = Double(rows)
        return inputHeight + rowsTop + n * rowHeight + (n - 1) * rowGap + bottomPadding
    }

    /// Whether ⌘L (Open Command Bar on the open tab's address) edits the developer bar in place: the focused page shows
    /// the developer bar, on screen. Elsewhere, and for a new tab, the centred bar opens as before.
    public static func opens(editingURL: Bool, barIsDeveloper: Bool, barShown: Bool) -> Bool {
        editingURL && barIsDeveloper && barShown
    }
}
