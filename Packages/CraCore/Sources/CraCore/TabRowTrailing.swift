import CoreGraphics

/// The trailing end of a tab's sidebar row: its controls (the capture dot, a peek badge, the unread
/// dot, the close button on hover) laid out right to left from the fill's end, and the width that
/// leaves the name (and the subtitle under it, which shares it).
///
/// Arc 1.171 (GitHub #139): the close button is a 24 pt square ending 6 pt before the fill's end; the
/// unread dot and a peek badge sit centred where it shows. Two controls are 11 pt apart.
public enum TabRowTrailing {
    /// The last control's slot ends this far before the row's end (the fill's end).
    public static let endInset: CGFloat = 6
    /// Between two trailing controls.
    public static let controlGap: CGFloat = 11
    /// The name's box (before `SidebarText.inset` widens the label) to the first control: 13 pt of
    /// air from the label's box, as in Arc (GitHub #243). It was 26, a gap kept from when a 22 pt
    /// "back to pinned page" button also sat before the close button.
    public static let nameGap: CGFloat = 15
    /// The name's box to the row's end with no control shown.
    public static let restingTail: CGFloat = 21

    public struct Control: Equatable, Sendable {
        /// The control's own width.
        public var width: CGFloat
        /// The width it's centred in: its own, or the close button's for a dot or badge that sits
        /// where the button shows on hover.
        public var slot: CGFloat

        public init(width: CGFloat, slot: CGFloat? = nil) {
            self.width = width
            self.slot = slot ?? width
        }
    }

    public struct Layout: Equatable, Sendable {
        /// Each control's minimum x, in the order given (leading to trailing).
        public var controlX: [CGFloat]
        /// The name's width from `textX`, never negative.
        public var textWidth: CGFloat
    }

    /// `controls` leading to trailing; `textX` is where the name starts, in the row's coordinates.
    public static func layout(rowWidth: CGFloat, textX: CGFloat, controls: [Control]) -> Layout {
        var right = rowWidth - endInset
        var xs = [CGFloat](repeating: 0, count: controls.count)
        for i in controls.indices.reversed() {
            let c = controls[i]
            xs[i] = right - c.slot / 2 - c.width / 2
            right = xs[i] - controlGap
        }
        let textEnd = xs.first.map { $0 - nameGap } ?? rowWidth - restingTail
        return Layout(controlX: xs, textWidth: max(0, textEnd - textX))
    }
}
