import CraCore
import Testing

/// The Little Window's strip in the page's colour, and its controls and menu for a light or a dark strip.
struct LittleChromeTonesTests {
    static let space = SpaceTheme(colors: ["#D9F2E8"], intensity: 0.8, noise: 0, appearance: "auto", accent: "#D9F2E8")

    static func bytes(_ c: RGB) -> [Int] { [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } }
    static func contrast(_ a: RGB, _ b: RGB) -> Double { AskOnPageTone.contrast((a.r, a.g, a.b), (b.r, b.g, b.b)) }

    /// A page's colour fills the strip, as it fills a browser window's toolbar and Peek's bar.
    @Test
    func thePagesColourFillsTheStrip() {
        let navy = LittleChromeTones(page: "#1E2A44", target: Self.space, systemDark: false)
        #expect(Self.bytes(navy.left) == [0x1E, 0x2A, 0x44] && navy.left == navy.right)
        #expect(!navy.light)
        let white = LittleChromeTones(page: "#FFFFFF", target: Self.space, systemDark: true)
        #expect(Self.bytes(white.left) == [255, 255, 255] && white.light)
    }

    /// Before the page reports one, Little Arc's own strip for the Mac's appearance (Arc 1.174.3 follows macOS).
    @Test
    func withoutAPageColourTheStripFollowsMacOS() {
        let dark = LittleChromeTones(page: nil, target: Self.space, systemDark: true)
        #expect(dark.left == LittleStripTones.stripLeft && dark.right == LittleStripTones.stripRight && !dark.light)
        let light = LittleChromeTones(page: "", target: Self.space, systemDark: false)
        #expect(Self.bytes(light.left) == [0xEB, 0xEC, 0xFE] && Self.bytes(light.right) == [0xFE, 0xF5, 0xF5] && light.light)
    }

    /// On its own strips the controls keep Arc's measured colours: the dark Little Arc's, and 1.174.3's light one.
    @Test
    func arcsOwnStripsKeepArcsColours() {
        let dark = LittleChromeTones(page: nil, target: Self.space, systemDark: true)
        #expect(Self.bytes(dark.text) == [163, 161, 169] && Self.bytes(dark.button) == [5, 6, 37])
        #expect(Self.bytes(dark.label) == [130, 131, 146] && Self.bytes(dark.menuGlyph) == [80, 81, 102])
        #expect(dark.spaceName == LittleStripTones(target: Self.space, systemDark: true).spaceName)
        let light = LittleChromeTones(page: nil, target: Self.space, systemDark: false)
        #expect(Self.bytes(light.text) == [0x2F, 0x30, 0x33] && Self.bytes(light.button) == [0xFD, 0xFD, 0xFF])
        #expect(Self.bytes(light.label) == [0x91, 0x91, 0x91] && Self.bytes(light.menuTitle) == [0x31, 0x33, 0x34])
    }

    /// The address reads on any page's colour: 4.5:1, or as far as white or black can on a strip the browser window's
    /// toolbar also calls dark or light (white on #FF0000 is 4:1).
    @Test(arguments: ["#FF0000", "#8C8C8C", "#1E2A44", "#2E7D32", "#FFFFFF", "#F8D558", "#000000", "#6C2BD9"])
    func theAddressReadsOnThePagesColour(page: String) {
        let tones = LittleChromeTones(page: page, target: Self.space, systemDark: false)
        #expect(tones.light == ToolbarColor.isLight(hex: page))
        let best = min(4.5, Self.contrast(tones.light ? .black : .white, tones.left)) - 0.01
        #expect(Self.contrast(tones.text, tones.left) >= best, "address on \(page)")
        #expect(Self.contrast(tones.icon, tones.left) >= best, "icons on \(page)")
    }

    /// The space's name reads on the light button in a dark shade of its colour, as Arc 1.174.3 draws it.
    @Test
    func theSpaceNameIsDarkenedOnALightButton() {
        let tones = LittleChromeTones(page: "#FFFFFF", target: Self.space, systemDark: false)
        #expect(Self.contrast(tones.spaceName, tones.button) >= 4.5)
        let mint = SpaceTheme.hsb(0xD9 / 255, 0xF2 / 255, 0xE8 / 255).h
        #expect(abs(SpaceTheme.hsb(tones.spaceName.r, tones.spaceName.g, tones.spaceName.b).h - mint) < 0.02)
    }

    /// The padlock reads on any page's colour, a red one included (Arc's orange on #D32F2F was lost), and keeps
    /// Arc's orange where it already reads.
    @Test(arguments: ["#D32F2F", "#E93700", "#FF6A00", "#FFFFFF", "#1E2A44", "#000000", "#8C8C8C"])
    func thePadlockReadsOnThePagesColour(page: String) {
        let tones = LittleChromeTones(page: page, target: Self.space, systemDark: false)
        #expect(Self.contrast(tones.padlock, tones.left) >= 3 - 0.01, "padlock on \(page)")
    }

    @Test
    func thePadlockIsArcsOrangeWhereItReads() {
        #expect(Self.bytes(LittleChromeTones(page: "#FFFFFF", target: Self.space, systemDark: false).padlock) == [233, 55, 0])
        #expect(Self.bytes(LittleChromeTones(page: nil, target: Self.space, systemDark: true).padlock) == [233, 55, 0])
    }
}
