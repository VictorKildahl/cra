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

/// The link a Peek came from: where it is in the browser window (window coordinates) and a picture
/// of it, at the window's scale (MainWindowController.peekSource).
struct PeekSource {
    let tabID: UUID
    let rect: NSRect
    let image: CGImage?
    /// How long a Peek waits for Chromium's answers before it opens or closes without them.
    static let wait: TimeInterval = 0.09

    /// A Runtime.evaluate result's value (returnByValue), when it is an object.
    static func value(_ result: String?) -> [String: Any]? {
        result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .flatMap { ($0["result"] as? [String: Any])?["value"] as? [String: Any] }
    }

    /// Page.captureScreenshot's picture.
    static func image(fromScreenshot shot: String?) -> CGImage? {
        shot.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .flatMap { $0["data"] as? String }.flatMap { Data(base64Encoded: $0) }
            .flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// The part of a viewport picture at `fraction` (y down, as the page measures).
    static func crop(_ image: CGImage, to fraction: CGRect) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let r = CGRect(x: fraction.minX * w, y: fraction.minY * h, width: fraction.width * w, height: fraction.height * h)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return r.isEmpty ? nil : image.cropping(to: r)
    }
}

/// Arc's Peek opening and closing, on Core Animation (GitHub #204). The card grows out of the
/// link it came from and closes back into it: a picture of the card and of its buttons rides in a
/// panel over the browser window while the real ones wait, invisible, at their places. A picture of
/// the link fills the moving frame and fades out over the card as it opens, back in as it closes.
/// Without a link (no pointer over one, a WebKit tab) the card grows from the whole area and fades
/// itself, as Arc does from a link that covers the page. The window server draws every frame,
/// nothing is resized or laid out while it runs, and the page window (which can't follow a frame
/// animation) is never moved. Every frame comes from PeekLayout, sampled at 120 Hz.
@MainActor
final class PeekTransition {
    private let panel: NSPanel
    /// The card's shadow and its clipped picture, faded together when there is no link picture.
    private let group = CALayer()
    private let shadow = CALayer()
    private let clip = CALayer()
    private let card = CALayer()
    private let link = CALayer()
    private let buttons = CALayer()
    private let cardFrame: NSRect
    private let columnFrame: NSRect
    private let source: NSRect
    private let hasLinkPicture: Bool
    static let easeOutCubic = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)

    /// `card`, `column` and `source` (the link, or the whole area) in `window`'s coordinates; the
    /// pictures at the window's scale.
    init(over window: NSWindow, card frame: NSRect, cardImage: CGImage?, column: NSRect, columnImage: CGImage?,
         source: NSRect, sourceImage: CGImage?) {
        cardFrame = frame
        columnFrame = column
        self.source = source
        hasLinkPicture = sourceImage != nil
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
        group.frame = view.bounds
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0.35
        shadow.shadowRadius = 14
        shadow.shadowOffset = CGSize(width: 0, height: -6)
        clip.cornerRadius = PeekLayout.cornerRadius
        clip.cornerCurve = .continuous
        clip.masksToBounds = true
        card.contents = cardImage
        card.contentsGravity = .resize
        card.contentsScale = scale
        link.contents = sourceImage
        link.contentsGravity = .resize
        link.contentsScale = scale
        link.opacity = 0
        buttons.contents = columnImage
        buttons.contentsGravity = .resize
        buttons.contentsScale = scale
        clip.addSublayer(card)
        clip.addSublayer(link)
        group.addSublayer(shadow)
        group.addSublayer(clip)
        view.layer?.addSublayer(group)
        view.layer?.addSublayer(buttons)
        place(PeekLayout.Moment(frame: frame, sourceOpacity: 0, buttonsOpacity: 1))
        // Nothing shows until open() or close() animates it: the panel reaches the screen before
        // the animations do, and its first frame showed the card at its final size.
        group.opacity = 0
        buttons.opacity = 0
        CATransaction.commit()
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    /// The layers' places at one moment, without animation.
    private func place(_ m: PeekLayout.Moment) {
        let v = values(m)
        for (layer, frame) in [(shadow, v.frame), (clip, v.frame), (card, v.content), (link, v.linkFrame), (buttons, v.column)] {
            layer.bounds = CGRect(origin: .zero, size: frame.size)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        shadow.shadowPath = v.shadowPath
    }

    private struct Values {
        var frame: CGRect, content: CGRect, linkFrame: CGRect, column: CGRect, shadowPath: CGPath
    }

    private func values(_ m: PeekLayout.Moment) -> Values {
        let f = m.frame
        let r = min(PeekLayout.cornerRadius, f.width / 2, f.height / 2)
        return Values(frame: f, content: PeekLayout.content(in: f, card: cardFrame),
                      linkFrame: CGRect(origin: .zero, size: f.size),
                      column: PeekLayout.column(columnFrame, card: cardFrame, frame: f),
                      shadowPath: CGPath(roundedRect: CGRect(origin: .zero, size: f.size), cornerWidth: r, cornerHeight: r, transform: nil))
    }

    /// Runs `moments` (sampled every 1/120 s over `duration`) on every layer, starting `lead` ahead.
    private func run(_ moments: [PeekLayout.Moment], duration: Double, keepEnd: Bool, done: @escaping () -> Void) {
        let begin = CACurrentMediaTime() + Self.lead
        let times = moments.indices.map { NSNumber(value: Double($0) / Double(max(1, moments.count - 1))) }
        let all = moments.map(values)
        func animate(_ layer: CALayer, _ keyPath: String, _ vals: [Any]) {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = vals
            a.keyTimes = times
            a.calculationMode = .linear
            a.beginTime = begin
            a.duration = duration
            a.fillMode = keepEnd ? .both : .backwards
            a.isRemovedOnCompletion = !keepEnd
            layer.add(a, forKey: keyPath)
        }
        func frames(_ layer: CALayer, _ pick: (Values) -> CGRect) {
            animate(layer, "bounds", all.map { NSValue(rect: CGRect(origin: .zero, size: pick($0).size)) })
            animate(layer, "position", all.map { NSValue(point: CGPoint(x: pick($0).midX, y: pick($0).midY)) })
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        frames(shadow) { $0.frame }
        frames(clip) { $0.frame }
        frames(card) { $0.content }
        frames(link) { $0.linkFrame }
        frames(buttons) { $0.column }
        animate(shadow, "shadowPath", all.map(\.shadowPath))
        let linkOpacity = moments.map { Float($0.sourceOpacity) }
        if hasLinkPicture {
            animate(link, "opacity", linkOpacity)
            animate(group, "opacity", moments.map { _ in Float(1) })
        } else {
            // No picture of the link: the card fades in its place.
            animate(group, "opacity", linkOpacity.map { 1 - $0 })
        }
        animate(buttons, "opacity", moments.map { Float($0.buttonsOpacity) })
        let end = moments.last!
        place(end)
        link.opacity = hasLinkPicture ? Float(end.sourceOpacity) : 0
        group.opacity = hasLinkPicture ? 1 : Float(1 - end.sourceOpacity)
        buttons.opacity = Float(end.buttonsOpacity)
        CATransaction.commit()
    }

    private static func samples(_ duration: Double, _ moment: (Double) -> PeekLayout.Moment) -> [PeekLayout.Moment] {
        let n = max(2, Int((duration * 120).rounded(.up)) + 1)
        return (0..<n).map { moment(duration * Double($0) / Double(n - 1)) }
    }

    /// A new panel reaches the screen a frame or two after it is ordered in, and the main thread
    /// still has the page to focus: animations clocked from now lost their first 60 ms. They start
    /// this far ahead instead, held at their first frame until then.
    static let lead: CFTimeInterval = 0.03

    /// The page behind a Peek drawn back to `scale` around `center` (the view's coordinates),
    /// animated from wherever it is now.
    static func scaleBackdrop(_ view: NSView, around center: CGPoint, to scale: CGFloat,
                              duration: TimeInterval, timing: CAMediaTimingFunction?) {
        guard let layer = view.layer else { return }
        let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                             y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
        let transform = CATransform3DMakeAffineTransform(PeekLayout.backdropTransform(scale: scale, around: center, anchor: anchor))
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = transform
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = NSValue(caTransform3D: from)
            animation.toValue = NSValue(caTransform3D: transform)
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: "peekBackdropScale")
        } else {
            layer.removeAnimation(forKey: "peekBackdropScale")
        }
        CATransaction.commit()
    }

    /// Out of the link (or the area) to the card's frame; `done` once it has landed.
    func open(done: @escaping () -> Void) {
        let d = PeekLayout.openDuration
        run(Self.samples(d) { PeekLayout.opening(from: self.source, to: self.cardFrame, at: $0) }, duration: d, keepEnd: false, done: done)
    }

    /// Back into the link (or out to the area, fading); `done` once it is gone.
    func close(done: @escaping () -> Void) {
        let target = source
        let scale = hasLinkPicture ? PeekLayout.closeScaleDuration : PeekLayout.closeToAreaDuration
        let d = PeekLayout.closeDuration(scale: scale)
        // The panel goes at the end, and the real link is under the picture.
        run(Self.samples(d) { PeekLayout.closing(from: self.cardFrame, to: target, at: $0, duration: scale) },
            duration: d, keepEnd: true, done: done)
    }

    func remove() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// A view's own drawing at its window's scale (the layer tree: Cra's views, not a page
    /// window), with `page` drawn over `pageRect` (the view's coordinates, y up) when given.
    static func picture(of view: NSView, page: CGImage? = nil, pageRect: NSRect = .zero) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        // AppKit hangs the subviews' layers under the view's only when the window displays;
        // before that render(in:) drew the card's navy background alone, without its bar or page.
        if let window = view.window { window.display() } else { view.displayIfNeeded() }
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
