import CraCore
import Testing

/// Arc's semantic palette, as it stores it for a space (a gold theme: shadedDark #6F5600, midTone
/// #E9B300, tintedLight #FCEDBC), against what ArcThemeData builds from the same primaries.
struct ArcThemeDataTests {
    static func rgb(_ hex: Int) -> RGB { RGB(Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255, Double(hex & 0xff) / 255) }
    static let sd = rgb(0x6F5600), mid = rgb(0xE9B300), tl = rgb(0xFCEDBC)

    static func channelGap(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] { stride(from: 1, to: 7, by: 2).map { Int(s.dropFirst($0).prefix(2), radix: 16)! } }
        return zip(parts(a), parts(b)).map { abs($0 - $1) }.max()!
    }

    @Test(arguments: [
        (false, "title", "#211A00"), (false, "background", "#F1EEE3"), (false, "backgroundExtra", "#FEFDFC"),
        (false, "foregroundPrimary", "#E9B300"), (false, "foregroundTertiary", "#FCEDBC"), (false, "maxContrastColor", "#6F5600"),
        (false, "hover", "#E2DDC8"), (false, "subtitle", "#C6BB91"), (false, "focus", "#B7AA75"),
        (true, "title", "#E9E6D6"), (true, "background", "#211A00"), (true, "backgroundExtra", "#110D00"),
        (true, "foregroundPrimary", "#FCEDBC"), (true, "subtitle", "#7E775E"), (true, "cutoutColor", "#6F5600"),
        (true, "focus", "#8B7721CF"), (true, "hover", "#9684367A"),
    ])
    func matchesArcsStoredPalette(dark: Bool, slot: String, arc: String) throws {
        let ours = try #require(ArcThemeData.palette(shadedDark: Self.sd, shaded: Self.mid, midTone: Self.mid, tintedLight: Self.tl, dark: dark)
            .first { $0.0 == slot }).1.css
        let full = arc.count == 7 ? arc + "FF" : arc
        #expect(abs(Int(ours.suffix(2), radix: 16)! - Int(full.suffix(2), radix: 16)!) <= 1, "Arc's alpha, always written")
        #expect(Self.channelGap(ours, full) <= 9, "\(slot): \(ours) vs Arc's \(full)")
    }

    @Test func declaresEveryNameArcUses() {
        let css = ArcThemeData.declarations(palette: ArcThemeData.palette(shadedDark: Self.sd, shaded: Self.mid, midTone: Self.mid, tintedLight: Self.tl, dark: false),
                                            gradient: ["#F8D558", "#A4F454"])
        for name in ["title", "subtitle", "background", "backgroundExtra", "foregroundPrimary", "foregroundSecondary",
                     "foregroundTertiary", "focus", "hover", "cutoutColor", "maxContrastColor", "minContrastColor"] {
            #expect(css.contains("--arc-palette-\(name): #"))
        }
        #expect(css.contains("--arc-background-gradient-color1: #A4F454FF;"))
    }

    /// Measured live on Arc's default blue palette, dark scheme, 7 Nov 2026: what a page read from
    /// getComputedStyle, against the palette built from that palette's primaries (shadedDark #212AFB,
    /// shaded #3139FB, midTone #8489FB, tintedLight #ECEDFE, read off the same page).
    @Test(arguments: [
        ("title", "#DEDFFDFF"), ("subtitle", "#76777FFF"), ("background", "#0A0D4BFF"), ("backgroundExtra", "#050625FF"),
        ("foregroundPrimary", "#ECEDFEFF"), ("foregroundSecondary", "#8489FBFF"), ("foregroundTertiary", "#3139FBFF"),
        ("focus", "#4D54FBCE"), ("hover", "#5D64FB7A"), ("cutoutColor", "#212AFBFF"), ("maxContrastColor", "#ECEDFEFF"),
        ("minContrastColor", "#212AFBFF"),
    ])
    func matchesArcLiveOnItsDefaultTheme(slot: String, arc: String) throws {
        let palette = ArcThemeData.palette(shadedDark: Self.rgb(0x212AFB), shaded: Self.rgb(0x3139FB), midTone: Self.rgb(0x8489FB),
                                           tintedLight: Self.rgb(0xECEDFE), dark: true)
        let ours = try #require(palette.first { $0.0 == slot }).1.css
        #expect(abs(Int(ours.suffix(2), radix: 16)! - Int(arc.suffix(2), radix: 16)!) <= 1, "alpha within a level")
        #expect(Self.channelGap(ours, arc) <= 10, "\(slot): \(ours) vs Arc's \(arc)")
    }

    /// Measured live on Victor's gold space (dark scheme), 7 Nov 2026, against its primaries read off
    /// the same page (shadedDark #6B5709, shaded = midTone #E1B514, tintedLight #FAEEC2).
    @Test(arguments: [
        ("title", "#E9E6D7FF"), ("subtitle", "#7D7761FF"), ("background", "#201A00FF"), ("backgroundExtra", "#100D00FF"),
        ("foregroundPrimary", "#FAEEC2FF"), ("foregroundTertiary", "#E1B514FF"), ("focus", "#887832CE"), ("hover", "#9384437A"),
    ])
    func matchesArcLiveOnAGoldSpace(slot: String, arc: String) throws {
        let palette = ArcThemeData.palette(shadedDark: Self.rgb(0x6B5709), shaded: Self.rgb(0xE1B514), midTone: Self.rgb(0xE1B514),
                                           tintedLight: Self.rgb(0xFAEEC2), dark: true)
        let ours = try #require(palette.first { $0.0 == slot }).1.css
        #expect(abs(Int(ours.suffix(2), radix: 16)! - Int(arc.suffix(2), radix: 16)!) <= 1)
        #expect(Self.channelGap(ours, arc) <= 10, "\(slot): \(ours) vs Arc's \(arc)")
    }
}
