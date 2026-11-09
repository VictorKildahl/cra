import Foundation

/// The colours of Arc's sidebar + menu (`ArcMenu.ArcMenuBackgroundView`, fed by the window's
/// `colorPalette`). Measured live on Arc 1.172.1 (9 Nov 2026, offline Arc, sRGB): the menu always
/// takes the space's DARK semantic palette, on a light space too. Fill = `dark.backgroundExtra`
/// ((17,13,0) on a gold space, (5,6,39) on Arc's default theme), row hover and the group
/// separators = `dark.hover` at its 0.48 over the fill ((81,70,26), (47,51,145)), shortcuts =
/// `dark.subtitle` ((126,119,94), (118,119,128)). Disabled rows are Arc's `MenuSubtitle` asset
/// (121,120,129) on every theme; titles and enabled glyphs are white.
public struct ArcMenuTones: Equatable, Sendable {
    public var fill: RGB
    public var hover: RGB
    public var separator: RGB
    public var shortcut: RGB
    public var disabled: RGB

    public static let disabledInk = RGB(121 / 255, 120 / 255, 129 / 255)

    public init(fill: RGB, hover: RGB, separator: RGB, shortcut: RGB, disabled: RGB = Self.disabledInk) {
        (self.fill, self.hover, self.separator, self.shortcut, self.disabled) = (fill, hover, separator, shortcut, disabled)
    }

    public init(shadedDark: RGB, shaded: RGB, midTone: RGB, tintedLight: RGB) {
        let slots = Dictionary(ArcThemeData.palette(shadedDark: shadedDark, shaded: shaded, midTone: midTone,
                                                    tintedLight: tintedLight, dark: true),
                               uniquingKeysWith: { a, _ in a })
        let fill = slots["backgroundExtra"]?.rgb ?? .black
        let hover = slots["hover"].map { fill.mixed(with: $0.rgb, $0.alpha) } ?? fill
        self.init(fill: fill, hover: hover, separator: hover, shortcut: slots["subtitle"]?.rgb ?? Self.disabledInk)
    }

    public init(theme: SpaceTheme) {
        self.init(shadedDark: theme.shadedDark, shaded: theme.shaded, midTone: theme.midTone, tintedLight: theme.tintedLight)
    }
}
