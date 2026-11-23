import CoreGraphics
import Foundation

/// The empty home screen: a field of small dots that a finger stirs, from a reference
/// recording of 23 November 2026 (a 430 pt phone in dark mode). Where a finger presses, the
/// dots under it swell and brighten; when it lifts, the swell travels outward as a ring and
/// fades. Measured on that recording: a dot every 20 pt, centred, 2 pt across at rest and
/// 6.5 pt at the top of a ring.
///
/// Past the recording: the swell starts on touch-down, not on lift, and grows the longer the
/// finger stays (a longer press sends a stronger ring); a second, weaker ring follows the first
/// as in water, and the crest pushes the dots it passes a little outward; a finger dragged
/// across leaves a wake of small rings; rings that cross add up without going past full; and
/// with Reduce Motion a lift fades where it is instead of travelling (`travels`).
public struct MobileRipples: Sendable {
    // MARK: The grid

    /// From one dot's centre to the next, across and down.
    public static let spacing: CGFloat = 20
    public static let restDiameter: CGFloat = 2
    public static let peakDiameter: CGFloat = 6.5

    /// The dots' centres in a view of `size`, row by row: a dot every `spacing`, at least half
    /// a spacing in from each edge, the grid centred so opposite margins match. 430 pt across
    /// (the recording) gives 21 columns starting 15 pt in.
    public static func grid(in size: CGSize) -> [CGPoint] {
        func line(_ length: CGFloat) -> (count: Int, first: CGFloat) {
            guard length >= spacing else { return (0, 0) }
            let count = Int(((length - spacing) / spacing).rounded(.down)) + 1
            return (count, (length - CGFloat(count - 1) * spacing) / 2)
        }
        let columns = line(size.width), rows = line(size.height)
        var points: [CGPoint] = []
        points.reserveCapacity(columns.count * rows.count)
        for row in 0..<rows.count {
            for column in 0..<columns.count {
                points.append(CGPoint(x: columns.first + CGFloat(column) * spacing, y: rows.first + CGFloat(row) * spacing))
            }
        }
        return points
    }

    /// How much of the way from rest to the top a dot shows at `level` (0 at rest, 1 at the
    /// top of a ring): eased out, so the shoulders of a ring read as part of it, as in the
    /// recording's wide bands, while the falloff stays soft.
    public static func emphasis(level: Double) -> Double {
        let rest = 1 - min(1, max(0, level))
        return 1 - rest * rest
    }

    /// A dot's diameter at `level`.
    public static func diameter(level: Double) -> CGFloat {
        restDiameter + (peakDiameter - restDiameter) * CGFloat(emphasis(level: level))
    }

    // MARK: The wave

    /// How fast a ring travels, in points a second: across a phone in about a second.
    public static let speed: Double = 420
    /// The ring's half-width (the spread of its bell curve, also the swell's under a finger) as
    /// it leaves; it widens as it travels, by `spread` of itself each second.
    public static let width: Double = 34
    public static let spread: Double = 0.3
    /// The second ring: this many widths behind the first (far enough for a dark gap between
    /// them), this strong beside it.
    public static let echoGap: Double = 3.6
    public static let echoStrength: Double = 0.4
    /// A ring loses strength with this time constant, in seconds.
    public static let fade: Double = 1.2
    /// Without travel (Reduce Motion), a lifted swell fades where it is, this fast.
    public static let stillFade: Double = 0.28
    /// How far a full-strength crest pushes a dot outward, in points.
    public static let push: Double = 3
    /// A press reaches most of its swell this quickly, and the rest by `holdRise`; a ring is as
    /// strong as the swell it left.
    public static let pressRise: Double = 0.08
    public static let holdRise: Double = 0.6
    /// A quick tap's swell beside a long press's.
    public static let tapStrength: Double = 0.75
    /// A drag drops a small ring every this many points, this strong beside the press.
    public static let wakeSpacing: Double = 34
    public static let wakeStrength: Double = 0.45
    /// The most rings at once; the oldest give way. Taps a few a second stay well under it.
    public static let maximumRings = 32
    /// A ring weaker than this is gone.
    static let threshold: Double = 0.01

    public struct Ring: Equatable, Sendable {
        public var origin: CGPoint
        public var start: Double
        public var strength: Double
    }

    struct Press: Sendable {
        var location: CGPoint
        var start: Double
        var lastWake: CGPoint
    }

    /// Whether rings travel outward; false with Reduce Motion.
    public var travels: Bool
    public private(set) var rings: [Ring] = []
    private var presses: [Int: Press] = [:]
    /// Every ring started so far, wakes included: what VoiceOver and the UI tests read.
    public private(set) var ringsStarted = 0

