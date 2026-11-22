import Foundation

/// How Arc draws a space's gradient across the window (GitHub #669, measured in Arc 1.174; see
/// docs/arc-reverse-engineering.md "The empty card and the gradient's direction"). The colours blend in
/// Oklab, not sRGB: a red to teal theme stays warm for longer and turns faster near the teal. Fitted to
/// Arc's capture, Oklab is off by 1.2/255 rms and an sRGB ramp by 3.0.
public enum SpaceGradient {
    /// Arc's axis: 45° down to the right from the window's top left corner, whatever the window's
    /// shape, reaching the last colour 0.76 of the way to the far corner and flat from there. Measured
    /// on a 1728×1084, two 927×1069 and a 927×531 window: the angle 45–46° on each (the end 0.76,
    /// 0.76, 0.76 and 0.73 of the way), so it is neither the window's diagonal nor fixed in points.
    public static let angle = 45.0
    public static let reach = 0.76

    /// Start and end of the gradient in a `width`×`height` frame, in points from its top left.
    public static func axis(width: Double, height: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        // Along 45°, the far corner is (w + h)/√2 away; the end point is `reach` of that along the axis.
        let d = reach * (max(0, width) + max(0, height)) / 2
        return ((0, 0), (d, d))
    }

    /// The end point for a gradient layer (Core Animation's, SwiftUI's) that takes unit points and blends
    /// perpendicular to the axis in unit space, from its top left (x right, y down, 0...1 of the frame).
    /// Handing it `axis` divided by the frame turned the lines of one colour toward the frame's shape: 68°
    /// on a 1728×1084 window, not Arc's 45°. With the end at 2d·(w, h)/(w² + h²) they run at 45° in points.
    public static func unitEnd(width: Double, height: Double) -> (x: Double, y: Double) {
        let w = max(0, width), h = max(0, height)
        let n = w * w + h * h
        guard n > 0 else { return (1, 1) }
        let d = axis(width: w, height: h).end.x
        return (2 * d * w / n, 2 * d * h / n)
    }

    /// Where along the gradient (0...1) a point of the frame is.
    public static func position(x: Double, y: Double, width: Double, height: Double) -> Double {
        let a = axis(width: width, height: height)
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return 0 }
        return max(0, min(1, ((x - a.start.x) * dx + (y - a.start.y) * dy) / len2))
    }

    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
        public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    }

    /// `x` toward `y` by `t` (0...1): the colour in Oklab, opacity straight.
    public static func mix(_ x: RGBA, _ y: RGBA, _ t: Double) -> RGBA {
        let k = max(0, min(1, t))
        if k == 0 { return x }
        if k == 1 { return y }
        let p = Oklab(x), q = Oklab(y)
        let c = Oklab(L: p.L + (q.L - p.L) * k, a: p.a + (q.a - p.a) * k, b: p.b + (q.b - p.b) * k).rgb
        return RGBA(r: c.r, g: c.g, b: c.b, a: x.a + (y.a - x.a) * k)
    }

    /// The colour at `t` (0...1) along stops spread evenly from first to last.
    public static func color(_ stops: [RGBA], at t: Double) -> RGBA {
        guard let first = stops.first else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        guard stops.count > 1 else { return first }
        let p = max(0, min(1, t)) * Double(stops.count - 1)
        let i = min(stops.count - 2, Int(p))
        return mix(stops[i], stops[i + 1], p - Double(i))
    }

    /// `count` colours spaced evenly from t = 0 to 1, for a gradient layer that blends linearly between
    /// its stops: close enough together, that is Arc's Oklab curve.
    public static func samples(_ stops: [RGBA], count: Int) -> [RGBA] {
        let n = max(2, count)
        return (0..<n).map { color(stops, at: Double($0) / Double(n - 1)) }
    }

    struct Oklab {
        var L, a, b: Double
        init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

        init(_ c: RGBA) {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let (r, g, b) = (lin(c.r), lin(c.g), lin(c.b))
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        }

        var rgb: (r: Double, g: Double, b: Double) {
            let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
            func enc(_ v: Double) -> Double {
                let x = max(0, min(1, v))
                return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
            }
            return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                    enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                    enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
        }
    }
}
