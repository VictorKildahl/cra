import AppKit
import ImageIO
import Observation

/// Favicons keyed by host or by a tab's own icon (FaviconKey). Chromium hands us PNG bytes through the bridge;
/// we keep them in memory and on disk so the sidebar is populated on launch
/// before any tab has loaded (Arc: SidebarItemsFaviconCache).
@MainActor
@Observable
final class FaviconCache {
    private static let persistenceQueue = DispatchQueue(label: "dk.kildahl.cra.favicons", qos: .utility)
    private(set) var images: [String: NSImage] = [:]
    private var attemptedDiskLoad: Set<String> = []

    /// FaviconKey.key(for:), for code written before it moved to CraCore (#51).
    static func key(for urlString: String) -> String? { FaviconKey.key(for: urlString) }

    /// The icon under `key`, else under what it falls back to: a tab's own icon not on disk (cleared, or
    /// saved by an incognito page) shows its section's (#909), then its site's (#211).
    func image(forKey key: String?) -> NSImage? {
        guard let key else { return nil }
        return FaviconKey.chain(of: key).lazy.compactMap { self.storedImage($0) }.first
    }

    /// Whether the row reading `key` has its own icon, not only its host's, which any page on the host
    /// overwrites (#909): a row without asks SiteIconLoader for its section's.
    func hasOwnImage(forKey key: String?) -> Bool {
        guard let key else { return false }
        return FaviconKey.ownKeys(of: key).contains { storedImage($0) != nil }
    }

    /// What is stored under exactly `key`, in memory or on disk.
    func storedImage(_ key: String) -> NSImage? {
        if let img = images[key] { return img }
        guard !attemptedDiskLoad.contains(key) else { return nil }
        attemptedDiskLoad.insert(key)
        guard let img = NSImage(contentsOf: AppPaths.favicons.appendingPathComponent(Self.fileName(key))) else { return nil }
        images[key] = img
        return img
    }

    func image(for urlString: String) -> NSImage? { image(forKey: FaviconKey.sectionKey(for: urlString)) }

    private var dominant: [String: String] = [:]
    private var selectionPalettes: [String: [String]] = [:]

    /// Spatial logo colors for the selected favorite's outline, cached until the icon changes.
    func selectionColors(forKey key: String?) -> [String]? {
        guard let key else { return nil }
        if let colors = selectionPalettes[key] { return colors }
        guard let image = image(forKey: key),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        let colors = FavoriteSelectionTint.sample(rgba: pixels, width: size, height: size)
        selectionPalettes[key] = colors
        return colors
    }

