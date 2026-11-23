import Foundation

/// Where the theme editor's pad puts a second and third colour (Arc: the saved theme's `wheel`, #632);
/// SpaceColorWheel places them. Here, with the theme, so a file that reads themes needs no more.
public enum SpaceThemeWheel: String, Codable, Sendable, CaseIterable {
    /// +40°, then −40°: a page-2 swatch.
    case analogous
    /// Across the wheel: 180°, or 150° and 210° (Arc's spelling, as its file has it).
    case complimentary
}

public struct SpaceTheme: Codable, Equatable {
    /// One or two hex colors blended into a gradient (Arc: blendedGradient.baseColors).
    public var colors: [String]
    /// 0...1, how saturated the gradient is rendered (Arc: intensityFactor).
    public var intensity: Double
    /// 0...1 grain overlay (Arc: noiseFactor).
    public var noise: Double
    /// "auto" | "light" | "dark" (Arc: contentOverBackgroundAppearance).
    public var appearance: String
    /// Arc's isVibrant: the gradient is laid over the blurred desktop at
    /// `intensity` opacity instead of being painted opaque.
    public var vibrant: Bool = false
    /// The theme's raw first colour (Arc's base colour); drives the toolbar band.
    public var accent: String? = nil
    /// Arc's one-colour theme (blendedSingleColor): a flat fill laid over a dark, slightly
    /// see-through material, at `intensity` (SpacePalette.solidAlpha), not a gradient.
    public var solid: Bool = false
    /// Arc's Auto theme (background.appearanceBased): with `appearance` "auto" the space follows
    /// macOS, the fields above are its light half and this is the half shown while macOS is dark.
    /// nil on an "auto" theme with one set of colours (saved before 0.1.29, the old Edit Space sheet's
    /// Auto, a Zen import): it stays on the side its colours suit whatever macOS shows. The theme
    /// editor's Auto always writes both halves (SpaceThemeVariants).
    public var dark: Variant? = nil
    /// The theme editor's pad colours the theme was built from (Arc: the editor's key colour and
    /// the ones its wheel adds); nil for a preset or an import, whose own colours go on the pad.
    public var key: [String]? = nil
    /// The pad's wheel for two or three `key` colours (Arc: the saved theme's `wheel`), which + , −
    /// and a drag place them on (#632); nil for one colour, a preset or an import, and for a theme
    /// saved before 0.1.53 (SpaceColorPresets.wheel(of:) then picks it).
    public var wheel: SpaceThemeWheel? = nil

    /// One half of an Auto theme: everything but the appearance, which is the half's own.
    public struct Variant: Codable, Equatable {
        public var colors: [String]
        public var intensity: Double
        public var noise: Double
        public var vibrant: Bool = false
        public var accent: String? = nil
        public var solid: Bool = false

        /// A half written without `vibrant` or `solid` (by hand, or by a later Cra that drops them)
        /// reads them as off instead of failing the file.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            colors = try c.decode([String].self, forKey: .colors)
            intensity = try c.decode(Double.self, forKey: .intensity)
            noise = try c.decodeIfPresent(Double.self, forKey: .noise) ?? 0
            vibrant = try c.decodeIfPresent(Bool.self, forKey: .vibrant) ?? false
            accent = try c.decodeIfPresent(String.self, forKey: .accent)
            solid = try c.decodeIfPresent(Bool.self, forKey: .solid) ?? false
        }

