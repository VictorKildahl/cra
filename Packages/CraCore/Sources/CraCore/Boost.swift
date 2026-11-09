import Foundation

/// Arc's Boosts (Arc 1.172.1, its editor captured on 7 Nov 2026; docs/arc-parity.md "Boosts,
/// measured"): a site's own restyle, kept per host. The editor's controls, top to bottom: a colour
/// wheel (a tint: hue round the wheel, strength out from the middle), Invert lightness, Advanced
/// colour controls (Contrast, Brightness, Original Saturation, 0–100, 50 = as the site is), Reset
/// colours, a grid of 20 fonts, Size, Case, Zap (hide what you click) and Code (your own CSS and JS).
public struct Boost: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// The site it applies to: a host, without "www.".
    public var host: String
    public var name: String
    public var enabled: Bool
    /// The tint: hue 0–1 round the wheel, strength 0–1 out from the middle (0: no tint).
    public var hue: Double
    public var strength: Double
    public var invert: Bool
    public var contrast: Double
    public var brightness: Double
    public var saturation: Double
    /// One of `fonts` by index, nil for the site's own.
    public var font: Int?
    /// Text size, 1 = the site's own.
    public var textScale: Double
    public var textCase: TextCase
    /// CSS selectors of what Zap hid.
    public var zapped: [String]
    public var css: String
    public var js: String

    public enum TextCase: String, Codable, CaseIterable, Sendable {
        case none, upper, lower, capitalize
        public var title: String {
            switch self {
            case .none: "As Is"
            case .upper: "UPPERCASE"
            case .lower: "lowercase"
            case .capitalize: "Title Case"
            }
        }
    }

    public init(id: UUID = UUID(), host: String, name: String = "My Boost") {
        self.id = id
        self.host = Self.siteHost(host)
        self.name = name
        enabled = true
        hue = 0; strength = 0; invert = false
        contrast = 50; brightness = 50; saturation = 50
        font = nil; textScale = 1; textCase = .none
        zapped = []; css = ""; js = ""
    }

    /// The 20 fonts of the editor's grid (Arc ships its own; these are the Mac's), 5 to a row.
    public static let fonts = [
        "-apple-system", "ui-rounded", "ui-serif", "ui-monospace", "Helvetica Neue",
        "Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia",
        "Palatino", "Baskerville", "Didot", "American Typewriter", "Menlo",
        "Snell Roundhand", "Copperplate", "Chalkboard SE", "Rockwell", "Marker Felt",
    ]

    /// The host a boost is keyed by: lowercased, "www." dropped.
    public static func siteHost(_ host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// The boost for a page, if one applies: same host, or a subdomain of it.
    public static func applying(to url: String, from boosts: [Boost]) -> [Boost] {
        guard let host = URL(string: url)?.host.map(siteHost) else { return [] }
        return boosts.filter { $0.enabled && (host == $0.host || host.hasSuffix("." + $0.host)) }
    }

    /// Whether the editor's colour controls are at the site's own colours.
    public var colorsUntouched: Bool { strength == 0 && !invert && contrast == 50 && brightness == 50 && saturation == 50 }

    /// The stylesheet the page gets.
    public var stylesheet: String {
        var rules: [String] = []
        var filters: [String] = []
        if invert { filters.append("invert(1) hue-rotate(180deg)") }
        if strength > 0 {
            // A tint: the page washed toward the hue, as much as the handle is out from the middle.
            filters.append("sepia(\(fmt(strength)))")
            filters.append("hue-rotate(\(fmt(hue * 360 - 38))deg)")
            filters.append("saturate(\(fmt(1 + strength * 2)))")
        }
        if contrast != 50 { filters.append("contrast(\(fmt(contrast / 50)))") }
        if brightness != 50 { filters.append("brightness(\(fmt(brightness / 50)))") }
        if saturation != 50 { filters.append("saturate(\(fmt(saturation / 50)))") }
        if !filters.isEmpty {
            rules.append("html { filter: \(filters.joined(separator: " ")) !important; }")
            // Pictures and video keep their own colours under an inverted page.
            if invert { rules.append("img, video, picture, canvas, iframe, svg image { filter: invert(1) hue-rotate(180deg) !important; }") }
        }
        if let font, Self.fonts.indices.contains(font) {
            rules.append("body, body * { font-family: \"\(Self.fonts[font])\", sans-serif !important; }")
        }
        if textScale != 1 { rules.append("html { zoom: \(fmt(textScale)) !important; }") }
        switch textCase {
        case .none: break
        case .upper: rules.append("body, body * { text-transform: uppercase !important; }")
        case .lower: rules.append("body, body * { text-transform: lowercase !important; }")
        case .capitalize: rules.append("body, body * { text-transform: capitalize !important; }")
        }
        if !zapped.isEmpty { rules.append(zapped.joined(separator: ", ") + " { display: none !important; }") }
        if !css.isEmpty { rules.append(css) }
        return rules.joined(separator: "\n")
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3g", v) }
}

/// How Arc 1.172.1's Boost editor moves (60 fps screen recordings of Victor's Arc, 7 Nov 2026).
/// Opening: the panel is there at 85 % on the first frame and grows to full size in 0.28 s about
/// the middle of its right edge, with no fade. Closing: gone from one frame to the next. Code
/// widens it (183 → 480 pt, the left edge moving) in 0.35 s; Back narrows it in 0.13 s. All three
/// follow an ease-out close to quadratic.
public enum BoostEditorMotion {
    public static let openScale = 0.85
    public static let openDuration = 0.28
    public static let widenDuration = 0.35
    public static let narrowDuration = 0.13
    /// The quadratic ease-out as a cubic Bézier's control points (x1, y1, x2, y2).
    public static let easeOut = (0.25, 0.46, 0.45, 0.94)
    /// The panel's anchor while it grows, in its own unit square from the bottom left.
    public static let openAnchor = (x: 1.0, y: 0.5)

    public static func resizeDuration(fromWidth old: Double, to new: Double) -> Double {
        new == old ? 0 : new > old ? widenDuration : narrowDuration
    }
}
