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
        onSite(of: url, from: boosts).filter(\.enabled)
    }

    /// Every boost on a page's site, on or off: the Site Control Center's Boosts section (#478).
    public static func onSite(of url: String, from boosts: [Boost]) -> [Boost] {
        guard let host = URL(string: url)?.host.map(siteHost) else { return [] }
        return boosts.filter { host == $0.host || host.hasSuffix("." + $0.host) }
    }

    /// Whether the editor's colour controls are at the site's own colours.
    public var colorsUntouched: Bool { strength == 0 && !invert && contrast == 50 && brightness == 50 && saturation == 50 }

    /// The stylesheet the page gets.
    public var stylesheet: String { stylesheet(engineTints: false) }

    /// The tint as Arc draws it (#602): a colorize in sRGB's HSL that leaves images alone. Measured in an offline
    /// Arc 1.174 on 21 Nov 2026 (40 swatches at 18 handle positions, within 3/255 on average, 8 at most):
    /// a colour keeps its lightness, squeezed into a band that narrows with the strength, and takes the big
    /// handle's hue when light and the small one's (an eighth of a turn on) when dark, with the saturation the
    /// handle adds plus half its own. So every saturated colour of one lightness becomes the same colour.
    /// Cra's Chromium engine draws every colour of the page but its images through it. nil without a tint.
    public var tint: Colorize? {
        guard strength > 0 else { return nil }
        let added = 0.5 * pow(min(1, strength), 1.2)
        return Colorize(hue: hue, darkHue: BoostWheel.accentOffset, saturationAdded: added, saturationKept: 0.5,
                        lightnessAtBlack: 0.4 * added, lightnessScale: 1 - 0.6 * added)
    }

    /// Arc's Boost colorize, in sRGB's HSL: hue = `hue` + `darkHue` × (1 − l) turns, saturation = `saturationAdded`
    /// + `saturationKept` × s, lightness = `lightnessAtBlack` + `lightnessScale` × l.
    public struct Colorize: Equatable, Sendable {
        public var hue, darkHue, saturationAdded, saturationKept, lightnessAtBlack, lightnessScale: Double

        /// What the engine reads (cc::ColorFilter::MakeCraColorize): the six numbers in that order.
        public var engineString: String {
            [hue, darkHue, saturationAdded, saturationKept, lightnessAtBlack, lightnessScale]
                .map { String(format: "%.6g", $0) }.joined(separator: ",")
        }

        /// An sRGB colour (0–1) as the page draws it under the tint.
        public func apply(_ r: Double, _ g: Double, _ b: Double) -> (r: Double, g: Double, b: Double) {
            let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
            let s = d <= 0 ? 0 : d / (1 - abs(2 * l - 1))
            let h = hue + darkHue * (1 - l)
            let sat = max(0, min(1, saturationAdded + saturationKept * s))
            let light = max(0, min(1, lightnessAtBlack + lightnessScale * l))
            let q = light < 0.5 ? light * (1 + sat) : light + sat - light * sat, p = 2 * light - q
            func channel(_ t: Double) -> Double {
                let t = t - floor(t)
                if t < 1.0 / 6 { return p + (q - p) * 6 * t }
                if t < 0.5 { return q }
                if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
                return p
            }
            return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
        }
    }

    /// The stylesheet, without the tint's filter when the engine draws the tint itself (`tint`), so the
    /// page's images keep their colours (#602).
    public func stylesheet(engineTints: Bool) -> String {
        var rules: [String] = []
        var filters: [String] = []
        if invert { filters.append("invert(1) hue-rotate(180deg)") }
        if strength > 0, !engineTints {
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
