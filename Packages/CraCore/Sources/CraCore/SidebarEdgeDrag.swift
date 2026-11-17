import CoreGraphics
import Foundation

/// A tab dragged from the sidebar and held at the sidebar's side edge pages to the space next to
/// it, as in Arc (GitHub #499): its `TablistEdgeDragController` keeps a timer, a proposed
/// `Direction` (`next`, `previous`), the last drag position and a `switchThreshold`, and calls
/// back with the direction when the threshold passes. Dropping the tab on a space's icon in the
/// dock does the same (SpaceCellView).
///
/// The edges go by the screen, not by the side the sidebar is on: the right edge pages toward
/// the next space and the left toward the previous one, the way the pages sit on the strip.
public struct SidebarEdgeDrag: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case next, previous
    }

    /// How far inside the sidebar an edge reaches. The rows end 8 pt or more from the edge, so a
    /// tab dragged within the list never pages.
    public static let inner: CGFloat = 6
    /// How far past the sidebar it reaches: over the page beside it (less than
    /// SplitDropProposal.sidebarSideBand, where no split opens yet) or past the window's edge.
    public static let outer: CGFloat = 30
    /// How long the tab stays at an edge before the space changes, and again for each space after
    /// that while it stays. Arc's `switchThreshold` is not measured yet; this is the space icon's
    /// wait (SpaceCellView).
    public static let delay: TimeInterval = 0.5

    /// The edge `point` is at, in the coordinates of `sidebar` (the frame the tab list pages in,
    /// y up or down), or nil away from both.
    public static func direction(at point: CGPoint, sidebar: CGRect) -> Direction? {
        guard !sidebar.isEmpty, point.y >= sidebar.minY, point.y <= sidebar.maxY else { return nil }
        if point.x >= sidebar.maxX - inner, point.x <= sidebar.maxX + outer { return .next }
        if point.x <= sidebar.minX + inner, point.x >= sidebar.minX - outer { return .previous }
        return nil
    }

    /// The page to show after paging `direction` from `index` among `count` spaces: none past
    /// the first or the last (a swipe stops there too).
    public static func target(from index: Int, count: Int, _ direction: Direction) -> Int? {
        let to = direction == .next ? index + 1 : index - 1
        return (0..<count).contains(to) && (0..<count).contains(index) ? to : nil
    }

    private struct Held: Equatable, Sendable {
        var direction: Direction
        var since: TimeInterval
    }

    private var held: Held?

    public init() {}

    /// Where the drag is at `time` (the edge it is at, or nil); returns the direction to page
    /// now, once per `delay` the tab stays at one edge. Leaving the edge starts the wait over.
    public mutating func update(_ direction: Direction?, at time: TimeInterval) -> Direction? {
        guard let direction else { held = nil; return nil }
        guard let h = held, h.direction == direction else {
            held = Held(direction: direction, since: time)
            return nil
        }
        guard time - h.since >= Self.delay else { return nil }
        held?.since = time
        return direction
    }
}
