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

    /// Arc's ring as sRGB stops (location, red, green, blue). SwiftUI shifts these when it draws
    /// them, so the values are pre-compensated to land on Arc's colours; the last stop closes it.
    public static let ringGradient: [(Double, Double, Double, Double)] = [
        (0.000, 0.920, 0.296, 0.223), (0.042, 0.916, 0.389, 0.211), (0.083, 0.920, 0.464, 0.219),
        (0.125, 0.937, 0.558, 0.251), (0.167, 0.954, 0.743, 0.306), (0.208, 0.967, 0.929, 0.357),
        (0.250, 0.820, 0.989, 0.365), (0.292, 0.641, 0.988, 0.381), (0.333, 0.586, 0.984, 0.455),
        (0.375, 0.524, 0.984, 0.536), (0.417, 0.527, 0.984, 0.680), (0.458, 0.524, 0.980, 0.807),
        (0.500, 0.516, 0.976, 0.940), (0.542, 0.369, 0.714, 0.959), (0.583, 0.227, 0.449, 0.966),
        (0.625, 0.083, 0.192, 0.950), (0.667, 0.205, 0.179, 0.954), (0.708, 0.356, 0.204, 0.958),
        (0.750, 0.504, 0.217, 0.962), (0.792, 0.743, 0.214, 0.878), (0.833, 0.857, 0.205, 0.748),
        (0.875, 0.849, 0.201, 0.564), (0.917, 0.869, 0.225, 0.435), (0.958, 0.892, 0.237, 0.307),
        (1, 0.920, 0.296, 0.223),
    ]

    private static func point(turns: Double, radius: Double) -> CGPoint {
        let a = turns * 2 * .pi
        return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
    }

    private static func wrap(_ h: Double) -> Double { h - floor(h) }
}
