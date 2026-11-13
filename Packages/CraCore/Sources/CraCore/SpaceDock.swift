import CoreGraphics
import Foundation

/// What one space's cell in the sidebar's dock draws (Arc: SidebarDockIconType).
public enum SpaceDockMark: Equatable, Sendable {
    case emoji(String)
    case symbol(String)
    case image(Data)
    /// A filled circle this many points across.
    case dot(diameter: CGFloat)
}

/// The row of space icons between the Library and + buttons at the bottom of the sidebar.
///
/// Arc 1.171, 5 to 22 spaces (31 Oct 2026): every space gets an equal share of the room between
/// the buttons (217 pt in a 300 pt sidebar), in half points and at most 34 pt. Below 22 pt the dock
/// is squeezed: the open space keeps 22 and the others split the rest, 17.5 pt each with 12 spaces,
/// 13 with 16, 9 with 22.
///
/// Arc 1.171, measured 8 Nov 2026 (#252, 2x window captures, 4 and 12 spaces): a space with no
/// icon (Remove Icon) is an 8 pt dot. In a squeezed dock every space but the open one is a 4 pt
/// dot, emoji spaces too; the open one keeps its emoji, or its 8 pt dot.
///
/// Arc 1.171, measured 10 Nov 2026 (#252, 12 spaces, light and dark): hovering a squeezed dot hands
/// the wide cell to that space, which shows its icon (an icon-less space its 8 pt dot) at full ink,
/// while the open space shrinks to a 4 pt dot in the others' ink. No hover fill. Cells slide and
/// the icons trade places in about 0.2 s.
public enum SpaceDock {
    public static let cellWidth: CGFloat = 34
    public static let openCellWidth: CGFloat = 22
    public static let dotDiameter: CGFloat = 8
    public static let squeezedDotDiameter: CGFloat = 4

    /// Every space's even share of `room`, in half points and at most `cellWidth`.
    static func evenWidth(count: Int, room: CGFloat) -> CGFloat {
        min(cellWidth, floor(max(0, room) / CGFloat(count) * 2) / 2)
    }

    /// Whether `count` spaces in `room` points squeeze the dock.
    public static func isSqueezed(count: Int, room: CGFloat) -> Bool {
        count > 1 && evenWidth(count: count, room: room) < openCellWidth
    }

    /// The space that holds a squeezed dock's wide cell and shows its icon: the hovered one, else
    /// the open one (#252). Pass it as `open` to `widths` and `isOpen` to `mark`.
    public static func wide<ID: Equatable>(open: ID?, hovered: ID?) -> ID? {
        hovered ?? open
    }

    /// Whether a cell is lit: its icon at full strength, its dot in `dotAlpha`'s open ink. The open
    /// space is lit unless a hovered space has taken a squeezed dock's wide cell from it (#252).
    public static func isLit(isOpen: Bool, hovered: Bool, pressed: Bool, isWide: Bool, squeezed: Bool) -> Bool {
        hovered || pressed || (isOpen && (isWide || !squeezed))
    }

    /// The cells' widths in order; `open` is the index of the space in the wide cell (`wide`), if
    /// it is in the dock.
    public static func widths(count: Int, open: Int?, room: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let even = evenWidth(count: count, room: room)
        guard isSqueezed(count: count, room: room) else { return Array(repeating: even, count: count) }
        let rest = max(4, floor((max(0, room) - openCellWidth) / CGFloat(count - 1) * 2) / 2)
        return (0..<count).map { $0 == open ? openCellWidth : rest }
    }

    /// The dot's ink: black on a light space and white on a dark one, at this alpha. Arc 1.171
    /// (8 Nov 2026, over the sidebar's fill): the open space's dot 0.5 either way, the others 0.25
    /// on light and 0.18 on dark, squeezed or not.
    public static func dotAlpha(dark: Bool, lit: Bool) -> CGFloat {
        lit ? 0.5 : (dark ? 0.18 : 0.25)
    }

    /// What a space's cell draws. `isOpen`: the space holds the wide cell (`wide`), which is the
    /// open space unless another one is hovered.
    public static func mark(for icon: SpaceIcon, isOpen: Bool, squeezed: Bool) -> SpaceDockMark {
        if squeezed && !isOpen { return .dot(diameter: squeezedDotDiameter) }
        switch icon {
        case .emoji(let e): return .emoji(e)
        case .symbol(let s): return .symbol(s)
        case .image(let d): return .image(d)
        case .none: return .dot(diameter: dotDiameter)
        }
    }
}
