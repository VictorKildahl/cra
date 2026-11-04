import Foundation

/// An sRGB colour, 0...1 a channel.
public struct RGB: Equatable, Sendable {
    public var r, g, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }

    /// `self` moved toward `other` by `t` (0...1), channel by channel.
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)
}

extension SpaceTheme {
    public static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0.00001 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    public static func rgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Arc's primaryColorPalette.shadedDark, which Cra doesn't store: the theme colour's hue,
    /// strongly saturated, at 10 % luminance. Arc's own values all sit at 0.095–0.102 (Victor
    /// #6F5614 for #F8D558, JYSK #1F2AFF, and #B70021 and #24569F on the spaces in GitHub #152).
    /// Greys stay grey.
    public static func shadedDark(_ hex: String?) -> RGB {
        let c = HexColor.components(hex ?? "") ?? (0.5, 0.5, 0.5)
        let (h, s, _) = hsb(c.r, c.g, c.b)
        let ds = s < 0.05 ? 0 : 0.94
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let v = (lo + hi) / 2, o = rgb(h: h, s: ds, v: v)
            if 0.2126 * lin(o.0) + 0.7152 * lin(o.1) + 0.0722 * lin(o.2) < 0.1 { lo = v } else { hi = v }
        }
        let o = rgb(h: h, s: ds, v: lo)
        return RGB(o.0, o.1, o.2)
    }

    /// OKLab lightness (0 black … 1 white).
    public static func oklabLightness(_ c: RGB) -> Double {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (lin(c.r), lin(c.g), lin(c.b))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    }

    /// Arc's primaryColorPalette.midTone, which Cra doesn't store: the theme colour while its OKLab
    /// lightness is within 0.68…0.794, else the most saturated colour of its hue at the nearer bound.
    /// Fits Arc's three palettes within 2/255 (Arc's light-blue #6CBAD9 is its own midTone, Victor
    /// #F8D558 → #E9B300, JYSK #010220 → #8389FF).
    public static func midTone(_ hex: String?) -> RGB {
        let base = paletteBase(hex)
        return oklabLightness(base) <= midToneCeiling ? base : edge(hex, lightness: midToneCeiling)
    }

    /// Arc's primaryColorPalette.tintedLight: the theme colour (raised to 0.68 like midTone) mixed
    /// toward white in sRGB until its OKLab lightness is 0.95. Arc's three: #6CBAD9 → #E4F2F8,
    /// #F8D558 → #FCEDBC, #010220 → #ECEDFF (within 2/255).
    public static func tintedLight(_ hex: String?) -> RGB {
        let base = paletteBase(hex)
        guard oklabLightness(base) < 0.95 else { return base }
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {
            let t = (lo + hi) / 2
            if oklabLightness(base.mixed(with: .white, t)) < 0.95 { lo = t } else { hi = t }
        }
        return base.mixed(with: .white, lo)
    }

    private static let midToneFloor = 0.68, midToneCeiling = 0.794

    private static func paletteBase(_ hex: String?) -> RGB {
        let c = HexColor.components(hex ?? "") ?? (0.5, 0.5, 0.5)
        let rgb = RGB(c.r, c.g, c.b)
        return oklabLightness(rgb) >= midToneFloor ? rgb : edge(hex, lightness: midToneFloor)
    }

    /// The colour of `hex`'s HSB hue on the sRGB gamut's edge (full saturation, or full brightness
    /// when that is too dark) with the given OKLab lightness. Greys stay grey.
    private static func edge(_ hex: String?, lightness target: Double) -> RGB {
        let c = HexColor.components(hex ?? "") ?? (0.5, 0.5, 0.5)
        let (h, s, _) = hsb(c.r, c.g, c.b)
        func at(_ s: Double, _ v: Double) -> RGB { let o = rgb(h: h, s: s, v: v); return RGB(o.0, o.1, o.2) }
        // Bisect x in 0...1 for f(x) = target, f rising.
        func solve(_ f: (Double) -> Double) -> Double {
            var lo = 0.0, hi = 1.0
            for _ in 0..<30 { let x = (lo + hi) / 2; if f(x) < target { lo = x } else { hi = x } }
            return (lo + hi) / 2
        }
        if s < 0.05 { return at(0, solve { oklabLightness(at(0, $0)) }) }
        if target <= oklabLightness(at(1, 1)) { return at(1, solve { oklabLightness(at(1, $0)) }) }
        return at(1 - solve { oklabLightness(at(1 - $0, 1)) }, 1)
    }

    /// The colour Arc builds the space's palette from.
    public var paletteSource: String? { accent ?? colors.first }

    public var shadedDark: RGB { Self.shadedDark(paletteSource) }
    public var midTone: RGB { Self.midTone(paletteSource) }
    public var tintedLight: RGB { Self.tintedLight(paletteSource) }
}

/// Arc's folder glyph colours (FolderIcon's ColorSpec, measured 4 Nov 2026 on offline-Arc 2x
/// captures of a light-blue, a gold and the default dark theme). Every panel is opaque. The back
/// panel is always the palette's midTone. Light themes: front tintedLight, outline shadedDark.
/// Dark themes swap these: front shadedDark, outline tintedLight.
public struct FolderTones: Equatable, Sendable {
    public var outline: RGB
    public var front: RGB
    public var back: RGB

    public init(outline: RGB, front: RGB, back: RGB) { (self.outline, self.front, self.back) = (outline, front, back) }

    public init(themeColor hex: String?, dark: Bool) {
        let light = SpaceTheme.tintedLight(hex), shaded = SpaceTheme.shadedDark(hex)
        self.init(outline: dark ? light : shaded, front: dark ? shaded : light, back: SpaceTheme.midTone(hex))
    }
}

/// Arc's hover tips (ArcTooltipConfiguration.colorPalette) are painted from the palette of the
/// space the window is in, whichever control or space icon they belong to. In Arc's data every
/// tone is shadedDark (= light.maxContrastColor) or a mix of it, the same on all four spaces
/// measured (Victor and JYSK in Arc's StorableSidebar.json, CloudDev and RM in GitHub #152):
/// - fill: dark.background, shadedDark at 30 %;
/// - title: dark.title, white with 15 % of shadedDark;
/// - badge: light.hover, white with 20 % of shadedDark: the profile pill and the key caps;
/// - ink: shadedDark itself: the profile's name, the avatar and the caps' glyphs.
/// The tip mixes two of Arc's schemes, which is why the pill reads as a light chip on a dark capsule.
public struct TooltipTones: Equatable, Sendable {
    public var fill: RGB
    public var title: RGB
    public var badge: RGB
    public var ink: RGB

    public init(fill: RGB, title: RGB, badge: RGB, ink: RGB) {
        (self.fill, self.title, self.badge, self.ink) = (fill, title, badge, ink)
    }

    public init(shadedDark ink: RGB) {
        self.init(fill: RGB.black.mixed(with: ink, 0.30), title: RGB.white.mixed(with: ink, 0.15),
                  badge: RGB.white.mixed(with: ink, 0.20), ink: ink)
    }

    public init(theme: SpaceTheme) { self.init(shadedDark: theme.shadedDark) }
}
