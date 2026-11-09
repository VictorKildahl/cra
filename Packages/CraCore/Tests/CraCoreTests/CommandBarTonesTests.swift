import CraCore
import Testing

/// Arc 1.172.1's ⌘T bar, measured live 9 Nov 2026 (offline Arc, sRGB window captures, Mac in Dark mode)
/// on a gold space (shadedDark #6F5600, midTone #E9B300, tintedLight #FCEDBC) and on Arc's default theme
/// (shadedDark #212AFB, shaded #3139FB, midTone #8489FB, tintedLight #ECEDFE). The panel under the
/// selected row reads ≈ 28 grey where it sits on the page.
struct CommandBarTonesTests {
    static func rgb(_ hex: Int) -> RGB { RGB(Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255, Double(hex & 0xff) / 255) }
    static let panel = RGB(28 / 255, 28 / 255, 28 / 255)
    static func gap(_ a: RGB, _ b: (Int, Int, Int)) -> Int {
        [abs(Int((a.r * 255).rounded()) - b.0), abs(Int((a.g * 255).rounded()) - b.1), abs(Int((a.b * 255).rounded()) - b.2)].max()!
    }
    static func onPanel(_ c: ArcThemeData.Color) -> RGB { panel.mixed(with: c.rgb, c.alpha) }

    static let gold = CommandBarTones(shadedDark: rgb(0x6F5600), shaded: rgb(0xE9B300), midTone: rgb(0xE9B300), tintedLight: rgb(0xFCEDBC), dark: true)
    static let arcDefault = CommandBarTones(shadedDark: rgb(0x212AFB), shaded: rgb(0x3139FB), midTone: rgb(0x8489FB), tintedLight: rgb(0xECEDFE), dark: true)

    @Test func theSelectedRowIsTheSpacesFocusColour() {
        #expect(Self.gap(Self.onPanel(Self.gold.selection), (121, 104, 33)) <= 8, "gold: \(Self.onPanel(Self.gold.selection))")
        #expect(Self.gap(Self.onPanel(Self.arcDefault.selection), (70, 77, 219)) <= 8, "default: \(Self.onPanel(Self.arcDefault.selection))")
        #expect(Self.gold.selection != Self.arcDefault.selection, "a themed space doesn't get the default theme's indigo")
    }

    @Test func theInfoBadgeIsTheSpacesBackgroundExtra() {
        #expect(Self.gap(Self.gold.badge, (17, 13, 0)) <= 1)
        #expect(Self.gap(Self.arcDefault.badge, (5, 6, 39)) <= 1)
    }
}
