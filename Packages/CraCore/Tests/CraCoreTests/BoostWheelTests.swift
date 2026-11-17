import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc 1.172.2's Boost colour wheel, against what Victor's Arc drew on 17 Nov 2026 (#478).
struct BoostWheelTests {
    private func near(_ p: CGPoint, _ x: Double, _ y: Double, within d: Double = 1.5) -> Bool {
        abs(p.x - x) <= d && abs(p.y - y) <= d
    }

    /// HSB as 0–255 RGB, to compare with colours read off Arc's screen.
    private func rgb(_ c: BoostWheel.HSB) -> (Double, Double, Double) {
        let h = c.hue * 6, s = c.saturation, v = c.brightness
        let i = floor(h), f = h - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch Int(i) % 6 {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return (r * 255, g * 255, b * 255)
    }

    private func close(_ c: BoostWheel.HSB, _ r: Double, _ g: Double, _ b: Double, within d: Double = 30) -> Bool {
        let (x, y, z) = rgb(c)
        return abs(x - r) <= d && abs(y - g) <= d && abs(z - b) <= d
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func untintedHandlesRestAtThreeOClock() {
        let h = BoostWheel.handles(hue: 0, strength: 0)
        #expect(near(h.big, 40, 0) && near(h.small, 28.3, 28.3))
        #expect(close(BoostWheel.tint(hue: 0, strength: 0), 130, 130, 130, within: 3))
        #expect(close(BoostWheel.accent(hue: 0, strength: 0), 68, 68, 68, within: 3))
    }

    /// Arc's hues go clockwise from 3 o'clock, with the small handle an eighth of a turn behind at
    /// the same distance.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func dragsPickHueClockwiseAndStrengthByDistance() {
        let up = BoostWheel.pick(CGPoint(x: 0, y: -40))
        #expect(abs(up.hue - 0.75) < 0.001 && abs(up.strength - 40.0 / 56) < 0.001)
        let left = BoostWheel.pick(CGPoint(x: -38.5, y: 0))
        #expect(abs(left.hue - 0.5) < 0.001)
        let far = BoostWheel.pick(CGPoint(x: 58.5, y: 59))
        #expect(abs(far.strength - 1) < 0.001, "the handle stops 56 pt out")
        let h = BoostWheel.handles(hue: far.hue, strength: far.strength)
        #expect(near(h.big, 39.5, 39.5) && near(h.small, 0, 57))
        let top = BoostWheel.handles(hue: up.hue, strength: up.strength)
        #expect(near(top.big, 0, -40) && near(top.small, 28.5, -28.5))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func colorsMatchArcs() {
        #expect(close(BoostWheel.tint(hue: 0.125, strength: 1), 193, 163, 81))
        #expect(close(BoostWheel.accent(hue: 0.125, strength: 1), 71, 88, 46))
        #expect(close(BoostWheel.tint(hue: 0.75, strength: 40.0 / 56), 152, 107, 209))
        #expect(close(BoostWheel.accent(hue: 0.75, strength: 40.0 / 56), 72, 50, 67))
        #expect(close(BoostWheel.tint(hue: 0.5, strength: 38.5 / 56), 140, 213, 216))
        #expect(close(BoostWheel.accent(hue: 0.5, strength: 38.5 / 56), 49, 54, 71))
        #expect(close(BoostWheel.tint(hue: 0.36, strength: 0.18), 236, 248, 236))
        #expect(close(BoostWheel.ring(0.724), 141, 90, 239))
        #expect(close(BoostWheel.ring(0.5), 168, 244, 243))
        #expect(close(BoostWheel.ring(0.03), 226, 104, 81))
        #expect(close(BoostWheel.ring(0.2), 216, 239, 129))
    }
}
