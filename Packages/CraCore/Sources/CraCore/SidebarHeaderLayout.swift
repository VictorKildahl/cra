import Foundation

/// The sidebar header with the toolbar hidden, by sidebar width (issue #287). Arc 1.17x keeps
/// three layouts (`SidebarHeaderWidthLayout`: regular, compact, narrow); measured live on an
/// offline Arc over AX, 9 Nov 2026, from 274 pt down to its 164 pt minimum:
///
/// - 214 pt and wider: the sidebar toggle after the traffic lights, then ← → ↻ as 32 pt
///   boxes 2 pt apart, ending 6 pt from the sidebar's edge. At 214 the toggle moves left to
///   stay 2 pt clear of ← (Arc's x 77 → 74).
/// - 208 pt and narrower: no toggle; ← → and "More options" (•••) as 28 pt boxes with no gap,
///   ending 6 pt from the edge, centred on the same line. ••• turns into ✕ while its popover
///   (Reload ⌘R, Toggle Sidebar ⌘S) is open.
///
/// Arc's resize snapping kept the drag from landing on 209–213 pt, so where between 208 and
/// 214 the switch happens wasn't seen; Cra switches below 214, where the toggle would have to
/// cover the traffic lights to keep its 2 pt gap.
public enum SidebarHeaderLayout {
    public static let narrowBelow: Double = 214
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
    /// or further left when ← comes within 2 pt of it.
    public static func toggleX(width: Double, afterLights: Double, toggleSize: Double = 32) -> Double {
        min(afterLights, navButtons(width: width)[0].x - 2 - toggleSize)
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
