import CoreGraphics
import Foundation
import ImageIO
import Testing

/// The icon Cra.app is bundled with (resources/AppIcon.icns) sits on Apple's icon grid: the tile 824 of 1024 px,
/// centred, with a transparent margin. macOS draws an icon like that in the Dark, Clear and Tinted icon styles; one
/// that fills its canvas edge to edge it leaves as drawn, light in the Dark style (EzraNz on #739, 0.1.57).
/// scripts/make-app-icons.swift --icns renders it.
struct AppIconGridTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func theBundledIconSitsOnApplesGrid() throws {
        let icns = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("resources/AppIcon.icns")
        let source = try #require(CGImageSourceCreateWithURL(icns as CFURL, nil))
        let largest = (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
            .max { $0.width < $1.width }
        let image = try #require(largest)
        #expect(image.width == 1024)
        let box = try #require(Self.opaqueBox(image))
        // Apple's grid: the tile from 100 to 924 px. Its shadow may reach a little further down.
        #expect(box.minX >= 90 && box.minY >= 90, "the tile starts at \(box.minX), \(box.minY)")
        #expect(box.maxX <= 934 && box.maxY <= 950, "the tile ends at \(box.maxX), \(box.maxY)")
        #expect(box.width >= 800, "the tile is \(box.width) px wide")
    }

    /// The smallest rectangle holding every pixel more than 6 % opaque, in pixels from the top left.
    private static func opaqueBox(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 16 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
