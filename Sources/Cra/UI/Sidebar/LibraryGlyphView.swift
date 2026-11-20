import AppKit

/// Arc's Library glyph: a box with a star, a dot and a triangle above it, which move when the pointer
/// is on the button and go back when it leaves (GitHub #608). Where everything is, and how it moves,
/// is `LibraryGlyph` in CraCore; this view draws its frames, on the display's refresh while a change
/// runs and not at all otherwise.
@MainActor
final class LibraryGlyphView: NSView {
    private var motion = LibraryGlyph.Motion()
    private var link: CADisplayLink?
    /// The frame drawn last, and how many were drawn since the last hover change, for cra://debug.
    private(set) var drawn = LibraryGlyph.Frame(pose: LibraryGlyph.rest)
    private(set) var framesSinceChange = 0
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var hovered: Bool { motion.target == LibraryGlyph.hovered }

    func setHovered(_ on: Bool) {
        let pose = on ? LibraryGlyph.hovered : LibraryGlyph.rest
        guard pose != motion.target else { return }
        framesSinceChange = 0
        // With Reduce Motion the glyph takes its new place at once.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window == nil {
            motion = LibraryGlyph.Motion(at: pose)
            needsDisplay = true
            return
        }
        motion.head(to: pose, at: CACurrentMediaTime())
        if link == nil {
            let l = displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
        needsDisplay = true
    }

    @objc private func step(_ link: CADisplayLink) {
        needsDisplay = true
        if motion.isSettled(at: link.targetTimestamp) {
            link.invalidate()
            self.link = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
            motion = LibraryGlyph.Motion(at: motion.target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let f = motion.frame(at: link?.targetTimestamp ?? CACurrentMediaTime())
        if f != drawn || framesSinceChange == 0 { framesSinceChange += 1 }
        drawn = f
        let ink = dark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.26)
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        // One layer at the ink's alpha, so where the shapes meet is no darker than elsewhere.
        ctx.setAlpha(ink.alphaComponent)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let solid = ink.withAlphaComponent(1).cgColor
        ctx.setFillColor(solid)
        ctx.addPath(LibraryGlyph.boxPath())
        ctx.fillPath(using: .evenOdd)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -bounds.width, y: -bounds.height, width: 2 * bounds.width,
                            height: bounds.height + LibraryGlyph.clipBottom))
        let star = LibraryGlyph.starPath(center: f.pose.star, angle: f.pose.starAngle)
        ctx.addPath(star)
        ctx.fillPath()
        ctx.setStrokeColor(solid)
        ctx.setLineWidth(LibraryGlyph.starRounding)
        ctx.setLineJoin(.round)
        ctx.addPath(star)
        ctx.strokePath()
        ctx.setFillColor(ink.withAlphaComponent(f.triangleOpacity).cgColor)
        ctx.addPath(LibraryGlyph.trianglePath(center: f.pose.triangle, angle: f.pose.triangleAngle, scale: f.triangleScale))
        ctx.fillPath()
        ctx.restoreGState()
        if f.dotVisible {
            let r = LibraryGlyph.dotRadius
            ctx.fillEllipse(in: CGRect(x: f.pose.dot.x - r, y: f.pose.dot.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// For cra://debug?libraryHover: where the glyph was drawn last, and in how many frames.
    var readout: String {
        let p = drawn.pose
        return String(format: "hover=%@ frames=%d star=%.2f,%.2f@%.0f dot=%.2f,%.2f triangle=%.2f,%.2f@%.0f",
                      hovered ? "on" : "off", framesSinceChange, p.star.x, p.star.y, p.starAngle,
                      p.dot.x, p.dot.y, p.triangle.x, p.triangle.y, p.triangleAngle)
    }
}
