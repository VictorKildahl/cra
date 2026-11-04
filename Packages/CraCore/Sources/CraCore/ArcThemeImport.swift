import Foundation

/// An Arc space's `customInfo.windowTheme` (StorableSidebar.json) as a Cra theme.
public enum ArcThemeImport {
    /// Arc's blendedGradient → SpaceTheme. An Auto theme (appearanceBased) keeps both halves and
    /// follows macOS; Light and Dark ones (single) keep their one look.
    public static func theme(from space: [String: Any]) -> SpaceTheme? {
        guard let info = space["customInfo"] as? [String: Any], let wt = info["windowTheme"] as? [String: Any],
              let bg = wt["background"] as? [String: Any] else { return nil }
        if let ab = bg["appearanceBased"] as? [String: Any] {
            let light = (ab["light"] as? [String: Any]).flatMap { theme(variant: $0, appearance: "light", windowTheme: wt) }
            let dark = (ab["dark"] as? [String: Any]).flatMap { theme(variant: $0, appearance: "dark", windowTheme: wt) }
            if let light, let dark { return SpaceTheme(light: light, dark: dark) }
            return dark ?? light
        }
        guard let single = (bg["single"] as? [String: Any])?["_0"] as? [String: Any],
              var t = theme(variant: single, appearance: "auto", windowTheme: wt) else { return nil }
        // A `single` theme never follows macOS in Arc. Without `contentOverBackgroundAppearance` it
        // takes the side its colours suit (#171).
        if t.followsSystem { t.appearance = t.isDark ? "dark" : "light" }
        return t
    }

    /// One half of `background`: its own `contentOverBackgroundAppearance` wins over `appearance`.
    private static func theme(variant v: [String: Any], appearance: String, windowTheme wt: [String: Any]) -> SpaceTheme? {
        var appearance = appearance
        if let a = v["contentOverBackgroundAppearance"] as? String { appearance = a }
        let vibrant = v["isVibrant"] as? Bool ?? false
        func comp(_ c: [String: Any], _ k: String) -> Double { max(0, min(1, c[k] as? Double ?? 0)) }
        func hexOf(_ c: [String: Any]) -> String {
            String(format: "#%02X%02X%02X", Int((comp(c, "red") * 255).rounded()),
                   Int((comp(c, "green") * 255).rounded()), Int((comp(c, "blue") * 255).rounded()))
        }
        let c0 = ((v["style"] as? [String: Any])?["color"] as? [String: Any])?["_0"] as? [String: Any]
        // A solid colour (Arc's colour picker with one dot) is `blendedSingleColor`. Themes
        // Cra can't read still carry Arc's derived palette, whose mid tone keeps the hue.
        if let s = (c0?["blendedSingleColor"] as? [String: Any])?["_0"] as? [String: Any], let c = s["color"] as? [String: Any] {
            let mods = s["modifiers"] as? [String: Any]
            return solidTheme(hexOf(c), intensity: mods?["intensityFactor"] as? Double ?? 1,
                              noise: mods?["noiseFactor"] as? Double ?? 0, appearance: appearance)
        }
        guard let bg2 = c0?["blendedGradient"] as? [String: Any], let g = bg2["_0"] as? [String: Any],
              let base = g["baseColors"] as? [[String: Any]], !base.isEmpty else {
            guard let mid = (wt["primaryColorPalette"] as? [String: Any])?["midTone"] as? [String: Any] else { return nil }
            return solidTheme(hexOf(mid), intensity: 1, noise: 0, appearance: appearance)
        }
        let overlays = g["overlayColors"] as? [[String: Any]] ?? []
        // Arc blends an overlay gradient onto the base gradient and the wheel
        // mixes the two base colours; bake both into our two stops (fitted to
        // Arc's rendering: top stop leans toward the second base colour).
        func hex(_ i: Int) -> String {
            let b = base[min(i, base.count - 1)]
            let other = base[min(i == 0 ? 1 : 0, base.count - 1)]
            var r = comp(b, "red"), gg = comp(b, "green"), bl = comp(b, "blue")
            if i == 0 {
                r += (comp(other, "red") - r) * 0.1; gg += (comp(other, "green") - gg) * 0.1; bl += (comp(other, "blue") - bl) * 0.1
            }
            if i < overlays.count {
                let o = overlays[i]
                let a = comp(o, "alpha") * 0.85
                r += (comp(o, "red") - r) * a; gg += (comp(o, "green") - gg) * a; bl += (comp(o, "blue") - bl) * a
            }
            return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((gg * 255).rounded()), Int((bl * 255).rounded()))
        }
        var colors = [hex(0), hex(1)]
        let mods = g["modifiers"] as? [String: Any]
        var intensity = mods?["intensityFactor"] as? Double ?? 0.5
        if vibrant && appearance != "dark" {
            // Fitted to Arc over white and black backdrops: the top stop is the
            // first base colour nudged toward the second and 30% toward white;
            // the bottom stop is the base colour pulled 30% toward the overlay's
            // end colour (or the second base colour) and 20% toward white.
            // Opacity ramps 0.45 → 0.59 (see SpacePalette).
            func rgb(_ c: [String: Any]) -> (Double, Double, Double) { (comp(c, "red"), comp(c, "green"), comp(c, "blue")) }
            func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
                (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            }
            func hexOf(_ c: (Double, Double, Double)) -> String {
                String(format: "#%02X%02X%02X", Int((c.0 * 255).rounded()), Int((c.1 * 255).rounded()), Int((c.2 * 255).rounded()))
            }
            let b0 = rgb(base[0]), b1 = rgb(base[min(1, base.count - 1)])
            let end = overlays.last(where: { comp($0, "alpha") > 0 }).map(rgb) ?? b1
            let white = (1.0, 1.0, 1.0)
            colors = [hexOf(mix(mix(b0, b1, 0.15), white, 0.30)), hexOf(mix(mix(b0, end, 0.30), white, 0.20))]
        }
        let accent = String(format: "#%02X%02X%02X", Int((comp(base[0], "red") * 255).rounded()),
                            Int((comp(base[0], "green") * 255).rounded()), Int((comp(base[0], "blue") * 255).rounded()))
        if appearance == "dark" && !vibrant {
            // Measured from Arc: dark themes show ~27% of the colour over a
            // slightly purple dark grey (#2B2632).
            colors = colors.map { c in
                let k = HexColor.components(c) ?? (0, 0, 0)
                func ch(_ v: Double, _ base: Double) -> Int { Int((v * 255 * 0.27 + base).rounded()) }
                return String(format: "#%02X%02X%02X", ch(k.r, 43), ch(k.g, 38), ch(k.b, 50))
            }
            intensity = 1
        }
        return SpaceTheme(colors: colors, intensity: intensity,
                          noise: mods?["noiseFactor"] as? Double ?? 0.15, appearance: appearance, vibrant: vibrant, accent: accent)
    }

    /// One flat colour (SpaceTheme.solid). Arc draws it the same whether or not it is
    /// marked vibrant, so only the colour, intensity and text appearance carry over.
    private static func solidTheme(_ hex: String, intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        SpaceTheme(colors: [hex, hex], intensity: intensity, noise: noise, appearance: appearance, accent: hex, solid: true)
    }
}
