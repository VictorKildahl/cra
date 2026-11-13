import CoreGraphics

/// Where Arc's menu (`ArcMenu.ArcMenuWindow`) puts its rows, separators and tail. Measured on Arc
/// 1.172.1: the sidebar + menu (live, 9 Nov 2026, 1x) has 40 pt rows 8 pt from the fill's top and
/// bottom, and 1 pt separators 8 pt after a group's last row and 8 pt before the next group's first
/// (rows at 8, 48 | 105, 145 | 202, 242 in a 290 pt fill), with the tail under the fill. The back and
/// forward list (a 2x capture, 13 Nov 2026, GitHub #416) is one group in the same rows (three entries
/// make a 136 pt fill) with the tail on top, pointing up at the button. The tail shows 6 pt of its
/// 7 pt height (it starts 1 pt inside the fill) and is 12 pt wide.
public struct ArcMenuLayout: Equatable, Sendable {
    public enum TailEdge: Sendable { case top, bottom }

    public static let rowHeight: CGFloat = 40
    public static let padding: CGFloat = 8
    public static let tailHeight: CGFloat = 6

    /// Each row's top in the fill, flipped (0 at the fill's top).
    public let rowTops: [CGFloat]
    /// Each separator's top in the fill.
    public let separatorTops: [CGFloat]
    public let fillHeight: CGFloat
    public let tail: TailEdge

    /// `groups` holds the number of rows in each group, in order.
    public init(groups: [Int], tail: TailEdge) {
        var y = Self.padding
        var rows: [CGFloat] = []
        var separators: [CGFloat] = []
        for (index, count) in groups.enumerated() {
            for _ in 0..<max(count, 0) {
                rows.append(y)
                y += Self.rowHeight
            }
            if index < groups.count - 1 {
                separators.append(y + Self.padding)
                y += Self.padding + 1 + Self.padding
            }
        }
        rowTops = rows
        separatorTops = separators
        fillHeight = y + Self.padding
        self.tail = tail
    }

    /// The window's content height: the fill and the tail beyond it.
    public var height: CGFloat { fillHeight + Self.tailHeight }
    /// Where the fill starts in the content, flipped: below the tail when the tail is on top.
    public var fillTop: CGFloat { tail == .top ? Self.tailHeight : 0 }
}
