import CoreGraphics
import Foundation

/// Arc's Library button glyph (Arc 1.173, `HomeBadging.HomeButton`): a box with a star, a dot and a
/// triangle above it, cut off just over the box. Hovering the button lifts and turns the star, moves the
/// dot up and turns the triangle; leaving runs it all back (GitHub #608).
///
/// Measured from 120 fps captures of Arc's button at 2x. Every part rides one critically damped spring
/// (ω 14.5/s: 42 % of the way at 0.1 s, 93 % at 0.3 s), whichever way it goes. At 0.14 s the dot and the
/// triangle are swapped for new ones: the old triangle has shrunk to half and faded by then, and the new
/// one comes in at 1.4x and settles on the same spring; the dot is gone until 0.3 s and comes back where
/// it is headed. What Arc showed at rest as a cloud is the star, sunk into the box.
///
/// Points are from the button's centre, y down, angles in degrees clockwise.
public enum LibraryGlyph {
    public struct Pose: Equatable, Sendable {
        /// The star's centre and turn (0 = a point straight up).
        public var star: CGPoint
        public var starAngle: Double
        public var dot: CGPoint
        /// The triangle's centre and the direction of one corner (0 = pointing right).
        public var triangle: CGPoint
        public var triangleAngle: Double

        public init(star: CGPoint, starAngle: Double, dot: CGPoint, triangle: CGPoint, triangleAngle: Double) {
            self.star = star
            self.starAngle = starAngle
            self.dot = dot
            self.triangle = triangle
            self.triangleAngle = triangleAngle
        }

        var components: [Double] {
            [star.x, star.y, starAngle, dot.x, dot.y, triangle.x, triangle.y, triangleAngle]
        }

        init(_ c: [Double]) {
            self.init(star: CGPoint(x: c[0], y: c[1]), starAngle: c[2], dot: CGPoint(x: c[3], y: c[4]),
                      triangle: CGPoint(x: c[5], y: c[6]), triangleAngle: c[7])
        }
    }

    /// Not hovered: the star sunk into the box with only its top above it, the triangle pointing right.
    public static let rest = Pose(star: CGPoint(x: -2.5, y: -2.78), starAngle: -8, dot: CGPoint(x: 2, y: -7.5),
                                  triangle: CGPoint(x: 4.7, y: -3.75), triangleAngle: 12)
    /// Hovered: the star up out of the box and turned a third of a turn and more (it reads upside down),
    /// the dot higher, the triangle a little up and to the right after turning back 133°.
    public static let hovered = Pose(star: CGPoint(x: -2.9, y: -4.65), starAngle: 104, dot: CGPoint(x: 3, y: -10),
                                     triangle: CGPoint(x: 6.17, y: -5.03), triangleAngle: -121)

    /// The box: square-ish top corners, round bottom ones, and a slot near the top that shows through.
    public static let box = CGRect(x: -6, y: -1, width: 12, height: 9)
    public static let boxTopRadius: CGFloat = 0.5
    public static let boxBottomRadius: CGFloat = 2.5
    public static let slot = CGRect(x: -1.75, y: 0, width: 3.5, height: 2)
    /// The star, dot and triangle are cut off below this line, 1.5 pt over the box.
    public static let clipBottom: CGFloat = -2.5

    public static let starOuterRadius: CGFloat = 4.75
    public static let starInnerRadius: CGFloat = 2.7
    /// The star's corners are rounded by a stroke this wide with round joins.
    public static let starRounding: CGFloat = 0.25
    public static let dotRadius: CGFloat = 0.95
    public static let triangleSide: CGFloat = 3.9

    /// The spring every part rides: critically damped, this stiff (rad/s).
    public static let omega = 14.5
    /// When the old dot and triangle are swapped for new ones.
    public static let swapTime = 0.14
    /// When the new dot shows, where it is headed.
    public static let dotReturnTime = 0.30
    /// How small and faint the old triangle has got by the swap.
    public static let oldTriangleScale = 0.5
    public static let oldTriangleOpacity = 0.4
    /// How big the new triangle comes in.
    public static let newTriangleScale = 1.4
    /// After this long, a change has come to rest (the spring is within 1e-5 of where it is headed).
    public static let settleTime = 1.0

    /// What to draw at one moment.
    public struct Frame: Equatable, Sendable {
        public var pose: Pose
        public var dotVisible: Bool
        public var triangleScale: Double
        public var triangleOpacity: Double

