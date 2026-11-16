import AppKit

/// A tiny tiled grain texture, like Arc's "grain" overlay modifier: 96 pt, one random grey a point, drawn at 2x
/// whatever screen is main. Made with lockFocus it took the main screen's scale, so a Cra started on a 1x monitor
/// tiled a 1x grain, scaled up and blurred, on a Retina screen; at 2x a 1x screen averages each 2 × 2 block back
/// to its one grey.
enum NoiseTexture {
    static let points = 96

    static let image: NSImage = {
        let px = points * 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: px * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        var rng = SystemRandomNumberGenerator()
        for y in 0..<points {
            for x in 0..<points {
                let v = UInt8.random(in: 0...255, using: &rng)
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let i = ((y * 2 + dy) * px + (x * 2 + dx)) * 4
                        data[i] = v; data[i + 1] = v; data[i + 2] = v; data[i + 3] = 255
                    }
                }
            }
        }
        rep.size = NSSize(width: points, height: points)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }()
}

/// NoiseOverlay in AppKit: the noise texture tiled in points at 9–10%, multiplied over light themes,
/// screened over dark. The layer's background is the texture as a pattern, which Core Animation tiles:
/// a view that drew it in `draw(_:)` had a window-sized backing store, in half float on a wide-colour
/// display: the browser process's largest single allocation at one tab (16 Nov 2026).
final class ThemeNoiseView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(patternImage: NoiseTexture.image).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(noise: Double, isDark: Bool) {
        alphaValue = noise * (isDark ? 0.1 : 0.09)
        layer?.compositingFilter = isDark ? "screenBlendMode" : "multiplyBlendMode"
    }
}
