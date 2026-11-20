import CraCore
import Testing

/// Arc 1.173.1, measured on local pages (#629): the bar takes the colour of the page's top-right
/// corner when the load ends, whatever the page's theme-color says and whatever most of its top is.
struct ToolbarSampleTests {
    /// A viewport capture `width`×`height` points at `scale`, painted by `color(x, y)` in points.
    private static func page(width: Int = 800, height: Int = 200, scale: Int = 2,
                             _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        let w = width * scale, h = height * scale
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let c = color(x / scale, y / scale), i = (y * w + x) * 4
                rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2
            }
        }
        return rgba
    }

    private static let red: (UInt8, UInt8, UInt8) = (255, 0, 0), blue: (UInt8, UInt8, UInt8) = (0, 0, 255)
    private static let green: (UInt8, UInt8, UInt8) = (0, 255, 0), white: (UInt8, UInt8, UInt8) = (255, 255, 255)

    private static func sample(_ rgba: [UInt8], width: Int = 800, height: Int = 200, scale: Int = 2,
                               scrollbarWidth: Double = 0) -> String? {
        ToolbarSample.hex(rgba: rgba, width: width * scale, height: height * scale, scale: Double(scale),
                          scrollbarWidth: scrollbarWidth)
    }

    /// GitHub (the report): a light header under a dark theme-color gives Arc a light bar; the
    /// theme-color isn't in the picture at all, so a page is judged by its pixels.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func lightHeaderGivesLightBar() {
        let github = Self.page { _, y in y < 64 ? (0xF6, 0xF8, 0xFA) : Self.white }
        #expect(Self.sample(github) == "#F6F8FA")
    }

    /// Arc's bar is neither the majority nor the average of the top: 70/30, 50/50 and 90/10 red
    /// and blue all gave the blue at the right; eight stripes gave the last one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"), arguments: [0.7, 0.5, 0.9])
    func rightCornerNotMajority(redShare: Double) {
        let split = Self.page { x, y in y < 64 ? (Double(x) < 800 * redShare ? Self.red : Self.blue) : Self.white }
        #expect(Self.sample(split) == "#0000FF")
        let stripes = Self.page { x, y in y < 64 ? (x / 100 == 7 ? (0, 0xE0, 0xE0) : Self.red) : Self.white }
        #expect(Self.sample(stripes) == "#00E0E0")
    }

    /// A black-to-white gradient across the top gave Arc pure white: the patch is the last
    /// sliver of the right edge, not a block of the page.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func gradientGivesItsRightEdge() {
        let gradient = Self.page { x, y in
            let v = UInt8(min(255, x * 256 / 800))
            return y < 64 ? (v, v, v) : Self.white
        }
        #expect(Self.sample(gradient) == "#FFFFFF")
    }

    /// A 24-point red band over green gave a red bar; a 2-point red line over green gave a bar
    /// that is mostly green: the patch is a few points tall from the top.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func patchIsAFewPointsTall() {
        let band = Self.page { _, y in y < 24 ? Self.red : (y < 64 ? Self.green : Self.white) }
        #expect(Self.sample(band) == "#FF0000")
        let line = Self.page { _, y in y < 2 ? Self.red : (y < 64 ? Self.green : Self.white) }
        let mixed = Self.sample(line).flatMap(HexColor.components)
        #expect(mixed.map { $0.g > $0.r && $0.r > 0 } == true, "mostly green with some red: \(String(describing: mixed))")
    }

    /// A plain page is its background, at 1x as at 2x.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"), arguments: [1, 2, 3])
    func plainPageAtEveryScale(scale: Int) {
        let plain = Self.page(scale: scale) { _, _ in (0x20, 0x30, 0x40) }
        #expect(Self.sample(plain, scale: scale) == "#203040")
    }

    /// With "Show scroll bars: Always" the page's top-right corner is the scroll bar's track,
    /// not the page: the patch stays left of it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func classicScrollbarIsNotThePage() {
        let page = Self.page { x, y in x >= 785 ? (0xFA, 0xFA, 0xFA) : (y < 64 ? (0x7A, 0x1F, 0xA2) : Self.white) }
        #expect(Self.sample(page, scrollbarWidth: 15) == "#7A1FA2")
    }

    /// Nothing to read: no colour, so the tab keeps the one it has.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func emptyCaptureHasNoColour() {
        #expect(ToolbarSample.hex(rgba: [], width: 0, height: 0, scale: 2) == nil)
        #expect(ToolbarSample.hex(rgba: [1, 2, 3], width: 10, height: 10, scale: 2) == nil)
        #expect(ToolbarSample.patch(imageWidth: 20, imageHeight: 20, scale: 2, scrollbarWidth: 15) == nil)
    }

    /// The patch the app crops before it decodes, so only a few pixels are colour-converted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/629"))
    func patchIsTheTopRightCorner() {
        let p = ToolbarSample.patch(imageWidth: 1600, imageHeight: 400, scale: 2)
        #expect(p == ToolbarSample.Patch(x: 1596, y: 0, width: 4, height: 24))
        let besideBar = ToolbarSample.patch(imageWidth: 1600, imageHeight: 400, scale: 2, scrollbarWidth: 15)
        #expect(besideBar == ToolbarSample.Patch(x: 1566, y: 0, width: 4, height: 24))
    }
}
