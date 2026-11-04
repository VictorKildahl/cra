import AppKit
import SwiftUI

/// Arc's Peek card bar (1.171, 3 Nov 2026): the page card's own 32 pt toolbar, not Little Arc's
/// strip. Back, forward and refresh from the card's edge as on a browser window's bar, the
/// address centred with its copy-link glyph, in the page's colour (white until it reports one).
@MainActor
final class PeekBarView: NSView {
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onReload: () -> Void = {}
    var onEditURL: () -> Void = {}
    var onCopy: () -> Void = {}

    private let state: LittleWindowState
    private let back = ToolbarGlyphButton()
    private let forward = ToolbarGlyphButton()
    private let reload = ToolbarGlyphButton()
    private let url = ToolbarURLButton()

    init(state: LittleWindowState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        for b in [back, forward, reload] { addSubview(b) }
        addSubview(url)
        back.action = { [weak self] in self?.onBack() }
        forward.action = { [weak self] in self?.onForward() }
        reload.action = { [weak self] in self?.onReload() }
        url.action = { [weak self] in self?.onEditURL() }
        url.onCopy = { [weak self] in self?.onCopy() }
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private struct Shown: Equatable {
        var url = "", themeColor = ""
        var canGoBack = false, canGoForward = false, isLoading = false
    }

    private func observe() {
        observeChanges(of: { [weak state] in
            state.map { Shown(url: $0.url, themeColor: $0.themeColor, canGoBack: $0.canGoBack, canGoForward: $0.canGoForward, isLoading: $0.isLoading) }
        }, apply: { [weak self] shown in
            if let shown { self?.apply(shown) }
        })
    }

    /// PaneToolbarView's colours for a page card: the page's report, else white.
    private func apply(_ state: Shown) {
        let hex = ToolbarColor.hex(reported: state.themeColor, remembered: nil)
        let light = (hex.flatMap(HexColor.luminance) ?? 1) > 0.6
        let fill = hex.map { NSColor(hex: $0) } ?? .white
        let fg = light ? NSColor.black.withAlphaComponent(0.8) : NSColor(hex: "#E4E0D4")
        let fgDim = light ? NSColor.black.withAlphaComponent(0.6) : NSColor(hex: "#F0E6CC").withAlphaComponent(0.9)
        let hover = NSColor.white.withAlphaComponent(0.1)
        layer?.backgroundColor = fill.cgColor
        back.configure(symbol: "arrow.left", image: nil, help: "Go Back (⌘[)", enabled: state.canGoBack, width: 37, iconSize: 15, tint: fgDim, hover: hover)
        forward.configure(symbol: "arrow.right", image: nil, help: "Go Forward (⌘])", enabled: state.canGoForward, width: 37, iconSize: 15,
                          tint: fgDim, hover: hover)
        reload.configure(symbol: state.isLoading ? "xmark" : "arrow.clockwise", image: nil, help: "Refresh (⌘R)", enabled: true, width: 37,
                         iconSize: 15, tint: fgDim, hover: hover, animated: true)
        let human = SuggestionEngine.humanURL(state.url)
        let host = AppSettings.siteKey(for: state.url) ?? human
        // Arc's Peek shows the path too ("example.com/peek"), dimmed after the host.
        url.isHidden = state.url.isEmpty
        url.show(host: host, path: human.hasPrefix(host) ? String(human.dropFirst(host.count)) : "", url: state.url, developer: false,
                 fg: fg, fgDim: fgDim, hover: NSColor.white.withAlphaComponent(0.08), copyHover: hover)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 2.5
        for b in [back, forward, reload] {
            b.iconRowHeight = 26
            b.frame = NSRect(x: x, y: (h - 26) / 2, width: b.width, height: 26)
            x += b.width
        }
        // Centred on the card, clear of the buttons on either side.
        let room = max(0, bounds.width - 2 * (x + 6 + 8))
        let uw = min(url.idealWidth, room)
        url.frame = NSRect(x: (bounds.width - uw) / 2, y: (h - 28) / 2, width: uw, height: 28)
    }
}

/// Close, Expand and Add To Split beside the Peek card (Arc's confirmCloseModal,
/// openInSpaceExpander and openInSplit): round buttons in the space's darkest tone with its light
/// foreground for the glyph, each with Arc's tip.
@MainActor
final class PeekControlsPanel: NSPanel {
    struct Button {
        let symbol: String
        let help: String
        let run: () -> Void
    }

    private let views: [PeekControlButton]

    init(buttons: [Button]) {
        views = buttons.map { PeekControlButton(symbol: $0.symbol, help: $0.help, run: $0.run) }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let content = NSView()
        for v in views { content.addSubview(v) }
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `frames`: each button's screen frame, top first.
    func place(_ frames: [NSRect], theme: SpaceTheme) {
        let margin: CGFloat = 8  // room for the buttons' shadows
        let all = frames.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
        setFrame(all, display: false)
        let tones = TooltipTones(theme: theme)
        let fill = NSColor(srgbRed: tones.fill.r, green: tones.fill.g, blue: tones.fill.b, alpha: 1)
        let ink = NSColor(LittlePalette.spaceName(theme))
        for (v, f) in zip(views, frames) {
            v.frame = NSRect(x: f.minX - all.minX, y: f.minY - all.minY, width: f.width, height: f.height)
            v.paint(fill: fill, ink: ink)
        }
    }
}

final class PeekControlButton: NSView {
    private let run: () -> Void
    private let glyph = NSImageView()
    private let symbol: String
    private var pressed = false

