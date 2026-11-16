import AppKit

/// A tiny tiled grain texture, like Arc's "grain" overlay modifier.
enum NoiseTexture {
    static let image: NSImage = {
        let size = 96
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        var rng = SystemRandomNumberGenerator()
        for y in 0..<size {
            for x in 0..<size {
                let v = Double.random(in: 0...1, using: &rng)
                NSColor(white: v, alpha: 1).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        img.unlockFocus()
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
