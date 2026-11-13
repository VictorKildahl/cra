import CoreGraphics

/// What a press on the Picture in Picture window does (issue #134): a drag from its middle moves
/// the window, a drag from an edge or corner resizes it with the video's aspect ratio, and a
/// press that travels less than `threshold` is a click and moves nothing. Points and frames are
/// AppKit screen coordinates: origin at the bottom left, y going up.
public struct PictureInPictureGesture: Sendable {
    public enum Edge: Sendable, Equatable, CaseIterable {
        case none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

        var isLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
        var isRight: Bool { self == .right || self == .topRight || self == .bottomRight }
        var isTop: Bool { self == .top || self == .topLeft || self == .topRight }
        var isBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    }

    /// How far in from the window's edge a press resizes.
    public static let grip: CGFloat = 8
    /// How far along an edge from a corner a press takes the corner (Chromium's PiP: 16).
    public static let corner: CGFloat = 16
    /// How far the pointer travels before a press becomes a drag, the way a click on a normal
    /// window never nudges it.
    public static let threshold: CGFloat = 3

    public let edge: Edge
    public let startMouse: CGPoint
    public let startFrame: CGRect
    /// Set once the pointer has gone past `threshold`; the press is a drag from then on.
    public private(set) var isDragging = false

    /// A press at `mouse` (screen) on a window at `frame`.
    public init(mouse: CGPoint, frame: CGRect) {
        startMouse = mouse
        startFrame = frame
        edge = Self.edge(at: CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY), in: frame.size)
    }

    /// The edge or corner a point in the window (origin at its bottom left) is on.
    public static func edge(at p: CGPoint, in size: CGSize) -> Edge {
        let onLeft = p.x < grip, onRight = p.x > size.width - grip
        let onBottom = p.y < grip, onTop = p.y > size.height - grip
        guard onLeft || onRight || onTop || onBottom else { return .none }
        let nearLeft = p.x < corner, nearRight = p.x > size.width - corner
        let nearBottom = p.y < corner, nearTop = p.y > size.height - corner
        let left = onLeft || ((onTop || onBottom) && nearLeft)
        let right = onRight || ((onTop || onBottom) && nearRight)
        let top = onTop || ((onLeft || onRight) && nearTop)
        let bottom = onBottom || ((onLeft || onRight) && nearBottom)
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        default: return .bottom
        }
    }

    /// Whether letting this press go returns to the video's tab: the second click of a double
    /// click that stayed a click, as on Arc's window. The buttons take their own clicks and never
    /// get here.
    public func returnsToTab(clickCount: Int) -> Bool { !isDragging && clickCount == 2 }

    /// The largest size a resize can reach with the window's anchored sides where they are and the
    /// grabbed ones still inside `visible`: the window grows up to the display's edges, not past
    /// them. A side already past an edge (a window under the menu bar) keeps the size it has.
    public func room(in visible: CGRect) -> CGSize {
        let s = startFrame
        let w = edge.isLeft ? s.maxX - visible.minX : edge.isRight ? visible.maxX - s.minX : .greatestFiniteMagnitude
        let h = edge.isTop ? visible.maxY - s.minY : edge.isBottom ? s.maxY - visible.minY : .greatestFiniteMagnitude
        return CGSize(width: max(w, s.width), height: max(h, s.height))
    }

    /// The window's frame with the pointer at `mouse`, or nil while the press is still a click.
    /// A resize keeps the edge or corner opposite the grabbed one where it was (both sides keep
    /// the top, the top and bottom keep the left) and stays between `minSize` and `maxSize`.
    public mutating func frame(mouse: CGPoint, minSize: CGSize, maxSize: CGSize) -> CGRect? {
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        if !isDragging {
            guard hypot(dx, dy) >= Self.threshold else { return nil }
            isDragging = true
        }
        let s = startFrame
        if edge == .none { return s.offsetBy(dx: dx, dy: dy) }

        let aspect = s.width / max(s.height, 1)
        let byX = s.width + (edge.isRight ? dx : edge.isLeft ? -dx : 0)
        let byY = (s.height + (edge.isTop ? dy : edge.isBottom ? -dy : 0)) * aspect
        var w: CGFloat
        switch edge {
        case .left, .right: w = byX
        case .top, .bottom: w = byY
        default: w = max(byX, byY)   // a corner follows whichever way the pointer went further
        }
        let lo = max(minSize.width, minSize.height * aspect)
        let hi = min(maxSize.width, maxSize.height * aspect)
        w = max(lo, min(w, max(lo, hi))).rounded()
        let h = (w / aspect).rounded()
        let x = edge.isLeft ? s.maxX - w : s.minX
        let y = edge.isTop ? s.minY : s.maxY - h
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
