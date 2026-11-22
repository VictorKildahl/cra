import Foundation

/// The white veil a card with no page in it lays over the space's colour.
///
/// A window with no tab shows a white card, in the same inset and with the same shadow as a
/// page's: measured on Arc screenshots in light and dark spaces (17 Nov 2026), the card is the
/// colour beside it under white at about 0.65 to 0.68 light and 0.10 dark. An empty pane (a tab
/// whose page isn't there) is fainter: the gradient plus about +9/+11/+12 per channel, a white
/// veil at about 0.2 (Arc 1.170, Victor theme, 2x).
public enum CardVeil {
    /// - Parameters:
    ///   - noTab: the window's card with no tab selected, rather than a pane's card.
    ///   - dark: the space's theme is on its dark half.
    public static func white(noTab: Bool, dark: Bool) -> Double {
        noTab ? (dark ? 0.10 : 0.65) : (dark ? 0.08 : 0.2)
    }

    /// The card of a window with no tab, as Arc 1.174 draws it (offline Arc, 21 Nov 2026, issue #669: its card
    /// against the sidebar beside it over a white backdrop, five themes, View ▸ Appearance Light and Dark).
    /// It follows Arc's appearance, not how dark the theme's colours are: on Light white over the theme at
    /// about 0.69–0.80 (Cra keeps #483's 0.65); on Dark the theme with about +20/255 added on every
    /// channel (+17 to +22, from a pastel to navy), which a white veil matches as 0.08 / (1 − lightness).
    /// Cra keyed it on the theme, so a light theme on a dark Mac got a white card where Arc's stays faint.
    /// - Parameters:
    ///   - light: Arc's appearance is Light: the space's Light or Dark, or macOS for Auto (SpaceTheme.isLight).
    ///   - groundLightness: how light the colour under the card is, 0…1 (the theme's colours as shown).
    public static func noTabCard(light: Bool, groundLightness: Double) -> Double {
        guard !light else { return white(noTab: true, dark: false) }
        let l = min(max(groundLightness, 0), 0.99)
        return min(max(addedOnDark / (1 - l), addedOnDark), maxOnDark)
    }

    /// What Arc adds over a dark appearance's empty card: 20/255 on each channel.
    public static let addedOnDark = 0.08
    /// The most white a dark appearance's card takes: a white veil adds more where a channel is darker, so over a
    /// pastel ground (216, 190, 193 in Cra) 0.35 gives +14 to +23 against Arc's even +18 (0.45 gave up to +29).
    public static let maxOnDark = 0.35

    /// The lightness of a theme's colours as drawn, the mean of their channels (0…1).
    public static func lightness(of hexes: [String]) -> Double {
        let parts = hexes.compactMap(HexColor.components)
        guard !parts.isEmpty else { return 0.5 }
        return parts.map { ($0.r + $0.g + $0.b) / 3 }.reduce(0, +) / Double(parts.count)
    }
}
