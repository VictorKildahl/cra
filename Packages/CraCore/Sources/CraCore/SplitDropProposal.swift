import CoreGraphics
import Foundation

/// A tab dragged from the sidebar onto the page makes a split where it is let go, as in Arc
/// (`SplitViewController` takes the drop over the window's contents: `DropTarget.insertContent`,
/// `ProposedDropTargetInfo`). Cra takes a page's link the same way (GitHub #419; Arc doesn't).
/// While the drag is over the panes, Arc opens an empty pane, the drop region, where the tab
/// would go, and the other panes make room for it.
public enum SplitDropProposal {
    /// Where the dropped page goes: a new pane at `index` among the panes, in a split laid out
    /// `orientation` (the split's own, or the one a drop on a lone page's top or bottom gives it).
    public struct Insert: Equatable, Sendable {
        public var index: Int
        public var orientation: SplitOrientation

        public init(index: Int, orientation: SplitOrientation) {
            self.index = index
            self.orientation = orientation
        }
    }

    /// Arc's most panes in one split.
    public static let maximumPanes = 4

    /// Next to the sidebar the drag still belongs to it: Arc offers nothing over the page's first
    /// 25 pt there and opens the region by 50 (1.173.1, measured with a real drag; 40 splits it).
    public static let sidebarSideBand: CGFloat = 40

    /// What a drop does: a new pane, or the page takes a pane's place (Arc's `DropTarget`
    /// `.insertContent` and `.replaceContent`).
    public enum Target: Equatable, Sendable {
        case insert(Insert)
        /// The pane at `index` gives its place to the dropped page and goes back to the sidebar.
        case replace(index: Int)

        public var insert: Insert? { if case .insert(let i) = self { i } else { nil } }
    }

    /// In a split, how far in from a pane's side its edge reaches, as a share of its length:
    /// Arc opened the region 20 pt from a pane's side and replaced the pane a quarter in (145 pt
    /// of 578); a fifth splits it.
    public static let paneEdgeShare: CGFloat = 0.2

    /// A link offers a split only this close to a pane's edge (Cra's own; Arc takes no link over
    /// the page). Everywhere else the page keeps it, so a link or an address still drops into a
    /// page's text field, and a pane is never replaced by one.
    public static let linkEdgeBand: CGFloat = 60

    /// What a drag at `point` proposes, in the panes' coordinates (AppKit's, y up), or nil when it
    /// proposes nothing there and the page keeps the drag.
    /// - `ids`, `frames`: the panes in order and where they are without the drop region.
    /// - `region`: where the region is now, laid out for `current`, the proposal shown now.
    /// - `sidebarSide`: the sidebar sits against the area's left edge (docked, not floating).
    /// - `link`: a link, not a tab: only a pane's edges take it (`linkEdgeBand`).
    ///
    /// Arc 1.173.1, measured: on a lone page the edge nearest the pointer decides, its left or
    /// right side by side, its top or bottom stacked. In a split the pane under the pointer has
    /// edges along the split, a fifth of it each: the first opens the region before the pane,
    /// the other after it, and the gap between two panes opens it there. The rest of the pane,
    /// its top and bottom too, is replaced (its ring shows); a split keeps its direction. The
    /// region, once open, keeps the drag while the pointer stays on it, so it doesn't flip back
    /// and forth as the panes make room for it. A split of four takes no more panes.
    public static func propose(at point: CGPoint, ids: [UUID], frames: [UUID: CGRect], orientation: SplitOrientation,
                               area: CGRect, region: CGRect?, current: Target?, sidebarSide: Bool, link: Bool = false) -> Target? {
        guard !ids.isEmpty, area.contains(point) else { return nil }
        if sidebarSide, point.x < area.minX + sidebarSideBand { return nil }
        let full = ids.count >= maximumPanes
        if !full, case .insert? = current, let region,
           region.insetBy(dx: -SplitPaneLayout.Constants.gap / 2, dy: -SplitPaneLayout.Constants.gap / 2).contains(point) {
            // A lone page's region reaches its middle line, so a drag that crossed the middle on
            // its way to an edge would keep the region it opened there: reaching another edge's
            // band, a fifth of the page, wins.
            if ids.count == 1, let f = frames[ids[0]], let edge = nearestEdge(point, in: f),
               edge.distance <= edge.extent * paneEdgeShare, !link || edge.distance <= linkEdgeBand,
               .insert(edge.insert) != current {
                return .insert(edge.insert)
            }
            return current
        }
        // The pane under the pointer, or in a gap the nearest one.
        let gap = SplitPaneLayout.Constants.gap
        guard let (index, f) = ids.enumerated().compactMap({ i, id in frames[id].map { (i, $0) } })
            .min(by: { distance(point, $0.1) < distance(point, $1.1) }), distance(point, f) <= gap else { return nil }
        if ids.count == 1 {
            guard let nearest = nearestEdge(point, in: f), !link || nearest.distance <= linkEdgeBand else { return nil }
            return .insert(nearest.insert)
        }
        let horizontal = orientation == .horizontal
        // Along the split: from the pane's first side (left, or top) to its last.
        let length = horizontal ? f.width : f.height
        let along = horizontal ? point.x - f.minX : f.maxY - point.y
        let edge = link ? min(length * paneEdgeShare, linkEdgeBand) : length * paneEdgeShare
        if along < edge { return full ? nil : .insert(Insert(index: index, orientation: orientation)) }
        if along > length - edge { return full ? nil : .insert(Insert(index: index + 1, orientation: orientation)) }
        return link ? nil : .replace(index: index)
    }

    /// A lone page's edge nearest `point`: the region it opens, how far away it is, and the page's
    /// extent across that edge (its width for the sides, its height for the top and bottom).
    private static func nearestEdge(_ point: CGPoint, in f: CGRect) -> (insert: Insert, distance: CGFloat, extent: CGFloat)? {
        let edges: [(Insert, CGFloat, CGFloat)] = [
            (Insert(index: 0, orientation: .horizontal), point.x - f.minX, f.width),
            (Insert(index: 1, orientation: .horizontal), f.maxX - point.x, f.width),
            (Insert(index: 0, orientation: .vertical), f.maxY - point.y, f.height),
            (Insert(index: 1, orientation: .vertical), point.y - f.minY, f.height),
        ]
        return edges.min(by: { $0.1 < $1.1 }).map { ($0.0, $0.1, $0.2) }
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// The panes with the drop region among them: it takes an even share, 1/(n+1), and the
    /// others keep their proportions in what is left.
    public static func panes(_ panes: [SplitPaneLayout.Pane], inserting id: UUID, at insert: Insert) -> [SplitPaneLayout.Pane] {
        let n = CGFloat(panes.count)
        let sum = panes.reduce(0) { $0 + $1.factor }
        var out = panes.map { SplitPaneLayout.Pane(id: $0.id, factor: sum > 0 ? $0.factor / sum * n / (n + 1) : 1 / (n + 1)) }
        out.insert(SplitPaneLayout.Pane(id: id, factor: 1 / (n + 1)), at: min(max(0, insert.index), out.count))
        return out
    }
}
