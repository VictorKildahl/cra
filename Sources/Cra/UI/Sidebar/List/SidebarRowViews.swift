import AppKit
import SwiftUI

// The rows of a space's tab list, drawn by AppKit (see SpaceListView). Each row is a plain
// layer-backed view: hover comes from the list's one tracking area, clicks and drags from the
// row's own mouse events. Rows draw what their model says and nothing else; the list rebuilds
// the models when the store changes and hands a row a new one only when it differs.

/// The palette's colours as AppKit colours, converted once per list update.
struct SidebarColors: Equatable {
    var isDark = false
    var textPrimary = NSColor.labelColor
    var textSecondary = NSColor.secondaryLabelColor
    var textTertiary = NSColor.tertiaryLabelColor
    var hoverFill = NSColor.clear
    var selectedFill = NSColor.clear
    var separator = NSColor.separatorColor
    var pillFill = NSColor.clear

    init() {}

    init(_ p: SpacePalette) {
        isDark = p.isDark
        textPrimary = NSColor(p.textPrimary)
        textSecondary = NSColor(p.textSecondary)
        textTertiary = NSColor(p.textTertiary)
        hoverFill = NSColor(p.hoverFill)
        selectedFill = NSColor(p.selectedFill)
        separator = NSColor(p.separator)
        pillFill = NSColor(p.pillFill)
    }

    /// SidebarIconButton's glyph tone outside the header (no active state).
    var glyph: NSColor { isDark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.26) }
    /// A one-colour favicon or GitHub's mark on the sidebar.
    var monoGlyph: NSColor { isDark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.85) }
}

enum SidebarSymbols {
    static func image(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    /// The tab row's ✕ (or − for a pinned tab that stays): Arc strokes two 2 pt round-capped lines
    /// 4.25 pt out from a centre on a whole point, crisp at 1x. No SF Symbol size matches it, and an
    /// NSImage drawn for it came out thinner and off-centre at 1x, so the button strokes this itself.
    static func closeMark(minus: Bool = false, centre c: CGPoint) -> CGPath {
        let d: CGFloat = 4.25
        let p = CGMutablePath()
        if minus {
            p.move(to: CGPoint(x: c.x - d, y: c.y)); p.addLine(to: CGPoint(x: c.x + d, y: c.y))
        } else {
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x - d, y: c.y + d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
        }
        return p
    }
}

extension NSImageView {
    /// Arc's refresh ⇄ stop swap, fitted frame by frame to a 120 fps capture of Arc 1.170 (30 Oct): over
    /// ~90 ms the old glyph fades while shrinking to 0.7 and the new one fades in growing from 0.7,
    /// both easing in and out. (The system's Replace transition un-draws arrow.clockwise over 0.8 s.)
    func swapSymbol(_ image: NSImage?) {
        guard let superview, window != nil, let old = self.image, image != nil else { self.image = image; return }
        let ghost = NSImageView(frame: frame)
        ghost.wantsLayer = true
        ghost.imageScaling = imageScaling
        ghost.image = old
        ghost.contentTintColor = contentTintColor
        superview.addSubview(ghost, positioned: .above, relativeTo: self)
        self.image = image
        guard let layer, let ghostLayer = ghost.layer else { ghost.removeFromSuperview(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { ghost.removeFromSuperview() }
        // A press turn still settling goes out with the old glyph; the new one starts square.
        ghostLayer.transform = layer.transform
        for key in layer.animationKeys() ?? [] where key.hasPrefix("turn") {
            if let turn = layer.animation(forKey: key) { ghostLayer.add(turn, forKey: key) }
            layer.removeAnimation(forKey: key)
        }
        layer.transform = CATransform3DIdentity
        layer.setValue(nil, forKey: "turn")
        ghostLayer.opacity = 0
        ghostLayer.add(Self.swapAnimation(ghostLayer, fadeIn: false), forKey: "swap")
        layer.add(Self.swapAnimation(layer, fadeIn: true), forKey: "swap")
        CATransaction.commit()
    }

    private static func swapAnimation(_ layer: CALayer, fadeIn: Bool) -> CAAnimationGroup {
        let c = centre(of: layer)
        var small = CATransform3DMakeTranslation(c.x, c.y, 0)
        small = CATransform3DScale(small, 0.7, 0.7, 1)
        small = CATransform3DTranslate(small, -c.x, -c.y, 0)
        // Added to whatever turn the glyph has.
        let scale = CABasicAnimation(keyPath: "transform")
        scale.isAdditive = true
        scale.fromValue = NSValue(caTransform3D: fadeIn ? small : CATransform3DIdentity)
        scale.toValue = NSValue(caTransform3D: fadeIn ? CATransform3DIdentity : small)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fadeIn ? 0 : 1
        fade.toValue = fadeIn ? 1 : 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.09
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return group
    }

    /// Arc's press on the refresh arrow (same capture): a quarter turn clockwise about the arrow's
    /// circle while the button is down, back on release, 0.15 s ease-in-out each way. As in SwiftUI a
    /// turn is added on top of one still running, so a quick click only nudges the arrow.
    func pressTurn(_ down: Bool) {
        guard let layer else { return }
        let to: CGFloat = down ? .pi / 2 : 0
        let from = layer.value(forKey: "turn") as? CGFloat ?? 0
        guard to != from else { return }
        layer.setValue(to, forKey: "turn")
        let flipped = layer.contentsAreFlipped()
        // arrow.clockwise's circle sits 1/16 of the image's height below the image's centre.
        var c = Self.centre(of: layer)
        c.y += (flipped ? 1 : -1) * (image?.size.height ?? 0) / 16
        func turned(_ angle: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(c.x, c.y, 0)
            t = CATransform3DRotate(t, flipped ? angle : -angle, 0, 0, 1)
            return CATransform3DTranslate(t, -c.x, -c.y, 0)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = turned(to)
        if window != nil {
            // Even steps of angle, eased as a whole: a single matrix tween would swing the pivot.
            let steps = 30
            let turn = CAKeyframeAnimation(keyPath: "transform")
            turn.values = (0...steps).map { NSValue(caTransform3D: turned((from - to) * CGFloat(steps - $0) / CGFloat(steps))) }
            turn.isAdditive = true
            turn.duration = 0.15
            turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            turn.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.add(turn, forKey: "turn\(turn.beginTime)")
        }
        CATransaction.commit()
    }

    /// The layer's centre relative to its anchor: AppKit keeps a view layer's anchor where it likes.
    private static func centre(of layer: CALayer) -> CGPoint {
        CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x), y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
    }
}

enum SidebarText {
    /// NSTextField draws its text this far in from its frame; labels are placed that much
    /// further left so the text lands where SwiftUI's Text put it.
    static let inset: CGFloat = 2
}

extension NSTextField {
    static func sidebarLabel(size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: size, weight: weight)
        l.lineBreakMode = .byTruncatingTail
        l.usesSingleLineMode = true
        l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true
        return l
    }
}

/// SidebarIconButton for AppKit rows: a glyph with a rounded hover fill and an Arc tooltip.
final class SidebarGlyphButton: NSView {
    var action: () -> Void
    let size: NSSize
    private let glyph = NSImageView()
    private var shownSymbol: String?
    /// Arc turns the refresh arrow while it is pressed (NSImageView.pressTurn).
    private var turnsOnPress = false
    /// Stroked instead of the image (SidebarSymbols.closeMark).
    private var mark: CAShapeLayer?
    private var markMinus = false
    private var tip: ArcTooltipAnchorView?
    private var hovering = false { didSet { refresh() } }
    var colors: SidebarColors { didSet { if colors != oldValue { refresh() } } }

    /// Header buttons follow the app's active state (nil: the plain sidebar tone).
    var active: Bool? { didSet { if active != oldValue { refresh() } } }
    var enabled = true { didSet { if enabled != oldValue { refresh() } } }
    /// Drawn in this colour instead of the sidebar's glyph tone.
    var tint: NSColor? { didSet { if tint != oldValue { refresh() } } }
    /// Keeps the hover fill while what it opened is open (the player's volume drawer).
    var highlighted = false { didSet { if highlighted != oldValue { refresh() } } }

