import Foundation

/// Arc's alignment guides on an Easel (EaselCanvasViewController+SnapGuides, AnchorGuide, the canvas
/// menu's "Use Alignment Guides", defaults key easel.useSnapguides): a moved item's left, centre and
/// right (and top, middle, bottom) snap to another item's when within a few points, and a line shows
/// along the edge they share.
extension Easel {
    /// How near an edge has to come to snap (points).
    public static let snapDistance: Double = 6

    public struct Guide: Equatable, Sendable {
        public enum Axis: Sendable { case vertical, horizontal }
        public var axis: Axis
        /// x for a vertical line, y for a horizontal one.
        public var position: Double
        /// Where the line starts and ends along the other axis.
        public var from: Double, to: Double
        public init(axis: Axis, position: Double, from: Double, to: Double) {
            (self.axis, self.position, self.from, self.to) = (axis, position, from, to)
        }
    }

    /// `frame` moved onto the nearest edges of `others`, and the guides to draw.
    public static func snapped(_ frame: Rect, to others: [Rect], within d: Double = snapDistance) -> (frame: Rect, guides: [Guide]) {
        func lines(_ r: Rect, _ axis: Guide.Axis) -> [Double] {
            axis == .vertical ? [r.x, r.x + r.width / 2, r.x + r.width] : [r.y, r.y + r.height / 2, r.y + r.height]
        }
        var out = frame
        var guides: [Guide] = []
        for axis in [Guide.Axis.vertical, .horizontal] {
            var best: (delta: Double, at: Double)?
            for mine in lines(frame, axis) {
                for other in others {
                    for theirs in lines(other, axis) {
                        let delta = theirs - mine
                        if abs(delta) <= d, abs(delta) < abs(best?.delta ?? .infinity) { best = (delta, theirs) }
                    }
                }
            }
            guard let best else { continue }
            if axis == .vertical { out.x += best.delta } else { out.y += best.delta }
            // The line runs along every item that shares it, the moved one included.
            let sharing = ([out] + others).filter { r in lines(r, axis).contains { abs($0 - best.at) < 0.5 } }
            let lo = sharing.map { axis == .vertical ? $0.y : $0.x }.min() ?? 0
            let hi = sharing.map { axis == .vertical ? $0.y + $0.height : $0.x + $0.width }.max() ?? 0
            guides.append(Guide(axis: axis, position: best.at, from: lo, to: hi))
        }
        return (out, guides)
    }
}
