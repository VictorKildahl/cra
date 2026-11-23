import Foundation

/// A tab's toolbar colour (Arc 1.171, measured for GitHub #84): the colour its page reported,
/// else the one the tab showed last (TabData.themeColor), so a slept or restored tab keeps its
/// bar while the page loads again. Nil means Arc's white bar: a page Arc has never shown gets
/// it, over a black canvas in dark mode too, until the page finishes loading.
///
/// "Reported" is the colour Cra read off the page (ToolbarSample), not its theme-color: Arc
/// ignores the meta tag (#629).
public enum ToolbarColor {
    /// "#RRGGBB", or nil for white. An empty, "none" or malformed value counts as unknown.
    public static func hex(reported: String?, remembered: String?) -> String? {
        [reported, remembered].lazy.compactMap { $0 }.first { HexColor.components($0) != nil }
    }

    /// Whether a bar of this colour (nil: white) is light: dark ink on it, and a dark hover.
    public static func isLight(hex: String?) -> Bool {
        (hex.flatMap(HexColor.luminance) ?? 1) > 0.6
    }

    /// A grey and its opacity.
    public struct Fill: Equatable, Sendable {
        public var white: Double
        public var alpha: Double
        public init(white: Double, alpha: Double) {
            self.white = white
            self.alpha = alpha
        }
    }

    /// The fill under the button the pointer is over (GitHub #694): white 10 % on a dark bar; on a
    /// light one, where white didn't show, black 6 %, Arc's hover on light surfaces
    /// (NewTabPageButtonHoveredBackground).
    public static func hover(light: Bool) -> Fill {
        light ? Fill(white: 0, alpha: 0.06) : Fill(white: 1, alpha: 0.1)
    }
}

/// The colour a tab's toolbar takes from its page (Arc 1.173.1, measured on local pages for #629):
/// the page's top-right corner, read once the load ends. Arc ignores theme-color (a light header
/// under a dark theme-color gives a light bar), takes neither the majority nor the average of the
/// top (70/30, 50/50 and 90/10 splits all give the right-hand colour; a black-to-white gradient
/// gives white), and doesn't read again on scroll or when the page repaints its header.
public enum ToolbarSample {
    /// The patch, in points from the top-right corner: a 24-point band fills it, a 2-point line
    /// over another colour only tints it (Arc: mostly the colour below, some of the line's).
    public static let width = 2.0, height = 12.0

    /// A rectangle of a capture, in pixels from its top-left.
    public struct Patch: Equatable, Sendable {
        public var x, y, width, height: Int
        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// Where to read in a viewport capture `imageWidth`×`imageHeight` pixels at `scale` pixels per
    /// point. `scrollbarWidth` (points) is the classic scroll bar's, whose track is the capture's
    /// right edge with "Show scroll bars: Always"; nil when the capture is too small.
    public static func patch(imageWidth: Int, imageHeight: Int, scale: Double, scrollbarWidth: Double = 0) -> Patch? {
        guard scale > 0 else { return nil }
        let w = max(1, Int((width * scale).rounded())), h = max(1, Int((height * scale).rounded()))
        let right = imageWidth - Int((max(0, scrollbarWidth) * scale).rounded())
        guard right - w >= 0, imageHeight >= h else { return nil }
        return Patch(x: right - w, y: 0, width: w, height: h)
    }

    /// "#RRGGBB", the mean of `rgba` (8-bit sRGB pixels, alpha ignored); nil for no pixels.
    public static func hex(rgba: [UInt8]) -> String? {
        let n = rgba.count / 4
        guard n > 0 else { return nil }
        var sum = (0, 0, 0)
        for i in 0..<n {
            sum.0 += Int(rgba[i * 4]); sum.1 += Int(rgba[i * 4 + 1]); sum.2 += Int(rgba[i * 4 + 2])
        }
        func mean(_ s: Int) -> Int { (s + n / 2) / n }
        return String(format: "#%02X%02X%02X", mean(sum.0), mean(sum.1), mean(sum.2))
    }

    /// The bar's colour from a whole capture (`rgba` rows of `width` pixels); nil when there is
    /// nothing to read.
    public static func hex(rgba: [UInt8], width: Int, height: Int, scale: Double, scrollbarWidth: Double = 0) -> String? {
        guard rgba.count >= width * height * 4,
              let p = patch(imageWidth: width, imageHeight: height, scale: scale, scrollbarWidth: scrollbarWidth) else { return nil }
        var pixels: [UInt8] = []
        pixels.reserveCapacity(p.width * p.height * 4)
        for y in p.y..<(p.y + p.height) {
            let row = (y * width + p.x) * 4
            pixels.append(contentsOf: rgba[row..<(row + p.width * 4)])
        }
        return hex(rgba: pixels)
    }
}
