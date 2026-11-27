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

    /// Both handles can be taken by a press. Moving the small one keeps the big one and the strength
    /// where they are, and sets the dark half's hue by where it landed; a later big drag carries it on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func theSmallHandleMovesOnItsOwn() {
        let h = BoostWheel.handles(hue: 0.25, strength: 0.5)
        #expect(BoostWheel.grabbedHandle(at: h.small, big: h.big, small: h.small) == .small)
        #expect(BoostWheel.grabbedHandle(at: h.big, big: h.big, small: h.small) == .big)
        #expect(BoostWheel.grabbedHandle(at: CGPoint(x: -40, y: -40), big: h.big, small: h.small) == .big)
        let pointer = CGPoint(x: -40, y: 0)
        #expect(abs(BoostWheel.turns(at: pointer) - 0.5) < 0.001)
        let d = BoostWheel.darkHue(pickedAt: pointer, hue: 0.25)
        #expect(abs(d - 0.25) < 0.001)
        let moved = BoostWheel.handles(hue: 0.25, strength: 0.5, darkHue: d)
        #expect(near(moved.big, h.big.x, h.big.y) && near(moved.small, -28, 0))
        #expect(abs(BoostWheel.accent(hue: 0.25, strength: 0.5, darkHue: d).hue - 0.5) < 0.001)
        #expect(abs(BoostWheel.darkHue(pickedAt: CGPoint(x: -5, y: -5), hue: 0.75) - 0.875) < 0.001, "it wraps around")
    }

    /// The connector always runs from the big handle clockwise to the small one: past half a turn it
    /// keeps going the same way instead of switching to the shorter arc.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/478"))
    func connectorNeverSwitchesPastHalfATurn() {
        let near = BoostWheel.handles(hue: 0.25, strength: 0.5, darkHue: 0.125)
        #expect(abs(BoostWheel.connectorSweep(big: near.big, small: near.small) - 0.125 * 2 * .pi) < 0.001)
        let far = BoostWheel.handles(hue: 0.25, strength: 0.5, darkHue: 0.75)
        #expect(abs(BoostWheel.connectorSweep(big: far.big, small: far.small) - 0.75 * 2 * .pi) < 0.001)
        let none = BoostWheel.handles(hue: 0.25, strength: 0.5, darkHue: 0)
        #expect(BoostWheel.connectorSweep(big: none.big, small: none.small) == 0)
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
        let ring = BoostWheel.ringGradient
        func nearStop(_ i: Int, _ r: Double, _ g: Double, _ b: Double) -> Bool {
            abs(ring[i].1 * 255 - r) < 2 && abs(ring[i].2 * 255 - g) < 2 && abs(ring[i].3 * 255 - b) < 2
        }
        #expect(nearStop(0, 235, 76, 57))
        #expect(nearStop(6, 209, 252, 93))
        #expect(nearStop(12, 132, 249, 240))
        #expect(nearStop(18, 129, 55, 245))
    }
}
