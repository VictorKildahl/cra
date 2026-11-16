import AppKit
import QuartzCore

/// The theme's grain over the main window: a pattern Core Animation tiles, not a view that draws it. Drawn in
/// `draw(_:)` it held a window-sized backing store in the browser process, in half float on a wide-colour
/// display: the process's largest single allocation at one tab (16 Nov 2026).
@main
enum ThemeNoiseTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        noWindowSizedBackingStore()
        sameGrainAsTheDrawnPattern()
        blendAndOpacityPerTheme()
        print("Theme noise: \(checks) checks passed")
    }

    private static func check(_ ok: Bool, _ what: String) {
        guard ok else {
            FileHandle.standardError.write("FAIL: \(what)\n".data(using: .utf8)!)
            exit(1)
        }
        checks += 1
    }

    /// In a window, displayed: nothing drawn into the layer (its contents stay empty), and no `draw(_:)` for
    /// AppKit to give a backing store to.
    @MainActor
    private static func noWindowSizedBackingStore() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        root.wantsLayer = true
        window.contentView = root
        let noise = ThemeNoiseView(frame: root.bounds)
        root.addSubview(noise)
        for dark in [false, true] {
            noise.apply(noise: 1, isDark: dark)
            noise.needsDisplay = true
            window.displayIfNeeded()
            CATransaction.flush()
            check(noise.layer?.contents == nil, "no drawn contents (dark \(dark))")
        }
        let drawSel = #selector(NSView.draw(_:))
        check(class_getMethodImplementation(ThemeNoiseView.self, drawSel) == class_getMethodImplementation(NSView.self, drawSel),
              "ThemeNoiseView doesn't draw")
    }

    /// The layer shows the grain the view drew: the texture tiled from the view's corner, 96 pt a tile, at 1x and 2x.
    @MainActor
    private static func sameGrainAsTheDrawnPattern() {
        let size = NSSize(width: 300, height: 200)
        for scale: CGFloat in [1, 2] {
            let noise = ThemeNoiseView(frame: NSRect(origin: .zero, size: size))
            // At full opacity and without the blend, which render(in:) would apply over nothing.
            let layer = noise.layer!
            layer.contentsScale = scale
            let got = pixels(size, scale) { ctx in layer.render(in: ctx) }
            // What the view drew in a window of that scale: its pattern fill at 1x; at 2x the texture in 96 pt tiles
            // from the corner (as a capture of the drawn view showed: a pattern fill into this bare context would
            // ignore the context's 2x scale, which a window's backing store doesn't).
            let want = pixels(size, scale) { ctx in
                let g = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.current = g
                defer { NSGraphicsContext.current = nil }
                guard scale > 1 else {
                    NSColor(patternImage: NoiseTexture.image).setFill()
                    NSRect(origin: .zero, size: size).fill()
                    return
                }
                g.imageInterpolation = .none
                let tile = NoiseTexture.image.size
                for y in stride(from: 0, to: size.height, by: tile.height) {
                    for x in stride(from: 0, to: size.width, by: tile.width) {
                        NoiseTexture.image.draw(in: NSRect(origin: NSPoint(x: x, y: y), size: tile))
                    }
                }
            }
            var maxDiff = 0
            for i in stride(from: 0, to: got.count, by: 4) {
                for c in 0..<3 { maxDiff = max(maxDiff, abs(Int(got[i + c]) - Int(want[i + c]))) }
            }
            check(maxDiff <= 2, "same grain at \(scale)x (max difference \(maxDiff))")
        }
    }

    /// 9 % multiplied over light themes, 10 % screened over dark, times the palette's noise.
    @MainActor
    private static func blendAndOpacityPerTheme() {
        let noise = ThemeNoiseView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        noise.apply(noise: 1, isDark: false)
        check(abs(noise.alphaValue - 0.09) < 1e-6, "light opacity")
        check(noise.layer?.compositingFilter as? String == "multiplyBlendMode", "light multiplies")
        noise.apply(noise: 0.5, isDark: true)
        check(abs(noise.alphaValue - 0.05) < 1e-6, "dark opacity")
        check(noise.layer?.compositingFilter as? String == "screenBlendMode", "dark screens")
        check(noise.hitTest(NSPoint(x: 5, y: 5)) == nil, "clicks pass through")
    }

    private static func pixels(_ size: NSSize, _ scale: CGFloat, _ draw: (CGContext) -> Void) -> [UInt8] {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        return buf
    }
}
