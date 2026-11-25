import CraCore
import Testing

/// A light, colourless favicon is drawn in the row's colour on ⌘T's white tile, not white on white (#755).
@Suite struct FaviconInkTests {
    /// A 10×10 icon: `ink` where `isInk(x, y)`, else `ground`; premultiplied RGBA.
    static func icon(ink: (UInt8, UInt8, UInt8, UInt8), ground: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0),
                     _ isInk: (Int, Int) -> Bool) -> [UInt8] {
        var p: [UInt8] = []
        for y in 0..<10 { for x in 0..<10 { let c = isInk(x, y) ? ink : ground; p += [c.0, c.1, c.2, c.3] } }
        return p
    }
    /// GitHub's octocat, roughly: a disc with see-through parts.
    static func disc(_ x: Int, _ y: Int) -> Bool { let dx = x - 5, dy = y - 5; return dx * dx + dy * dy <= 16 && !(y == 4 && (x == 3 || x == 7)) }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/755"))
    func githubsWhiteOctocatIsALightMark() {
        let ink = FaviconInk(rgbaPremultiplied: Self.icon(ink: (255, 255, 255, 255), Self.disc))
        #expect(ink.isLightMark)
        // Its light grey edge pixels too (#F0F6FC, GitHub's dark-mode foreground).
        #expect(FaviconInk(rgbaPremultiplied: Self.icon(ink: (240, 246, 252, 255), Self.disc)).isLightMark)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/755"))
    func iconsThatShowOnWhiteStayAsTheyAre() {
        // The black octocat of a light page.
        #expect(!FaviconInk(rgbaPremultiplied: Self.icon(ink: (31, 35, 40, 255), Self.disc)).isLightMark)
        // A coloured icon.
        #expect(!FaviconInk(rgbaPremultiplied: Self.icon(ink: (66, 133, 244, 255), Self.disc)).isLightMark)
        // A pale but coloured one (a light yellow star).
        #expect(!FaviconInk(rgbaPremultiplied: Self.icon(ink: (255, 236, 140, 255), Self.disc)).isLightMark)
        // A white glyph on a black disc: its own dark ground shows it.
        #expect(!FaviconInk(rgbaPremultiplied: Self.icon(ink: (255, 255, 255, 255), ground: (0, 0, 0, 255)) { x, _ in x < 6 }).isLightMark)
        // Fully see-through: nothing to draw.
        #expect(!FaviconInk(rgbaPremultiplied: Self.icon(ink: (0, 0, 0, 0)) { _, _ in true }).isLightMark)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/755"))
    func halfSeeThroughPixelsCountByTheirColour() {
        // Premultiplied white at alpha 0.8 is (204, 204, 204, 204): still white.
        let ink = FaviconInk(rgbaPremultiplied: Self.icon(ink: (204, 204, 204, 204), Self.disc))
        #expect(ink.luminance > 0.99)
        #expect(ink.isLightMark)
    }
}
