import Foundation

/// The light and dark halves of an Auto theme (Arc: SpaceStyleEditorState+WindowTheme, which builds
/// `background.appearanceBased` from the editor's key colour).
public enum SpaceThemeVariants {
    /// What the theme editor makes of its pad: both halves for Auto, one for Light or Dark.
    /// Auto always gets both halves, one colour too (#155): Arc saves a swatch picked on Auto as one
    /// `single` theme that never changes with macOS, and copying that (0.1.30–0.1.32) left a space set
    /// to Auto stuck on one side. An imported Arc `single` stays on its side (ArcThemeImport, #171).
    /// `wheel` is kept with two or three colours, so the editor reopens on it (#632).
    public static func theme(key: [String], intensity: Double, noise: Double, appearance: String,
                             wheel: SpaceThemeWheel? = nil) -> SpaceTheme {
        var t: SpaceTheme
        if key.isEmpty {
            t = colourless(intensity: intensity, noise: noise, appearance: appearance)
            t.key = key
            return t
        }
        switch appearance {
        case "light": t = picked(key: key, intensity: intensity, noise: noise, appearance: "light")
        case "dark": t = picked(key: key, intensity: intensity, noise: noise, appearance: "dark")
        default: t = SpaceTheme(light: light(key: key, intensity: intensity, noise: noise), dark: dark(key: key, intensity: intensity, noise: noise))
        }
        t.key = key
        t.wheel = key.count > 1 ? wheel : nil
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

    /// Auto's half shown while macOS is light, from the pad's colours: the colours themselves (Arc
    /// saves a colour picked in Light as that colour), lifted to Arc's default light half (HSL
    /// lightness 0.9, #8389FF → #C8CAFF) when they would read as a dark theme. One colour is Arc's
    /// one-dot theme (`blendedSingleColor`), a flat fill like an imported one (ArcThemeImport).
    public static func light(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        var t = SpaceTheme(colors: key, intensity: intensity, noise: noise, appearance: "auto", accent: key.first)
        if t.isDark { t.colors = key.map { shade($0, lightness: 0.9) }; t.accent = t.colors.first }
        t.appearance = "light"
        if t.colors.count == 1 { t.colors.append(t.colors[0]); t.solid = true } else { t.vibrant = true }
        return t
    }

    /// Auto's half shown while macOS is dark, from the pad's colours: the colours themselves over the dark
    /// material, as Arc on Automatic draws a picked colour while macOS is dark (offline Arc 1.172 and 1.174: every
    /// picked colour saved and drawn as itself, the appearance changing only the material under it), so it is the
    /// same as Cra's Dark (#677, Victor 22 Nov 2026). One colour is Arc's one-dot theme over the dark material
    /// (SpaceTheme.solid), two or three a see-through gradient, at the slider's intensity (#643). Until #677 a
    /// colour that read light was darkened here to HSL lightness 0.064 (`darkenedHalf`).
    public static func dark(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        picked(key: key, intensity: intensity, noise: noise, appearance: "dark")
    }

    /// A pad colour as the dark half uses it: itself when it already reads dark, else its hue darkened.
    /// The dark half Cra built before #677: a colour that read light darkened to HSL lightness 0.064 in its hue,
    /// a dark one kept. Only to recognise a saved half `upgradedDarkHalf` replaces.
    public static func darkenedHalf(key: [String], intensity: Double, noise: Double) -> SpaceTheme {
        let base = key.map(darkTone)
        if base.count == 1 {
            return SpaceTheme(colors: base + base, intensity: intensity, noise: noise, appearance: "dark", accent: base[0], solid: true)
        }
        return SpaceTheme(colors: base, intensity: intensity, noise: noise, appearance: "dark", vibrant: true, accent: base.first)
    }

    /// An Auto theme the editor saved before #677, whose dark half is still the darkened one, with today's half (the
    /// pad's colours as they are); nil for any other theme: Light, Dark, an Arc import's own halves, one set of
    /// colours, or a half already current. Run where sidebar.json is loaded, so a space looks as Arc would without
    /// being edited again.
    public static func upgradedDarkHalf(_ theme: SpaceTheme) -> SpaceTheme? {
        guard theme.followsSystem, let key = theme.key, !key.isEmpty, let saved = theme.dark else { return nil }
        let old = darkenedHalf(key: key, intensity: theme.intensity, noise: theme.noise).variant
        let new = dark(key: key, intensity: theme.intensity, noise: theme.noise).variant
        guard saved == old, saved != new else { return nil }
        var out = theme
        out.dark = new
        return out
    }

    static func darkTone(_ hex: String) -> String {
        (HexColor.luminance(hex) ?? 1) < 0.45 ? hex.uppercased() : shade(hex, lightness: 0.064)
    }

    /// Light or Dark, as Arc draws a picked colour on either appearance (offline Arc 1.172, 12 Nov
    /// 2026): the pad's colours as they are, one colour Arc's one-dot fill, at the slider's intensity.
    /// Arc lightens and darkens nothing: a light colour is a light sidebar with dark text and a dark
    /// one a dark sidebar with white text, on Light and Dark alike (SpaceTheme.isDark, #392). Only
    /// Auto's halves are lifted or darkened (`light`, `dark`), so an Auto space follows macOS (#155).
    /// Two or three colours are a see-through gradient: Arc's editor saves every pick as one `single`
    /// theme with `isVibrant` (offline Arc 1.171–1.172, its preset pairs and Victor's own space), drawn
    /// over the blurred desktop at the slider's intensity. Cra made them opaque, so the slider only
    /// took the colours toward white (#596, #643).
    public static func picked(key: [String], intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        var t = SpaceTheme(colors: key.map { $0.uppercased() }, intensity: intensity, noise: noise, appearance: appearance, accent: key.first?.uppercased())
        if t.colors.count == 1 { t.colors.append(t.colors[0]); t.solid = true } else { t.vibrant = true }
        return t
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
