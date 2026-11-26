import Foundation

/// The colours of Arc's sidebar + menu (`ArcMenu.ArcMenuBackgroundView`, fed by the window's
/// `colorPalette`). It takes the half of the space's semantic palette that matches the Mac's appearance:
/// dark in Dark mode, light in Light mode, whatever the space (Arc 1.174.2, 26 Nov 2026, one light space captured
/// in both; #822, whose reporter's Arc showed it light. The 9 Nov measurement, below, ran in Dark mode only). Fill = `dark.backgroundExtra`
/// ((17,13,0) on a gold space, (5,6,39) on Arc's default theme), row hover and the group
/// separators = `dark.hover` at its 0.48 over the fill ((81,70,26), (47,51,145)), shortcuts =
/// `dark.subtitle` ((126,119,94), (118,119,128)). Disabled rows are Arc's `MenuSubtitle` asset
/// (121,120,129) on every theme; titles and enabled glyphs are white. In Light mode: fill `light.backgroundExtra`
/// ((254,253,252) on that gold space), separators `light.hover`, shortcuts `light.subtitle`, disabled rows
/// `MenuDisabledText`'s light value (171,171,171) (ARC_ArcMenu.bundle), titles and glyphs black.
public struct ArcMenuTones: Equatable, Sendable {
    public var fill: RGB
    public var hover: RGB
    public var separator: RGB
    public var shortcut: RGB
    public var disabled: RGB
    /// Titles and enabled glyphs.
    public var ink: RGB

    public static let disabledInk = RGB(121 / 255, 120 / 255, 129 / 255)
    public static let disabledInkLight = RGB(171 / 255, 171 / 255, 171 / 255)

    public init(fill: RGB, hover: RGB, separator: RGB, shortcut: RGB, disabled: RGB = Self.disabledInk, ink: RGB = RGB(1, 1, 1)) {
        (self.fill, self.hover, self.separator, self.shortcut, self.disabled, self.ink) = (fill, hover, separator, shortcut, disabled, ink)
    }

    /// `dark`: the Mac's appearance where the menu shows (Dark mode).
    public init(shadedDark: RGB, shaded: RGB, midTone: RGB, tintedLight: RGB, dark: Bool = true) {
        let slots = Dictionary(ArcThemeData.palette(shadedDark: shadedDark, shaded: shaded, midTone: midTone,
                                                    tintedLight: tintedLight, dark: dark),
                               uniquingKeysWith: { a, _ in a })
        let fill = slots["backgroundExtra"]?.rgb ?? (dark ? .black : RGB(1, 1, 1))
        let hover = slots["hover"].map { fill.mixed(with: $0.rgb, $0.alpha) } ?? fill
        let disabled = dark ? Self.disabledInk : Self.disabledInkLight
        self.init(fill: fill, hover: hover, separator: hover, shortcut: slots["subtitle"]?.rgb ?? disabled,
                  disabled: disabled, ink: dark ? RGB(1, 1, 1) : RGB(0, 0, 0))
    }

    public init(theme: SpaceTheme, dark: Bool = true) {
        self.init(shadedDark: theme.shadedDark, shaded: theme.shaded, midTone: theme.midTone, tintedLight: theme.tintedLight, dark: dark)
    }
}
