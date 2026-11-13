import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A picture the user chose as a space's icon (not in Arc). The file is read once, scaled down to
/// a 96 px square (about 7× the dock's 13 pt, so it stays sharp on a Retina screen and in the
/// Spaces page's larger tile) and kept as PNG bytes in `Space.iconImage`, so the icon travels
/// with sidebar.json and its sync and never depends on the original file again.
@MainActor
enum SpaceIconImage {
    static let pixels = 96
    /// What the open panel and the drop target take: PNG and SVG first, any other picture too.
    static let contentTypes: [UTType] = [.png, .svg, .jpeg, .heic, .image]

    private static let cache = NSCache<NSData, NSImage>()

    /// PNG bytes for the picture at `url`, fitted inside a transparent square, or nil when the file
    /// isn't a picture AppKit can read. An SVG is drawn at the target size, so it stays crisp.
    static func normalized(from url: URL) -> Data? {
        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else { return nil }
        return normalized(source)
    }

    static func normalized(_ source: NSImage) -> Data? {
        let side = CGFloat(pixels)
        let scale = min(side / source.size.width, side / source.size.height)
        let w = (source.size.width * scale).rounded(), h = (source.size.height * scale).rounded()
        guard w >= 1, h >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1)
        return rep.representation(using: .png, properties: [:])
    }

    /// The icon at `points` square, in full colour (never a template, so no tint reaches it).
    static func image(_ data: Data, points: CGFloat) -> NSImage? {
        let key = data as NSData
        let base: NSImage
        if let hit = cache.object(forKey: key) { base = hit } else {
            guard isStoredPicture(data), let made = NSImage(data: data) else { return nil }
            cache.setObject(made, forKey: key)
            base = made
        }
        guard let copy = base.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: points, height: points)
        copy.isTemplate = false
        return copy
    }

    /// Whether `data` is what `normalized` stores: a PNG no bigger than a few times its square. The
    /// bytes come from sidebar.json, which another Mac's sync or a hand edit can fill, so anything
    /// else (a PDF, an SVG, a huge bitmap) is never handed to a decoder.
    static func isStoredPicture(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return w > 0 && h > 0 && w <= 4 * pixels && h <= 4 * pixels
    }

    /// A space's icon image: its picture, else its symbol (a template the caller tints). `points` is
    /// the symbol's size; a picture fills its square, so it is drawn a quarter larger, about what an
    /// emoji of that size covers.
    static func glyph(for space: Space, points: CGFloat, weight: NSFont.Weight = .medium) -> NSImage? {
        if let data = space.iconImage, !data.isEmpty { return image(data, points: (points * 1.25).rounded()) }
        return space.symbol.flatMap { SidebarSymbols.image($0, size: points, weight: weight) }
    }

    /// Choose Image…: a sheet-less open panel; `completion` gets the bytes, or nothing on cancel.
    static func choose(completion: @escaping (Data) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a PNG or SVG for this space's icon"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = normalized(from: url) { completion(data) } else { NSSound.beep() }
    }
}
