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

    // Arc's primaryColorPalette, which Cra doesn't store, rebuilt from the theme colour (#490). Measured
    // on 18 palettes offline Arc 1.172.2 wrote for its editor's swatches (17 Nov 2026,
    // `arcPalettesFollowTheColoursSaturation`): Arc works in Display P3, and every tone keeps the colour's
    // P3 HSL hue and saturation; only its lightness moves, until the tone's luminance reaches its bound.
    // A muted colour keeps muted tones, a dark one is its own shadedDark, and saturated colours run
    // outside sRGB as Arc's do. All four land within 6/255 of Arc's. Before #490 Cra took the hue
    // alone at full saturation, so every green got the same vivid green.

    /// shadedDark: the colour darkened to 10 % luminance; a darker colour is its own.
    public static func shadedDark(_ hex: String?) -> RGB {
        if let arc = arcDefault(hex) { return arc.shadedDark }
        return paletteTone(hex, below: 0.1)
    }

    /// shaded: the colour darkened to luminance 0.495; a darker colour is its own.
    public static func shaded(_ hex: String?) -> RGB {
        if let arc = arcDefault(hex) { return arc.shaded }
        return paletteTone(hex, below: shadedCeiling)
    }

    /// midTone: shaded, lightened to luminance 0.306 when darker than that.
    public static func midTone(_ hex: String?) -> RGB {
        if let arc = arcDefault(hex) { return arc.midTone }
        return paletteTone(hex, below: shadedCeiling, above: 0.306)
    }

    /// tintedLight: the colour lightened to luminance 0.856; a lighter colour is its own.
    public static func tintedLight(_ hex: String?) -> RGB {
        if let arc = arcDefault(hex) { return arc.tintedLight }
        return paletteTone(hex, above: 0.856)
    }

    private static let shadedCeiling = 0.495

    /// Arc's colourless default theme keeps the palette Arc ships with it, which no single colour
    /// rebuilds (its shaded sits far below its midTone): StorableSidebar.json's values for the
    /// default space. Cra's colourless halves (#C8CAFF light, #010220 dark) and Arc imports of
    /// that theme (#010220 / #01021F) take it.
    private static func arcDefault(_ hex: String?) -> (shadedDark: RGB, shaded: RGB, midTone: RGB, tintedLight: RGB)? {
        guard let hex = hex?.uppercased(), ["#010220", "#01021F", "#C8CAFF"].contains(hex) else { return nil }
        func c(_ r: Double, _ g: Double, _ b: Double) -> RGB { RGB(r / 255, g / 255, b / 255) }
        return (c(31.06, 42.36, 261.65), c(47.0, 57.3, 261.1), c(131.1, 137.2, 258.7), c(236.2, 237.1, 255.6))
    }

    /// The theme colour at the P3 HSL lightness whose luminance is `below` when it is lighter than
    /// that, then `above` when it is darker than that; hue and saturation stay.
    private static func paletteTone(_ hex: String?, below: Double? = nil, above: Double? = nil) -> RGB {
        let c = HexColor.components(hex ?? "") ?? (0.5, 0.5, 0.5)
        let p3 = displayP3(RGB(c.r, c.g, c.b))
        var (h, s, l) = hsl(p3)
        func luminance(_ l: Double) -> Double { p3Luminance(fromHSL(h, s, l)) }
        // Bisect the lightness in lo...hi whose luminance is `target` (luminance rises with lightness).
        func solve(_ target: Double, _ lo: Double, _ hi: Double) -> Double {
            var (lo, hi) = (lo, hi)
            for _ in 0..<40 { let m = (lo + hi) / 2; if luminance(m) < target { lo = m } else { hi = m } }
            return (lo + hi) / 2
        }
        if let below, luminance(l) > below { l = solve(below, 0, l) }
        if let above, luminance(l) < above { l = solve(above, l, 1) }
        if s == 0 { h = 0 }
        return sRGB(fromDisplayP3: fromHSL(h, s, l))
    }

    /// sRGB ↔ Display P3 (both D65, the sRGB curve), channels beyond 0...1 kept: Arc's tones leave sRGB.
    public static func displayP3(_ c: RGB) -> RGB {
        let (r, g, b) = (linear(c.r), linear(c.g), linear(c.b))
        return RGB(encoded(0.8224621 * r + 0.1775380 * g), encoded(0.0331941 * r + 0.9668058 * g),
                   encoded(0.0170827 * r + 0.0723974 * g + 0.9105199 * b))
    }

    public static func sRGB(fromDisplayP3 c: RGB) -> RGB {
        let (r, g, b) = (linear(c.r), linear(c.g), linear(c.b))
        return RGB(encoded(1.2249401 * r - 0.2249404 * g), encoded(-0.0420569 * r + 1.0420571 * g),
                   encoded(-0.0196376 * r - 0.0786361 * g + 1.0982735 * b))
    }

    private static func p3Luminance(_ c: RGB) -> Double {
        0.2289746 * linear(c.r) + 0.6917385 * linear(c.g) + 0.0792869 * linear(c.b)
    }

    private static func linear(_ x: Double) -> Double {
        let a = abs(x)
        return (a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)) * (x < 0 ? -1 : 1)
    }

    private static func encoded(_ x: Double) -> Double {
        let a = abs(x)
        return (a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055) * (x < 0 ? -1 : 1)
    }

    /// HSL (hue 0..<1), as Arc's tones keep it in Display P3.
    public static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn, l = (mx + mn) / 2
        guard d > 0.00001 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        let (h, _, _) = hsb(c.r, c.g, c.b)
        return (h, s, l)
    }

    private static func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        let chroma = (1 - abs(2 * l - 1)) * s, m = l - chroma / 2
        guard chroma > 0 else { return RGB(l, l, l) }
        let o = rgb(h: h, s: 1, v: 1)   // the pure hue, scaled to the chroma and lifted by m
        return RGB(m + o.0 * chroma, m + o.1 * chroma, m + o.2 * chroma)
    }

    /// The colour Arc builds the space's palette from.
    public var paletteSource: String? { accent ?? colors.first }

    public var shadedDark: RGB { Self.shadedDark(paletteSource) }
    public var midTone: RGB { Self.midTone(paletteSource) }
    public var shaded: RGB { Self.shaded(paletteSource) }
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
