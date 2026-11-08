import AppKit
import Observation

/// Favicons keyed by host or by a tab's own icon (FaviconKey). Chromium hands us PNG bytes through the bridge;
/// we keep them in memory and on disk so the sidebar is populated on launch
/// before any tab has loaded (Arc: SidebarItemsFaviconCache).
@MainActor
@Observable
final class FaviconCache {
    private(set) var images: [String: NSImage] = [:]
    private var attemptedDiskLoad: Set<String> = []

    /// FaviconKey.key(for:), for code written before it moved to CraCore (#51).
    static func key(for urlString: String) -> String? { FaviconKey.key(for: urlString) }

    func image(forKey key: String?) -> NSImage? {
        guard let key else { return nil }
        if let img = images[key] { return img }
        if !attemptedDiskLoad.contains(key) {
            attemptedDiskLoad.insert(key)
            let file = AppPaths.favicons.appendingPathComponent(Self.fileName(key))
            if let img = NSImage(contentsOf: file) {
                images[key] = img
                return img
            }
        }
        // A tab's own icon not on disk (cleared, or saved by an incognito page): the site's (#211).
        let site = FaviconKey.siteKey(of: key)
        return site == key ? nil : image(forKey: site)
    }

    func image(for urlString: String) -> NSImage? { image(forKey: FaviconKey.key(for: urlString)) }

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
    /// on a tile of their own tone. Custom icons are left as picked.
    func glyphIsDark(forKey key: String?) -> Bool? {
        guard let key, !Self.isCustom(key) else { return nil }
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
        guard let src = NSImage(contentsOf: url), src.size.width > 0, src.size.height > 0,
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
        let key = "custom-" + UUID().uuidString.lowercased()
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
        images[key] = image
        selectionPalettes[key] = nil
        guard persist else { return }
        let file = AppPaths.favicons.appendingPathComponent(Self.fileName(key))
        DispatchQueue.global(qos: .utility).async {
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
}
