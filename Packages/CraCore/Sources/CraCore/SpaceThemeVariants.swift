import Foundation

/// The light and dark halves of an Auto theme (Arc: SpaceStyleEditorState+WindowTheme, which builds
/// `background.appearanceBased` from the editor's key colour).
public enum SpaceThemeVariants {
    /// What the theme editor makes of its pad: both halves for Auto, one for Light or Dark.
    /// Auto always gets both halves, one colour too (#155): Arc saves a swatch picked on Auto as one
    /// `single` theme that never changes with macOS, and copying that (0.1.30–0.1.32) left a space set
    /// to Auto stuck on one side. An imported Arc `single` stays on its side (ArcThemeImport, #171).
    public static func theme(key: [String], intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        var t: SpaceTheme
        if key.isEmpty {
            t = colourless(intensity: intensity, noise: noise, appearance: appearance)
            t.key = key
            return t
        }
        switch appearance {
        case "light": t = light(key: key, intensity: intensity, noise: noise)
        case "dark": t = dark(key: key, intensity: intensity, noise: noise)
        default: t = SpaceTheme(light: light(key: key, intensity: intensity, noise: noise), dark: dark(key: key, intensity: intensity, noise: noise))
        }
        t.key = key
        return t
    }

    /// Arc's colourless theme, what its editor saves with no colour on the pad ("Tap to pick a color
    /// for this space", #300): the default space's two halves, base #C8CAFF / #FFE5E5 light and
    /// #01021F / #1A001F dark, as ArcThemeImport draws them (pinned against Arc's own file by
    /// `noColourIsArcsColourlessTheme`). Auto follows macOS; Light or Dark keeps that half. The
    /// intensity slider still sets the light half's.
    public static func colourless(intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        let light = SpaceTheme(colors: ["#CDCDFC", "#FFE5E5"], intensity: intensity, noise: noise, appearance: "light", accent: "#C8CAFF")
        let dark = SpaceTheme(colors: ["#2C273B", "#32263A"], intensity: 1, noise: noise, appearance: "dark", accent: "#010220")
        switch appearance {
        case "light": return light
        case "dark": return dark
        default: return SpaceTheme(light: light, dark: dark)
        }
    }

    /// The half shown while macOS is light, from the pad's colours: the colours themselves (Arc
    /// saves a colour picked in Light as that colour), lifted to Arc's default light half (HSL
    /// lightness 0.9, #8389FF → #C8CAFF) when they would read as a dark theme. One colour is Arc's
    /// one-dot theme (`blendedSingleColor`), a flat fill like an imported one (ArcThemeImport).
    public static func light(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        var t = SpaceTheme(colors: key, intensity: intensity, noise: noise, appearance: "auto", accent: key.first)
        if t.isDark { t.colors = key.map { shade($0, lightness: 0.9) }; t.accent = t.colors.first }
        t.appearance = "light"
        if t.colors.count == 1 { t.colors.append(t.colors[0]); t.solid = true }
        return t
    }

    /// The half shown while macOS is dark, from the pad's colours. A colour dark enough for a dark
    /// theme stays itself, as Arc keeps every picked colour (offline Arc 1.172, 12 Nov 2026: black,
    /// #1A1A1A, #333333 and navy were saved as themselves); a lighter one keeps its hue at HSL
    /// lightness ≈ 0.064, as Arc's default dark half does (#8389FF → #01021F). Arc draws them over a
    /// neutral grey, never a purple one (#392). One colour is Arc's one-dot theme over the dark
    /// material (SpaceTheme.solid), at the slider's intensity like the light half.
    public static func dark(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        let base = key.map(darkTone)
        if base.count == 1 {
            return SpaceTheme(colors: base + base, intensity: intensity, noise: noise, appearance: "dark", accent: base[0], solid: true)
        }
        // A gradient is opaque: each stop at Arc's solid-theme opacity for the intensity over the
        // grey Arc's default dark half is drawn on (its top stop: 0.63 of #01021F over #5E5E5E).
        let a = SpaceTheme.solidAlpha(intensity: intensity)
        let colors = base.map { hex in
            let k = HexColor.components(hex) ?? (0, 0, 0)
            func ch(_ v: Double) -> Int { Int((a * v * 255 + (1 - a) * neutralGrey).rounded()) }
            return String(format: "#%02X%02X%02X", ch(k.r), ch(k.g), ch(k.b))
        }
        return SpaceTheme(colors: colors, intensity: 1, noise: noise, appearance: "dark", accent: base.first)
    }

    /// The grey under a dark gradient half (sRGB 0–255), fitted to Arc's default dark half.
    static let neutralGrey = 94.0

    /// A pad colour as the dark half uses it: itself when it already reads dark, else its hue darkened.
    static func darkTone(_ hex: String) -> String {
        (HexColor.luminance(hex) ?? 1) < 0.45 ? hex.uppercased() : shade(hex, lightness: 0.064)
    }

    /// The intensity the editor's slider had for a theme it built: a dark gradient bakes it into its
    /// colours (`dark`), so it's read back from the first stop; any other theme keeps it.
    public static func padIntensity(of theme: SpaceTheme) -> Double {
        guard theme.appearance == "dark", !theme.solid, theme.dark == nil, let key = theme.key, key.count > 1,
              let out = theme.colors.first.flatMap(HexColor.components),
              let base = HexColor.components(darkTone(key[0])) else { return theme.intensity }
        let g = neutralGrey / 255
        let pairs = [(base.r, out.r), (base.g, out.g), (base.b, out.b)]
        guard let (b, o) = pairs.max(by: { abs($0.0 - g) < abs($1.0 - g) }), abs(b - g) > 0.03 else { return theme.intensity }
        let a = (o - g) / (b - g)
        return max(0, min(1, (a - 0.19) / 0.55))
    }

    /// The colour's HSL hue and saturation at another lightness.
    static func shade(_ hex: String, lightness l: Double) -> String {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        let l0 = (mx + mn) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l0 - 1))
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h = (h / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
        let q = (1 - abs(2 * l - 1)) * min(1, s)
        let x = q * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1)), m = l - q / 2
        let (r, g, b): (Double, Double, Double)
        switch Int(h * 6) % 6 {
        case 0: (r, g, b) = (q, x, 0)
        case 1: (r, g, b) = (x, q, 0)
        case 2: (r, g, b) = (0, q, x)
        case 3: (r, g, b) = (0, x, q)
        case 4: (r, g, b) = (x, 0, q)
        default: (r, g, b) = (q, 0, x)
        }
        func byte(_ v: Double) -> Int { Int((max(0, min(1, v + m)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
