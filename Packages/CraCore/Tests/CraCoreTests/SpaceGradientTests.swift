import CraCore
import Foundation
import Testing

/// The space gradient as Arc 1.174 draws it (GitHub #669): diagonal from the top left, flat past 0.76 of
/// the way to the far corner, blended in Oklab.
struct SpaceGradientTests {
    /// Cra ran the gradient top to bottom; Arc's runs from the top left corner at 45°, so the top right
    /// is already part way and the bottom left only half way, and the far corner is the last colour.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func runsFromTheTopLeftAt45Degrees() {
        let w = 1728.0, h = 1084.0
        #expect(SpaceGradient.position(x: 0, y: 0, width: w, height: h) == 0)
        #expect(SpaceGradient.position(x: w, y: h, width: w, height: h) == 1)
        // A 45° axis: points the same distance along it (x + y equal) are the same colour.
        let a = SpaceGradient.position(x: 600, y: 200, width: w, height: h)
        let b = SpaceGradient.position(x: 200, y: 600, width: w, height: h)
        #expect(abs(a - b) < 1e-12)
        // Arc's 1728×1084 window (measured 22 Nov 2026): the top right is 0.82 of the way, the bottom left
        // 0.51, and the last colour arrives 0.76 of the way to the far corner along the axis.
        #expect(abs(SpaceGradient.position(x: w, y: 0, width: w, height: h) - 0.809) < 0.01)
        #expect(abs(SpaceGradient.position(x: 0, y: h, width: w, height: h) - 0.507) < 0.01)
        let end = 0.76 * (w + h) / 2
        #expect(SpaceGradient.position(x: end, y: end, width: w, height: h) == 1)
        #expect(SpaceGradient.position(x: end - 50, y: end - 50, width: w, height: h) < 1)
    }

    /// The same shape in a narrower or shorter window: Arc's gradient scales with the window.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func scalesWithTheWindow() {
        let big = SpaceGradient.position(x: 400, y: 300, width: 1600, height: 1000)
        let small = SpaceGradient.position(x: 200, y: 150, width: 800, height: 500)
        #expect(abs(big - small) < 1e-12)
        let a = SpaceGradient.axis(width: 927, height: 531)
        #expect(a.start.x == 0 && a.start.y == 0 && abs(a.end.x - a.end.y) < 1e-12)
    }

    /// A gradient layer blends in unit space: the end it gets puts the colours where `position` says, at
    /// 45° in points on a wide, a tall and a square frame. Handed the axis divided by the frame, Cra's ran
    /// at 68° on a 1728×1084 window (#669).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func layerEndMatchesTheAxis() {
        for (w, h) in [(1728.0, 1084.0), (927.0, 1069.0), (500.0, 500.0), (300.0, 900.0)] {
            let e = SpaceGradient.unitEnd(width: w, height: h)
            let n = e.x * e.x + e.y * e.y
            for (x, y) in [(0.0, 0.0), (w, 0), (0, h), (w * 0.3, h * 0.6), (w, h)] {
                // What a layer does with unit points: project (x/w, y/h) on the end, clamp.
                let layer = max(0, min(1, (x / w * e.x + y / h * e.y) / n))
                #expect(abs(layer - SpaceGradient.position(x: x, y: y, width: w, height: h)) < 1e-9, "\(w)×\(h) at \(x),\(y)")
            }
        }
    }

    /// Red to teal in Oklab (Arc's blend): the red channel falls slowly at first and fast near the teal,
    /// green rises fast first; the midpoint isn't sRGB's average. Fitted to Arc's capture with an rms of
    /// 1.2/255 against 3.0 for an sRGB ramp.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func blendsInOklab() {
        let red = SpaceGradient.RGBA(r: 242 / 255, g: 144 / 255, b: 149 / 255)
        let teal = SpaceGradient.RGBA(r: 127 / 255, g: 223 / 255, b: 217 / 255)
        let mid = SpaceGradient.mix(red, teal, 0.5)
        #expect(mid.r * 255 > (242 + 127) / 2 + 2, "red stays up longer than an sRGB average")
        #expect(mid.g * 255 > (144 + 223) / 2 + 1, "green rises sooner")
        let q1 = SpaceGradient.mix(red, teal, 0.25).r, q3 = SpaceGradient.mix(red, teal, 0.75).r
        #expect(red.r - q1 < q3 - teal.r, "the steps grow toward the teal")
        #expect(SpaceGradient.mix(red, teal, 0) == red)
        let end = SpaceGradient.mix(red, teal, 1)
        #expect(abs(end.r - teal.r) < 1e-6 && abs(end.g - teal.g) < 1e-6 && abs(end.b - teal.b) < 1e-6)
    }

    /// Three colours sit at 0, ½ and 1; samples go evenly between them; opacity blends straight.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func threeColoursAndOpacity() {
        let a = SpaceGradient.RGBA(r: 1, g: 0, b: 0, a: 0.4), b = SpaceGradient.RGBA(r: 0, g: 1, b: 0, a: 0.6),
            c = SpaceGradient.RGBA(r: 0, g: 0, b: 1, a: 0.8)
        let s = SpaceGradient.samples([a, b, c], count: 5)
        #expect(s.count == 5 && s[0] == a && abs(s[2].g - 1) < 1e-6 && abs(s[4].b - 1) < 1e-6)
        #expect(abs(s[1].a - 0.5) < 1e-9 && abs(s[3].a - 0.7) < 1e-9)
        #expect(SpaceGradient.color([a], at: 0.7) == a)
    }
}
