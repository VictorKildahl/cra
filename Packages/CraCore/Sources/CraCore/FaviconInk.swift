/// What a favicon's pixels are like, to tell how it shows on a ground that could swallow it.
///
/// ⌘T's selected row puts the favicon on a white tile, and GitHub's icon on a dark page is a
/// white octocat with see-through parts: the row showed a plain white square (#755). Such a light,
/// colourless mark is drawn in the row's colour on the tile instead, as Arc draws its arrow on its
/// white tile. The iPhone's dark sheet does the mirror image for dark marks (MobileFavicons.drawsAsMark).
public struct FaviconInk: Equatable, Sendable {
    /// The share of pixels that aren't see-through.
    public var coverage: Double
    /// Over those: the mean luminance, the mean of max − min channel (absolute, so a near-white grey
    /// counts as colourless), and the shares brighter than 0.6 and darker than 0.4.
    public var luminance: Double
    public var chroma: Double
    public var lightShare: Double
    public var darkShare: Double

    public init(coverage: Double, luminance: Double, chroma: Double, lightShare: Double, darkShare: Double) {
        (self.coverage, self.luminance, self.chroma, self.lightShare, self.darkShare) = (coverage, luminance, chroma, lightShare, darkShare)
    }

    /// From 8-bit premultiplied RGBA pixels, four bytes each.
    public init(rgbaPremultiplied pixels: [UInt8]) {
        let count = pixels.count / 4
        var covered = 0.0, luminance = 0.0, chroma = 0.0, light = 0.0, dark = 0.0
        for i in stride(from: 0, to: count * 4, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }
            let r = min(1, Double(pixels[i]) / 255 / a), g = min(1, Double(pixels[i + 1]) / 255 / a), b = min(1, Double(pixels[i + 2]) / 255 / a)
            covered += 1
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luminance += y
            if y > 0.6 { light += 1 }
            if y < 0.4 { dark += 1 }
            chroma += max(r, g, b) - min(r, g, b)
        }
        let n = max(covered, 1)
        self.init(coverage: count == 0 ? 0 : covered / Double(count), luminance: luminance / n, chroma: chroma / n,
                  lightShare: light / n, darkShare: dark / n)
    }

    /// A light, colourless mark with see-through parts, which a white tile would swallow. An icon with
    /// dark parts of its own (a white glyph on a black disc) or colour shows as it is.
    public var isLightMark: Bool {
        coverage > 0 && coverage < 0.9 && luminance > 0.75 && chroma < 0.08 && darkShare < 0.03
    }
}
