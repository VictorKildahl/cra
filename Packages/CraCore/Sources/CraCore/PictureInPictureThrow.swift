import CoreGraphics
import Foundation

/// A two-finger swipe on the Picture in Picture window (Arc: the window follows the fingers and
/// is thrown into a corner of the screen when they lift). Arc keeps the window either at a frame
/// the user dragged it to (`absolute`) or in one of the screen's four corners (`screen`), which is
/// where a swipe leaves it. Points, frames and velocities are AppKit screen coordinates: origin at
/// the bottom left, y going up.
public struct PictureInPictureThrow: Sendable {
    public enum Corner: String, Sendable, Equatable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// How far back the fingers' last moves count toward the throw's speed.
    public static let sampleWindow: Double = 0.08
    /// How far a throw carries per point/s of speed: UIKit's normal deceleration (0.998 a
    /// millisecond) comes to rest after v · 0.998 / (1 − 0.998) / 1000 = v · 0.499 s.
    public static let projection: CGFloat = 0.998 / (1 - 0.998) / 1000

    /// Where the fingers have the window: after the latest move, ahead of what is on screen.
    public private(set) var frame: CGRect
    /// False while the fingers only rest on the window: lifting them then throws nothing.
    public private(set) var hasMoved = false
    private let start: Double
    private var samples: [(time: Double, dx: CGFloat, dy: CGFloat)] = []
    /// The window's origin after each move, for `origin(at:)`.
    private var path: [(time: Double, origin: CGPoint)]
    /// The time between the last few moves (a trackpad sends about 120 a second, unevenly).
    private var gaps: [Double] = []

    /// The fingers touched down on a window at `frame` at `time` (seconds, any clock).
    public init(frame: CGRect, at time: Double) {
        self.frame = frame
        start = time
        path = [(time, frame.origin)]
    }

    /// The fingers moved the window by `dx, dy` at `time`; returns where it is now.
    public mutating func move(dx: CGFloat, dy: CGFloat, at time: Double) -> CGRect {
        frame = frame.offsetBy(dx: dx, dy: dy)
        if dx != 0 || dy != 0 { hasMoved = true }
        samples.append((time, dx, dy))
        samples.removeAll { $0.time < time - 2 * Self.sampleWindow }

        let last = path[path.count - 1]
        let gap = time - last.time
        if gap > 0.05 {
            // The fingers rested before this move: they were still where they were until just
            // before it, rather than creeping there since the last one.
            path.append((time - (gaps.last ?? 1.0 / 120), last.origin))
        } else if gap > 0 {
            gaps.append(gap)
            if gaps.count > 8 { gaps.removeFirst() }
        }
        path.append((max(time, last.time), frame.origin))
        if path.count > 64 { path.removeFirst(path.count - 64) }
        return frame
    }

    /// How far the window on screen runs behind the fingers: the longest of the last few gaps
    /// between moves, so a frame almost always falls between two moves that have both come in.
    public var lag: Double { min(max((gaps.max() ?? 1.0 / 120) + 0.001, 1.0 / 240), 1.0 / 30) }

    /// Where to show the window for a display frame at `time` (the same clock as the moves):
    /// where the fingers had it `lag` earlier, interpolated between the two moves around then.
    /// Moving the window on each move instead puts it wherever the last move left it when the
    /// screen refreshes, so a frame that caught two moves jumps twice as far as one that caught
    /// one, and the window shudders even though the fingers glide. Past the latest move the
    /// window waits for the next one rather than guessing ahead and stepping back.
    public func origin(at time: Double) -> CGPoint {
        let t = time - lag
        guard let after = path.firstIndex(where: { $0.time > t }) else { return path[path.count - 1].origin }
        guard after > 0 else { return path[0].origin }
        let a = path[after - 1], b = path[after]
        let f = CGFloat((t - a.time) / (b.time - a.time))
        return CGPoint(x: a.origin.x + (b.origin.x - a.origin.x) * f, y: a.origin.y + (b.origin.y - a.origin.y) * f)
    }

    /// The window's speed when the fingers lift at `time`: how far it went in the moves of the
    /// last `sampleWindow`, over the time since the move before them. Fingers that rested before
    /// lifting throw nothing.
    public func velocity(at time: Double) -> CGVector {
        guard let first = samples.firstIndex(where: { $0.time >= time - Self.sampleWindow }) else { return .zero }
        let recent = samples[first...]
        let since = first > 0 ? samples[first - 1].time : start
        let span = max(1.0 / 240, time - since)
        return CGVector(dx: recent.reduce(0) { $0 + $1.dx } / span, dy: recent.reduce(0) { $0 + $1.dy } / span)
    }

    /// Where the window's centre would come to rest if it slid on with `velocity`.
    public static func restingCentre(of frame: CGRect, velocity: CGVector) -> CGPoint {
        CGPoint(x: frame.midX + velocity.dx * projection, y: frame.midY + velocity.dy * projection)
    }

    /// The corner of `visible` (a screen's visible frame) nearest to where the window would
    /// come to rest.
    public static func corner(for frame: CGRect, velocity: CGVector, in visible: CGRect) -> Corner {
        let c = restingCentre(of: frame, velocity: velocity)
        switch (c.x < visible.midX, c.y < visible.midY) {
        case (true, false): return .topLeft
        case (false, false): return .topRight
        case (true, true): return .bottomLeft
        case (false, true): return .bottomRight
        }
    }

    /// A window of `size` in `corner` of `visible`, `margin` in from both edges (Arc: 10 pt,
    /// the same as its first placement in the top right).
    public static func frame(in corner: Corner, size: CGSize, visible: CGRect, margin: CGFloat) -> CGRect {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let x = left ? visible.minX + margin : visible.maxX - margin - size.width
        let y = top ? visible.maxY - margin - size.height : visible.minY + margin
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}

/// The window's flight into its corner: a critically damped spring on its origin that starts
/// at the fingers' speed, so the throw carries on without a jolt and lands without bouncing off
/// the screen's edge.
public struct PictureInPictureFlight: Sendable {
    /// Seconds the spring takes to swing once if undamped (SwiftUI's `response`).
    public static let response: Double = 0.4
    public static let dampingRatio: Double = 1

    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector
    public let target: CGPoint

    public init(from position: CGPoint, velocity: CGVector, to target: CGPoint) {
        self.position = position
        self.velocity = velocity
        self.target = target
    }

    /// Within half a point of the corner and slower than 10 pt/s.
    public var isSettled: Bool {
        abs(position.x - target.x) < 0.5 && abs(position.y - target.y) < 0.5 && hypot(velocity.dx, velocity.dy) < 10
    }

    /// Advances by `dt` seconds (sub-stepped, so a dropped frame doesn't overshoot) and returns
    /// the new origin, the target itself once settled.
    public mutating func step(_ dt: Double) -> CGPoint {
        let stiffness = pow(2 * .pi / Self.response, 2)
        let damping = 4 * .pi * Self.dampingRatio / Self.response
        var left = max(0, min(dt, 0.1))
        while left > 0 {
            let h = min(left, 1.0 / 240)
            left -= h
            let ax = -stiffness * (position.x - target.x) - damping * velocity.dx
            let ay = -stiffness * (position.y - target.y) - damping * velocity.dy
            velocity.dx += ax * h
            velocity.dy += ay * h
            position.x += velocity.dx * h
            position.y += velocity.dy * h
        }
        if isSettled {
            position = target
            velocity = .zero
        }
        return position
    }
}
