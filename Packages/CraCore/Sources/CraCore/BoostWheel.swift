import CoreGraphics
import Foundation

/// Arc 1.172.2's Boost colour wheel (BoostsEditor.ColorPicker: HueRingBackdrop, DraggablePuck,
/// ComplementaryColorControl), measured in Victor's Arc by dragging the handle on 17 Nov 2026 (#478).
///
/// - The big handle goes where it is dragged, up to 56 pt from the middle of the 133 pt dotted square.
///   Its direction is the hue, clockwise from 3 o'clock (red, yellow at 6, cyan at 9, purple at 12),
///   and its distance the strength: pale near the middle, full 56 pt out.
/// - The small handle trails it by an eighth of a turn, clockwise, at the same distance, in a dark
///   shade of that hue. A faint circle through both shows the orbit, and a line joins them.
/// - Untinted, both handles are grey and rest 40 pt out at 3 o'clock (the small one at half past
///   4) inside a brushed grey frame; once tinted, the frame is a ring of every hue in the same order.
///
/// Offsets are from the square's middle in points, y down.
public enum BoostWheel {
    public static let maxRadius: Double = 56
    public static let restRadius: Double = 40
    /// How far the small handle trails, in turns.
    public static let accentOffset: Double = 0.125

    public struct Handles: Equatable, Sendable {
        public var big: CGPoint
        public var small: CGPoint
    }

    /// Hue, saturation and brightness, 0–1.
    public struct HSB: Equatable, Sendable {
        public var hue: Double, saturation: Double, brightness: Double
        public init(_ hue: Double, _ saturation: Double, _ brightness: Double) {
            self.hue = hue; self.saturation = saturation; self.brightness = brightness
        }
    }

    public static func handles(hue: Double, strength: Double) -> Handles {
        let tinted = strength > 0
        let r = tinted ? min(1, strength) * maxRadius : restRadius
        let a = tinted ? hue : 0
        return Handles(big: point(turns: a, radius: r), small: point(turns: a + accentOffset, radius: r))
    }

    /// What a drag to `offset` picks.
    public static func pick(_ offset: CGPoint) -> (hue: Double, strength: Double) {
        let r = hypot(offset.x, offset.y)
        var turns = atan2(offset.y, offset.x) / (2 * .pi)
        if turns < 0 { turns += 1 }
        return (r == 0 ? 0 : turns, min(1, r / maxRadius))
    }

    /// The big handle's colour (Arc: 193/163/81 at full strength toward 6 minutes past, 236/248/236
    /// a few points out). Grey 130 untinted.
    public static func tint(hue: Double, strength: Double) -> HSB {
        guard strength > 0 else { return HSB(0, 0, 0.51) }
        let t = min(1, strength)
        return HSB(wrap(hue), 0.6 * pow(t, 1.3), 1 - 0.24 * t)
    }

    /// The small handle's colour: the hue an eighth of a turn on, dark (Arc: 71/88/46 against the
    /// tint above). Grey 68 untinted.
    public static func accent(hue: Double, strength: Double) -> HSB {
        guard strength > 0 else { return HSB(0, 0, 0.27) }
        let t = min(1, strength)
        return HSB(wrap(hue + accentOffset), 0.48 * pow(t, 1.2), 0.27 + 0.08 * pow(t, 4))
    }

    /// The tinted frame's colour at a hue. Arc's ring isn't one saturation all round: read off it
    /// every 15°, red is 226/104/81, cyan 168/244/243, purple 141/90/239.
    public static func ring(_ hue: Double) -> HSB {
        let h = wrap(hue)
        guard let i = ringStops.lastIndex(where: { $0.hue <= h }), i + 1 < ringStops.count else { return ringStops[0] }
        let a = ringStops[i], b = ringStops[i + 1], f = (h - a.hue) / (b.hue - a.hue)
        return HSB(h, a.saturation + (b.saturation - a.saturation) * f, a.brightness + (b.brightness - a.brightness) * f)
    }

    /// Arc's ring, measured: saturation and brightness by hue (the last stop closes the circle).
    public static let ringStops: [HSB] = [
        HSB(0, 0.64, 0.89), HSB(0.2, 0.47, 0.96), HSB(0.45, 0.31, 0.97), HSB(0.6, 0.48, 0.95),
        HSB(0.7, 0.65, 0.94), HSB(0.76, 0.62, 0.94), HSB(0.86, 0.58, 0.87), HSB(0.97, 0.56, 0.86), HSB(1, 0.64, 0.89),
    ]

    private static func point(turns: Double, radius: Double) -> CGPoint {
        let a = turns * 2 * .pi
        return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
    }

    private static func wrap(_ h: Double) -> Double { h - floor(h) }
}
