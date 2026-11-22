import Foundation

/// Resizing a picked item on an Easel, as Arc 1.174.1 does (EaselUI's AspectRatioControlPoints and FrameControlPoint
/// with its ExtendedDragArea; measured 22 Nov 2026, #680, docs/arc-reverse-engineering.md "Easel resize handles"):
/// four corner dots on everything that resizes and none on the edges. A picture keeps its proportions with the
/// opposite corner fixed. A rectangle or ellipse follows the pointer freely, by a corner or anywhere along an edge
/// (that side only). A text box takes its width from a corner or its left or right edge, the opposite side fixed,
/// and is always as tall as its text: its top and bottom edges show Arc's up-down cursor and move nothing.
/// Arrows, strokes and link cards don't resize.
extension Easel {
    public enum Corner: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        /// One of the four corners, rather than an edge.
        public var isCorner: Bool { self == .topLeft || self == .topRight || self == .bottomLeft || self == .bottomRight }
    }

    /// How close to a corner or edge a press grabs it (points, either side of the outline).
    public static let cornerGrab: Double = 8
    /// The smallest an item gets.
    public static let minimumSide: Double = 16

    /// The corners drawn as dots: all four on everything that resizes, as in Arc (edges have no dots).
    public static func handles(for kind: Item.Kind) -> [Corner] {
        resizes(kind) ? [.topLeft, .topRight, .bottomLeft, .bottomRight] : []
    }

    /// Whether `kind` also resizes from anywhere along its edges (Arc's ExtendedDragArea): shapes and text, not pictures.
    public static func resizesFromEdges(_ kind: Item.Kind) -> Bool {
        switch kind {
        case .rectangle, .ellipse, .text: return true
        default: return false
        }
    }

    /// The corner of `r` under `p`, or with `kind` given an edge along its whole length when that kind resizes
    /// from its edges; nil elsewhere (the canvas's y grows downwards). Corners win where they meet an edge.
    public static func corner(of r: Rect, at p: Point, kind: Item.Kind? = nil) -> Corner? {
        let g = cornerGrab
        let corners: [(Corner, Point)] = [(.topLeft, Point(r.x, r.y)), (.topRight, Point(r.x + r.width, r.y)),
                                          (.bottomLeft, Point(r.x, r.y + r.height)), (.bottomRight, Point(r.x + r.width, r.y + r.height))]
        if let hit = corners.first(where: { abs($0.1.x - p.x) <= g && abs($0.1.y - p.y) <= g }) { return hit.0 }
        guard let kind, resizesFromEdges(kind) else { return nil }
        let alongY = p.y >= r.y - g && p.y <= r.y + r.height + g, alongX = p.x >= r.x - g && p.x <= r.x + r.width + g
        if abs(p.x - (r.x + r.width)) <= g, alongY { return .right }
        if abs(p.x - r.x) <= g, alongY { return .left }
        if abs(p.y - (r.y + r.height)) <= g, alongX { return .bottom }
        if abs(p.y - r.y) <= g, alongX { return .top }
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

    /// `r` with `corner` dragged to `p`; `keepRatio` holds `r`'s proportions (pictures, or ⇧ with shapes). An edge
    /// moves that side only (about the other axis's middle when keeping the ratio).
    public static func resized(_ r: Rect, corner: Corner, to p: Point, keepRatio: Bool = false) -> Rect {
        let left = r.x, top = r.y, right = r.x + r.width, bottom = r.y + r.height
        switch corner {
        case .top, .bottom:
            let h = max(minimumSide, corner == .top ? bottom - p.y : p.y - top)
            var w = r.width, x = left
            if keepRatio, r.height > 0 { w = max(minimumSide, h * r.width / r.height); x = left + (r.width - w) / 2 }
            return Rect(x: x, y: corner == .top ? bottom - h : top, width: w, height: h)
        case .left, .right:
            let w = max(minimumSide, corner == .left ? right - p.x : p.x - left)
            var h = r.height, y = top
            if keepRatio, r.width > 0 { h = max(minimumSide, w * r.height / r.width); y = top + (r.height - h) / 2 }
            return Rect(x: corner == .left ? right - w : left, y: y, width: w, height: h)
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

    /// A text box `r` with `corner` dragged to `p`: its new left edge and width, the opposite side fixed; nil for its
    /// top or bottom edge, which move nothing (its height is its text's). Never narrower than one short word.
    public static func resizedText(_ r: Rect, corner: Corner, to p: Point) -> (x: Double, width: Double)? {
        let left = r.x, right = r.x + r.width, narrowest = textPadding + 40
        switch corner {
        case .right, .topRight, .bottomRight: return (left, max(narrowest, p.x - left))
        case .left, .topLeft, .bottomLeft:
            let w = max(narrowest, right - p.x)
            return (right - w, w)
        case .top, .bottom: return nil
        }
    }

    /// The width `item` (a text box) lays its text out at: its own once a drag set it (`fixedWidth`), else as wide as
    /// `longestLine` up to Easel's widest text (#580).
    public static func textBoxWidth(_ item: Item, longestLine: Double) -> Double {
        item.fixedWidth == true ? item.frame.width : textWidth(longestLine: longestLine)
    }
}
