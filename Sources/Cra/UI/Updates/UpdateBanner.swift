import AppKit

/// Arc's software-update sidebar banners (SidebarBanner `updateAvailable` and `updateSummary`),
/// above the space dock. Built from TidBITS's screenshots of Arc's banners (May 2023, at 4 px per
/// point) and Arc 1.171's bundle (ARC_SidebarBanner's update-heart-animation timing, the state's
/// fields: title, release notes, referral and video rows):
///
/// - Ready ("An update is ready!" / "Click to restart", and "New Cra Version Available"): a
///   56 pt card, title 13 pt semibold and subtitle 11 pt at 10 pt in, a 40 × 37 pt heart with a
///   download arrow knocked out of it, 10 pt from the right edge. The arrow lifts, dips and springs
///   back while a heart-shaped ripple grows to 129 % and fades (Arc's 2 s timing); it plays when
///   the card appears and loops while it's hovered.
/// - Updated ("Cra updated!"): a 102 pt card, title 14 pt medium with twinkling sparkles, an ✕,
///   and rows 31.7 pt apart with an icon on a faint 21 pt tile, 13 pt text and a drawn arrow:
///   What's new, Sponsor Cra. It pops in with a slight tilt that settles.
///
/// Cards are white at 82 % over light spaces (a faint white over dark ones); the heart, icons and
/// sparkles take the space's colour. The heart and arrow are Cra's own drawing.
@MainActor
final class UpdateBannerView: NSView {
    private enum Kind: Equatable {
        case ready(title: String, subtitle: String)
        case updated
    }

    /// What the banner says, or nil when there is nothing to say.
    static var isShown: Bool { kind != nil }

    /// Room the sidebar gives the banner (8 pt above the card).
    static var preferredHeight: CGFloat {
        switch kind {
        case .ready?: return 8 + ReadyCard.height
        case .updated?: return 8 + UpdatedCard.height
        case nil: return 0
        }
    }

    private static var kind: Kind? {
        let u = SoftwareUpdater.shared
        if u.readyRelease != nil, !u.bannerDismissed { return .ready(title: "An update is ready!", subtitle: "Click to restart") }
        if let r = u.foundRelease, !u.bannerDismissed { return .ready(title: "New Cra Version Available", subtitle: "Cra \(r.version)") }
        if u.updatedTo != nil { return .updated }
        return nil
    }

    var colors = SidebarColors() { didSet { if colors != oldValue { refresh() } } }
    /// The space's colour (its accent), for the heart, icons and sparkles.
    var themeColor: String? { didSet { if themeColor != oldValue { refresh() } } }
    private var shown: Kind?
    private var card: BannerCard?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        let kind = withObservationTracking { Self.kind } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard kind != shown else { return }
        let wasShown = shown != nil
        shown = kind
        card?.removeFromSuperview()
        card = nil
        guard let kind else { return }
        let c: BannerCard
        switch kind {
        case let .ready(title, subtitle): c = ReadyCard(title: title, subtitle: subtitle)
        case .updated: c = UpdatedCard()
        }
        c.onClose = { SoftwareUpdater.shared.dismissBanner() }
        addSubview(c)
        card = c
        refresh()
        needsLayout = true
        layoutSubtreeIfNeeded()
        if !wasShown { c.appear() }
    }

    private func refresh() {
        card?.apply(BannerPalette(colors: colors, themeColor: themeColor))
    }

    override func layout() {
        super.layout()
        guard let card else { return }
        let h = card is UpdatedCard ? UpdatedCard.height : ReadyCard.height
        card.frame = NSRect(x: 8, y: 8, width: max(0, bounds.width - 16), height: h)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let card, card.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}

/// Colours a banner card takes from its space.
struct BannerPalette {
    /// The card's fill at its top-left and bottom-right ends.
    let fill: (NSColor, NSColor)
    let hoverFill: (NSColor, NSColor)
    let title: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let accent: NSColor
    let icon: NSColor
    let hoverIcon: NSColor
    let heart: NSColor
    let tile: NSColor
    let dark: Bool