        public init(pose: Pose, dotVisible: Bool = true, triangleScale: Double = 1, triangleOpacity: Double = 1) {
            self.pose = pose
            self.dotVisible = dotVisible
            self.triangleScale = triangleScale
            self.triangleOpacity = triangleOpacity
        }
    }

    /// The glyph's motion: where it is headed, and the change under way, as a function of time. The app
    /// asks for a frame on each display refresh; a test asks for any moment it likes.
    public struct Motion: Sendable {
        public private(set) var target: Pose
        private var start: Double = -.infinity
        private var from: [Double]
        private var velocity: [Double]
        private var fromTriangleScale = 1.0
        private var fromTriangleOpacity = 1.0

        public init(at pose: Pose = LibraryGlyph.rest) {
            target = pose
            from = pose.components
            velocity = Array(repeating: 0, count: pose.components.count)
        }

        /// Heads for `pose` from wherever the glyph is at `time`, keeping its speed: leaving the button
        /// halfway through the lift turns it back without a jump.
        public mutating func head(to pose: Pose, at time: Double) {
            guard pose != target else { return }
            let now = frame(at: time)
            let (_, v) = spring(at: time)
            from = now.pose.components
            velocity = v
            fromTriangleScale = now.triangleScale
            fromTriangleOpacity = now.triangleOpacity
            target = pose
            start = time
        }

        public func isSettled(at time: Double) -> Bool { time - start >= LibraryGlyph.settleTime }

        public func frame(at time: Double) -> Frame {
            let e = time - start
            guard e < LibraryGlyph.settleTime else {
                return Frame(pose: target, dotVisible: true, triangleScale: 1, triangleOpacity: 1)
            }
            var pose = Pose(spring(at: time).0)
            let dotVisible = e < LibraryGlyph.swapTime || e >= LibraryGlyph.dotReturnTime
            if e >= LibraryGlyph.dotReturnTime { pose.dot = target.dot }
            let scale: Double, opacity: Double
            if e < LibraryGlyph.swapTime {
                let f = max(0, e) / LibraryGlyph.swapTime
                scale = fromTriangleScale + (LibraryGlyph.oldTriangleScale - fromTriangleScale) * f
                opacity = fromTriangleOpacity + (LibraryGlyph.oldTriangleOpacity - fromTriangleOpacity) * f * f
            } else {
                scale = 1 + (LibraryGlyph.newTriangleScale - 1) * LibraryGlyph.decay(e - LibraryGlyph.swapTime)
                opacity = 1
            }
            return Frame(pose: pose, dotVisible: dotVisible, triangleScale: scale, triangleOpacity: opacity)
        }

        /// Each part's value and speed at `time`.
        private func spring(at time: Double) -> ([Double], [Double]) {
            let e = max(0, time - start)
            let w = LibraryGlyph.omega
            let k = exp(-w * e)
            let to = target.components
            var x = to, v = velocity.map { _ in 0.0 }
            guard e.isFinite, e < LibraryGlyph.settleTime else { return (to, v) }
            for i in to.indices {
                let d0 = from[i] - to[i], v0 = velocity[i]
                x[i] = to[i] + (d0 + (v0 + w * d0) * e) * k
                v[i] = (v0 - w * (v0 + w * d0) * e) * k
            }
            return (x, v)
        }
    }

    /// How far along a change is from its start (0) to where it is headed (1), with no starting speed.
    public static func progress(_ elapsed: Double) -> Double { 1 - decay(elapsed) }

    static func decay(_ t: Double) -> Double {
        let u = omega * max(0, t)
        return (1 + u) * exp(-u)
    }

    // MARK: Shapes

    public static func boxPath() -> CGPath {
        let p = CGMutablePath()
        let r = box, t = boxTopRadius, b = boxBottomRadius
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: t)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: t)
        p.closeSubpath()
        p.addRoundedRect(in: slot, cornerWidth: slot.height / 2, cornerHeight: slot.height / 2)
        return p
    }

    public static func starPath(center: CGPoint, angle: Double) -> CGPath {
        let p = CGMutablePath()
        for k in 0..<10 {
            let a = angle * .pi / 180 + Double(k) * .pi / 5
            let r = k.isMultiple(of: 2) ? starOuterRadius : starInnerRadius
            let pt = CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a))
            k == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    public static func trianglePath(center: CGPoint, angle: Double, scale: Double) -> CGPath {
        let p = CGMutablePath()
        let r = triangleSide / sqrt(3) * scale
        for k in 0..<3 {
            let a = angle * .pi / 180 + Double(k) * 2 * .pi / 3
            let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            k == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}
