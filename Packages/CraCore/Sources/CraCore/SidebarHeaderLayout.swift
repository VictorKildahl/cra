import Foundation

/// The sidebar header with the toolbar hidden, by sidebar width (issue #287). Arc 1.17x keeps
/// three layouts (`SidebarHeaderWidthLayout`: regular, compact, narrow); measured live on an
/// offline Arc over AX, 9 Nov 2026, from 274 pt down to its 164 pt minimum:
///
/// - 212 pt and wider: the sidebar toggle after the traffic lights, then ← → ↻ as 32 pt
///   boxes 2 pt apart, ending 6 pt from the sidebar's edge. The toggle moves left to stay 2 pt
///   clear of ← (Arc's x 77 → 74 at 214, 73 at 213, 72 at 212).
/// - 211 pt and narrower: no toggle; ← → and "More options" (•••) as 28 pt boxes with no gap,
///   ending 6 pt from the edge, centred on the same line. ••• turns into ✕ while its popover
///   (Reload ⌘R, Toggle Sidebar ⌘S) is open. Each of 213, 212, 211, 210 and 209 was opened
///   on its own (the resize snapping skips some widths during a drag).
///
/// With the toolbar shown the header holds only the toggle, which is 28 pt under 212. On a
/// Developer Mode page it holds toggle + ← → ↻ again (← at width − 107) and goes narrow
/// below 212 the same way, ← → ••• included.
public enum SidebarHeaderLayout {
    public static let narrowBelow: Double = 212
    public static let edgeInset: Double = 6

    public static func isNarrow(width: Double) -> Bool { width < narrowBelow }

    /// The nav buttons' boxes, left to right (← → ↻, or ← → ••• when narrow): x and size.
    public static func navButtons(width: Double) -> [(x: Double, size: Double)] {
        let narrow = isNarrow(width: width)
        let size = narrow ? 28.0 : 32.0, gap = narrow ? 0.0 : 2.0
        let first = width - edgeInset - 3 * size - 2 * gap
        return (0..<3).map { (first + Double($0) * (size + gap), size) }
    }

    /// The toggle's x in the regular layout: right after the traffic lights (`afterLights`),
    /// or further left when ← comes within 2 pt of it. On a Developer Mode page Arc's ← sits
    /// 1 pt further left (Arc: 71 beside ← at 105 for 212 pt).
    public static func toggleX(width: Double, afterLights: Double, developer: Bool = false, toggleSize: Double = 32) -> Double {
        let back = developer ? width - 107 : navButtons(width: width)[0].x
        return min(afterLights, back - 2 - toggleSize)
    }
}

/// The popover under the narrow header's ••• (Arc 1.17x, 1x window capture, 9 Nov 2026).
public enum SidebarMoreMenu {
    public static let width: Double = 200
    public static let rowHeight: Double = 40
    /// Padding around the rows; also the highlight's inset from the panel's sides.
    public static let inset: Double = 8
    public static let cornerRadius: Double = 12
    public static let highlightRadius: Double = 8
    public static let arrowHeight: Double = 6
    public static let arrowWidth: Double = 12
    /// The arrow's tip sits this far under the button's bottom edge.
    public static let arrowGap: Double = 10
    /// Icon centre, title start and the shortcut's trailing edge, from the panel's sides.
    public static let iconCentre: Double = 27.5
    public static let titleX: Double = 50.5
    public static let shortcutTrailing: Double = 21

    public static func height(rows: Int) -> Double { 2 * inset + Double(rows) * rowHeight }

    /// The panel's fill: black with 15 % of the theme's shadedDark, half the tooltip's 30 %
    /// (Arc's yellow "Lab" theme: shadedDark (111, 86, −20) → (17, 13, 0) measured).
    public static func fill(shadedDark ink: RGB) -> RGB {
        clamped(RGB.black.mixed(with: ink, 0.15))
    }

    /// The hovered row: the fill with 41 % of shadedDark over it, then 13 % white
    /// (measured (81, 70, 26) on the same theme).
    public static func highlight(shadedDark ink: RGB) -> RGB {
        clamped(RGB.black.mixed(with: ink, 0.15).mixed(with: ink, 0.41).mixed(with: .white, 0.13))
    }

    private static func clamped(_ c: RGB) -> RGB {
        RGB(min(max(c.r, 0), 1), min(max(c.g, 0), 1), min(max(c.b, 0), 1))
    }
}