    init(colors: SidebarColors, themeColor: String?) {
        dark = colors.isDark
        let c = HexColor.components(themeColor ?? "") ?? (0.55, 0.45, 0.75)
        let (h, s, measured) = SpaceTheme.hsb(c.r, c.g, c.b)
        func hsb(_ s: Double, _ v: Double, _ a: CGFloat = 1) -> NSColor {
            let o = SpaceTheme.rgb(h: h, s: max(0, min(1, s)), v: max(0, min(1, v)))
            return NSColor(srgbRed: o.0, green: o.1, blue: o.2, alpha: a)
        }
        // Arc's purple space (#9E6EC4): the card fades from white 94 % at its top-left to 58 %
        // toward the bottom right; text is a dark tint of the space (secondary 70 %, the ✕ 36 %);
        // the heart a paler space colour at 60 %; icons the space colour, darker on hover;
        // sparkles a lighter, greyer tone.
        // On a pale space (a light grey, a yellow) those tones would vanish into the white card, so
        // the brightness they're built from is capped where the icon reaches the purple space's
        // contrast (luminance 0.21, about 4:1 on white). Arc's purple is untouched.
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        func iconLuminance(_ v: Double) -> Double {
            let o = SpaceTheme.rgb(h: h, s: max(0, min(1, s * 0.89)), v: max(0, min(1, v * 0.913)))
            return 0.2126 * lin(o.0) + 0.7152 * lin(o.1) + 0.0722 * lin(o.2)
        }
        var v = measured
        if !dark, iconLuminance(v) > 0.21 {
            var lo = 0.0, hi = v
            for _ in 0..<20 {
                let m = (lo + hi) / 2
                if iconLuminance(m) > 0.21 { hi = m } else { lo = m }
            }
            v = lo
        }
        let white = NSColor.white
        fill = dark ? (white.withAlphaComponent(0.12), white.withAlphaComponent(0.07)) : (white.withAlphaComponent(0.94), white.withAlphaComponent(0.58))
        hoverFill = dark ? (white.withAlphaComponent(0.16), white.withAlphaComponent(0.11)) : (white.withAlphaComponent(0.96), white.withAlphaComponent(0.66))
        let ink = hsb(s * 1.2, 0.216)
        title = dark ? colors.textPrimary : ink
        secondary = dark ? colors.textSecondary : ink.withAlphaComponent(0.7)
        tertiary = dark ? colors.textTertiary : ink.withAlphaComponent(0.36)
        accent = dark ? hsb(s * 0.55, 0.95) : hsb(s * 0.9, min(1, max(v, 0.55) * 1.04))
        icon = dark ? accent : hsb(s * 0.89, v * 0.913)
        hoverIcon = dark ? hsb(s * 0.4, 1) : hsb(s * 1.28, v * 0.78)
        heart = dark ? hsb(s * 0.5, 0.95, 0.45) : hsb(s * 0.735, v, 0.6)
        tile = dark ? NSColor.white.withAlphaComponent(0.03) : NSColor.black.withAlphaComponent(0.015)
    }
}

/// A banner card: hover, the ✕, and its entrance.
@MainActor
class BannerCard: NSView {
    var onClose: () -> Void = {}
    fileprivate var palette: BannerPalette?
    var hovering = false { didSet { if hovering != oldValue { hoverChanged() } } }
    let close = NSImageView()
    private let backdrop = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        backdrop.actions = ["colors": NSNull(), "bounds": NSNull(), "position": NSNull(), "startPoint": NSNull(), "endPoint": NSNull()]
        layer?.addSublayer(backdrop)
        close.image = SidebarSymbols.image("xmark", size: 10, weight: .medium)
        close.imageScaling = .scaleNone
        _ = ArcTooltipAnchorView.attach(to: close, help: "Dismiss")
        addSubview(close)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func apply(_ p: BannerPalette) {
        palette = p
        let f = hovering ? p.hoverFill : p.fill
        backdrop.colors = [f.0.cgColor, f.1.cgColor]
        close.contentTintColor = p.tertiary
    }

    override func layout() {
        super.layout()
        // Arc's fill falls 0.15 % per point across and 0.05 % per point down from the top-left
        // corner. The layer grades along its end point in unit space, so the slopes are scaled
        // into that space first.
        backdrop.frame = bounds
        let span: CGFloat = 0.94 - 0.58
        let a = 0.0015 * bounds.width / span, b = 0.0005 * bounds.height / span
        let n = max(0.0001, a * a + b * b)
        backdrop.startPoint = CGPoint(x: 0, y: 0)
        backdrop.endPoint = CGPoint(x: a / n, y: b / n)
    }

