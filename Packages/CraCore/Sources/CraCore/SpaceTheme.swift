import Foundation

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

    public init(colors: [String], intensity: Double, noise: Double, appearance: String, vibrant: Bool = false, accent: String? = nil,
         solid: Bool = false) {
        self.colors = colors
        self.intensity = intensity
        self.noise = noise
        self.appearance = appearance
        self.vibrant = vibrant
        self.accent = accent
        self.solid = solid
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

    public var isDark: Bool {
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

