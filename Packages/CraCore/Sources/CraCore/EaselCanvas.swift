import Foundation

/// An Easel's canvas has no edge (#580, Victor 20 Nov 2026). Arc's is a fixed width that grows down
/// with its items; Cra's goes on in every direction, with zoom, so a board of ideas never runs out of room.
extension Easel {
    /// How far from the home sheet an item still stretches the canvas: a million points, hundreds of
    /// screens in every direction.
    public static let canvasReach: Double = 1_000_000

    /// How far the canvas zooms out and in (View ▸ Zoom Out/In, a pinch).
    public static let zoomRange: ClosedRange<Double> = 0.1...4

    /// The magnification for View's zoom level, a page's steps (⌘+ and ⌘− add and take 0.5, each 1.2×),
    /// held to `zoomRange`. Level 0 is actual size.
    public static func magnification(zoomLevel level: Double) -> Double {
        min(max(pow(1.2, level), zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The zoom level a magnification stands for: the inverse of `magnification(zoomLevel:)`.
    public static func zoomLevel(magnification m: Double) -> Double { log(max(m, 0.0001)) / log(1.2) }

    /// The home sheet: where a new easel starts and where Cra's easels before #580 kept everything,
    /// the window's width and Arc's 2436 pt.
    public static func home(width: Double) -> Rect { Rect(x: 0, y: 0, width: width, height: canvasHeight) }

    /// The part of the endless canvas that exists right now: the home sheet, every item and what is in
    /// view, with a whole view's room past them on every side, so scrolling or dragging toward any edge
    /// always finds more. While a scroll or drag goes on the canvas only grows (`keeping` the extent
    /// so far), so what is under the pointer never jumps; when it ends, it shrinks back round what is
    /// there. Whole points, so the view never lands between pixels.
    public static func extent(home: Rect, items: [Rect], visible: Rect, keeping current: Rect? = nil) -> Rect {
        var box = union(home, visible)
        // An item from a damaged file or another app's pasteboard can name any number: past the
        // canvas's reach (or not a number) it doesn't stretch the canvas.
        let reachable = items.filter { f in
            [f.x, f.y, f.width, f.height].allSatisfy(\.isFinite)
                && abs(f.x) + f.width <= canvasReach && abs(f.y) + f.height <= canvasReach
        }
        if let content = bounds(of: reachable) { box = union(box, content) }
        let room = Rect(x: box.x - visible.width, y: box.y - visible.height,
                        width: box.width + 2 * visible.width, height: box.height + 2 * visible.height)
        var out = room
        if let current { out = union(out, current) }
        let minX = out.x.rounded(.down), minY = out.y.rounded(.down)
        return Rect(x: minX, y: minY, width: (out.x + out.width).rounded(.up) - minX, height: (out.y + out.height).rounded(.up) - minY)
    }

    static func union(_ a: Rect, _ b: Rect) -> Rect {
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        return Rect(x: minX, y: minY, width: max(a.x + a.width, b.x + b.width) - minX, height: max(a.y + a.height, b.y + b.height) - minY)
    }
}
