import Foundation

/// The space's colours in Arc's command bar (`CommandBar.SuggestionsView` takes its row theme from the
/// window's palette). Measured live on Arc 1.172.1 (9 Nov 2026, offline Arc, sRGB, Mac in Dark mode): the
/// bar uses the semantic palette of its own appearance, dark over a light space too. The selected row is
/// the palette's `focus` colour: (121,104,33) on a gold space, (70,77,219) on Arc's default theme, which
/// both fit `focus` at 0.86 over the panel where it sits on the page (≈ 28 grey) within 8/255.
/// The info badge right of the empty field is filled with `backgroundExtra` ((17,13,0), (5,6,39)).
public struct CommandBarTones: Equatable, Sendable {
    public var selection: ArcThemeData.Color
    public var badge: RGB

    public static let selectionAlpha = 0.86

    public init(selection: ArcThemeData.Color, badge: RGB) { (self.selection, self.badge) = (selection, badge) }

    public init(shadedDark: RGB, shaded: RGB, midTone: RGB, tintedLight: RGB, dark: Bool) {
        let slots = Dictionary(ArcThemeData.palette(shadedDark: shadedDark, shaded: shaded, midTone: midTone,
                                                    tintedLight: tintedLight, dark: dark),
                               uniquingKeysWith: { a, _ in a })
        self.init(selection: ArcThemeData.Color(slots["focus"]?.rgb ?? shadedDark, Self.selectionAlpha),
                  badge: slots["backgroundExtra"]?.rgb ?? (dark ? .black : .white))
    }

    public init(theme: SpaceTheme, dark: Bool) {
        self.init(shadedDark: theme.shadedDark, shaded: theme.shaded, midTone: theme.midTone, tintedLight: theme.tintedLight, dark: dark)
    }
}
