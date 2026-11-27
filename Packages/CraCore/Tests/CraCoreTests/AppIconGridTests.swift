import CoreGraphics
import Foundation
import ImageIO
import Testing

/// The .icns Cra.app is bundled with (its icon on macOS 14 and 15, the Alerts helper's and the DMG's) sits on Apple's icon
/// grid: the tile 824 of 1024 px, centred, with a transparent margin, like the Dock's other icons (EzraNz on #739,
/// 0.1.57). Since Gilad's Icon Composer icon became Cra's (27 Nov), actool renders it from resources/AppIcon.icon
/// (scripts/compile-app-icon.sh, as scripts/build.sh does); macOS 26 and later draw the catalog (AppIconCatalogTests).
struct AppIconGridTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func theBundledIconSitsOnApplesGrid() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cra-app-icon-grid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = root.appendingPathComponent("scripts/compile-app-icon.sh")
        process.arguments = [out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let icns = out.appendingPathComponent("AppIcon.icns")
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

    /// Settings ▸ Icon's Segments tile on macOS 26 (resources/app-icons/segments-glass.png, scripts/render-app-icon-preview.sh
    /// renders it from resources/AppIcon.icon) sits on the grid like the picker's other tiles: 412 of 512 px, centred (#865).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/865")) func theGlassSegmentsTileSitsOnTheGrid() throws {
        let png = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("resources/app-icons/segments-glass.png")
        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil), "segments-glass.png is missing")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 512 && image.height == 512)
        let box = try #require(Self.opaqueBox(image))
        #expect(box.minX >= 45 && box.minY >= 45 && box.maxX <= 467 && box.maxY <= 475, "the tile is at \(box)")
        #expect(box.width >= 400, "the tile is \(box.width) px wide")
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