    init(symbol: String, size: CGFloat, height: CGFloat? = nil, iconSize: CGFloat, weight: NSFont.Weight = .medium, help: String,
         optionHelp: String? = nil, colors: SidebarColors, action: @escaping () -> Void) {
        self.size = NSSize(width: size, height: height ?? min(size, 28))
        self.colors = colors
        self.action = action
        super.init(frame: NSRect(origin: .zero, size: self.size))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        glyph.image = SidebarSymbols.image(symbol, size: iconSize, weight: weight)
        shownSymbol = symbol
        glyph.imageScaling = .scaleNone
        glyph.frame = bounds
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
        if !help.isEmpty {
            tip = ArcTooltipAnchorView.attach(to: self, help: help)
            tip?.optionText = optionHelp
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `animated` swaps another symbol in the way Arc swaps refresh and stop.
    func setSymbol(_ symbol: String, iconSize: CGFloat, weight: NSFont.Weight = .medium, help: String, animated: Bool = false) {
        let image = SidebarSymbols.image(symbol, size: iconSize, weight: weight)
        if animated, shownSymbol != nil, shownSymbol != symbol {
            glyph.swapSymbol(image)
            setHelp(help)
        } else {
            setGlyph(image, help: help)
        }
        shownSymbol = symbol
        turnsOnPress = animated && symbol == "arrow.clockwise"
    }

    func setGlyph(_ image: NSImage?, help: String) {
        shownSymbol = nil
        glyph.image = image
        glyph.isHidden = false
        mark?.isHidden = true
        setHelp(help)
    }

    /// Shows the tab row's ✕ / − (SidebarSymbols.closeMark) in place of the image.
    func setCloseMark(minus: Bool, help: String) {
        if mark == nil {
            let m = CAShapeLayer()
            m.fillColor = nil
            m.lineWidth = 2
            m.lineCap = .round
            m.actions = ["path": NSNull(), "strokeColor": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(m)
            mark = m
        }
        markMinus = minus
        shownSymbol = nil
        glyph.isHidden = true
        mark?.isHidden = false
        needsLayout = true
        refresh()
        setHelp(help)
    }

    func setHelp(_ help: String) {
        if let tip { (tip.text, tip.keys) = ArcTooltipLabel.split(help) } else if !help.isEmpty { tip = ArcTooltipAnchorView.attach(to: self, help: help) }
    }

    /// Arc 1.170 draws these glyphs at roughly 26% black while the app is in the background; with
    /// the app active its header glyphs darken to ~59% black, disabled ones stay at ~24%.
    private func refresh() {
        let tint: NSColor
        if colors.isDark {
            // Arc's row ✕ is a touch brighter than its other glyphs (white 0.6 over the hover fill, 1x).
            tint = enabled ? NSColor.white.withAlphaComponent(mark != nil ? 0.6 : 0.55) : colors.textTertiary.withAlphaComponent(colors.textTertiary.alphaComponent * 0.55)
        } else if let active {
            tint = NSColor.black.withAlphaComponent(enabled && active ? 0.59 : 0.24)
        } else {
            tint = enabled ? colors.glyph : colors.textTertiary.withAlphaComponent(colors.textTertiary.alphaComponent * 0.55)
        }
        glyph.contentTintColor = self.tint ?? tint
        mark?.strokeColor = (self.tint ?? tint).cgColor
        layer?.backgroundColor = ((hovering || highlighted) && enabled ? colors.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        guard let mark else { return }
        mark.frame = bounds
        // The centre on a whole point of the window: a dragged sidebar width is fractional.
        let mid = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let centre = convert(CGPoint(x: mid.x.rounded(), y: mid.y.rounded()), from: nil)
        mark.path = SidebarSymbols.closeMark(minus: markMinus, centre: centre)
        mark.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mark?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        // A new area under the pointer gets no mouseEntered, so without assumeInside it never sends
        // the mouseExited either and the hover fill sticks (buttons moved under a resting pointer).
        let inside = window.map { visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if inside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
        if hovering != inside { hovering = inside }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A button that appears under a resting pointer (a row's hover buttons) is hovered at once.
        if let w = window { hovering = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    // Rows hide their buttons rather than remove them; a button shown again under the pointer is hovered.
    override func viewDidHide() { hovering = false }
    override func viewDidUnhide() {
        viewDidMoveToWindow()
        if mark != nil { needsLayout = true }   // the row may have scrolled while hidden
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        if mark != nil { needsLayout = true }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        if turnsOnPress, enabled { glyph.pressTurn(true) }
    }
    override func mouseDragged(with event: NSEvent) {
        if turnsOnPress, enabled { glyph.pressTurn(bounds.contains(convert(event.locationInWindow, from: nil))) }
    }
    override func mouseUp(with event: NSEvent) {
        if turnsOnPress { glyph.pressTurn(false) }
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// FaviconView for AppKit rows: the cached favicon, one-colour glyphs flipped to suit the fill,
/// a globe while there is none.
final class SidebarFaviconView: NSImageView {
    private var shown: (NSImage?, Bool, Bool)?

    init(size: CGFloat = CraMetrics.favicon) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ icon: NSImage?, flip: Bool, colors: SidebarColors) {
        if let s = shown, s.0 === icon, s.1 == flip, s.2 == colors.isDark { return }
        shown = (icon, flip, colors.isDark)
        let size = frame.width
        if let icon {
            imageScaling = .scaleProportionallyUpOrDown
            if flip {
                let t = icon.copy() as! NSImage
                t.isTemplate = true
                image = t
                contentTintColor = colors.monoGlyph
            } else {
                image = icon
                contentTintColor = nil
            }
            layer?.cornerRadius = size * 0.22
            layer?.masksToBounds = true
        } else {
            imageScaling = .scaleNone
            image = SidebarSymbols.image("globe", size: size * 0.8)
            contentTintColor = colors.textTertiary
            layer?.masksToBounds = false
        }
    }

    func showGitHubMark(colors: SidebarColors, color: NSColor? = nil) {
        shown = nil
        imageScaling = .scaleProportionallyUpOrDown
        image = GitHubMark.image
        contentTintColor = color ?? colors.monoGlyph
        layer?.masksToBounds = false
    }
}

/// Arc's folder glyph (FolderIconView, read from Arc 1.171's binary): a back panel with the tab
/// and a front panel, both hinged at the bottom-left corner. Opening turns them toward you in
/// perspective, the front tipping forward and the back leaning away, each shaded darker as it
/// turns, with Core Animation's implicit 0.25 s transition. GitHub's mark on a live folder.
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
    private let mark = NSImageView()
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
        front.addSublayer(frontShade)
        for l in [back, front] as [CALayer] {
            // Hinged on the bottom-left corner.
            l.anchorPoint = CGPoint(x: 0, y: 1)
            icon.addSublayer(l)
        }
        layer?.addSublayer(icon)
        layer?.addSublayer(dots)
        mark.image = GitHubMark.image
        mark.imageScaling = .scaleProportionallyUpOrDown
        addSubview(mark)
        apply(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(expanded: Bool, peeked: Bool = false, live: Bool, tint: NSColor, fillColor: NSColor, animated: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [back, frontPanel] {
            l.fillColor = fillColor.cgColor
            l.strokeColor = tint.cgColor
        }
        mark.isHidden = !live
        mark.contentTintColor = tint
        dots.isHidden = !peeked || expanded || live
        dots.fillColor = tint.cgColor
        CATransaction.commit()
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
        // In the front panel, on whole points so each dot is two pixels square at 1x.
        dots.frame = bounds
        let dotPath = CGMutablePath()
        let y = (icon.frame.minY + frontFrame.midY).rounded(.down) - 1
        for i in -1...1 { dotPath.addEllipse(in: CGRect(x: (bounds.width / 2).rounded(.down) + CGFloat(i) * 4 - 1, y: y, width: 2, height: 2)) }
        dots.path = dotPath
        CATransaction.commit()
        mark.frame = NSRect(x: icon.frame.minX + (w - 7) / 2, y: icon.frame.minY + frontFrame.midY - 3.5, width: 7, height: 7)
    }
}

/// Arc's keyboard-focus ring: 2 pt systemYellow with black 6/6 dashes, inside the edge.
final class FocusRingLayer: CALayer {
    private let yellow = CAShapeLayer()
    private let dashes = CAShapeLayer()
    private var radius = CraMetrics.rowCorner
    /// Arc's ring round the open tab of a site in developer mode (TabHighlightView,
    /// TabHighlightState.developerTab, GitHub #139): systemYellow under black dashes at 80 %, a
    /// radius of 11, and dashes cut to the edge's length (1/60, 1/80 or 1/100 of it by width).
    private(set) var developer = false

    convenience init(radius: CGFloat) {
        self.init()
        self.radius = radius
    }

    convenience init(developer: Bool) {
        self.init()
        guard developer else { return }
        self.developer = true
        radius = 11
        yellow.strokeColor = NSColor.systemYellow.cgColor
        dashes.strokeColor = NSColor.black.cgColor
        dashes.opacity = 0.8
    }

    override init() {
        super.init()
        for l in [yellow, dashes] {
            l.fillColor = nil
            l.lineWidth = 2
            addSublayer(l)
        }
        yellow.strokeColor = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1).cgColor
        dashes.strokeColor = NSColor.black.withAlphaComponent(0.92).cgColor
        dashes.lineDashPattern = [6, 6]
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSublayers() {
        super.layoutSublayers()
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let r = developer ? min(radius, rect.width / 2, rect.height / 2) : radius - 1
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        for l in [yellow, dashes] {
            l.frame = bounds
            l.path = path
        }
        if developer, rect.width > 0 {
            let edge = 2 * rect.width + 2 * rect.height - 8 * r + 2 * .pi * r
            let d = edge / (rect.width < 210 ? 60 : rect.width < 346 ? 80 : 100)
            dashes.lineDashPattern = [NSNumber(value: Double(d)), NSNumber(value: Double(d))]
        }
    }
}

/// Arc's SlashView: between a pinned tab's favicon and its name once the tab has left its
/// pinned page (GitHub #139). A 2 pt round-capped stroke corner to corner of a 4 × 15 pt box,
/// in TabCellSlash (black or white at 30 %).
final class SidebarSlashView: NSView {
    static let size = NSSize(width: 4, height: 15)
    var color: NSColor = .gray { didSet { if color != oldValue { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 1, y: 1))
        p.line(to: NSPoint(x: bounds.width - 1, y: bounds.height - 1))
        p.lineWidth = 2
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
    }
}

/// What a drag over the list does to one row (SidebarDropPreview).
struct DropDecor: Equatable {
    var dimmed = false
    var nudge: CGFloat = 0
    /// "Move to Folder" / "Add to Split" on a folder or split the drop goes into.
    var badge: Badge?
    /// The row turns into what the drop makes.
    var combine: CombineDropPreview.Kind?
    var combineDragged: UUID?

    struct Badge: Equatable {
        let symbol: String
        let label: String
    }
}

// MARK: - Row base

@MainActor
class SidebarRowView: NSView {
    weak var list: SpaceListView?
    let key: SpaceListView.RowKey
    var colors: SidebarColors
    var isHovered = false { didSet { if isHovered != oldValue { hoverChanged() } } }
    private(set) var decor = DropDecor()
    private var badgeView: DropBadgeView?
    private var combineView: NSView?
    private var press: (event: NSEvent, point: NSPoint)?
    /// The hover/selection fill. Arc 1.170 draws it 36 pt tall on the 41 pt row pitch, so two
    /// filled rows keep a 5 pt gap (GitHub #10: Cra filled all 40 pt and rows touched).
    private let fillLayer = CALayer()
    static let fillInset: CGFloat = 2
    /// Arc starts a nested row's fill after its indent, so the gutter by a folder's tabs stays
    /// empty (GitHub #139). The fill, shadow, drop badge and focus ring all follow it.
    var fillLeading: CGFloat { 0 }
    var fillRect: CGRect {
        CGRect(x: fillLeading, y: Self.fillInset, width: max(0, bounds.width - fillLeading), height: max(0, bounds.height - 2 * Self.fillInset))
    }

    init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        self.key = key
        self.list = list
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = CraMetrics.rowCorner
        layer?.cornerCurve = .continuous
        fillLayer.cornerRadius = CraMetrics.rowCorner
        fillLayer.cornerCurve = .continuous
        // Changes show at once, as the view's own layer background did.
        fillLayer.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.insertSublayer(fillLayer, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func hoverChanged() { refreshBackground() }
    /// The row's resting fill (hover, selection).
    func baseFill() -> NSColor { .clear }
    /// Pointer moved within a hovered row (split rows track which pane it is over).
    func hoverMoved(to point: NSPoint) {}
    /// The item a press at `point` drags; nil when the row can't be dragged.
    func dragItemID(at point: NSPoint) -> UUID? { nil }
    func click(_ event: NSEvent, at point: NSPoint) {}
    func contextMenu(at point: NSPoint) -> NSMenu? { nil }
    /// The tooltip owner under the pointer.
    func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { nil }
    func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        colors = c
        refreshBackground()
    }

    func refreshBackground() {
        var fill = baseFill()
        if decor.combine != nil { fill = .clear } else if decor.badge != nil, fill == .clear { fill = colors.selectedFill }
        fillLayer.backgroundColor = fill.cgColor
    }

    /// Arc's bounce when a close button keeps the item (TabCellView, `deselect`): the row jumps to
    /// 90 % and springs back in ~0.24 s without overshoot (critically damped, recorded at 100 fps).
    func bounce() {
        guard let layer else { return }
        let a = layer.anchorPoint
        let c = CGPoint(x: bounds.width * (0.5 - a.x), y: bounds.height * (0.5 - a.y))
        var t = CATransform3DMakeTranslation(c.x, c.y, 0)
        t = CATransform3DScale(t, 0.9, 0.9, 1)
        t = CATransform3DTranslate(t, -c.x, -c.y, 0)
        let spring = CASpringAnimation(keyPath: "sublayerTransform")
        spring.fromValue = NSValue(caTransform3D: t)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        // Critically damped; tuned against a Cra recording to Arc's curve (half way at ~0.12 s).
        spring.mass = 1
        spring.stiffness = 119
        spring.damping = 21.8
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "bounce")
    }

    /// The open row's soft shadow under its fill, on light themes only.
    func setLifted(_ selected: Bool) {
        let lifted = selected && !colors.isDark && decor.combine == nil
        layer?.shadowOpacity = lifted ? 0.06 : 0
        if lifted {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowRadius = 3
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowPath = CGPath(roundedRect: fillRect, cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        }
    }

    override func layout() {
        super.layout()
        fillLayer.frame = fillRect
        if layer?.shadowOpacity ?? 0 > 0 {
            layer?.shadowPath = CGPath(roundedRect: fillRect, cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        }
    }

    func applyDecor(_ d: DropDecor, animated: Bool) {
        guard d != decor else { return }
        let old = decor
        decor = d
        let alpha: CGFloat = d.combine != nil ? 0 : (d.dimmed ? 0.4 : 1)
        for v in subviews where v !== combineView { animated ? (v.animator().alphaValue = alpha) : (v.alphaValue = alpha) }
        if let badge = d.badge {
            let v = badgeView ?? DropBadgeView()
            if badgeView == nil {
                badgeView = v
                v.frame = fillRect
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            v.show(badge, colors: colors)
            v.alphaValue = alpha
        } else if let v = badgeView {
            badgeView = nil
            v.removeFromSuperview()
        }
        if d.combine != old.combine || d.combineDragged != old.combineDragged {
            combineView?.removeFromSuperview()
            combineView = nil
            if let kind = d.combine, let dragged = d.combineDragged, let list, let target = list.store.item(itemIDForCombine),
               let draggedItem = list.store.item(dragged) {
                let depth = list.depth(of: key)
                let host = CombineDropPreview(kind: kind, target: target, dragged: draggedItem, depth: depth,
                                              palette: list.palette, favicons: list.favicons)
                host.frame = bounds
                host.autoresizingMask = [.width, .height]
                addSubview(host)
                combineView = host
            }
        }
        refreshBackground()
    }

    /// The item a combine preview draws as the drop's target.
    var itemIDForCombine: UUID { if case .item(let id) = key { return id }; return UUID() }

    // Clicks act on release (SwiftUI's tap); a press that moves 3 pt starts the row's drag.
    override func mouseDown(with event: NSEvent) {
        press = (event, convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = press else { return }
        let q = convert(event.locationInWindow, from: nil)
        guard hypot(q.x - p.point.x, q.y - p.point.y) > 3 else { return }
        press = nil
        if let id = dragItemID(at: p.point) { list?.beginDrag(id, from: self, event: p.event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let p = press else { return }
        press = nil
        click(event, at: p.point)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu(at: convert(event.locationInWindow, from: nil))
    }
}

/// The badge a folder or split shows while a drop would go into it.
private final class DropBadgeView: NSView {
    private let pill = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 11, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = CraMetrics.rowCorner
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.shadow = NSShadow()
        pill.layer?.shadowOpacity = 0.08
        pill.layer?.shadowRadius = 2
        pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(pill)
        pill.addSubview(icon)
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ badge: DropDecor.Badge, colors: SidebarColors) {
        layer?.borderColor = colors.textPrimary.withAlphaComponent(0.3).cgColor
        pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(colors.isDark ? 0.14 : 0.9).cgColor
        icon.image = SidebarSymbols.image(badge.symbol, size: 10, weight: .semibold)
        icon.contentTintColor = colors.textPrimary
        label.stringValue = badge.label
        label.textColor = colors.textPrimary
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let ls = label.intrinsicContentSize
        let w = 8 + 12 + 4 + ls.width + 8
        pill.frame = NSRect(x: bounds.width - 8 - w, y: (bounds.height - 22) / 2, width: w, height: 22)
        icon.frame = NSRect(x: 8, y: 5, width: 12, height: 12)
        label.frame = NSRect(x: 24, y: (22 - ls.height) / 2, width: ls.width, height: ls.height)
    }
}

// MARK: - Tab row

struct TabRowModel: Equatable {
    var id: UUID
    var depth: Int
    var pinned: Bool
    var title: String
    var customTitle: Bool
    var renameText: String
    var subtitle: String?
    var icon: NSImage?
    var flipIcon: Bool
    var githubMark: Bool
    var editing: Bool
    var selected: Bool
    var highlighted: Bool
    var capturing: Bool
    var audible: Bool
    var muted: Bool
    var unread: Bool
    var navigatedAway: Bool
    var focusRing: Bool
    /// The page's site is in developer mode: Arc rings the open tab (TabHighlightState.developerTab).
    var developerMode: Bool
    /// Shown under a closed folder (FolderPeek): its close button keeps it pinned.
    var peeked: Bool
    /// The pinned page's favicon (Arc: resetTabIcon), shown on the icon while it would go back there.
    var homeIcon: NSImage?
    var homeFlipIcon: Bool
    /// The favicon of a Peek opened from this tab (Arc: modalIcon), in the close button's place.
    var peekIcon: NSImage?
}

final class TabRowView: SidebarRowView, ArcTooltipTarget, NSTextFieldDelegate {
    private(set) var model: TabRowModel?
    private let favicon = SidebarFaviconView()
    private let titleLabel = NSTextField.sidebarLabel(size: 14)
    private let subtitleLabel = NSTextField.sidebarLabel(size: 11)
    private var renameField: NSTextField?
    private var accessories: [NSView] = []
    private var focusRing: FocusRingLayer?
    private let slash = SidebarSlashView(frame: NSRect(origin: .zero, size: SidebarSlashView.size))
    /// The pointer is on the favicon of a pinned tab away from its page (Arc's icon region):
    /// a click there goes back, and the line under the name says so.
    private var overIcon = false
    /// ⌘ is down while `overIcon`: a click separates the page from the pinned tab instead.
    private var separating = false
    private var flagsMonitor: Any?
    /// Arc's regional hover background for a tab that can go back: the icon's square or the body.
    private let regionLayer = CALayer()

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(favicon)
        addSubview(slash)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        regionLayer.cornerRadius = CraMetrics.rowCorner
        regionLayer.cornerCurve = .continuous
        regionLayer.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer?.insertSublayer(regionLayer, at: 1)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ m: TabRowModel) {
        guard m != model else { return }
        // A subtitle coming or going moves the title (developer mode on a live tab, GitHub #88).
        if (m.subtitle == nil) != (model?.subtitle == nil) || m.depth != model?.depth || m.navigatedAway != model?.navigatedAway {
            needsLayout = true
        }
        model = m
        if overIcon, !canReset { overIcon = false; stopWatchingFlags(); needsLayout = true }
        refreshIcon()
        slash.color = (colors.isDark ? NSColor.white : .black).withAlphaComponent(0.3)
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        refreshSubtitle()
        setAccessibilityLabel(m.title)
        if m.editing != (renameField != nil) { m.editing ? beginRename(m.renameText) : endRename() }
        // The keyboard's ring wins over developer mode's; they differ in tone and dash length.
        let ring: Bool? = m.focusRing ? false : (m.developerMode && m.selected ? true : nil)
        if ring != focusRing.map(\.developer) {
            focusRing?.removeFromSuperlayer()
            focusRing = nil
            if let developer = ring {
                let r = FocusRingLayer(developer: developer)
                r.frame = fillRect
                r.zPosition = 10
                layer?.addSublayer(r)
                focusRing = r
            }
        }
        rebuildAccessories()
        refreshBackground()
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override var fillLeading: CGFloat { CGFloat(model?.depth ?? 0) * CraMetrics.indent }

    override func baseFill() -> NSColor {
        guard let m = model else { return .clear }
        if m.highlighted { return colors.selectedFill }
        // A tab that can go back fills only the hovered region (regionLayer), as Arc does.
        return isHovered && !canReset ? colors.hoverFill : .clear
    }

    override func refreshBackground() {
        super.refreshBackground()
        setLifted(model?.highlighted == true)
        refreshRegion()
    }

    override func hoverChanged() {
        super.hoverChanged()
        if !isHovered { setOverIcon(false) }
        refreshIcon()
        rebuildAccessories()
    }

    override func hoverMoved(to point: NSPoint) { setOverIcon(canReset && iconRegion.contains(point)) }

    private var canReset: Bool { model.map { $0.navigatedAway && !$0.editing } ?? false }
    /// Arc's icon region (TabCellView.BackgroundRegion.icon): the 36 pt square at the fill's left.
    private var iconRegion: NSRect {
        NSRect(x: fillLeading, y: 0, width: Self.iconRegionWidth, height: bounds.height)
    }
    private static let iconRegionWidth: CGFloat = 36
    /// The body region starts this far into the fill (it overlaps the icon's square by 6 pt).
    private static let bodyRegionInset: CGFloat = 30

    private func setOverIcon(_ on: Bool) {
        guard on != overIcon else { return }
        overIcon = on
        if on { watchFlags() } else { stopWatchingFlags() }
        refreshIcon()
        refreshSubtitle()
        rebuildAccessories()
        refreshBackground()
        needsLayout = true
    }

    private func watchFlags() {
        separating = NSEvent.modifierFlags.contains(.command)
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, self.overIcon {
                let cmd = event.modifierFlags.contains(.command)
                if cmd != self.separating {
                    self.separating = cmd
                    self.refreshIcon()
                    self.refreshSubtitle()
                }
            }
            return event
        }
    }

    private func stopWatchingFlags() {
        separating = false
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopWatchingFlags() }
    }

    /// On the icon the pinned page's favicon stands in (⌘: the page's own, which separates);
    /// the slash hides on the icon and, on a background row, on the body too.
    private func refreshIcon() {
        guard let m = model else { return }
        if overIcon && !separating {
            favicon.show(m.homeIcon, flip: m.homeFlipIcon, colors: colors)
        } else if m.githubMark {
            favicon.showGitHubMark(colors: colors)
        } else {
            favicon.show(m.icon, flip: m.flipIcon, colors: colors)
        }
        slash.isHidden = !m.navigatedAway || overIcon || (isHovered && !m.highlighted)
    }

    private func refreshRegion() {
        guard let m = model, canReset, isHovered else { regionLayer.isHidden = true; return }
        let fill = fillRect
        if overIcon {
            // Over the open row's white fill only the icon's left corners round.
            regionLayer.frame = CGRect(x: fill.minX, y: fill.minY, width: Self.iconRegionWidth, height: fill.height)
            regionLayer.maskedCorners = m.highlighted ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        } else if !m.highlighted {
            regionLayer.frame = CGRect(x: fill.minX + Self.bodyRegionInset, y: fill.minY,
                                       width: max(0, fill.width - Self.bodyRegionInset), height: fill.height)
            regionLayer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        } else {
            regionLayer.isHidden = true
            return
        }
        regionLayer.backgroundColor = colors.hoverFill.cgColor
        regionLayer.isHidden = false
    }

    /// Arc's hover subtitle (HoverSubtitleState.reset, ⌘: resetAndSeparate) stands in for the
    /// line under the title while the pointer is on the icon.
    private var shownSubtitle: String? {
        overIcon ? (separating ? "Separate From Pinned Tab" : "Back to Pinned URL") : model?.subtitle
    }

    private func refreshSubtitle() {
        subtitleLabel.stringValue = shownSubtitle ?? ""
        subtitleLabel.textColor = colors.textTertiary
        subtitleLabel.isHidden = shownSubtitle == nil || renameField != nil
    }

    /// Recording dot, mute or playing sound, unread dot, and on hover close. Made once
    /// per row and shown or hidden: hover moves from row to row on every frame of a scroll.
    private lazy var captureDot: NSView = {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        let c = CALayer()
        c.frame = CGRect(x: 4.5, y: 4.5, width: 7, height: 7)
        c.cornerRadius = 3.5
        c.backgroundColor = NSColor.systemRed.cgColor
        dot.wantsLayer = true
        dot.layer?.addSublayer(c)
        _ = ArcTooltipAnchorView.attach(to: dot, help: "This tab is using your camera or microphone")
        return dot
    }()
    /// Arc 1.171: a playing or muted tab shows a speaker between the favicon and the title (17.5 pt
    /// wide, 8 pt before the title, in the glyph tone); clicking it mutes or unmutes the tab
    /// (31 Oct 2026, issue #28).
    private lazy var soundButton = SidebarGlyphButton(symbol: Self.soundSymbol, size: 20, iconSize: 13, weight: .regular,
                                                     help: "Mute Tab", colors: colors) { [weak self] in
        guard let self, let m = self.model, let list = self.list else { return }
        list.store.setMuted(m.id, !m.muted)
        list.actions.performAction("muteTab:\(m.id)")
    }
    private static let soundSymbol = "speaker.wave.3"
    private static let soundGlyphWidth: CGFloat = 17.5
    private var showsSound = false
    private lazy var peekBadge = SidebarFaviconView()
    private lazy var unreadDot: NSView = {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        return dot
    }()
    private lazy var closeButton: SidebarGlyphButton = {
        let b = SidebarGlyphButton(symbol: "xmark", size: Self.closeSize, iconSize: 13, help: "", colors: colors) {}
        b.setCloseMark(minus: false, help: "")
        return b
    }()
    /// Arc's close button: a 24 pt square (TabCellView, GitHub #139).
    private static let closeSize: CGFloat = 24
    private var closeKind: SidebarClose.Button?

    private func rebuildAccessories() {
        guard let m = model, list != nil else { return }
        let id = m.id
        var shown: [NSView] = []
        if m.capturing { shown.append(captureDot) }
        let sound = (m.muted || m.audible) && !m.editing
        if sound {
            if soundButton.superview == nil { addSubview(soundButton) }
            soundButton.colors = colors
            soundButton.setSymbol(m.muted ? "speaker.slash" : Self.soundSymbol, iconSize: 13, weight: .regular,
                                  help: m.muted ? "Unmute Tab" : "Mute Tab")
        }
        soundButton.isHidden = !sound
        if sound != showsSound { showsSound = sound; needsLayout = true }
        if let peek = m.peekIcon, !isHovered {
            peekBadge.show(peek, flip: false, colors: colors)
            shown.append(peekBadge)
        }
        if m.unread && !m.selected && !isHovered {
            unreadDot.layer?.backgroundColor = colors.textPrimary.withAlphaComponent(0.55).cgColor
            shown.append(unreadDot)
        }
        // Arc hides the button while the pointer is on the icon of a tab it can take back.
        if isHovered && !m.editing && !overIcon {
            // SidebarClose: a minus keeps the tab pinned (it unloads and goes back to its page), an
            // ✕ archives it. Either acts on this row only, picked tabs or not; ⌘W takes them all.
            let button = SidebarClose.tab(pinned: m.pinned, current: m.selected, navigatedAway: m.navigatedAway, peeked: m.peeked)
            if button != closeKind {
                closeKind = button
                closeButton.setCloseMark(minus: button.minus, help: button.help)
                closeButton.action = { [weak self] in
                    guard let self, let list = self.list else { return }
                    if button.minus {
                        self.bounce()
                        list.actions.closeTab(id)
                    } else {
                        list.store.archiveTab(id, reason: .manual)
                    }
                    list.ui.multiSelection.remove(id)
                }
            }
            closeButton.colors = colors
            shown.append(closeButton)
        }
        guard shown.map(ObjectIdentifier.init) != accessories.map(ObjectIdentifier.init) else { return }
        for v in accessories where !shown.contains(where: { $0 === v }) { v.isHidden = true }
        for v in shown {
            if v.superview == nil { addSubview(v) }
            v.isHidden = false
        }
        accessories = shown
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let h = bounds.height
        var x = CraMetrics.rowLeading + CGFloat(m.depth) * CraMetrics.indent
        favicon.frame = NSRect(x: x, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        if m.navigatedAway {
            // Arc: 4 pt, the slash, then the name 5 pt on (2 pt later than without it).
            x += CraMetrics.favicon + 4
            let s = SidebarSlashView.size
            slash.frame = NSRect(x: x, y: ((h - s.height) / 2).rounded(), width: s.width, height: s.height)
            x += s.width + 5
        } else {
            x += CraMetrics.favicon + 11
        }
        if showsSound {
            let s = soundButton.size
            soundButton.frame = NSRect(x: x - (s.width - Self.soundGlyphWidth) / 2, y: (h - s.height) / 2, width: s.width, height: s.height)
            x += Self.soundGlyphWidth + 8
        }
        // HStack(spacing: 11) with a Spacer(minLength: 4) between the text and the trailing items.
        var right = bounds.width - 6
        for v in accessories.reversed() {
            // The unread dot is centred where the close button shows on hover, which is also
            // under a live folder's refresh button (FolderRowView, Arc lines them up too).
            let s = v.frame.size
            let slot = v === unreadDot || v === peekBadge ? Self.closeSize : s.width
            v.frame = NSRect(x: right - slot / 2 - s.width / 2, y: (h - s.height) / 2, width: s.width, height: s.height)
            right = v.frame.minX - 11
        }
        let textWidth = max(0, right - 4 - 11 - x)
        let th = titleLabel.intrinsicContentSize.height
        if shownSubtitle != nil {
            let sh = subtitleLabel.intrinsicContentSize.height
            let top = (h - th - 1 - sh) / 2
            titleLabel.frame = NSRect(x: x - SidebarText.inset, y: top, width: textWidth + 2 * SidebarText.inset, height: th)
            subtitleLabel.frame = NSRect(x: x - SidebarText.inset, y: top + th + 1, width: textWidth + 2 * SidebarText.inset, height: sh)
        } else {
            titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: textWidth + 2 * SidebarText.inset, height: th)
        }
        if let f = renameField {
            let fh = f.intrinsicContentSize.height
            f.frame = NSRect(x: x - SidebarText.inset, y: (h - fh) / 2, width: max(0, bounds.width - 6 - x + SidebarText.inset), height: fh)
        }
        focusRing?.frame = fillRect
        refreshRegion()
    }

    // MARK: Rename

    private func beginRename(_ text: String) {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 14)
        f.textColor = colors.textPrimary
        f.delegate = self
        f.cell?.isScrollable = true
        renameField = f
        addSubview(f)
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
        needsLayout = true
        DispatchQueue.main.async { [weak self, weak f] in
            guard let f, let w = self?.window else { return }
            w.makeFirstResponder(f)
        }
    }

    private func endRename() {
        guard let f = renameField else { return }
        renameField = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        titleLabel.isHidden = false
        refreshSubtitle()
    }

    private func commitRename() {
        guard let m = model, let list, list.ui.renamingID == m.id, let f = renameField else { return }
        list.store.rename(m.id, to: f.stringValue)
        list.ui.renamingID = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { list?.ui.renamingID = nil; return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }

    // MARK: Events

    override func dragItemID(at point: NSPoint) -> UUID? { model?.editing == true ? nil : model?.id }

    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let m = model, let list else { return }
        // A click on the row (not the field) ends a rename, so it can never get stuck.
        if m.editing { commitRename() }
        // Arc: the favicon of a pinned tab away from its page takes it back there and opens it;
        // with ⌘ the page moves out to a new Today tab first (GitHub #139).
        if canReset, iconRegion.contains(point) {
            setOverIcon(false)
            if event.modifierFlags.contains(.command) {
                list.actions.separatePinnedTab(m.id)
            } else {
                list.actions.resetPinnedTab(m.id)
                list.ui.clearPicks(anchor: m.id)
                list.store.selectTab(m.id, window: list.ui.windowID)
            }
            return
        }
        list.clickTab(m.id, event: event)
    }

    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list else { return nil }
        return SidebarMenus.tab(m, list: list)
    }

    override func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { self }

    // ArcTooltipTarget: the title by the pointer; like Arc (didShowRenameHint),
    // "Double-click to rename" rides along once.
    var text: String { model.map { $0.editing ? "" : $0.title } ?? "" }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? {
        UserDefaults.standard.bool(forKey: "didShowRenameHint") || model?.customTitle != false ? nil : "Double-click to rename"
    }
    var optionText: String? { nil }
    var onShow: (() -> Void)? {
        { [weak self] in
            if self?.model?.customTitle == false { UserDefaults.standard.set(true, forKey: "didShowRenameHint") }
        }
    }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

// MARK: - Folder row

struct FolderRowModel: Equatable {
    var id: UUID
    var depth: Int
    var title: String
    var renameText: String
    var editing: Bool
    var expanded: Bool
    /// Closed with tabs kept in sight under it (FolderPeek): Arc draws three dots in the glyph.
    var peeked: Bool
    var live: Bool
    var tint: NSColor
    var fill: NSColor
    var tabCount: Int
    var liveBusy: Bool
    /// The warning button's tip after a failed refresh.
    var liveError: String?
    /// Where the warning button signs in, when GitHub asked for that (else it tries again).
    var liveSignInURL: String?
    var liveHelp: String
}

final class FolderRowView: SidebarRowView, NSTextFieldDelegate {
    private(set) var model: FolderRowModel?
    private let glyph = FolderGlyphView(frame: NSRect(x: 0, y: 0, width: CraMetrics.favicon, height: 20))
    private let titleLabel = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private var renameField: NSTextField?
    private var accessory: NSView?

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(glyph)
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ m: FolderRowModel) {
        guard m != model else { return }
        // The same folder opening or closing turns its glyph; a row taking another folder doesn't.
        let toggled = model.map { $0.id == m.id && $0.expanded != m.expanded } ?? false
        model = m
        glyph.show(expanded: m.expanded, peeked: m.peeked, live: m.live, tint: m.tint, fillColor: m.fill, animated: toggled && window != nil)
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        setAccessibilityLabel(m.title)
        if m.editing != (renameField != nil) { m.editing ? beginRename(m.renameText) : endRename() }
        rebuildAccessory()
        refreshBackground()
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override var fillLeading: CGFloat { CGFloat(model?.depth ?? 0) * CraMetrics.indent }
    override func baseFill() -> NSColor { isHovered ? colors.hoverFill : .clear }

    override func hoverChanged() {
        super.hoverChanged()
        rebuildAccessory()
    }

    /// A live folder's refresh button (spinner while it runs, warning after a failure);
    /// a closed folder's tab count on hover.
    private func rebuildAccessory() {
        accessory?.removeFromSuperview()
        accessory = nil
        guard let m = model, let list else { return }
        let id = m.id
        let hover = isHovered && !m.editing
        if m.live {
            if m.liveBusy {
                // A spinner fills its frame: the glyph's size, centred where the refresh button sits.
                let slot = NSView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
                let p = NSProgressIndicator(frame: NSRect(x: 7, y: 7, width: 12, height: 12))
                p.style = .spinning
                p.controlSize = .mini
                p.isIndeterminate = true
                p.startAnimation(nil)
                slot.addSubview(p)
                accessory = slot
            } else if let error = m.liveError {
                // Arc keeps the warning on hover too ("Sign back in to GitHub."): a click signs in, or tries again.
                let signIn = m.liveSignInURL
                accessory = SidebarGlyphButton(symbol: "exclamationmark.triangle", size: 26, iconSize: 13, weight: .regular,
                                               help: error, colors: colors) { [weak list] in
                    if let signIn { list?.actions.openURL(signIn) } else { LiveFolderManager.shared.refresh(id) }
                }
            } else if hover {
                accessory = SidebarGlyphButton(symbol: "arrow.clockwise", size: 26, iconSize: 12, help: m.liveHelp, colors: colors) {
                    LiveFolderManager.shared.refresh(id)
                }
            }
        } else if hover && !m.expanded {
            let l = NSTextField.sidebarLabel(size: 11, weight: .medium)
            l.stringValue = "\(m.tabCount)"
            l.textColor = colors.textTertiary
            l.sizeToFit()
            accessory = l
        }
        _ = list
        if let a = accessory { addSubview(a) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let h = bounds.height
        var x = CraMetrics.rowLeading + CGFloat(m.depth) * CraMetrics.indent
        glyph.frame = NSRect(x: x, y: (h - 20) / 2, width: CraMetrics.favicon, height: 20)
        x += CraMetrics.favicon + 11
        var right = bounds.width
        if let a = accessory {
            let s = a.frame.size
            // A live folder's button is centred over its tabs' unread dots and close buttons (17 pt in).
            right -= (m.live ? 4 : 8) + s.width
            a.frame = NSRect(x: right, y: (h - s.height) / 2, width: s.width, height: s.height)
            right -= 11
        }
        let th = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, right - 8 - 11 - x) + 2 * SidebarText.inset, height: th)
        if let f = renameField {
            let fh = f.intrinsicContentSize.height
            f.frame = NSRect(x: x - SidebarText.inset, y: (h - fh) / 2, width: max(0, bounds.width - 8 - x + SidebarText.inset), height: fh)
        }
    }

    private func beginRename(_ text: String) {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 14, weight: .medium)
        f.textColor = colors.textPrimary
        f.delegate = self
        f.cell?.isScrollable = true
        renameField = f
        addSubview(f)
        titleLabel.isHidden = true
        needsLayout = true
        DispatchQueue.main.async { [weak self, weak f] in
            guard let f, let w = self?.window else { return }
            w.makeFirstResponder(f)
        }
    }

    private func endRename() {
        guard let f = renameField else { return }
        renameField = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        titleLabel.isHidden = false
    }

    private func commitRename() {
        guard let m = model, let list, list.ui.renamingID == m.id, let f = renameField else { return }
        list.store.rename(m.id, to: f.stringValue.isEmpty ? "Folder" : f.stringValue)
        list.ui.renamingID = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { list?.ui.renamingID = nil; return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }

    override func dragItemID(at point: NSPoint) -> UUID? { model?.editing == true ? nil : model?.id }

    // Every click toggles, however fast they come: double-click-to-rename made quick
    // open/close clicks start a rename that then swallowed the clicks. Rename is in the menu.
    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let m = model, let list else { return }
        if m.editing { commitRename() }
        list.store.setExpanded(m.id, FolderPeek.clickOpens(expanded: m.expanded, peeked: m.peeked))
    }

    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list, let item = list.store.item(m.id) else { return nil }
        return item.isLiveFolder ? SidebarMenus.liveFolder(item, list: list) : SidebarMenus.folder(item, list: list)
    }
}

// MARK: - Split row

struct SplitRowModel: Equatable {
    struct Cell: Equatable {
        var id: UUID
        var title: String
        var icon: NSImage?
        var flipIcon: Bool
    }
    var id: UUID
    var depth: Int
    var today: Bool
    var selected: Bool
    /// Filled as the open row; not while the ⌘T bar's New Tab row stands in for it.
    var highlighted: Bool
    var focusRing: Bool
    var cells: [Cell]
}

/// Arc's split cell (SplitViewCellView): the panes side by side, hairlines between them, each
/// pane a pill while the split is open. Its close buttons follow SidebarClose.split: one at the
/// row's end for a pinned split or a Today split in the background, one in every pane of an
/// open Today split (GitHub #139).
final class SplitRowView: SidebarRowView {
    private(set) var model: SplitRowModel?
    private var cells: [SplitCellView] = []
    private var separators: [NSView] = []
    private var focusRing: FocusRingLayer?
    private lazy var closeButton: SidebarGlyphButton = {
        let b = SidebarGlyphButton(symbol: "xmark", size: SplitRowMetrics.button, iconSize: 13, help: "", colors: colors) {}
        b.setCloseMark(minus: false, help: "")
        b.isHidden = true
        addSubview(b)
        return b
    }()
    private var shownButtons: SidebarClose.SplitButtons?

    func apply(_ m: SplitRowModel) {
        guard m != model else { return }
        model = m
        if cells.map(\.cellID) != m.cells.map(\.id) {
            cells.forEach { $0.removeFromSuperview() }
            separators.forEach { $0.removeFromSuperview() }
            cells = m.cells.map { SplitCellView(cellID: $0.id, row: self) }
            separators = (0..<max(0, m.cells.count - 1)).map { _ in
                let v = NSView()
                v.wantsLayer = true
                return v
            }
            cells.forEach { addSubview($0) }
            separators.forEach { addSubview($0) }
        }
        for (c, cm) in zip(cells, m.cells) { c.apply(cm, colors: colors, pill: m.highlighted) }
        for s in separators {
            s.layer?.backgroundColor = colors.separator.cgColor
            s.isHidden = m.highlighted
        }
        if m.focusRing != (focusRing != nil) {
            if m.focusRing {
                let r = FocusRingLayer()
                r.zPosition = 10
                layer?.addSublayer(r)
                focusRing = r
            } else {
                focusRing?.removeFromSuperlayer()
                focusRing = nil
            }
        }
        refreshButtons()
        refreshBackground()
        needsLayout = true
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override var fillLeading: CGFloat { CGFloat(model?.depth ?? 0) * CraMetrics.indent }

    override func baseFill() -> NSColor {
        guard let m = model else { return .clear }
        return m.highlighted ? colors.selectedFill : (isHovered ? colors.hoverFill : .clear)
    }

    override func refreshBackground() {
        super.refreshBackground()
        setLifted(model?.highlighted == true)
    }

    override func hoverChanged() {
        super.hoverChanged()
        if !isHovered { cells.forEach { $0.hovering = false } }
        refreshButtons()
    }

    override func hoverMoved(to point: NSPoint) {
        for c in cells { c.hovering = c.frame.contains(point) }
    }

    /// The buttons show while the row is hovered, as on a tab's row.
    private func refreshButtons() {
        guard let m = model, let list else { return }
        let buttons: SidebarClose.SplitButtons? = isHovered ? SidebarClose.split(pinned: !m.today, current: m.selected) : nil
        guard buttons != shownButtons else { return }
        shownButtons = buttons
        let panes = m.cells.map(\.id)
        if case .row(let b)? = buttons {
            closeButton.setCloseMark(minus: b.minus, help: b.help)
            closeButton.colors = colors
            closeButton.action = { [weak self, weak list] in
                guard let self, let list else { return }
                // Keep: the whole split unloads and stays pinned; archive: the whole split goes.
                if b.minus {
                    self.bounce()
                    if let first = panes.first { list.actions.closeTab(first) }
                } else {
                    for p in panes { list.store.archiveTab(p, reason: .manual) }
                }
            }
            closeButton.isHidden = false
        } else {
            closeButton.isHidden = true
        }
        let perPane: SidebarClose.Button?
        if case .perPane(let b)? = buttons { perPane = b } else { perPane = nil }
        for c in cells { c.setClose(perPane) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard model != nil, !cells.isEmpty else { return }
        let fill = fillRect
        let gap = SplitRowMetrics.cellGap
        let n = CGFloat(cells.count)
        let w = (fill.width - 2 * SplitRowMetrics.cellInset - (n - 1) * gap) / n
        let button = closeButton.isHidden ? nil
            : NSRect(x: fill.maxX - SplitRowMetrics.buttonInset - SplitRowMetrics.button, y: (bounds.height - SplitRowMetrics.button) / 2,
                     width: SplitRowMetrics.button, height: SplitRowMetrics.button)
        if let button { closeButton.frame = button }
        var x = fill.minX + SplitRowMetrics.cellInset
        for (i, c) in cells.enumerated() {
            if i > 0 {
                separators[i - 1].frame = NSRect(x: x - gap / 2 - 0.5, y: SplitRowMetrics.separatorInset, width: 1,
                                                 height: bounds.height - 2 * SplitRowMetrics.separatorInset)
            }
            var cw = w
            // The row's button takes the end of the last pane (Arc shortens its pill to 5 pt before it).
            if let button, i == cells.count - 1 { cw = max(0, button.minX - SplitRowMetrics.cellToButton - x) }
            c.frame = NSRect(x: x, y: fill.minY, width: cw, height: fill.height)
            x += w + gap
        }
        focusRing?.frame = fillRect
    }

    private func cell(at point: NSPoint) -> SplitCellView? { cells.first { $0.frame.contains(point) } }

    // The split moves as one (into Pinned, a folder, another space); a pane leaves it through
    // the menu or ⌥ on its close button, as in Arc.
    override func dragItemID(at point: NSPoint) -> UUID? { model?.id }

    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let c = cell(at: point), let list else { return }
        list.store.selectTab(c.cellID, window: list.ui.windowID)
    }

    // Arc shows the split's menu over any pane; each pane's own items are a submenu in it.
    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list else { return nil }
        return SidebarMenus.split(m, list: list)
    }

    override func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { cell(at: point) }
}

/// Arc 1.171, measured at 1x (GitHub #139): panes 4 pt inside the fill and 4 pt apart, buttons 24 pt.
enum SplitRowMetrics {
    static let separatorInset: CGFloat = 9
    static let cellInset: CGFloat = 4
    static let cellGap: CGFloat = 4
    static let button: CGFloat = 24
    /// The row's button ends this far before the fill's end; a pane's 2 pt before the pane's.
    static let buttonInset: CGFloat = 6
    static let paneButtonInset: CGFloat = 2
    static let cellToButton: CGFloat = 5
    /// An open split's pane pill: 4 pt inside the fill top and bottom.
    static let pillInset: CGFloat = 4
    static let pillRadius: CGFloat = 7
    /// The favicon sits this far into its pane.
    static let favicon: CGFloat = 6
}

/// One pane inside the split row (Arc: SplitViewCellChildItemView).
final class SplitCellView: NSView, ArcTooltipTarget {
    let cellID: UUID
    private weak var row: SplitRowView?
    private let favicon = SidebarFaviconView()
    private let titleLabel = NSTextField.sidebarLabel(size: 14)
    private let pill = CALayer()
    private var close: SidebarGlyphButton?
    private var title = ""
    var hovering = false

    init(cellID: UUID, row: SplitRowView) {
        self.cellID = cellID
        self.row = row
        super.init(frame: .zero)
        wantsLayer = true
        pill.cornerRadius = SplitRowMetrics.pillRadius
        pill.cornerCurve = .continuous
        pill.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(pill)
        addSubview(favicon)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    // Presses go to the row, which knows which pane they are on; the close button keeps its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let close, close.frame.contains(convert(point, from: superview)) { return close }
        return nil
    }

    func apply(_ m: SplitRowModel.Cell, colors: SidebarColors, pill shown: Bool) {
        title = m.title
        favicon.show(m.icon, flip: m.flipIcon, colors: colors)
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        close?.colors = colors
        // Arc's open split: each pane a pill a shade darker than the white fill (224 on 241).
        pill.backgroundColor = (colors.isDark ? NSColor.white : .black).withAlphaComponent(0.07).cgColor
        pill.isHidden = !shown
        needsLayout = true
    }

    /// An open Today split's ✕ in this pane, or none.
    func setClose(_ button: SidebarClose.Button?) {
        close?.removeFromSuperview()
        close = nil
        guard let button, let row, let list = row.list else { needsLayout = true; return }
        let id = cellID
        let b = SidebarGlyphButton(symbol: "xmark", size: SplitRowMetrics.button, iconSize: 13, help: button.help,
                                   optionHelp: "Separate from Split View", colors: row.colors) { [weak list] in
            // Option-click un-splits instead of closing (Arc flag option-click-split-tab-close-button-to-unsplit).
            if NSEvent.modifierFlags.contains(.option) { list?.store.separateFromSplit(id) } else { list?.actions.closePane(id) }
        }
        b.setCloseMark(minus: false, help: button.help)
        addSubview(b)
        close = b
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.frame = bounds.insetBy(dx: 0, dy: SplitRowMetrics.pillInset)
        CATransaction.commit()
        let fx = SplitRowMetrics.favicon
        favicon.frame = NSRect(x: fx, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        var right = bounds.width
        if let close {
            let s = SplitRowMetrics.button
            close.frame = NSRect(x: right - SplitRowMetrics.paneButtonInset - s, y: (h - s) / 2, width: s, height: s)
            right = close.frame.minX
        }
        let th = titleLabel.intrinsicContentSize.height
        let x = fx + CraMetrics.favicon + 11
        titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, right - 4 - x) + 2 * SidebarText.inset, height: th)
    }

    var text: String { title }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

// MARK: - Small rows

struct LiveStatusModel: Equatable {
    var text: String
    var url: String?
    var depth: Int
}

/// A line inside an open live folder with nothing to show, or when GitHub can't be read.
final class LiveStatusRowView: SidebarRowView {
    private(set) var model: LiveStatusModel?
    private let label: NSTextField = {
        let l = NSTextField(wrappingLabelWithString: "")
        l.font = .systemFont(ofSize: 12)
        l.maximumNumberOfLines = 3
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func leading(depth: Int) -> CGFloat { CraMetrics.rowLeading + CGFloat(depth) * CraMetrics.indent + CraMetrics.favicon + 11 }

    static func height(_ m: LiveStatusModel, width: CGFloat) -> CGFloat {
        let w = max(1, width - leading(depth: m.depth) - 10)
        let font = NSFont.systemFont(ofSize: 12)
        let line = ceil(font.ascender - font.descender + font.leading)
        let r = (m.text as NSString).boundingRect(with: NSSize(width: w, height: line * 3), options: [.usesLineFragmentOrigin],
                                                  attributes: [.font: font])
        return ceil(min(r.height, line * 3)) + 16
    }

    func apply(_ m: LiveStatusModel) {
        guard m != model else { return }
        model = m
        label.stringValue = m.text
        refreshColors()
        needsLayout = true
    }

    private func refreshColors() {
        label.textColor = model?.url != nil && isHovered ? colors.textSecondary : colors.textTertiary
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refreshColors()
    }

    override func baseFill() -> NSColor { model?.url != nil && isHovered ? colors.hoverFill : .clear }
    override var fillLeading: CGFloat { CGFloat(model?.depth ?? 0) * CraMetrics.indent }

    override func hoverChanged() {
        super.hoverChanged()
        refreshColors()
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let x = Self.leading(depth: m.depth)
        label.frame = NSRect(x: x - SidebarText.inset, y: 8, width: max(0, bounds.width - x - 10) + 2 * SidebarText.inset, height: max(0, bounds.height - 16))
    }

    override func click(_ event: NSEvent, at point: NSPoint) {
        if let url = model?.url { list?.actions.openURL(url) }
    }
}

final class NewTabRowView: SidebarRowView {
    private let plus = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 14)
    /// Zen's ⌘ + New Tab: the clipboard's text under "Paste and Search", in Arc's 11 pt second line.
    private let preview = NSTextField.sidebarLabel(size: 11)
    private var flagsMonitor: Any?
    /// What a click opens while ⌘ is held over the row with text on the clipboard; nil reads New Tab.
    private var paste: ClipboardPaste?
    private var pasteCheck: Task<Void, Never>?

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        // Arc's plus, fitted pixel by pixel at 1x and 2x.
        plus.image = Self.plusImage
        plus.imageScaling = .scaleNone
        label.stringValue = "New Tab"
        preview.lineBreakMode = .byTruncatingTail
        preview.isHidden = true
        addSubview(plus)
        addSubview(label)
        addSubview(preview)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("New Tab")
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let plusImage = SidebarSymbols.image("plus", size: 14.5, weight: .medium)
    private static let clipboardImage = SidebarSymbols.image("doc.on.clipboard", size: 13, weight: .medium)

    /// While the ⌘T bar is open Arc draws this row as the open one: the selected tab's fill,
    /// shadow and text.
    private var active = false

    func apply(active: Bool) {
        guard active != self.active else { return }
        self.active = active
        refreshColors()
        refreshBackground()
    }

    private func refreshColors() {
        let c = isHovered || active ? colors.textPrimary : colors.textSecondary
        plus.contentTintColor = c
        label.textColor = c
        preview.textColor = colors.textTertiary
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refreshColors()
    }

    override func baseFill() -> NSColor { isHovered || active ? colors.selectedFill : .clear }

    override func refreshBackground() {
        super.refreshBackground()
        setLifted(active)
    }

    override func hoverChanged() {
        super.hoverChanged()
        refreshColors()
        if isHovered, flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                self?.checkClipboard(e.modifierFlags)
                return e
            }
        } else if !isHovered {
            stopWatchingKeys()
        }
        checkClipboard(NSEvent.modifierFlags)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopWatchingKeys() }
    }

    private func stopWatchingKeys() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
    }

    /// ⌘ alone over the row: what the clipboard holds, asked without reading it where reading
    /// would raise macOS's paste alert.
    private func checkClipboard(_ flags: NSEvent.ModifierFlags) {
        pasteCheck?.cancel()
        guard isHovered, flags.intersection([.command, .shift, .option, .control]) == .command else { return show(nil) }
        pasteCheck = Task { [weak self] in
            let found = await ClipboardPaste.peek()
            guard !Task.isCancelled else { return }
            self?.show(found)
        }
    }

    private func show(_ p: ClipboardPaste?) {
        guard p != paste else { return }
        paste = p
        plus.image = p == nil ? Self.plusImage : Self.clipboardImage
        label.stringValue = p?.title ?? "New Tab"
        preview.stringValue = p?.text?.replacingOccurrences(of: "\n", with: " ") ?? ""
        preview.isHidden = preview.stringValue.isEmpty
        setAccessibilityLabel(label.stringValue)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        plus.frame = NSRect(x: CraMetrics.rowLeading, y: 0, width: CraMetrics.favicon, height: h)
        let th = label.intrinsicContentSize.height
        let x = CraMetrics.rowLeading + CraMetrics.favicon + 9
        let w = max(0, bounds.width - 10 - x) + 2 * SidebarText.inset
        guard !preview.isHidden else {
            label.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: w, height: th)
            return
        }
        let ph = preview.intrinsicContentSize.height
        let top = (h - th - ph) / 2
        label.frame = NSRect(x: x - SidebarText.inset, y: top, width: w, height: th)
        preview.frame = NSRect(x: x - SidebarText.inset, y: top + th, width: w, height: ph)
    }

    override func click(_ event: NSEvent, at point: NSPoint) {
        // Read on the click: the user asked for the paste, so macOS lets it through or asks once.
        if paste != nil, event.modifierFlags.contains(.command), let text = ClipboardPaste.read() {
            show(nil)
            list?.actions.openTyped(text)
        } else {
            list?.actions.openCommandBar(.newTab)
        }
    }
}

/// The clipboard's text as a new tab (Zen's ⌘ + New Tab; Chrome's "Paste and Go" / "Paste and Search").
struct ClipboardPaste: Equatable {
    let isAddress: Bool
    /// The text itself where it can be read without macOS's paste alert, else nil.
    let text: String?

    var title: String { isAddress ? "Paste and Go" : "Paste and Search" }

    /// What the clipboard holds. Since macOS 15.4 reading it unasked raises an alert unless the user
    /// allowed Cra always; asking what kind of text it is never does.
    @MainActor static func peek() async -> ClipboardPaste? {
        let board = NSPasteboard.general
        guard board.types?.contains(.string) == true else { return nil }
        if #available(macOS 15.4, *), board.accessBehavior != .alwaysAllow {
            guard let found = try? await board.detectedPatterns(for: [\.probableWebURL, \.probableWebSearch]), !found.isEmpty else { return nil }
            return ClipboardPaste(isAddress: found.contains(\.probableWebURL), text: nil)
        }
        return read().map { ClipboardPaste(isAddress: TypedURL.looksLikeURL($0), text: $0) }
    }

    /// The clipboard's text on one line, nil when it holds none.
    @MainActor static func read() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string) else { return nil }
        let line = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty || line.count > 2048 ? nil : line
    }
}

/// The line between pinned and Today; "Clear" shows on hover.
final class DividerRowView: SidebarRowView {
    private let line = NSView()
    private var clear: ClearButton?
    private var hasToday = false

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        line.wantsLayer = true
        addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event) }

    func apply(hasToday: Bool) {
        self.hasToday = hasToday
        refresh()
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refresh()
    }

    override func hoverChanged() { refresh() }

    private func refresh() {
        line.layer?.backgroundColor = colors.separator.cgColor
        line.alphaValue = hasToday ? 1 : 0
        let show = isHovered && hasToday
        if show, clear == nil, let list {
            let b = ClearButton(colors: colors) { [weak list] in
                guard let list else { return }
                list.store.clearToday(list.spaceID)
            }
            b.alphaValue = 0
            addSubview(b)
            clear = b
            b.animator().alphaValue = 1
        } else if !show, let b = clear {
            clear = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                b.animator().alphaValue = 0
            } completionHandler: { b.removeFromSuperview() }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Arc 1.171 at 1x (GitHub #139): the line runs 18 pt in from both edges; "Clear" ends 20 pt in.
        var right = bounds.width - 18
        if let clear {
            let s = clear.fittingSize
            clear.frame = NSRect(x: bounds.width - 20 - s.width, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
            right = clear.frame.minX - 8
        }
        line.frame = NSRect(x: 18, y: (bounds.height - 1) / 2, width: max(0, right - 18), height: 1)
    }

    private final class ClearButton: NSView {
        private let label = NSTextField.sidebarLabel(size: 11, weight: .semibold)
        private let action: () -> Void

        init(colors: SidebarColors, action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            label.stringValue = "Clear"
            label.textColor = colors.textSecondary
            label.sizeToFit()
            addSubview(label)
            frame.size = label.frame.size
            _ = ArcTooltipAnchorView.attach(to: self, help: "Clear Today tabs")
        }

        required init?(coder: NSCoder) { fatalError() }

        override var fittingSize: NSSize { label.frame.size }
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
        }
    }
}

/// "Drop to Pin": an empty pinned list opens a target while a drag is on.
final class PinPlaceholderRowView: SidebarRowView {
    private let border = CAShapeLayer()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 12, weight: .medium)
    private var active = false

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        border.fillColor = nil
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer?.addSublayer(border)
        icon.image = SidebarSymbols.image("pin", size: 11, weight: .semibold)
        icon.imageScaling = .scaleNone
        label.stringValue = "Drop to Pin"
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(active: Bool) {
        self.active = active
        refresh()
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refresh()
    }

    override func baseFill() -> NSColor { active ? colors.hoverFill : .clear }

    private func refresh() {
        border.strokeColor = colors.textTertiary.withAlphaComponent(active ? 0.6 : 0.3).cgColor
        icon.contentTintColor = colors.textSecondary
        label.textColor = colors.textSecondary
        refreshBackground()
    }

    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        let ls = label.intrinsicContentSize
        let w = 14 + 6 + ls.width
        let x = (bounds.width - w) / 2
        icon.frame = NSRect(x: x, y: 0, width: 14, height: bounds.height)
        label.frame = NSRect(x: x + 20, y: (bounds.height - ls.height) / 2, width: ls.width, height: ls.height)
    }
}
