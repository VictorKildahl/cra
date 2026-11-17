import Foundation

/// The command bar in the site's colour while Tab's site search is on (GitHub #457, not in Arc):
/// Settings ▸ Advanced ▸ Command bar ▸ "Fill the command bar with the site’s color". Arc keeps its
/// bar neutral and shows the site in the pill and a one-second wash only (CommandBarView's
/// splash), which stays the default.
///
/// The look is the one in #457's video (Zen-style): the bar holds the site's hue at one saturation
/// and lightness, whatever the site's own colour is. Its fills were (74,33,39) for YouTube (#FF0033)
/// and (37,53,75) for Google (#4285F4), both close to HSL(hue, 36 %, 21.5 %). A light bar takes the
/// same hue as a pale wash, so the dark text stays readable.
public enum ScopedSearchFill {
    public static let saturation = 0.36
    public static let darkLightness = 0.215
    public static let lightSaturation = 0.55
    public static let lightLightness = 0.92

    /// The bar's fill for a site search, nil for the bar's own. `siteColor` is the site's "#RRGGBB"
    /// (SiteSearch.color); a site without one takes `space`, the space's colour, as its pill does.
    /// A grey or black colour (X's) has no hue to fill with, so the bar keeps its own.
    public static func fill(enabled: Bool, siteColor: String?, space: RGB, dark: Bool) -> RGB? {
        guard enabled else { return nil }
        let brand = siteColor.flatMap(HexColor.components).map { RGB($0.r, $0.g, $0.b) } ?? space
        let (h, s, _) = hsl(brand)
        guard s >= 0.08 else { return nil }
        return dark ? rgb(h: h, s: saturation, l: darkLightness) : rgb(h: h, s: lightSaturation, l: lightLightness)
    }

    /// Hue 0..<1, saturation and lightness 0...1.
    static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        let l = (mx + mn) / 2
        guard d > 0.00001 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, l)
    }

    static func rgb(h: Double, s: Double, l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch Int(hp) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGB(r + m, g + m, b + m)
    }
}