        public init(colors: [String], intensity: Double, noise: Double, vibrant: Bool = false, accent: String? = nil, solid: Bool = false) {
            self.colors = colors
            self.intensity = intensity
            self.noise = noise
            self.vibrant = vibrant
            self.accent = accent
            self.solid = solid
        }
    }

    public init(colors: [String], intensity: Double, noise: Double, appearance: String, vibrant: Bool = false, accent: String? = nil,
         solid: Bool = false, dark: Variant? = nil, key: [String]? = nil, wheel: SpaceThemeWheel? = nil) {
        self.colors = colors
        self.intensity = intensity
        self.noise = noise
        self.appearance = appearance
        self.vibrant = vibrant
        self.accent = accent
        self.solid = solid
        self.dark = dark
        self.key = key
        self.wheel = wheel
    }

    /// Arc's Auto: a light and a dark half, shown as macOS' appearance says.
    public init(light: SpaceTheme, dark: SpaceTheme) {
        self = light
        appearance = "auto"
        self.dark = dark.variant
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? ["#1C242B", "#3A3660"]
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.8
        noise = try c.decodeIfPresent(Double.self, forKey: .noise) ?? 0.15
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "auto"
        vibrant = try c.decodeIfPresent(Bool.self, forKey: .vibrant) ?? false
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
        solid = try c.decodeIfPresent(Bool.self, forKey: .solid) ?? false
        // A dark half that can't be read is dropped, not the whole sidebar.json with it.
        dark = (try? c.decodeIfPresent(Variant.self, forKey: .dark)) ?? nil
        key = try c.decodeIfPresent([String].self, forKey: .key)
        // A wheel this Cra doesn't know falls back to the colours' own, not a failed sidebar.json.
        wheel = (try? c.decodeIfPresent(SpaceThemeWheel.self, forKey: .wheel)) ?? nil
    }

    var variant: Variant {
        Variant(colors: colors, intensity: intensity, noise: noise, vibrant: vibrant, accent: accent, solid: solid)
    }

    /// Auto follows macOS; Light and Dark keep their look whatever macOS shows.
    public var followsSystem: Bool { appearance == "auto" }

    /// The theme as shown while macOS is dark or light: a Light or Dark theme as it is, an
    /// Auto one as the matching half with that half's appearance.
    public func resolved(systemDark: Bool) -> SpaceTheme {
        guard followsSystem else { return self }
        if let d = dark {
            if !systemDark { var t = self; t.appearance = "light"; t.dark = nil; return t }
            var t = SpaceTheme(colors: d.colors, intensity: d.intensity, noise: d.noise, appearance: "dark", vibrant: d.vibrant,
                               accent: d.accent, solid: d.solid)
            // The pad's colours belong to both halves: the dark one is the editor's too (drawnOverMaterial).
            t.key = key
            return t
        }
        // One set of colours keeps its look on both sides, as an Arc `single` theme does: swapping
        // it for a derived half made an imported space look nothing like Arc's while macOS ran the
        // other way (#171).
        var t = self
        t.appearance = isDark ? "dark" : "light"
        return t
    }

    /// Whether a one-colour sidebar is drawn over Arc's light material rather than its dark one. Arc's
    /// follows its own appearance (View ▸ Appearance, which the theme editor's sun and moon set) and
    /// never changes the colour for it (offline Arc 1.172, 17 Nov 2026); a Cra space's Light or Dark
    /// stands in for that appearance, and Auto follows macOS, as Arc on Automatic does (#455).
    /// `forcedDark`: View ▸ Appearance set to Dark (true) or Light (false), nil on Automatic.
    public func usesLightMaterial(systemDark: Bool, forcedDark: Bool? = nil) -> Bool {
        Self.isLight(appearance, systemDark: systemDark, forcedDark: forcedDark)
    }

    /// Light or Dark as they are, Auto as macOS shows: Arc's appearance setting, which picks the
    /// one-colour material and the theme editor's card (light card, black controls) alike (#455).
    /// View ▸ Appearance set to Light or Dark (`forcedDark`) is that setting for every space, as in Arc,
    /// where it is one for the whole browser (#700).
    public static func isLight(_ appearance: String, systemDark: Bool, forcedDark: Bool? = nil) -> Bool {
        if let forcedDark { return !forcedDark }
        switch appearance {
        case "light": return true
        case "dark": return false
        default: return !systemDark
        }
    }

    /// Dark first: colors borrowed from Victor's other projects (GhostWriter
    /// ink + brand purple, Spook's "wall" browns, Phantom's greys, moss, gold,
    /// ember), then a few lighter Arc-style gradients.
    public static let presets: [SpaceTheme] = [
        SpaceTheme(colors: ["#1C242B", "#3A3660"], intensity: 0.85, noise: 0.18, appearance: "dark"),  // Ink
        SpaceTheme(colors: ["#1C1712", "#2E2620"], intensity: 0.9, noise: 0.22, appearance: "dark"),   // Wall
        SpaceTheme(colors: ["#181818", "#262626"], intensity: 0.9, noise: 0.12, appearance: "dark"),   // Phantom
        SpaceTheme(colors: ["#0F2420", "#2F6F5E"], intensity: 0.75, noise: 0.18, appearance: "dark"),  // Moss
        SpaceTheme(colors: ["#2A1A14", "#A2481D"], intensity: 0.7, noise: 0.2, appearance: "dark"),    // Ember
        SpaceTheme(colors: ["#2A2310", "#7A5C0F"], intensity: 0.75, noise: 0.2, appearance: "dark"),   // Gold
        SpaceTheme(colors: ["#241C3A", "#6944AE"], intensity: 0.75, noise: 0.18, appearance: "dark"),  // Brand
        SpaceTheme(colors: ["#F8D558", "#A4F554"], intensity: 0.45, noise: 0.25, appearance: "light"),
        SpaceTheme(colors: ["#C7CAFF", "#FFE5E5"], intensity: 0.5, noise: 0.1, appearance: "light"),
        SpaceTheme(colors: ["#F4F1EA", "#E6DCC8"], intensity: 0.6, noise: 0.15, appearance: "light"),  // Parchment
    ]

    /// Incognito windows: near-black with a cool violet cast, so they never pass for a space.
    public static let incognito = SpaceTheme(colors: ["#141318", "#2B2638"], intensity: 0.9, noise: 0.14, appearance: "dark")

    /// Arc 1.171 over solid white and black backdrops (31 Oct 2026, nine colours, sRGB after undoing
    /// the display's P3): a one-colour theme shows α·colour + (1 − α)·(66 + 0.52·backdrop) while
    /// active, α·colour + (1 − α)·212 while inactive, with α = 0.19 + 0.55·intensity (fits 0.191,
    /// 0.459, 0.742 at 0, 0.5, 1; within 3/255). isVibrant and the text appearance don't matter.
    public static func solidAlpha(intensity: Double) -> Double { 0.19 + 0.55 * max(0, min(1, intensity)) }

    /// Whether the sidebar is drawn as Arc draws a theme made in its editor: the colours at
    /// `solidAlpha(intensity)` over Arc's material (SidebarBackdrop's solid one, light or dark by
    /// appearance). A one-colour theme always is (31 Oct, 17 Nov 2026), and so is a gradient made in
    /// the editor: Arc 1.174 on a fake home under Dark (20 Nov 2026), Brand8 and its pair (#6CBAD9,
    /// #7F7EDC) at 0.8 read 144/187/210 over white and 94/139/162 over black at the top: α 0.63 =
    /// solidAlpha(0.8) of the first colour over 63 + 0.53·backdrop; at 0.3 α ≈ 0.34. Until #643 Cra
    /// drew it opaque, then (on the way) with the imported themes' fit, nearly opaque above 0.5. An
    /// imported vibrant theme keeps the stops that fit baked in (ArcThemeImport).
    public var drawnOverMaterial: Bool { solid || (vibrant && key != nil) }

    /// An editor gradient whose colours read dark: Arc saves it with `translucencyStyle` dark and draws it
    /// over a darker material than one colour's (SidebarBackdrop.solidActiveDarkGradient, #643).
    public var drawnOverDarkGradientMaterial: Bool { !solid && vibrant && key != nil && isDark }

    public var isDark: Bool {
        // Light and Dark from the theme editor keep a picked colour as it is, as Arc does, so its own
        // lightness picks the text (#392). Presets, imports and Auto's dark half have no pad colours;
        // Auto's light half has them lifted, so it still reads light.
        if appearance == "dark" || appearance == "light", let key, !key.isEmpty {
            return (colors.first.flatMap(HexColor.luminance) ?? 1) < 0.45
        }
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        // auto: judge by the first color's luminance
        return (colors.first.flatMap(HexColor.luminance) ?? 1) < 0.45
    }
}

public enum HexColor {
    public static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
    public static func luminance(_ hex: String) -> Double? {
        guard let c = components(hex) else { return nil }
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }
}

