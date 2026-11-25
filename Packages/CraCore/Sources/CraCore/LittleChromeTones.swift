import Foundation

/// The Little Window's colours: its strip in the page's colour, as a browser window's toolbar and Peek's bar
/// (ToolbarColor, #629), and the strip's controls and the "Open in" menu drawn for a light or a dark strip.
///
/// Until the page reports a colour the strip is Little Arc's own for the Mac's appearance: the dark gradient of
/// 1.172.1 (LittleStripTones) on a dark Mac, the light one of 1.174.3 on a light Mac. Arc 1.174.3's strip follows
/// macOS and never the page (a white, a navy and a green page gave the same strip, light and dark Mac, 25 Nov 2026).
/// The dark set is Arc's dark Little Arc as measured before; the light set is 1.174.3's light Little Arc.
public struct LittleChromeTones: Equatable, Sendable {
    /// Arc 1.174.3's strip on a light Mac, left to right (2x window captures, 25 Nov 2026).
    public static let lightStripLeft = RGB(0xEB / 255, 0xEC / 255, 0xFE / 255)
    public static let lightStripRight = RGB(0xFE / 255, 0xF5 / 255, 0xF5 / 255)

    /// A colour laid over the strip: white or black at `alpha`, so it follows the strip's colour.
    public typealias Wash = ToolbarColor.Fill

    public var left: RGB
    public var right: RGB
    /// Whether the strip is light: dark ink on it, and the light "Open in" button and menu.
    public var light: Bool
    public var pill: Wash
    public var pillHover: Wash
    /// The address and the profile chip's name.
    public var text: RGB
    public var icon: RGB
    public var iconHot: RGB
    public var iconHover: Wash
    public var chip: Wash
    public var chipHover: Wash
    /// "Open in" and the chevron.
    public var label: RGB
    public var button: RGB
    public var buttonBorder: RGB
    public var buttonHover: RGB
    public var badge: RGB
    public var badgeText: RGB
    /// The menu's magnifier, ∧ and "No results".
    public var menuGlyph: RGB
    public var menuPlaceholder: RGB
    public var menuTitle: RGB
    /// The space's name in "Open in <Space>": its colour lightened on a dark button, darkened on a light one until it
    /// reads (Arc 1.174.3: a mint space's green as #0F7636 on the light button).
    public var spaceName: RGB
    /// The open padlock for a page that isn't served over https (#330): Arc's orange, its lightness moved until it
    /// reads on the strip as a graphic does (3:1), so it doesn't vanish on a red or an orange page.
    public var padlock: RGB

