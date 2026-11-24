import Foundation

/// Behind the status bar over a page, Arc Search draws a solid band in the page's colour, so the time
/// and battery stay readable while the page's text scrolls under them (#657, the reporter's screenshot
/// of Arc Search: a purple site under a purple band). Cra's page ran up under a see-through status bar.
public enum MobileStatusBand {
    /// The band's colour, as hex: the page's theme-color, else the colour WebKit paints past the
    /// page's edges (its underPageBackgroundColor, the page's own background). nil: no band.
    public static func fill(themeColor: String?, underPage: String?) -> String? {
        themeColor ?? underPage
    }

    /// Whether the band shows: over a page shown full size, and not while the tab row is up,
    /// whose cards carry their own bands. The search sheet shrinks the band with the page instead
    /// of hiding it, so it does not come into this.
    public static func shown(hasPage: Bool, switching: Bool) -> Bool {
        hasPage && !switching
    }

    /// White time and battery over a dark band, black over a light one.
    public static func lightContent(fill: String) -> Bool {
        (HexColor.luminance(fill) ?? 1) < 0.5
    }
}
