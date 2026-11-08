import AppKit

/// Component contract: the real layer tree and image pixels, without CEF or an on-screen window.
@main
enum FolderGlyphTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        followsFrontPanel()
        imageRendering()
        backingScaleAndRemoval()
        print("Folder glyph: \(checks) checks passed")
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
        let cachedImage = mark.contents as! CGImage
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
            expect((mark.contents as! CGImage) === cachedImage, "a toggle must reuse the image bitmap")
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
        let originalImage = mark.contents as! CGImage
        show(glyph, emblem: FolderEmblem(image: wide))
        expect((mark.contents as! CGImage) === originalImage, "unchanged artwork is not rasterized again")

        show(glyph, emblem: FolderEmblem(image: wide, coloring: .template))
        expect(isBlue(pixel(bitmap(mark))), "template artwork takes the folder's blue ink")
        show(glyph, emblem: FolderEmblem(image: wide, coloring: .template), tint: .red)
        expect(isRed(pixel(bitmap(mark))), "changing the theme updates template ink")

        let tall = image(size: CGSize(width: 10, height: 20), color: .green)
        show(glyph, emblem: FolderEmblem(image: tall))
        let replaced = bitmap(mark)
        expect(pixel(replaced).greenComponent > 0.9, "replacing the emblem replaces its pixels")
        expect(pixel(replaced, x: 0).alphaComponent < 0.01, "tall artwork keeps its aspect ratio")

        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 0.5))
        expect(mark.bounds.size == CGSize(width: 6, height: 6), "size is relative to the front panel")
        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 2))
        expect(mark.bounds.size == CGSize(width: 12, height: 12), "oversized artwork fits inside the panel")
        show(glyph, emblem: FolderEmblem(image: wide, relativeSize: 0))
        expect(mark.contents == nil, "zero-size artwork has no stale pixels")
        show(glyph, emblem: FolderEmblem(image: NSImage(size: .zero)))
        expect(mark.contents == nil, "an empty image has no stale pixels")
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
        for scale: CGFloat in [1, 2, 1] {
            window.testScale = scale
            glyph.viewDidChangeBackingProperties()
            show(glyph, emblem: emblem)
            let mark = imageLayer(in: glyph.layer!)!
            let pixels = bitmap(mark)
            expect(pixels.pixelsWide == Int(7 * scale) && pixels.pixelsHigh == Int(7 * scale),
                   "moving between 1x and Retina regenerates artwork at the correct resolution")
            expect(mark.contentsScale == scale, "the bitmap is displayed at its backing scale")
        }
        let mark = imageLayer(in: glyph.layer!)!
        show(glyph, emblem: nil, peeked: true)
        expect(mark.isHidden && mark.contents == nil, "reusing a row without an emblem removes the old image")
        let dots = glyph.layer!.sublayers!.last!
        expect(!dots.isHidden, "a plain peeked folder still shows its dots")
        show(glyph, open: true, emblem: nil, peeked: true)
        expect(dots.isHidden, "an open folder hides peek dots")
        show(glyph, emblem: emblem, peeked: true)
        expect(!mark.isHidden && mark.contents != nil, "an emblem reappears after removing it")
        expect(dots.isHidden, "an emblem takes precedence over peek dots")
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
        if layer.contents != nil { return layer }
        return layer.sublayers?.lazy.compactMap { imageLayer(in: $0) }.first
    }

    private static func bitmap(_ layer: CALayer) -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: layer.contents as! CGImage)
    }

    private static func pixel(_ bitmap: NSBitmapImageRep, x: Int? = nil, y: Int? = nil) -> NSColor {
        bitmap.colorAt(x: x ?? bitmap.pixelsWide / 2, y: y ?? bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    }

    private static func isRed(_ color: NSColor) -> Bool { color.redComponent > 0.9 && color.blueComponent < 0.1 }
    private static func isBlue(_ color: NSColor) -> Bool { color.blueComponent > 0.9 && color.redComponent < 0.1 }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
        checks += 1
    }
}

private final class EmblemTestWindow: NSWindow {
    var testScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { testScale }
}
