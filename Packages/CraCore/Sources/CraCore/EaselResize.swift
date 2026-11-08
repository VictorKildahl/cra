import Foundation

/// Resizing a picked item on an Easel by its corners (Arc 1.172.1's EaselUI AspectRatioControlPoints):
/// a picture keeps its proportions with the opposite corner fixed; a rectangle or ellipse follows the
/// pointer freely. Text sizes with the pill, arrows and strokes don't resize.
extension Easel {
    public enum Corner: CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }

    /// How close to a corner a press grabs it (points, either side of the outline).
    public static let cornerGrab: Double = 8
    /// The smallest an item gets.
    public static let minimumSide: Double = 16

    /// The corner of `r` under `p`, if any (the canvas's y grows downwards).
    public static func corner(of r: Rect, at p: Point) -> Corner? {
        let g = cornerGrab
        let points: [(Corner, Point)] = [(.topLeft, Point(r.x, r.y)), (.topRight, Point(r.x + r.width, r.y)),
                                         (.bottomLeft, Point(r.x, r.y + r.height)), (.bottomRight, Point(r.x + r.width, r.y + r.height))]
        return points.first { abs($0.1.x - p.x) <= g && abs($0.1.y - p.y) <= g }?.0
    }

    public static func resizes(_ kind: Item.Kind) -> Bool {
        switch kind {
        case .image, .rectangle, .ellipse: return true
        case .text, .arrow, .freehand: return false
        }
    }

    /// `r` with `corner` dragged to `p`; `keepRatio` holds `r`'s proportions (pictures).
    public static func resized(_ r: Rect, corner: Corner, to p: Point, keepRatio: Bool) -> Rect {
        let left = r.x, top = r.y, right = r.x + r.width, bottom = r.y + r.height
        // The fixed corner, opposite the dragged one.
        let fx = (corner == .topLeft || corner == .bottomLeft) ? right : left
        let fy = (corner == .topLeft || corner == .topRight) ? bottom : top
        let sx: Double = (corner == .topLeft || corner == .bottomLeft) ? -1 : 1
        let sy: Double = (corner == .topLeft || corner == .topRight) ? -1 : 1
        var w = max(minimumSide, (p.x - fx) * sx)
        var h = max(minimumSide, (p.y - fy) * sy)
        if keepRatio, r.width > 0, r.height > 0 {
            let ratio = r.width / r.height
            // The pointer's larger pull wins, so the corner stays under it along the diagonal.
            if w / ratio >= h { h = w / ratio } else { w = h * ratio }
            if w < minimumSide { w = minimumSide; h = w / ratio }
            if h < minimumSide { h = minimumSide; w = h * ratio }
        }
        return Rect(x: sx < 0 ? fx - w : fx, y: sy < 0 ? fy - h : fy, width: w, height: h)
    }
}
