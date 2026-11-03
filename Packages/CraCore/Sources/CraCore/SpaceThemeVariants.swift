import Foundation

/// The light and dark halves of an Auto theme (Arc: SpaceStyleEditorState+WindowTheme, which builds
/// `background.appearanceBased` from the editor's key colour).
public enum SpaceThemeVariants {
    /// What the theme editor makes of its pad: both halves for Auto, one for Light or Dark.
    public static func theme(key: [String], intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        var t: SpaceTheme
        switch appearance {
        case "light": t = light(key: key, intensity: intensity, noise: noise)
        case "dark": t = dark(key: key, intensity: intensity, noise: noise)
        default: t = SpaceTheme(light: light(key: key, intensity: intensity, noise: noise), dark: dark(key: key, intensity: intensity, noise: noise))
        }
        t.key = key
        return t
    }

    /// The other half of a theme that has one: a dark theme's light half or a light theme's dark half.
    public static func flipped(_ t: SpaceTheme) -> SpaceTheme {
        t.isDark ? light(key: t.colors, intensity: t.intensity, noise: t.noise)
            : dark(key: t.colors, intensity: t.intensity, noise: t.noise)
    }

    /// The half shown while macOS is light, from the pad's colours: the colours themselves (Arc
    /// saves a colour picked in Light as that colour), lifted to Arc's default light half (HSL
    /// lightness 0.9, #8389FF → #C8CAFF) when they would read as a dark theme.
    public static func light(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        var t = SpaceTheme(colors: key, intensity: intensity, noise: noise, appearance: "auto", accent: key.first)
        if t.isDark { t.colors = key.map { shade($0, lightness: 0.9) }; t.accent = t.colors.first }
        t.appearance = "light"
        return t
    }

    /// The half shown while macOS is dark, from the pad's colours: Arc's default dark half keeps the
    /// key's hue at HSL lightness ≈ 0.064 (#8389FF → #01021F).
    public static func dark(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        let base = key.map { shade($0, lightness: 0.064) }
        // Drawn the way ArcThemeImport draws Arc's opaque dark halves: ~27% of the colour over #2B2632.
        let colors = base.map { hex in
            let k = HexColor.components(hex) ?? (0, 0, 0)
            func ch(_ v: Double, _ b: Double) -> Int { Int((v * 255 * 0.27 + b).rounded()) }
            return String(format: "#%02X%02X%02X", ch(k.r, 43), ch(k.g, 38), ch(k.b, 50))
        }
        return SpaceTheme(colors: colors, intensity: 1, noise: noise, appearance: "dark", accent: base.first)
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