    /// `page`: the colour the page reported ("#RRGGBB"), nil or malformed before it has one.
    public init(page: String?, target theme: SpaceTheme, systemDark: Bool) {
        let dark = LittleStripTones(target: theme, systemDark: systemDark)
        let reported = ToolbarColor.hex(reported: page, remembered: nil)
        let pageColour = reported.flatMap(HexColor.components).map { RGB($0.r, $0.g, $0.b) }
        light = reported.map { ToolbarColor.isLight(hex: $0) } ?? !systemDark
        left = pageColour ?? (systemDark ? dark.left : Self.lightStripLeft)
        right = pageColour ?? (systemDark ? dark.right : Self.lightStripRight)
        // Arc's inks on its own strip; on a page's colour (a red, a mid grey) the same inks, taken further from
        // the strip until they read on it.
        let strip = left, isLight = light
        padlock = Self.graphic(Self.rgb(233, 55, 0), on: strip, lighter: !isLight)
        func ink(_ measured: RGB) -> RGB {
            guard pageColour != nil else { return measured }
            let c = AskOnPageTone.readable((measured.r, measured.g, measured.b), on: (strip.r, strip.g, strip.b), lighter: !isLight)
            return RGB(c.r, c.g, c.b)
        }
        guard light else {
            pill = Wash(white: 1, alpha: 0.09)
            pillHover = Wash(white: 1, alpha: 0.14)
            text = ink(Self.rgb(163, 161, 169))
            icon = ink(Self.rgb(110, 111, 128))
            iconHot = ink(Self.rgb(170, 168, 180))
            // Arc's #413946 over the pill's #38394A.
            iconHover = Wash(white: 1, alpha: 0.05)
            chip = Wash(white: 1, alpha: 31 / 255)
            chipHover = Wash(white: 1, alpha: 46 / 255)
            label = Self.rgb(130, 131, 146)
            button = Self.rgb(5, 6, 37)
            buttonBorder = Self.rgb(29, 30, 55)
            buttonHover = Self.rgb(22, 23, 52)
            badge = Self.rgb(23, 24, 50)
            badgeText = Self.rgb(139, 140, 153)
            menuGlyph = Self.rgb(80, 81, 102)
            menuPlaceholder = Self.rgb(142, 143, 157)
            menuTitle = RGB.white.mixed(with: button, 0.18)
            spaceName = dark.spaceName
            return
        }
        // Arc 1.174.3, light Mac: the pill a faint grey over the strip, #2F3033 text, the button #FDFDFF with "Open in"
        // #919191, a #EEEEF0 badge with #888889 text and a #BFBEBF chevron; the menu #FDFDFF with a #F6F6F8
        // highlight, #313334 names, a #BFBFC0 magnifier and a #919192 placeholder. The hovers weren't measured.
        pill = Wash(white: 0, alpha: 0.04)
        pillHover = Wash(white: 0, alpha: 0.07)
        text = ink(Self.rgb(0x2F, 0x30, 0x33))
        icon = ink(Self.rgb(0xB3, 0xAD, 0xB0))
        iconHot = text
        iconHover = Wash(white: 0, alpha: 0.06)
        chip = Wash(white: 0, alpha: 0.05)
        chipHover = Wash(white: 0, alpha: 0.09)
        label = Self.rgb(0x91, 0x91, 0x91)
        button = Self.rgb(0xFD, 0xFD, 0xFF)
        buttonBorder = Self.rgb(0xE9, 0xE9, 0xEA)
        buttonHover = Self.rgb(0xF6, 0xF6, 0xF8)
        badge = Self.rgb(0xEE, 0xEE, 0xF0)
        badgeText = Self.rgb(0x88, 0x88, 0x89)
        menuGlyph = Self.rgb(0xBF, 0xBF, 0xC0)
        menuPlaceholder = Self.rgb(0x91, 0x91, 0x92)
        menuTitle = Self.rgb(0x31, 0x33, 0x34)
        let shown = theme.resolved(systemDark: systemDark)
        let c = HexColor.components(shown.accent ?? shown.colors.first ?? "#888888") ?? (0.5, 0.5, 0.5)
        let ink = AskOnPageTone.readable(c, on: (button.r, button.g, button.b), lighter: false)
        spaceName = RGB(ink.r, ink.g, ink.b)
    }

    /// `c` with its HSL lightness stepped until it reaches 3:1 on `bg` (WCAG's minimum for a graphic), hue kept:
    /// lighter or darker as asked, the other way when that end can't reach it (white on a bright orange is 2.6:1).
    static func graphic(_ c: RGB, on bg: RGB, lighter: Bool) -> RGB {
        let (h, s, l0) = AskOnPageTone.hsl((c.r, c.g, c.b))
        func reads(_ l: Double) -> Bool { AskOnPageTone.contrast(AskOnPageTone.at(h, s, l), (bg.r, bg.g, bg.b)) >= 3 }
        func stepped(lighter: Bool) -> Double {
            var l = l0
            while !reads(l), lighter ? l < 1 : l > 0 { l = lighter ? min(1, l + 0.005) : max(0, l - 0.005) }
            return l
        }
        var l = stepped(lighter: lighter)
        if !reads(l) { l = stepped(lighter: !lighter) }
        let x = AskOnPageTone.at(h, s, l)
        return RGB(x.r, x.g, x.b)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> RGB { RGB(Double(r) / 255, Double(g) / 255, Double(b) / 255) }
}
