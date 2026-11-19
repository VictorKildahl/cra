import Foundation

/// The Little Window strip's colours for the space "Open in" names (Arc's Little Arc).
///
/// Arc draws the strip from its default theme's dark palette in every space. Measured on 1.168 with
/// the yellow "Victor" space focused, and on 1.172.1, where every sampled pixel stayed the same when
/// switching between two spaces (#329). Only the space's name in "Open in <Space>" takes the space's
/// colour (Arc: `semanticColorPalette.dark.foregroundPrimary`; Victor → #FCEDBC). #549 reported the
/// unthemed strip as a bug; it stays as Arc has it.
public struct LittleStripTones: Equatable, Sendable {
    /// Arc 1.172.1's strip, left to right (10 Nov 2026, 2x window captures of a 1185 pt window: #242438 at
    /// the left end, #26243A, #292839 and #2C2439 between, #312339 at the right).
    public static let stripLeft = RGB(0x24 / 255, 0x24 / 255, 0x38 / 255)
    public static let stripRight = RGB(0x31 / 255, 0x23 / 255, 0x39 / 255)

    public var left: RGB
    public var right: RGB
    /// The space's name in "Open in <Space>", and the Peek buttons' glyphs: the space's colour (its
    /// accent, else its first colour) 72 % of the way to white.
    public var spaceName: RGB

    public init(target theme: SpaceTheme, systemDark: Bool) {
        let shown = theme.resolved(systemDark: systemDark)
        let c = HexColor.components(shown.accent ?? shown.colors.first ?? "#FFFFFF") ?? (0.5, 0.5, 0.5)
        left = Self.stripLeft
        right = Self.stripRight
        spaceName = RGB(c.r, c.g, c.b).mixed(with: .white, 0.72)
    }
}
