import Foundation

/// Ideas #366, not in Arc: the colour of the now-playing cards over the bottom of the tab list.
/// `.arc` is Arc's own (NowPlayingColors: near-white on a light space, 15 % of the theme's deep shade
/// over black on a dark one). `.theme` fills a card like a selected tab, the sidebar's own colour
/// under Arc's selected-row white, made opaque so the cards stacked behind it don't show through.
public enum NowPlayingTint: String, Codable, Sendable, CaseIterable {
    case arc
    case theme

    /// A selected tab's white over the sidebar: 13 % on a dark space, 74 % on a light one
    /// (SpacePalette.selectedFill).
    public static func selectedWhite(dark: Bool) -> Double { dark ? 0.13 : 0.74 }

    /// The `.theme` card's fill over the sidebar's colour where the cards sit (`ground`, opaque
    /// sRGB 0…1): that colour with a selected tab's white laid over it.
    public static func themeFill(ground: (r: Double, g: Double, b: Double), dark: Bool) -> (r: Double, g: Double, b: Double) {
        let w = selectedWhite(dark: dark)
        func over(_ c: Double) -> Double { min(1, max(0, c)) * (1 - w) + w }
        return (over(ground.r), over(ground.g), over(ground.b))
    }
}
