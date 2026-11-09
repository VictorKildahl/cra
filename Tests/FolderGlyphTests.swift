import AppKit

/// Component contract: the real layer tree and image pixels, without CEF or an on-screen window.
@main
enum FolderGlyphTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        templateMask()
        arcEmblemSize()
        followsFrontPanel()
        imageRendering()
        backingScaleAndRemoval()
        symbolArtwork()
        liveFolderArtwork()
        print("Folder glyph: \(checks) checks passed")
    }

    @MainActor
    private static func templateMask() {
        let glyph = makeGlyph()
        let emblem = FolderEmblem(image: image(), coloring: .template)
        show(glyph, emblem: emblem)
        let mark = imageLayer(in: glyph.layer!)!
        expect(mark.contents == nil && mark.mask?.contents != nil,
               "template artwork is an alpha mask over the folder ink")
        let source = sourceImage(mark)
        show(glyph, emblem: emblem, tint: .red)
        expect(sourceImage(mark) === source, "changing ink reuses the original mask")
        expect(isRed(pixel(bitmap(mark))), "the layer fill updates template ink")
        show(glyph, emblem: nil)
        expect(mark.isHidden && mark.mask == nil && mark.contents == nil && mark.backgroundColor == nil,
               "removing template artwork clears its mask and fill")
        show(glyph, emblem: emblem)
        expect(!mark.isHidden && mark.mask?.contents != nil && isBlue(pixel(bitmap(mark))),
               "template artwork reappears with the current ink after removal")
    }

    @MainActor
    private static func arcEmblemSize() {
        let glyph = makeGlyph()
        let emblem = FolderEmblem(image: image(), coloring: .template)
        for open in [false, true, false] {
            show(glyph, open: open, emblem: emblem)
            let mark = imageLayer(in: glyph.layer!)!
            expect(mark.bounds.size == CGSize(width: 9.5, height: 9.5),
                   "Arc fits the emblem to the front panel's shorter side minus 2.5 pt")
        }
    }

    @MainActor
    private static func followsFrontPanel() {
        let glyph = makeGlyph()
        let emblem = FolderEmblem(image: image(), coloring: .template)
        show(glyph, emblem: emblem)
        let root = glyph.layer!
        let mark = imageLayer(in: root)!
        let front = root.sublayers!.first!.sublayers!.last!
        let corners = [CGPoint.zero, CGPoint(x: mark.bounds.width, y: 0),
                       CGPoint(x: 0, y: mark.bounds.height),
                       CGPoint(x: mark.bounds.width, y: mark.bounds.height)]
        let closed = corners.map { mark.convert($0, to: root) }
        let cachedImage = sourceImage(mark)
        for open in [true, false, true, false] {
            show(glyph, open: open, emblem: emblem, animated: true)
            for (i, corner) in corners.enumerated() {
                let actual = mark.convert(corner, to: root)
                let onPanel = CGPoint(x: (front.bounds.width - mark.bounds.width) / 2 + corner.x,
                                      y: (front.bounds.height - mark.bounds.height) / 2 + corner.y)
                let expected = front.convert(onPanel, to: root)
                expect(distance(actual, expected) < 0.001,
                       "every emblem corner must follow the front panel's perspective when toggled")
                expect(open ? distance(actual, closed[i]) > 0.5 : distance(actual, closed[i]) < 0.001,
                       "opening moves the emblem; closing returns it without drift")
            }
            expect(sourceImage(mark) === cachedImage, "a toggle must reuse the image bitmap")
        }
        expect(glyph.hitTest(.zero) == nil, "the emblem must not intercept folder clicks")
    }

    @MainActor
    private static func imageRendering() {
        let glyph = makeGlyph()
        let wide = image(size: CGSize(width: 20, height: 10))
        show(glyph, emblem: FolderEmblem(image: wide))
        let mark = imageLayer(in: glyph.layer!)!
        let original = bitmap(mark)
        expect(isRed(pixel(original)), "original artwork keeps its color despite the blue folder tint")
        expect(pixel(original, y: 0).alphaComponent < 0.01, "wide artwork is letterboxed, not stretched")
        let originalImage = sourceImage(mark)
        expect(pixelSize(originalImage) == nativePixelSize(wide) && originalImage.width == 2 * originalImage.height,
               "artwork keeps its native source resolution before fitting")
        show(glyph, emblem: FolderEmblem(image: wide))
        expect(sourceImage(mark) === originalImage, "unchanged artwork is not rasterized again")

        show(glyph, emblem: FolderEmblem(image: wide, coloring: .template))
        expect(sourceImage(mark) === originalImage, "template coloring reuses the original image")
        expect(isBlue(pixel(bitmap(mark))), "template artwork takes the folder's blue ink")
        show(glyph, emblem: FolderEmblem(image: wide, coloring: .template), tint: .red)
        expect(isRed(pixel(bitmap(mark))), "changing the theme updates template ink")
        show(glyph, emblem: FolderEmblem(image: wide))
        expect(mark.mask == nil && mark.backgroundColor == nil,
               "original coloring removes the template mask and ink")
        expect(sourceImage(mark) === originalImage, "restoring original coloring reuses the source image")

        let tall = image(size: CGSize(width: 10, height: 20), color: .green)
        show(glyph, emblem: FolderEmblem(image: tall))
        let replaced = bitmap(mark)
        expect(pixel(replaced).greenComponent > 0.9, "replacing the emblem replaces its pixels")
        expect(pixel(replaced, x: 0).alphaComponent < 0.01, "tall artwork keeps its aspect ratio")

        show(glyph, emblem: FolderEmblem(image: wide))
        let resizedImage = sourceImage(mark)
        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 0.5))
        expect(mark.bounds.size == CGSize(width: 6, height: 6), "size is relative to the front panel")
        expect(sourceImage(mark) === resizedImage, "changing display size reuses the source image")
        expect(wide.size == CGSize(width: 20, height: 10), "rendering preserves the shared source image size")
        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 2))
        expect(mark.bounds.size == CGSize(width: 12, height: 12), "oversized artwork fits inside the panel")
        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 0))
        expect(mark.contents == nil && mark.mask == nil && mark.backgroundColor == nil,
               "zero-size artwork has no stale pixels")
        show(glyph, emblem: FolderEmblem(image: NSImage(size: .zero)))
        expect(mark.contents == nil, "an empty image has no stale pixels")
        show(glyph, emblem: FolderEmblem(image: NSImage(size: .zero), coloring: .template))
        expect(mark.mask?.contents == nil && mark.backgroundColor == nil,
               "an empty template image has no stale mask or ink")
    }

    @MainActor
    private static func backingScaleAndRemoval() {
        let window = EmblemTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let glyph = makeGlyph()
        window.contentView!.addSubview(glyph)
        let emblem = FolderEmblem(image: image())
        show(glyph, emblem: emblem)
        let cachedSource = sourceImage(imageLayer(in: glyph.layer!)!)
        for scale: CGFloat in [1, 2, 1] {
            window.testScale = scale
            glyph.viewDidChangeBackingProperties()
            show(glyph, emblem: emblem)
            let mark = imageLayer(in: glyph.layer!)!
            let source = sourceImage(mark)
            expect(pixelSize(source) == nativePixelSize(emblem.image),
                   "backing scale does not resample the native source")
            expect(source === cachedSource, "moving between displays reuses the source image")
            expect(mark.contentsScale == scale, "the bitmap is displayed at its backing scale")
            expect(allLayers(in: glyph.layer!).dropFirst().allSatisfy { $0.contentsScale == scale },
                   "folder panels and their masks use the backing scale")
        }
        let mark = imageLayer(in: glyph.layer!)!
        show(glyph, emblem: nil, peeked: true)
        expect(mark.isHidden && mark.contents == nil && mark.mask == nil && mark.backgroundColor == nil,
               "reusing a row without an emblem removes the old image")
        let dots = glyph.layer!.sublayers!.last!
        expect(!dots.isHidden, "a plain peeked folder still shows its dots")
        show(glyph, open: true, emblem: nil, peeked: true)
        expect(dots.isHidden, "an open folder hides peek dots")
        show(glyph, emblem: emblem, peeked: true)
        expect(!mark.isHidden && mark.contents != nil, "an emblem reappears after removing it")
        expect(dots.isHidden, "an emblem takes precedence over peek dots")
    }

    @MainActor
    private static func symbolArtwork() {
        let glyph = makeGlyph()
        for symbol in FolderSymbol.allCases {
            expect(symbol.image.isTemplate, "folder symbols use the folder's ink")
            show(glyph, emblem: FolderEmblem(image: symbol.image, coloring: .template))
            let mark = imageLayer(in: glyph.layer!)!
            let source = sourceImage(mark)
            expect(symbol.image.size == CGSize(width: 16, height: 16) && pixelSize(source) == nativePixelSize(symbol.image),
                   "picker symbols use Arc's 16 pt font canvas: \(symbol)")
            let pixels = bitmap(mark)
            let visible = (0..<pixels.pixelsHigh).contains { y in
                (0..<pixels.pixelsWide).contains { x in pixel(pixels, x: x, y: y).alphaComponent > 0.1 }
            }
            expect(visible, "every picker symbol must render visible pixels: \(symbol)")
        }
    }

    @MainActor
    private static func liveFolderArtwork() {
        let glyph = makeGlyph()
        for artwork in [GitHubMark.image, GitLabMark.image] {
            expect(artwork.isTemplate, "live folder marks use the folder's ink")
            show(glyph, emblem: FolderEmblem(image: artwork, coloring: .template))
            let mark = imageLayer(in: glyph.layer!)!
            let source = sourceImage(mark)
            expect(artwork.size == CGSize(width: 32, height: 32) && pixelSize(source) == nativePixelSize(artwork),
                   "live folder source matches Arc's 32 pt asset canvas")
            expect(mark.bounds.size == CGSize(width: 9.5, height: 9.5),
                   "live folder marks use the same fit as picker symbols")
            let pixels = bitmap(mark)
            let visible = (0..<pixels.pixelsHigh).contains { y in
                (0..<pixels.pixelsWide).contains { x in pixel(pixels, x: x, y: y).alphaComponent > 0.1 }
            }
            expect(visible, "live folder marks render visible pixels")
        }
    }

    @MainActor
    private static func makeGlyph() -> FolderGlyphView {
        FolderGlyphView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    }

    @MainActor
    private static func show(_ glyph: FolderGlyphView, open: Bool = false, emblem: FolderEmblem?,
                             tint: NSColor = .blue, peeked: Bool = false, animated: Bool = false) {
        glyph.show(expanded: open, peeked: peeked, emblem: emblem, tint: tint,
                   fillColor: .white, animated: animated)
        glyph.layoutSubtreeIfNeeded()
    }

    private static func image(size: CGSize = CGSize(width: 10, height: 10), color: NSColor = .red) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private static func imageLayer(in layer: CALayer) -> CALayer? {
        if layer.contents != nil || layer.mask?.contents != nil { return layer }
        return layer.sublayers?.lazy.compactMap { imageLayer(in: $0) }.first
    }

    private static func allLayers(in layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { allLayers(in: $0) }
            + (layer.mask.map { allLayers(in: $0) } ?? [])
    }

    private static func sourceImage(_ layer: CALayer) -> CGImage {
        (layer.mask?.contents ?? layer.contents) as! CGImage
    }

    private static func bitmap(_ layer: CALayer) -> NSBitmapImageRep {
        let scale = layer.contentsScale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: Int(ceil(layer.bounds.width * scale)),
                                      pixelsHigh: Int(ceil(layer.bounds.height * scale)),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return bitmap
    }

    private static func pixel(_ bitmap: NSBitmapImageRep, x: Int? = nil, y: Int? = nil) -> NSColor {
        bitmap.colorAt(x: x ?? bitmap.pixelsWide / 2, y: y ?? bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    }

    private static func isRed(_ color: NSColor) -> Bool { color.redComponent > 0.9 && color.blueComponent < 0.1 }
    private static func isBlue(_ color: NSColor) -> Bool { color.blueComponent > 0.9 && color.redComponent < 0.1 }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// What the image's own CGImage measures. NSImage picks the main display's scale for a nil
    /// context (2x on a Retina Mac, 1x on a display-less CI runner); the contract is only that the
    /// emblem's frame and the window's backing scale never re-rasterize the artwork.
    private static func nativePixelSize(_ image: NSImage) -> CGSize {
        var rect = CGRect(origin: .zero, size: image.size)
        return pixelSize(image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!)
    }

    private static func pixelSize(_ image: CGImage) -> CGSize { CGSize(width: image.width, height: image.height) }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }
}

private final class EmblemTestWindow: NSWindow {
    var testScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { testScale }
}