    func hoverChanged() { if let palette { apply(palette) } }

    /// Slides up from under the dock and fades in (the ready card); the updated card overrides.
    func appear() {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = 14
        move.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade, move]
        group.duration = 0.35
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer.add(group, forKey: "appear")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// After an automatic update Cra restarts in the background; the banner acts on the click
    /// that brings the window forward.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}

    /// True when the click was on the ✕ (and was handled).
    func handleClose(_ event: NSEvent) -> Bool {
        guard !close.isHidden, close.frame.insetBy(dx: -5, dy: -5).contains(convert(event.locationInWindow, from: nil)) else { return false }
        onClose()
        return true
    }
}

// MARK: - Ready to update

@MainActor
final class ReadyCard: BannerCard {
    static let height: CGFloat = 56
    private let title = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let subtitle = NSTextField.sidebarLabel(size: 11)
    private let heart = UpdateHeartView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        self.title.stringValue = title
        self.subtitle.stringValue = subtitle
        for v in [self.title, self.subtitle, heart] as [NSView] { addSubview(v) }
        close.isHidden = true
        addSubview(close, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(_ p: BannerPalette) {
        super.apply(p)
        title.textColor = p.title
        subtitle.textColor = p.secondary
        heart.color = p.heart
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        heart.frame = NSRect(x: w - 10 - 40, y: (Self.height - 37) / 2, width: 40, height: 37)
        let tw = max(0, heart.frame.minX - 6 - 10)
        title.frame = NSRect(x: 10 - SidebarText.inset, y: 11.5, width: tw + 2 * SidebarText.inset, height: 17)
        subtitle.frame = NSRect(x: 10 - SidebarText.inset, y: 30.5, width: tw + 2 * SidebarText.inset, height: 15)
        close.frame = NSRect(x: w - 18, y: 4, width: 14, height: 14)
    }

    override func appear() {
        super.appear()
        heart.play(after: 0.25)
    }

    override func hoverChanged() {
        super.hoverChanged()
        close.isHidden = !hovering
        heart.loops = hovering
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)), !handleClose(event) else { return }
        let u = SoftwareUpdater.shared
        if u.readyRelease != nil { u.installAndRelaunch() } else if u.foundRelease != nil { u.showFoundUpdate() }
    }
}

