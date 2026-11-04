import AppKit

/// Arc's Tidy Downloads card (SidebarBanner, "Download renamed to:"), over the sidebar's foot with
/// its tail on the download bin. Measured on Arc 1.171, 4 Nov 2026 (60 fps, a dark space, 347 pt
/// sidebar): 8 pt from either side, 65 pt tall plus a 9 pt tail; "Download renamed to:" 12 pt in
/// blue, the new name 14 pt semibold, the old name 12 pt in blue, struck through; revert ↶ and close
/// ✕ at the top right; four-point sparkles twinkling round it. It springs out of the bin (0.55× to
/// 1.05× at 0.29 s, settled by 0.55 s), the strike draws in 0.5 s later over 0.15 s, and it shrinks
/// back into the bin in 0.12 s after 8 s.
final class DownloadRenameCard: NSView {
    static let bodyHeight: CGFloat = 65
    static let tail: CGFloat = 9
    static var height: CGFloat { bodyHeight + tail }

    let rename: TidyDownloadsService.Rename
    var onRevert: () -> Void = {}
    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    /// Where the tail points, in the card's coordinates (the bin's top centre).
    var tailX: CGFloat = 33 { didSet { needsLayout = true } }

    private let shape = CAShapeLayer()
    private let label = NSTextField.sidebarLabel(size: 12)
    private let newName = NSTextField.sidebarLabel(size: 14, weight: .semibold)
    private let oldName = NSTextField.sidebarLabel(size: 12)
    private let strike = CAShapeLayer()
    private let sparkles = CALayer()
    private var revert: SidebarGlyphButton!
    private var close: SidebarGlyphButton!
    private var dark: Bool

    init(rename: TidyDownloadsService.Rename, colors: SidebarColors) {
        self.rename = rename
        dark = colors.isDark
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(shape)
        label.stringValue = "Download renamed to:"
        newName.stringValue = rename.newName
        oldName.stringValue = rename.oldName
        for l in [label, newName, oldName] { addSubview(l) }
        oldName.wantsLayer = true
        strike.fillColor = nil
        strike.lineWidth = 1
        strike.strokeEnd = 0
        strike.actions = ["strokeEnd": NSNull(), "path": NSNull()]
        layer?.addSublayer(strike)
        layer?.addSublayer(sparkles)
        revert = SidebarGlyphButton(symbol: "arrow.uturn.backward", size: 26, iconSize: 13, weight: .medium,
                                    help: "Revert to original name", colors: colors) { [weak self] in self?.onRevert() }
        close = SidebarGlyphButton(symbol: "xmark", size: 26, iconSize: 13, help: "", colors: colors) { [weak self] in self?.onClose() }
        close.setCloseMark(minus: false, help: "Close")
        addSubview(revert)
        addSubview(close)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Download renamed to:, \(rename.newName), \(rename.oldName)")
        style()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Arc drew it navy on a dark space; a light space's card is white (Arc's Max picture), not measured.
    private func style() {
        let blue = NSColor(srgbRed: 0x34 / 255, green: 0x3B / 255, blue: 0xD1 / 255, alpha: 1)
        shape.fillColor = (dark ? NSColor(srgbRed: 0x03 / 255, green: 0x06 / 255, blue: 0x1F / 255, alpha: 1) : .white).cgColor
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = dark ? 0 : 0.12
        shape.shadowRadius = 6
        shape.shadowOffset = CGSize(width: 0, height: -1)
        label.textColor = blue
        oldName.textColor = blue
        strike.strokeColor = blue.cgColor
        newName.textColor = dark ? NSColor(white: 0.94, alpha: 1) : .black
        for b in [revert, close] { b?.tint = NSColor(white: dark ? 0.55 : 0.5, alpha: 1) }
    }

