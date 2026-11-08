import Foundation

/// Arc's Settings ▸ Advanced "Allow websites to get your theme data": pages get the space's
/// semantic palette as CSS variables (`--arc-palette-title` … `--arc-palette-minContrastColor`, names
/// from Arc 1.172.1's binary). Arc stores that palette per space (StorableSidebar.json
/// `semanticColorPalette.appearanceBased`); each slot is the primary palette (shadedDark, midTone,
/// tintedLight) or a mix of it with white or black, fitted to Arc's stored values (exact to 1/255
/// except focus, hover and the light subtitle, within 9/255), and checked live on Arc's default blue
/// space (dark scheme). Arc puts them on the page without touching its DOM (no inline style, no
/// <style>); Cra adopts a stylesheet from its isolated world, which the page's markup doesn't show.
public enum ArcThemeData {
    public struct Color: Equatable, Sendable {
        public var rgb: RGB
        public var alpha: Double
        public init(_ rgb: RGB, _ alpha: Double = 1) { (self.rgb, self.alpha) = (rgb, alpha) }

        /// `#RRGGBBAA`, alpha always written, as Arc writes them (measured live, Arc 1.172.1).
        public var css: String {
            func b(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
            return String(format: "#%02X%02X%02X%02X", b(rgb.r), b(rgb.g), b(rgb.b), b(alpha))
        }
    }

    /// Arc's semantic palette for one scheme, slot name → colour, in Arc's slot names.
    public static func palette(shadedDark sd: RGB, shaded: RGB, midTone mid: RGB, tintedLight tl: RGB, dark: Bool) -> [(String, Color)] {
        let w = RGB.white, k = RGB.black
        if dark {
            return [
                ("title", Color(w.mixed(with: sd, 0.157))), ("subtitle", Color(k.mixed(with: tl, 0.5))),
                ("background", Color(k.mixed(with: sd, 0.3))), ("backgroundExtra", Color(k.mixed(with: sd, 0.15))),
                ("foregroundPrimary", Color(tl)), ("foregroundSecondary", Color(mid)), ("foregroundTertiary", Color(shaded)),
                ("focus", Color(w.mixed(with: sd, 0.842), 0.81)), ("hover", Color(w.mixed(with: sd, 0.762), 0.48)),
                ("cutoutColor", Color(sd)), ("maxContrastColor", Color(tl)), ("minContrastColor", Color(sd)),
            ]
        }
        return [
            ("title", Color(k.mixed(with: sd, 0.3))), ("subtitle", Color(k.mixed(with: tl, 0.782))),
            ("background", Color(w.mixed(with: sd, 0.105))), ("backgroundExtra", Color(w.mixed(with: sd, 0.01))),
            ("foregroundPrimary", Color(shaded)), ("foregroundSecondary", Color(mid)), ("foregroundTertiary", Color(tl)),
            ("focus", Color(w.mixed(with: sd, 0.523))), ("hover", Color(w.mixed(with: sd, 0.209))),
            ("cutoutColor", Color(tl)), ("maxContrastColor", Color(sd)), ("minContrastColor", Color(tl)),
        ]
    }

    /// The palette of a Cra space theme in the scheme its pages see.
    public static func palette(theme: SpaceTheme, dark: Bool) -> [(String, Color)] {
        palette(shadedDark: theme.shadedDark, shaded: theme.shaded, midTone: theme.midTone, tintedLight: theme.tintedLight, dark: dark)
    }

    /// The `:root` declarations a page gets: the palette, then the background's colours.
    public static func declarations(palette: [(String, Color)], gradient: [String]) -> String {
        var out = palette.map { "--arc-palette-\($0.0): \($0.1.css);" }
        // A one-colour theme is Arc's simple background, more colours its gradient (#RRGGBBAA too).
        let colors = gradient.map { HexColor.components($0).map { Color(RGB($0.r, $0.g, $0.b)).css } ?? $0 }
        if colors.count == 1 { out.append("--arc-background-simple-color: \(colors[0]);") }
        else { for (i, c) in colors.prefix(3).enumerated() { out.append("--arc-background-gradient-color\(i): \(c);") } }
        return out.joined(separator: " ")
    }
}