/// A heart with a download arrow knocked out of it, and a heart-shaped ripple. Drawn in Arc's
/// 247 × 229 design box; the motion is Arc's update-heart-animation (60 fps, 120 frames): the arrow
/// lifts 10 units by frame 15, dips 17.5 below rest by frame 45 and is home by 80; the ripple grows
/// from 100 % to 129 % and fades from 80 % to 0 between frames 26 and 107.
@MainActor
final class UpdateHeartView: NSView {
    private let heart = CAShapeLayer()
    private let ripple = CAShapeLayer()
    private static let box = CGSize(width: 247, height: 229)
    private static let cycle: CFTimeInterval = 2
    private var looping = false
    var color = NSColor.systemPurple { didSet { heart.fillColor = color.cgColor; ripple.fillColor = color.cgColor } }
    var loops = false {
        didSet {
            guard loops != oldValue else { return }
            if loops, !looping { play(after: 0) }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [ripple, heart] {
            l.fillRule = .evenOdd
            l.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(l)
        }
        ripple.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The heart, top cleft at (123.5, 38), point at (123.5, 229).
    private static func heartPath() -> CGMutablePath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 123.5, y: 229))
        p.addCurve(to: CGPoint(x: 0, y: 72), control1: CGPoint(x: 62, y: 184), control2: CGPoint(x: 0, y: 136))
        p.addCurve(to: CGPoint(x: 66, y: 0), control1: CGPoint(x: 0, y: 30), control2: CGPoint(x: 28, y: 0))
        p.addCurve(to: CGPoint(x: 123.5, y: 36), control1: CGPoint(x: 94, y: 0), control2: CGPoint(x: 114, y: 16))
        p.addCurve(to: CGPoint(x: 181, y: 0), control1: CGPoint(x: 133, y: 16), control2: CGPoint(x: 153, y: 0))
        p.addCurve(to: CGPoint(x: 247, y: 72), control1: CGPoint(x: 219, y: 0), control2: CGPoint(x: 247, y: 30))
        p.addCurve(to: CGPoint(x: 123.5, y: 229), control1: CGPoint(x: 247, y: 136), control2: CGPoint(x: 185, y: 184))
        p.closeSubpath()
        return p
    }

    /// A rounded down arrow, `dy` units below its resting place, stem and head merged into one
    /// shape. Measured from Arc's banner at 4 px per point: a 2.75 pt stroke, the stem's cap at
    /// 10.5 pt and the tip at 26.5 pt down a 36.75 pt heart, arms ending 6.2 pt either side.
    private static func arrowPath(dy: CGFloat) -> CGPath {
        let stem = CGMutablePath(), head = CGMutablePath()
        stem.move(to: CGPoint(x: 123.5, y: 73 + dy))
        stem.addLine(to: CGPoint(x: 123.5, y: 150 + dy))
        head.move(to: CGPoint(x: 85, y: 123.5 + dy))
        head.addLine(to: CGPoint(x: 123.5, y: 155 + dy))
        head.addLine(to: CGPoint(x: 162, y: 123.5 + dy))
        let w: CGFloat = 17
        return stem.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
            .union(head.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4))
    }

    private func transform() -> CGAffineTransform {
        let s = min(bounds.width / Self.box.width, bounds.height / Self.box.height)
        let x = (bounds.width - Self.box.width * s) / 2, y = (bounds.height - Self.box.height * s) / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: s, y: s)
    }

    private func heartWithArrow(_ dy: CGFloat) -> CGPath {
        let p = Self.heartPath().subtracting(Self.arrowPath(dy: dy))
        var t = transform()
        return p.copy(using: &t) ?? p
    }

    /// The ripple: a band along the heart's edge (the heart minus a 75 % heart).
    private func ripplePath() -> CGPath {
        let p = Self.heartPath()
        var inner = CGAffineTransform(translationX: 123.5, y: 114.5).scaledBy(x: 0.75, y: 0.75).translatedBy(x: -123.5, y: -114.5)
        if let i = Self.heartPath().copy(using: &inner) { p.addPath(i) }
        var t = transform()
        return p.copy(using: &t) ?? p
    }

    override func layout() {
        super.layout()
        for l in [heart, ripple] { l.frame = bounds }
        heart.path = heartWithArrow(0)
        ripple.path = ripplePath()
        let t = transform()
        ripple.anchorPoint = CGPoint(x: (123.5 * t.a + t.tx) / max(1, bounds.width), y: (114.5 * t.d + t.ty) / max(1, bounds.height))
        ripple.frame = bounds
    }

    /// One 2 s cycle; while `loops` is set it starts the next when this one ends.
    func play(after delay: CFTimeInterval) {
        looping = true
        layoutSubtreeIfNeeded()
        let begin = CACurrentMediaTime() + delay
        let frame: (Double) -> NSNumber = { NSNumber(value: $0 / 120) }

        let arrow = CAKeyframeAnimation(keyPath: "path")
        arrow.values = [heartWithArrow(0), heartWithArrow(-10), heartWithArrow(17.5), heartWithArrow(0), heartWithArrow(0)]
        arrow.keyTimes = [frame(0), frame(15), frame(45), frame(80), frame(120)]
        arrow.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.333, 0, 0.288, 1),
                                 CAMediaTimingFunction(controlPoints: 0.522, 0, 0.29, 1),
                                 CAMediaTimingFunction(controlPoints: 0.333, 0, 0.066, 1),
                                 CAMediaTimingFunction(name: .linear)]
        arrow.duration = Self.cycle
        arrow.beginTime = begin
        heart.add(arrow, forKey: "arrow")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1, 1.29, 1.29]
        scale.keyTimes = [frame(0), frame(26), frame(107), frame(120)]
        scale.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(controlPoints: 0.245, 0, 0.671, 1),
                                 CAMediaTimingFunction(name: .linear)]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.8, 0.8, 0, 0]
        fade.keyTimes = scale.keyTimes
        fade.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(controlPoints: 0.167, 0, 0.357, 1),
                                CAMediaTimingFunction(name: .linear)]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Self.cycle
        group.beginTime = begin
        ripple.add(group, forKey: "ripple")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.cycle) { [weak self] in
            guard let self else { return }
            self.looping = false
            if self.loops, self.window != nil { self.play(after: 0) }
        }
    }
}

