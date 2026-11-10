import AppKit

/// Particle notes above a playing favorite. The grid owns the overlay so notes can drift over
/// neighboring tiles without being clipped by a split's cells.
final class MusicNotesView: NSView {
    private let emitter = CAEmitterLayer()
    /// The tile's tone: white notes on a dark tile, black on a light one.
    var dark: Bool { didSet { if dark != oldValue { fill() } } }
    nonisolated(unsafe) private var motionObserver: NSObjectProtocol?

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: .zero)
        wantsLayer = true
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: MusicNotes.emitterRadius, height: MusicNotes.emitterRadius)
        layer?.addSublayer(emitter)
        fill()
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fill() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let o = motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    /// Keep the emitter's angle pointing up regardless of the parent's coordinates.
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// With Reduce Motion on nothing floats.
    private func fill() {
        emitter.emitterCells = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? [] : MusicNotes.Shape.allCases.map { Self.cell($0, dark: dark) }
    }

    private static func cell(_ shape: MusicNotes.Shape, dark: Bool) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = sprite(shape, dark: dark)
        c.birthRate = MusicNotes.birthRate(shape)
        c.lifetime = MusicNotes.lifetime
        c.scale = MusicNotes.scale
        c.scaleRange = MusicNotes.scaleRange
        c.scaleSpeed = MusicNotes.scaleSpeed
        c.alphaRange = MusicNotes.alphaRange
        c.alphaSpeed = MusicNotes.alphaSpeed
        c.velocity = MusicNotes.velocity
        c.velocityRange = MusicNotes.velocityRange
        c.emissionLongitude = MusicNotes.emissionLongitude
        c.emissionRange = MusicNotes.emissionRange
        return c
    }

    private static var sprites: [String: CGImage] = [:]

    /// Cache each note shape in the tile's ink so updates reuse the bitmap.
    static func sprite(_ shape: MusicNotes.Shape, dark: Bool) -> CGImage? {
        let key = "\(shape)-\(dark)"
        if let made = sprites[key] { return made }
        let n = MusicNotes.spritePixels
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ink = MusicNotes.ink(dark: dark)
        // One layer, so the ink's alpha counts once where a head meets its stem.
        ctx.setAlpha(ink.alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(gray: ink.white, alpha: 1)
        ctx.setStrokeColor(gray: ink.white, alpha: 1)
        let head = { (x: CGFloat, y: CGFloat) in
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: 0.35)
            ctx.fillEllipse(in: CGRect(x: -2.5, y: -1.8, width: 5, height: 3.6))
            ctx.restoreGState()
        }
        switch shape {
        case .single:
            head(4.4, 2.8)
            ctx.fill(CGRect(x: 5.4, y: 3, width: 1.6, height: 8))
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 6.6, y: 10.2))
            ctx.addQuadCurve(to: CGPoint(x: 9.3, y: 6.8), control: CGPoint(x: 9.6, y: 9.4))
            ctx.strokePath()
        case .beamed:
            head(2.9, 2.4)
            head(8.7, 3.4)
            ctx.fill(CGRect(x: 3.9, y: 2.6, width: 1.5, height: 7))
            ctx.fill(CGRect(x: 9.7, y: 3.6, width: 1.5, height: 7))
            ctx.move(to: CGPoint(x: 3.9, y: 8.2))
            ctx.addLine(to: CGPoint(x: 11.2, y: 9.2))
            ctx.addLine(to: CGPoint(x: 11.2, y: 11.6))
            ctx.addLine(to: CGPoint(x: 3.9, y: 10.6))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.endTransparencyLayer()
        let image = ctx.makeImage()
        sprites[key] = image
        return image
    }
}

/// A click-through overlay in the favorites grid's top-left coordinates.
final class MusicNotesHost: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