    /// Average colour of the favicon's opaque pixels as "#RRGGBB" (Arc tints
    /// the toolbar with the favicon's dominant colour when a page has no
    /// theme-color).
    func dominantColor(forKey key: String?) -> String? {
        guard let key else { return nil }
        if let c = dominant[key] { return c.isEmpty ? nil : c }
        guard let img = image(forKey: key), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 16, h = 16
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = 0, g = 0, b = 0, n = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i + 3] > 200 {
            r += Int(buf[i]); g += Int(buf[i + 1]); b += Int(buf[i + 2]); n += 1
        }
        guard n > 40 else { dominant[key] = ""; return nil }
        let hex = String(format: "#%02X%02X%02X", r / n, g / n, b / n)
        dominant[key] = hex
        return hex
    }

    private var glyphTone: [String: Bool?] = [:]

    /// For a one-color gray glyph on a transparent background (GitHub's
    /// octocat, black or white depending on the page's color scheme): true when
    /// it is dark, false when light, nil for any other icon. Such glyphs vanish
    /// on a tile of their own tone. Custom icons are left as picked, but for a picked symbol (#640),
    /// drawn in black so that it turns light on a dark space as a site's glyph does.
    func glyphIsDark(forKey key: String?) -> Bool? {
        guard let key, !Self.isCustom(key) || TabCustomIcon.followsTheme(key: key) else { return nil }
        if let v = glyphTone[key] { return v }
        guard let img = image(forKey: key), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = 32, h = 32
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var opaque = 0, dark = 0, light = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i + 3] > 128 {
            let a = Double(buf[i + 3])
            let r = Double(buf[i]) / a, g = Double(buf[i + 1]) / a, b = Double(buf[i + 2]) / a
            opaque += 1
            guard max(r, g, b) - min(r, g, b) < 0.15 else { continue }
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if l < 0.3 { dark += 1 } else if l > 0.75 { light += 1 }
        }
        // Mostly see-through and almost every visible pixel the same gray.
        var v: Bool?
        if opaque > 20, opaque < w * h * 85 / 100 {
            if Double(dark) / Double(opaque) > 0.92 { v = true } else if Double(light) / Double(opaque) > 0.92 { v = false }
        }
        glyphTone[key] = .some(v)
        return v
    }

    /// Forget in-memory state so files added on disk (imports) are picked up.
    func reset() {
        images = [:]
        attemptedDiskLoad = []
        dominant = [:]
        selectionPalettes = [:]
        glyphTone = [:]
    }

    static func isCustom(_ key: String) -> Bool { key.hasPrefix("custom-") }

    /// Fits an image the user picked into a 256px square and caches it under a
    /// fresh key, so a replaced icon never shows a stale copy.
    func importCustomIcon(from url: URL) -> String? {
        NSImage(contentsOf: url).flatMap { importCustomIcon($0, prefix: "custom-") }
    }

    /// A picture as a custom icon under a fresh key that starts with `prefix` (TabCustomIcon).
    func importCustomIcon(_ src: NSImage, prefix: String) -> String? {
        guard src.size.width > 0, src.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let side: CGFloat = 256
        let scale = min(side / src.size.width, side / src.size.height)
        let size = NSSize(width: src.size.width * scale, height: src.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        src.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: 128, height: 128)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        let key = prefix + UUID().uuidString.lowercased()
        store(img, forKey: key)
        return key
    }

    func removeCustomIcon(_ key: String) {
        guard Self.isCustom(key) else { return }
        images[key] = nil
        try? FileManager.default.removeItem(at: AppPaths.favicons.appendingPathComponent(Self.fileName(key)))
    }

    /// `persist` false keeps the icon in memory only (incognito pages).
    func store(_ image: NSImage, forKey key: String, persist: Bool = true) {
        dominant[key] = nil
        glyphTone[key] = nil
        images[key] = image
        selectionPalettes[key] = nil
        guard persist else { return }
        let file = AppPaths.favicons.appendingPathComponent(Self.fileName(key))
        Self.persistenceQueue.async {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: file, options: .atomic)
        }
    }

    static func fileName(_ key: String) -> String {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "_" }.joined()
        return safe + ".png"
    }

    /// The most pixels a side of an icon file may claim: a small file can claim 40000 and cost a GB.
    nonisolated static let largestSource = 1024

    /// An icon file's bytes (another browser's store, a site) as a PNG at most `side` px on its long
    /// side. ImageIO shrinks a bitmap without decoding it at full size; AppKit draws an SVG small.
    nonisolated static func png(_ data: Data, side: Int = 64) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            return NSImage(data: data).flatMap { png($0, side: CGFloat(side)) }
        }
        // An .ico holds several sizes: the widest one not claiming too many pixels.
        let sizes = (0..<CGImageSourceGetCount(source)).compactMap { i -> (index: Int, width: Int)? in
            guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                  let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, max(w, h) <= largestSource else { return nil }
            return (i, w)
        }
        guard let pick = sizes.max(by: { $0.width < $1.width }) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, pick.index, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: thumb).representation(using: .png, properties: [:])
    }

    /// An image as a PNG at most `side` px on its long side, drawn at that size: for an image made in
    /// code or an SVG, which can declare any size (drawn at it, one ran a 0.1.43 import out of memory).
    nonisolated static func png(_ img: NSImage, side: CGFloat = 64) -> Data? {
        guard img.size.width > 0, img.size.height > 0 else { return nil }
        let scale = min(1, side / max(img.size.width, img.size.height))
        let w = max(1, Int((img.size.width * scale).rounded())), h = max(1, Int((img.size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
