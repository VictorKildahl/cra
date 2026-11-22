import Foundation

/// Resizing a picked item on an Easel by its corners and edges (Arc 1.172.1's EaselUI AspectRatioControlPoints):
/// a picture keeps its proportions with the opposite corner fixed; a rectangle or ellipse follows the
/// pointer freely by its corners or edges. A text box resizes horizontally to wrap text.
extension Easel {
    public enum Corner: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    /// How close to a corner or edge handle a press grabs it (points, either side of the outline).
    public static let cornerGrab: Double = 8
    /// The smallest an item gets.
    public static let minimumSide: Double = 16

    /// The handles shown and active for `kind`.
    public static func handles(for kind: Item.Kind) -> [Corner] {
        switch kind {
        case .rectangle, .ellipse, .text:
            return [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
        case .image, .capture:
            return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .arrow, .freehand, .link:
            return []
        }
    }

    /// The corner or edge handle of `r` under `p`, if any (the canvas's y grows downwards).
    public static func corner(of r: Rect, at p: Point, kind: Item.Kind? = nil) -> Corner? {
        let g = cornerGrab
        let corners: [(Corner, Point)] = [
            (.topLeft, Point(r.x, r.y)),
            (.topRight, Point(r.x + r.width, r.y)),
            (.bottomLeft, Point(r.x, r.y + r.height)),
            (.bottomRight, Point(r.x + r.width, r.y + r.height))
        ]
        let allowed = kind.map(handles(for:))
        if let match = corners.first(where: { (corner, pt) in
            (allowed == nil || allowed!.contains(corner)) && abs(pt.x - p.x) <= g && abs(pt.y - p.y) <= g
        }) {
            return match.0
        }

        let midX = r.x + r.width / 2
        let midY = r.y + r.height / 2
        let edgePoints: [(Corner, Point)] = [
            (.top, Point(midX, r.y)),
            (.bottom, Point(midX, r.y + r.height)),
            (.left, Point(r.x, midY)),
            (.right, Point(r.x + r.width, midY))
        ]
        if let match = edgePoints.first(where: { (corner, pt) in
            (allowed == nil || allowed!.contains(corner)) && abs(pt.x - p.x) <= g && abs(pt.y - p.y) <= g
        }) {
            return match.0
        }

        if case .text = kind {
            // For text boxes, dragging anywhere along the edges resizes:
            if abs(r.x + r.width - p.x) <= g && p.y >= r.y - g && p.y <= r.y + r.height + g {
                return .right
            }
            if abs(r.x - p.x) <= g && p.y >= r.y - g && p.y <= r.y + r.height + g {
                return .left
            }
            if abs(r.y + r.height - p.y) <= g && p.x >= r.x - g && p.x <= r.x + r.width + g {
                return .bottom
            }
            if abs(r.y - p.y) <= g && p.x >= r.x - g && p.x <= r.x + r.width + g {
                return .top
            }
        }

        return nil
    }

    public static func resizes(_ kind: Item.Kind) -> Bool {
        switch kind {
        case .image, .rectangle, .ellipse, .capture, .text: return true
        case .arrow, .freehand, .link: return false
        }
    }

    /// Pictures and captures keep their proportions as they resize; shapes don't (⇧ makes them).
    /// Link cards keep Arc's size (no handles in Arc 1.172.2).
    public static func keepsRatio(_ kind: Item.Kind) -> Bool {
        switch kind {
        case .image, .capture: return true
        default: return false
        }
    }

    /// `r` with `corner` dragged to `p`; `keepRatio` holds `r`'s proportions (pictures, or ⇧ with shapes).
    public static func resized(_ r: Rect, corner: Corner, to p: Point, keepRatio: Bool = false) -> Rect {
        let left = r.x, top = r.y, right = r.x + r.width, bottom = r.y + r.height
        switch corner {
        case .top:
            let h = max(minimumSide, bottom - p.y)
            var w = r.width
            var x = left
            if keepRatio, r.height > 0 {
                w = max(minimumSide, h * (r.width / r.height))
                x = left + (r.width - w) / 2
            }
            return Rect(x: x, y: bottom - h, width: w, height: h)
        case .bottom:
            let h = max(minimumSide, p.y - top)
            var w = r.width
            var x = left
            if keepRatio, r.height > 0 {
                w = max(minimumSide, h * (r.width / r.height))
                x = left + (r.width - w) / 2
            }
            return Rect(x: x, y: top, width: w, height: h)
        case .left:
            let w = max(minimumSide, right - p.x)
            var h = r.height
            var y = top
            if keepRatio, r.width > 0 {
                h = max(minimumSide, w / (r.width / r.height))
                y = top + (r.height - h) / 2
            }
            return Rect(x: right - w, y: y, width: w, height: h)
        case .right:
            let w = max(minimumSide, p.x - left)
            var h = r.height
            var y = top
            if keepRatio, r.width > 0 {
                h = max(minimumSide, w / (r.width / r.height))
                y = top + (r.height - h) / 2
            }
            return Rect(x: left, y: y, width: w, height: h)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
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

    /// Resizing a text box horizontally (Arc parity): dragging left or right handles or corners adjusts
    /// width and preserves top-left anchor (or right anchor if dragged from left).
    public static func resizedText(_ r: Rect, corner: Corner, to p: Point) -> (x: Double, width: Double) {
        let left = r.x, right = r.x + r.width
        switch corner {
        case .right, .topRight, .bottomRight:
            let w = max(minimumSide, p.x - left)
            return (left, w)
        case .left, .topLeft, .bottomLeft:
            let w = max(minimumSide, right - p.x)
            return (right - w, w)
        default:
            return (left, r.width)
        }
    }
}