    public init(travels: Bool = true) {
        self.travels = travels
    }

    /// Whether nothing is moving: no finger down and every ring faded. The view stops drawing then.
    public var isStill: Bool { presses.isEmpty && rings.isEmpty }

    // MARK: Fingers

    public mutating func press(_ finger: Int, at point: CGPoint, time: Double) {
        presses[finger] = Press(location: point, start: time, lastWake: point)
    }

    /// The swell follows the finger, and every `wakeSpacing` of the way drops a small ring.
    public mutating func move(_ finger: Int, to point: CGPoint, time: Double) {
        guard var press = presses[finger] else { return }
        press.location = point
        if travels, hypot(point.x - press.lastWake.x, point.y - press.lastWake.y) >= Self.wakeSpacing {
            press.lastWake = point
            addRing(Ring(origin: point, start: time, strength: Self.wakeStrength * Self.swell(held: time - press.start)))
        }
        presses[finger] = press
    }

    /// The finger is gone: its swell leaves as a ring, as strong as the swell was. A touch the
    /// system took over (`cancelled`) leaves the same way, so the swell never just vanishes.
    public mutating func lift(_ finger: Int, time: Double) {
        guard let press = presses.removeValue(forKey: finger) else { return }
        addRing(Ring(origin: press.location, start: time, strength: Self.swell(held: time - press.start)))
    }

    /// Every finger gone at once (the view left the screen): no rings for them.
    public mutating func liftAll() {
        presses.removeAll()
    }

    private mutating func addRing(_ ring: Ring) {
        rings.append(ring)
        ringsStarted += 1
        if rings.count > Self.maximumRings { rings.removeFirst(rings.count - Self.maximumRings) }
    }

    /// How swollen a press is after `held` seconds: most of the way at once, the rest with time.
    public static func swell(held: Double) -> Double {
        tapStrength * smoothstep(held / pressRise) + (1 - tapStrength) * smoothstep(held / holdRise)
    }

    // MARK: Reading the field

    /// How stirred the dot at `point` is at `time`: `level` 0 at rest to 1 at the top of a ring,
    /// and `offset`, how far the waves have pushed it from its place.
    public func state(at point: CGPoint, time: Double) -> (level: Double, offset: CGVector) {
        var calm = 1.0
        var dx = 0.0, dy = 0.0
        func add(_ level: Double, pushing amount: Double, from origin: CGPoint, distance: Double) {
            guard level > 0.001 else { return }
            calm *= 1 - min(1, level)
            guard amount > 0, distance > 0.5 else { return }
            dx += Double(point.x - origin.x) / distance * amount
            dy += Double(point.y - origin.y) / distance * amount
        }
        for press in presses.values {
            let distance = Double(hypot(point.x - press.location.x, point.y - press.location.y))
            let level = Self.swell(held: time - press.start) * Self.bell(distance, Self.width)
            // The dots round the finger give way to it; the one under it stays put.
            add(level, pushing: travels ? Self.push * level * min(1, distance / Self.width) : 0, from: press.location, distance: distance)
        }
        for ring in rings {
            let age = max(0, time - ring.start)
            let distance = Double(hypot(point.x - ring.origin.x, point.y - ring.origin.y))
            guard travels else {
                add(ring.strength * exp(-age / Self.stillFade) * Self.bell(distance, Self.width), pushing: 0, from: ring.origin, distance: distance)
                continue
            }
            let strength = ring.strength * exp(-age / Self.fade)
            let width = Self.width * (1 + Self.spread * age)
            let front = Self.speed * age
            let crest = Self.bell(distance - front, width)
            // Behind the finger at first, so it comes up out of the middle.
            let echo = Self.echoStrength * Self.bell(distance - (front - Self.echoGap * width), width)
            add(strength * (crest + echo), pushing: Self.push * strength * crest, from: ring.origin, distance: distance)
        }
        var offset = CGVector(dx: dx, dy: dy)
        let length = hypot(dx, dy), most = Self.push * 1.5
        if length > most { offset = CGVector(dx: dx / length * most, dy: dy / length * most) }
        return (1 - calm, offset)
    }

    /// Drops the rings that have faded out by `time`.
    public mutating func prune(time: Double) {
        rings.removeAll { ring in
            let age = time - ring.start
            return ring.strength * exp(-age / (travels ? Self.fade : Self.stillFade)) * (1 + Self.echoStrength) < Self.threshold
        }
    }

    /// A bell curve: 1 at 0, about 0.6 at one `width` out, nothing past four.
    static func bell(_ x: Double, _ width: Double) -> Double {
        let scaled = x / width
        guard abs(scaled) < 4 else { return 0 }
        return exp(-scaled * scaled / 2)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}