    init(symbol: String, help: String, run: @escaping () -> Void) {
        self.run = run
        self.symbol = symbol
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        _ = ArcTooltipAnchorView.attach(to: self, help: help)
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(fill: NSColor, ink: NSColor) {
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        glyph.image = SidebarSymbols.image(symbol, size: 15, weight: .semibold)
        glyph.contentTintColor = ink
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        glyph.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        pressed = true
        alphaValue = 0.8
    }
    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { pressed = false; return }
        pressed = false
        run()
    }
}

/// Arc's Peek opening and closing, on Core Animation. A picture of the card and of its buttons
/// rides in a panel over the browser window while the real ones wait, invisible, at their places:
/// the window server draws every frame, nothing is resized or laid out while it runs, and the
/// page window (which can't follow a frame animation) is never moved. Curves from PeekLayout.
@MainActor
final class PeekTransition {
    private let panel: NSPanel
    private let group = CALayer()
    private let shadow = CALayer()
    private let card = CALayer()
    private let buttons = CALayer()
    /// Arc's ease-out on the card's scale, and the near-linear way back out.
    static let easeOutCubic = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
    static let closeCurve = CAMediaTimingFunction(controlPoints: 0.25, 0.25, 0.5, 1)

    /// `card` and `column` in `window`'s coordinates; the pictures at the window's scale.
    init(over window: NSWindow, card frame: NSRect, cardImage: CGImage?, column: NSRect, columnImage: CGImage?) {
        panel = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let view = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        view.wantsLayer = true
        panel.contentView = view
        let scale = window.backingScaleFactor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        group.frame = frame
        shadow.frame = group.bounds
        shadow.shadowPath = CGPath(roundedRect: group.bounds, cornerWidth: PeekLayout.cornerRadius, cornerHeight: PeekLayout.cornerRadius, transform: nil)
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0.35
        shadow.shadowRadius = 14
        shadow.shadowOffset = CGSize(width: 0, height: -6)
        card.frame = group.bounds
        card.cornerRadius = PeekLayout.cornerRadius
        card.cornerCurve = .continuous
        card.masksToBounds = true
        card.contents = cardImage
        card.contentsGravity = .resize
        card.contentsScale = scale
        group.addSublayer(shadow)
        group.addSublayer(card)
        buttons.frame = column
        buttons.contents = columnImage
        buttons.contentsGravity = .resize
        buttons.contentsScale = scale
        view.layer?.addSublayer(group)
        view.layer?.addSublayer(buttons)
        // Nothing shows until open() or close() animates it: the panel reaches the screen before
        // the animations do, and its first frame showed the card at its final size.
        group.opacity = 0
        buttons.opacity = 0
        CATransaction.commit()
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    /// From the whole area to the card's frame, fading in; `done` once it has landed.
    /// A new panel reaches the screen a frame or two after it is ordered in, and the main thread
    /// still has the page to focus: animations clocked from now lost their first 60 ms. They start
    /// this far ahead instead, held at their first frame until then.
    static let lead: CFTimeInterval = 0.03

    func open(done: @escaping () -> Void) {
        let k = PeekLayout.areaScale
        let shift = PeekLayout.cornerShift(card: group.frame, scale: k)
        let now = CACurrentMediaTime() + Self.lead
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        for layer in [group, buttons] {
            layer.opacity = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = PeekLayout.openFadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.beginTime = now
            fade.fillMode = .backwards
            layer.add(fade, forKey: "fade")
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = k
        grow.toValue = 1
        let ride = CABasicAnimation(keyPath: "position")
        ride.fromValue = NSValue(point: NSPoint(x: buttons.position.x + shift.dx, y: buttons.position.y + shift.dy))
        ride.toValue = NSValue(point: buttons.position)
        for (layer, a) in [(group, grow), (buttons, ride)] as [(CALayer, CABasicAnimation)] {
            a.beginTime = now + PeekLayout.openScaleDelay
            a.duration = PeekLayout.openScaleDuration
            a.timingFunction = Self.easeOutCubic
            a.fillMode = .backwards
            layer.add(a, forKey: "move")
        }
        CATransaction.commit()
    }

    /// Back out to the whole area, fading partway; `done` once it is gone.
    func close(done: @escaping () -> Void) {
        let k = PeekLayout.areaScale
        let shift = PeekLayout.cornerShift(card: group.frame, scale: k)
        let now = CACurrentMediaTime() + Self.lead
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = k
        let ride = CABasicAnimation(keyPath: "position")
        ride.fromValue = NSValue(point: buttons.position)
        ride.toValue = NSValue(point: NSPoint(x: buttons.position.x + shift.dx, y: buttons.position.y + shift.dy))
        for (layer, a) in [(group, grow), (buttons, ride)] as [(CALayer, CABasicAnimation)] {
            a.beginTime = now
            a.duration = PeekLayout.closeScaleDuration
            a.timingFunction = Self.closeCurve
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: "move")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.beginTime = now + PeekLayout.closeFadeDelay
            fade.duration = PeekLayout.closeFadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.fillMode = .backwards
            layer.add(fade, forKey: "fade")
            layer.opacity = 0
        }
        CATransaction.commit()
    }

    func remove() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// A view's own drawing at its window's scale (the layer tree: Cra's views, not a page
    /// window), with `page` drawn over `pageRect` (the view's coordinates, y up) when given.
    static func picture(of view: NSView, page: CGImage? = nil, pageRect: NSRect = .zero) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let layer = view.layer else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.saveGState()
        if layer.isGeometryFlipped || view.isFlipped {
            ctx.translateBy(x: 0, y: view.bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        ctx.restoreGState()
        if let page { ctx.draw(page, in: pageRect) }
        return ctx.makeImage()
    }
}
