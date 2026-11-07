import AppKit

/// An image printed on the folder's front panel, independent of its source or folder type.
struct FolderEmblem: Equatable {
    enum Coloring { case template, original }

    var image: NSImage
    var coloring: Coloring = .original
    /// Fraction of the front panel's shorter side (7 pt on the current 16 × 12 pt panel).
    var relativeSize: CGFloat = 7.0 / 12.0

    fileprivate func rasterized(size: CGSize, scale: CGFloat, tint: NSColor) -> CGImage? {
        guard image.size.width > 0, image.size.height > 0,
              let context = CGContext(data: nil, width: Int(ceil(size.width * scale)),
                                      height: Int(ceil(size.height * scale)), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let fit = min(size.width / image.size.width, size.height / image.size.height)
        let fitted = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        let rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                          width: fitted.width, height: fitted.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        if coloring == .template {
            context.setBlendMode(.sourceIn)
            context.setFillColor(tint.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        return context.makeImage()
    }
}

/// Arc's folder glyph (FolderIconView, read from Arc 1.171's binary): a back panel with the tab
/// and a front panel, both hinged at the bottom-left corner. Opening turns them toward you in
/// perspective, the front tipping forward and the back leaning away, each shaded darker as it
/// turns, with Core Animation's implicit 0.25 s transition. An optional emblem turns with the front.
final class FolderGlyphView: NSView {
    /// Arc fixes the glyph at 16 × 16 pt.
    static let side: CGFloat = 16
    private let icon = CALayer()
    private let back = CAShapeLayer()
    private let backShade = CAGradientLayer()
    private let backShadeMask = CAShapeLayer()
    private let front = CALayer()
    private let frontPanel = CAShapeLayer()
    private let frontShade = CAGradientLayer()
    private let frontShadeMask = CAShapeLayer()
    /// The back panel shows only outside the front one. Theme folders are opaque (FolderTones), so
    /// the front hides the back's outline anyway; the White and Black icon styles fill with
    /// translucent tones, and without this an open folder showed the back's edges through the
    /// front. The mask is the front panel's shape cut out of a larger square, turned with the
    /// front's own transform so it moves with it.
    private let backHolder = CALayer()
    private let frontHole = CAShapeLayer()
    private let mark = CALayer()
    private var emblem: FolderEmblem?
    private var emblemTint = NSColor.labelColor
    private struct EmblemRendering: Equatable {
        var emblem: FolderEmblem
        var tint: NSColor
        var size: CGSize
        var scale: CGFloat
    }
    private var renderedEmblem: EmblemRendering?
    /// Arc's peeked folder (FolderPeek): three 2 pt dots on a 4 pt pitch in the closed body.
    private let dots = CAShapeLayer()
    private var expanded = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Arc: black from clear to 0.36 across the back, to 0.15 across the front.
        backShade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.36).cgColor]
        backShade.startPoint = CGPoint(x: 0, y: 0)
        backShade.endPoint = CGPoint(x: 0.6, y: 1)
        backShade.mask = backShadeMask
        frontShade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.15).cgColor]
        frontShade.startPoint = CGPoint(x: 0.1, y: 0)
        frontShade.endPoint = CGPoint(x: 0.9, y: 1)
        frontShade.mask = frontShadeMask
        back.addSublayer(backShade)
        front.addSublayer(frontPanel)
        // The mark is in the panel's local coordinates, so its perspective, hinge and animation
        // come from the panel. Shading covers the printed mark as well as the folder's surface.
        front.addSublayer(mark)
        front.addSublayer(frontShade)
        for l in [back, front, frontHole] as [CALayer] {
            // Hinged on the bottom-left corner.
            l.anchorPoint = CGPoint(x: 0, y: 1)
        }
        frontHole.fillRule = .evenOdd
        frontHole.fillColor = NSColor.black.cgColor
        backHolder.addSublayer(back)
        backHolder.mask = frontHole
        icon.addSublayer(backHolder)
        icon.addSublayer(front)
        layer?.addSublayer(icon)
        layer?.addSublayer(dots)
        mark.contentsGravity = .resizeAspect
        apply(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(expanded: Bool, peeked: Bool = false, emblem: FolderEmblem? = nil, tint: NSColor,
              fillColor: NSColor, backColor: NSColor? = nil, animated: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        back.fillColor = (backColor ?? fillColor).cgColor
        frontPanel.fillColor = fillColor.cgColor
        for l in [back, frontPanel] { l.strokeColor = tint.cgColor }
        self.emblem = emblem
        emblemTint = tint
        mark.isHidden = emblem == nil
        dots.isHidden = !peeked || expanded || emblem != nil
        dots.fillColor = tint.cgColor
        CATransaction.commit()
        needsLayout = true
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        apply(animated: animated)
    }

    /// Arc's per-state transforms: perspective m34 −0.00291, 3 pt to the right, 32° about the
    /// vertical axis, then the back 28° and the front −30° about the horizontal one.
    private func apply(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        let open = expanded
        var t = CATransform3DIdentity
        t.m34 = -0.0029129464
        t = CATransform3DTranslate(t, open ? 3 : 0, 0, 0)
        t = CATransform3DRotate(t, open ? 32 * .pi / 180 : 0, 0, 1, 0)
        back.transform = CATransform3DRotate(t, open ? 28 * .pi / 180 : 0, 1, 0, 0)
        front.transform = CATransform3DRotate(t, open ? -30 * .pi / 180 : 0, 1, 0, 0)
        frontHole.transform = front.transform
        frontShade.opacity = open ? 1 : 0
        backShade.opacity = open ? 1 : 0.2
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let w = Self.side, h = Self.side
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icon.frame = CGRect(x: px((bounds.width - w) / 2), y: px((bounds.height - h) / 2), width: w, height: h)
        let r = (w / 7).rounded()
        let tabH = px((h * 0.25).rounded())
        let t = (tabH / 1.5).rounded(.down)
        let line = px(1.25)
        // The back panel with its tab (the view is flipped: y runs down).
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: px(0.41 * w), y: 0))
        path.addLine(to: CGPoint(x: px(0.58 * w), y: t))
        path.addLine(to: CGPoint(x: w - r, y: t))
        path.addArc(center: CGPoint(x: w - r, y: t + r), radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        path.closeSubpath()
        let backFrame = CGRect(x: 0, y: 0, width: w, height: h)
        back.bounds = CGRect(origin: .zero, size: backFrame.size)
        back.position = CGPoint(x: backFrame.minX, y: backFrame.maxY)
        back.path = path
        back.lineWidth = line
        backShade.frame = back.bounds
        backShadeMask.frame = back.bounds
        backShadeMask.path = path
        let frontFrame = CGRect(x: 0, y: tabH, width: w, height: h - tabH)
        front.bounds = CGRect(origin: .zero, size: frontFrame.size)
        front.position = CGPoint(x: frontFrame.minX, y: frontFrame.maxY)
        let panel = CGPath(roundedRect: front.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        frontPanel.frame = front.bounds
        frontPanel.path = panel
        frontPanel.lineWidth = line
        frontShade.frame = front.bounds
        frontShadeMask.frame = front.bounds
        frontShadeMask.path = panel
        layoutEmblem(scale: scale)
        // In the holder's space (the icon's), everything but the front panel; the margin keeps the
        // turned square over the whole glyph.
        backHolder.frame = CGRect(x: 0, y: 0, width: w, height: h)
        frontHole.bounds = front.bounds
        frontHole.position = front.position
        let hole = CGMutablePath()
        hole.addRect(front.bounds.insetBy(dx: -w, dy: -h))
        hole.addPath(panel)
        frontHole.path = hole
        // In the front panel, on whole points so each dot is two pixels square at 1x.
        dots.frame = bounds
        let dotPath = CGMutablePath()
        let y = (icon.frame.minY + frontFrame.midY).rounded(.down) - 1
        for i in -1...1 { dotPath.addEllipse(in: CGRect(x: (bounds.width / 2).rounded(.down) + CGFloat(i) * 4 - 1, y: y, width: 2, height: 2)) }
        dots.path = dotPath
        CATransaction.commit()
    }

    /// Rasterize only when the image, ink, size or backing scale changes, never on animation frames.
    private func layoutEmblem(scale: CGFloat) {
        guard let emblem else {
            mark.contents = nil
            renderedEmblem = nil
            return
        }
        let side = min(front.bounds.width, front.bounds.height) * min(1, max(0, emblem.relativeSize))
        guard side > 0 else { mark.contents = nil; renderedEmblem = nil; return }
        let size = CGSize(width: side, height: side)
        mark.bounds = CGRect(origin: .zero, size: size)
        mark.position = CGPoint(x: front.bounds.midX, y: front.bounds.midY)
        mark.contentsScale = scale
        let rendering = EmblemRendering(emblem: emblem, tint: emblemTint, size: size, scale: scale)
        guard rendering != renderedEmblem else { return }
        mark.contents = emblem.rasterized(size: size, scale: scale, tint: emblemTint)
        renderedEmblem = rendering
    }
}