// MARK: - Updated

@MainActor
final class UpdatedCard: BannerCard {
    static let height: CGFloat = 102
    private let title = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private let sparkles = SparklesView()
    private let rows: [BannerRow]

    init() {
        rows = [BannerRow(symbol: "heart", text: "What’s new") { SoftwareUpdater.shared.openReleaseNotes() },
                BannerRow(symbol: "gift", text: "Sponsor Cra") { SoftwareUpdater.shared.openSponsors() }]
        super.init(frame: .zero)
        title.stringValue = "Cra updated!"
        // Arc's ✕ here is larger and lighter than the ready card's hover one.
        close.image = SidebarSymbols.image("xmark", size: 12, weight: .regular)
        addSubview(title)
        addSubview(sparkles)
        for r in rows { addSubview(r) }
        addSubview(close, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply(_ p: BannerPalette) {
        super.apply(p)
        title.textColor = p.title
        sparkles.color = p.accent
        for r in rows { r.apply(p) }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let text = ceil(title.attributedStringValue.size().width)
        let tw = min(text, max(0, w - 12 - 34))
        title.frame = NSRect(x: 12 - SidebarText.inset, y: 18.5 - 9, width: tw + 2 * SidebarText.inset, height: 18)
        // The big sparkle's centre sits 6.4 pt past the title's last glyph, the small ones around it.
        let ink = min(tw, title.attributedStringValue.boundingRect(with: .zero, options: .usesDeviceMetrics).maxX)
        sparkles.frame = NSRect(x: 4, y: 2, width: min(w - 36, ink + 18.4), height: 36)
        close.frame = NSRect(x: w - 17 - 7, y: 19 - 7, width: 14, height: 14)
        for (i, r) in rows.enumerated() {
            r.frame = NSRect(x: 4, y: 49.4 + CGFloat(i) * 31.7 - 15, width: w - 8, height: 30)
        }
    }

    /// Pops in with a slight tilt that settles (Arc's banner is caught tilted mid-entrance).
    override func appear() {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.duration = 0.2
        let pop = CASpringAnimation(keyPath: "transform")
        var from = CATransform3DMakeScale(0.9, 0.9, 1)
        from = CATransform3DRotate(from, -0.05, 0, 0, 1)
        pop.fromValue = NSValue(caTransform3D: from)
        pop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        pop.mass = 1
        pop.stiffness = 220
        pop.damping = 16
        pop.duration = pop.settlingDuration
        // Scale and turn about the card's centre.
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        layer.add(fade, forKey: "fade")
        layer.add(pop, forKey: "pop")
        sparkles.start()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { sparkles.start() } else { sparkles.stop() }
    }

    override func mouseUp(with event: NSEvent) { _ = handleClose(event) }
}

/// A row: an icon on a faint tile and a label with an arrow; the whole row is the link.
@MainActor
final class BannerRow: NSView {
    private let tile = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 13, weight: .medium)
    private let arrow = CAShapeLayer()
    private let action: () -> Void
    private var palette: BannerPalette?
    private var hovering = false { didSet { if hovering != oldValue, let palette { apply(palette) } } }

    init(symbol: String, text: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 5
        tile.layer?.cornerCurve = .continuous
        icon.image = SidebarSymbols.image(symbol, size: 12.75, weight: .semibold)
        icon.imageScaling = .scaleNone
        label.stringValue = text
        // Arc's arrow is larger than the font's →: 12 × 10.25 pt with a 1.5 pt stroke.
        wantsLayer = true
        arrow.fillColor = nil
        arrow.lineWidth = 1.5
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.actions = ["position": NSNull(), "bounds": NSNull(), "strokeColor": NSNull()]
        let a = CGMutablePath(), c: CGFloat = 5.125, r: CGFloat = 4.375
        a.move(to: CGPoint(x: 0.75, y: c))
        a.addLine(to: CGPoint(x: 11.25, y: c))
        a.move(to: CGPoint(x: 11.25 - r, y: c - r))
        a.addLine(to: CGPoint(x: 11.25, y: c))
        a.addLine(to: CGPoint(x: 11.25 - r, y: c + r))
        arrow.path = a
        arrow.bounds = CGRect(x: 0, y: 0, width: 12, height: 10.25)
        addSubview(tile)
        addSubview(icon)
        addSubview(label)
        layer?.addSublayer(arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func apply(_ p: BannerPalette) {
        palette = p
        tile.layer?.backgroundColor = p.tile.cgColor
        icon.contentTintColor = hovering ? p.hoverIcon : p.icon
        label.textColor = hovering ? p.title : p.secondary
        arrow.strokeColor = label.textColor?.cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        // A 21 pt tile 8.6 pt in, the symbol centred on it (its image draws a little left of centre).
        tile.frame = NSRect(x: 8.6, y: (h - 21) / 2, width: 21, height: 21)
        icon.frame = tile.frame.offsetBy(dx: 0.25, dy: 0)
        let lh = label.intrinsicContentSize.height
        let ink = label.attributedStringValue.boundingRect(with: .zero, options: .usesDeviceMetrics).maxX
        let lw = min(ceil(label.attributedStringValue.size().width), max(0, bounds.width - 38 - 18))
        label.frame = NSRect(x: 38 - SidebarText.inset, y: (h - lh) / 2, width: lw + 2 * SidebarText.inset, height: lh)
        // 5.5 pt after the last glyph, centred 0.2 pt below the row's middle.
        arrow.position = CGPoint(x: 38 + min(ink, lw) + 5.5 + 6, y: h / 2 + 0.2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Four-point stars around the updated title that twinkle in turn (Arc's SparklesView: stars of
/// a few sizes, each pulsing scale and opacity on its own delay).
@MainActor
final class SparklesView: NSView {
    /// Position as a fraction of the view, size in points, delay in seconds.
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: CFTimeInterval)] = [
        (1.0, 0.2333, 8, 0), (0.06, 0.88, 2.5, 0.5), (0.42, 0.12, 2, 0.9), (0.62, 0.84, 1.8, 1.3), (0.24, 0.1, 1.6, 0.25)]
    private var layers: [CAShapeLayer] = []
    var color = NSColor.systemPurple { didSet { for l in layers { l.fillColor = color.cgColor } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in Self.stars {
            let l = CAShapeLayer()
            l.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull()]
            layer?.addSublayer(l)
            layers.append(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A four-point star with concave sides.
    private static func star(_ s: CGFloat) -> CGPath {
        let p = CGMutablePath(), r = s / 2, k = r * 0.1
        p.move(to: CGPoint(x: r, y: 0))
        p.addQuadCurve(to: CGPoint(x: 2 * r, y: r), control: CGPoint(x: r + k, y: r - k))
        p.addQuadCurve(to: CGPoint(x: r, y: 2 * r), control: CGPoint(x: r + k, y: r + k))
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: r - k, y: r + k))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: r - k, y: r - k))
        p.closeSubpath()
        return p
    }

    override func layout() {
        super.layout()
        for (l, s) in zip(layers, Self.stars) {
            l.bounds = CGRect(x: 0, y: 0, width: s.size, height: s.size)
            l.path = Self.star(s.size)
            l.fillColor = color.cgColor
            l.position = CGPoint(x: bounds.width * s.x - s.size / 2, y: bounds.height * s.y)
        }
    }

    func start() {
        layoutSubtreeIfNeeded()
        let now = CACurrentMediaTime()
        for (l, s) in zip(layers, Self.stars) where l.animation(forKey: "twinkle") == nil {
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.75, 1, 0.75]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.55, 1, 0.55]
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.6
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.repeatCount = .infinity
            group.beginTime = now + s.delay
            group.fillMode = .backwards
            l.add(group, forKey: "twinkle")
        }
    }

    func stop() { for l in layers { l.removeAnimation(forKey: "twinkle") } }
}