    override func layout() {
        super.layout()
        let w = bounds.width, body = Self.bodyHeight
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: body), cornerWidth: 12, cornerHeight: 12)
        let tx = min(max(tailX, 16), w - 16)
        p.move(to: CGPoint(x: tx - 7, y: body - 0.5))
        p.addLine(to: CGPoint(x: tx, y: body + Self.tail))
        p.addLine(to: CGPoint(x: tx + 7, y: body - 0.5))
        p.closeSubpath()
        shape.path = p
        shape.frame = bounds
        // Text 13 pt in; cap tops 12.5, 31 and 50 pt down (Arc).
        // The label stops short of ↶; the names may run to the card's right padding.
        func place(_ l: NSTextField, capTop: CGFloat, right: CGFloat) {
            let f = l.font ?? .systemFont(ofSize: 12)
            let top = capTop - (f.ascender - f.capHeight) - 1
            l.frame = NSRect(x: 13 - SidebarText.inset, y: top, width: max(0, w - 13 - right) + 2 * SidebarText.inset,
                             height: l.intrinsicContentSize.height)
        }
        place(label, capTop: 12.5, right: 64)
        place(newName, capTop: 31, right: 13)
        place(oldName, capTop: 50, right: 13)
        // ↶ and ✕ centred 47 and 21 pt in from the right, 17 pt down.
        close.frame = NSRect(x: w - 21 - 13, y: 17 - 13, width: 26, height: 26)
        revert.frame = NSRect(x: w - 47 - 13, y: 17 - 13, width: 26, height: 26)
        // The strike runs through the old name's lower-case middle.
        let f = oldName.font ?? .systemFont(ofSize: 12)
        let ink = (oldName.stringValue as NSString).size(withAttributes: [.font: f]).width
        let midY = 50 + f.capHeight - f.xHeight / 2
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 13, y: midY))
        line.addLine(to: CGPoint(x: 13 + ink, y: midY))
        strike.path = line
        strike.frame = bounds
        sparkles.frame = bounds
        if sparkles.sublayers == nil { addSparkles() }
    }

    /// Four-point stars where Arc had them: by the label, after the new name, at the old name's end,
    /// at the bottom left, each breathing on its own beat.
    private func addSparkles() {
        let w = bounds.width
        let spots: [(CGPoint, CGFloat, Float)] = [
            (CGPoint(x: 92, y: 9), 5, 0.6), (CGPoint(x: min(w - 70, 205), y: 30), 4, 0.5),
            (CGPoint(x: 168, y: 57), 10, 0.8), (CGPoint(x: 13, y: 60), 8, 0.6), (CGPoint(x: 68, y: 44), 4, 0.45),
        ]
        for (i, (c, size, peak)) in spots.enumerated() {
            let star = CAShapeLayer()
            star.path = Self.star(size: size)
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            star.position = c
            star.fillColor = NSColor(white: dark ? 0.85 : 0.6, alpha: 1).cgColor
            star.opacity = 0
            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            twinkle.values = [0, peak, peak * 0.35, peak]
            twinkle.keyTimes = [0, 0.3, 0.65, 1]
            twinkle.duration = 1.4 + Double(i) * 0.23
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.beginTime = CACurrentMediaTime() + 0.1 * Double(i)
            twinkle.fillMode = .both
            star.add(twinkle, forKey: "twinkle")
            sparkles.addSublayer(star)
        }
    }

    private static func star(size s: CGFloat) -> CGPath {
        let p = CGMutablePath(), c = s / 2, k = s * 0.12
        p.move(to: CGPoint(x: c, y: 0))
        p.addQuadCurve(to: CGPoint(x: s, y: c), control: CGPoint(x: c + k, y: c - k))
        p.addQuadCurve(to: CGPoint(x: c, y: s), control: CGPoint(x: c + k, y: c + k))
        p.addQuadCurve(to: CGPoint(x: 0, y: c), control: CGPoint(x: c - k, y: c + k))
        p.addQuadCurve(to: CGPoint(x: c, y: 0), control: CGPoint(x: c - k, y: c - k))
        return p
    }

    /// The tail's tip, where the card grows from and goes back to. The sidebar's layers run top
    /// down (flipped superview), so the tip is the layer's bottom edge at y 1.
    private func anchorOnTail() {
        guard let layer else { return }
        let f = frame
        let ax = tailX / max(1, f.width)
        layer.anchorPoint = CGPoint(x: ax, y: 1)
        layer.position = CGPoint(x: f.minX + ax * f.width, y: f.maxY)
    }

    func appear() {
        layoutSubtreeIfNeeded()
        anchorOnTail()
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.55
        spring.toValue = 1
        spring.mass = 1
        spring.stiffness = 162
        spring.damping = 14.4
        spring.duration = spring.settlingDuration
        layer?.add(spring, forKey: "in")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.1
        layer?.add(fade, forKey: "fadeIn")
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.beginTime = CACurrentMediaTime() + 0.5
        draw.duration = 0.15
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        draw.fillMode = .backwards
        strike.strokeEnd = 1
        strike.add(draw, forKey: "draw")
    }

    func disappear(then done: @escaping () -> Void) {
        anchorOnTail()
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.55
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [shrink, fade]
        g.duration = 0.12
        g.timingFunction = CAMediaTimingFunction(name: .easeIn)
        g.fillMode = .forwards
        g.isRemovedOnCompletion = false
        layer?.add(g, forKey: "out")
        CATransaction.commit()
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y <= Self.bodyHeight, bounds.contains(p) { onOpen() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard p.y >= 0, p.y <= Self.bodyHeight, p.x >= 0, p.x <= bounds.width else { return nil }
        return super.hitTest(point) ?? self
    }
}
