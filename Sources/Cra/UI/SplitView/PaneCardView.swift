import AppKit
import CraCEF
import SwiftUI

/// One content pane: Arc's rounded card with its toolbar strip on top and the
/// page below (ARCUI.SplitViewContentPaneView + Arc.WindowContentViewController).
/// A pane without a page (Arc's "Search or Enter URL…" pane) is a translucent
/// tinted card with nothing but the toolbar.
final class PaneCardView: NSView {
    private(set) var tabID: UUID
    /// The pane's toolbar (PaneToolbarView); it follows the card's tab itself.
    let toolbarHost: NSView
    /// Where the Chromium view lives (or where the page window is positioned).
    let webArea = NSView()
    /// Hairline under the toolbar when the pane has no page (Arc draws it on the tinted card).
    private let hairline = NSView()
    /// The card behind the toolbar, in the toolbar's colour. A card with a page paints nothing else:
    /// under the page window's anti-aliased corners any fill of the card's shape shows as a light rim.
    private let toolbarBackground = NSView()
    /// The page's stand-in fill under the page window, inset from the card's rounded edges: the
    /// page window's corners are anti-aliased, so a fill reaching the card's edge showed through
    /// them as a light rim in every rounded corner.
    private let pageBackground = NSView()
    var showToolbar = true { didSet { needsLayout = true } }
    var toolbarHeight: CGFloat = CraMetrics.toolbarHeight {
        didSet { if toolbarHeight != oldValue { needsLayout = true; onToolbarHeightChange?() } }
    }
    /// The shell lays the page windows out again when the bar's height changes.
    var onToolbarHeightChange: (() -> Void)?
    /// Arc's developer bar (PaneToolbarView): its colour behind the bar, and its 40 pt height.
    var developerBar: NSColor? {
        didSet {
            guard developerBar != oldValue else { return }
            toolbarHeight = developerBar == nil ? CraMetrics.toolbarHeight : CraMetrics.developerToolbarHeight
            refreshBackground()
        }
    }
    var cornerRadius: CGFloat = CraMetrics.contentCornerRadius {
        didSet {
            layer?.cornerRadius = cornerRadius
            ring.layer?.cornerRadius = cornerRadius
            needsLayout = true
            syncShadow()
        }
    }
    /// White page card, or Arc's tinted translucent empty pane.
    var hasPage = true { didSet { refreshBackground(); syncShadow() } }
    var isDark = false { didSet { refreshBackground() } }
    /// The page's own background ("#RRGGBB"; Arc's canvas until it reports one). The page window
    /// trails the card by a frame or more while the window is resized quickly, and a page that is
    /// loading has not painted yet; in those gaps the page area must look like the page, not
    /// like a white card.
    var pageColor: String? { didSet { refreshBackground() } }
    /// The canvas follows the appearance pages get (the app's), not the space theme's.
    private var appearanceObservation: NSKeyValueObservation?
    /// The toolbar's colour (ToolbarColor: the page's, else the tab's last, else white). A white backing
    /// under a dark bar shows through the bar's anti-aliased left edge as a 1px light line.
    var toolbarColor: String? { didSet { refreshBackground() } }
    /// The no-tab stand-in: toolbar on the gradient, no card at all.
    var transparent = false { didSet { refreshBackground(); syncShadow() } }
    /// While a pane is being dragged open/closed its page keeps its last size.
    var frozenWebBounds: NSRect?
    /// The page is on screen in another window: Arc keeps the tab selected here and shows a
    /// blurred snapshot of it (BlurredItemContent) until this window is used again.
    var elsewhereSnapshot: NSImage? {
        didSet {
            guard elsewhereSnapshot !== oldValue else { return }
            elsewhereView.layer?.contents = elsewhereSnapshot.flatMap(Self.blurred)
        }
    }
    var showsElsewhere = false { didSet { elsewhereView.isHidden = !showsElsewhere } }
    private let elsewhereView = NSView()
    /// Arc's ring around the focused split pane (its focusBorderLayer, GitHub #178): 2 pt in the
    /// space's shadedDark, along the card's rounded edge, over the bar and the page. nil = none.
    var focusRing: NSColor? {
        didSet {
            guard focusRing != oldValue else { return }
            ring.isHidden = focusRing == nil
            ring.layer?.borderColor = focusRing?.cgColor
        }
    }
    private let ring = FocusRingView()
    /// Arc's shadow under a page card (GitHub #178): a sibling behind the card in its superview,
    /// on the card's frame and alpha. Off for the empty and no-tab cards and square cards.
    private let shadowView = CardShadowView()
    var castsShadow = false { didSet { syncShadow() } }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let superview {
            if shadowView.superview !== superview { superview.addSubview(shadowView, positioned: .below, relativeTo: self) }
        } else {
            shadowView.removeFromSuperview()
        }
        syncShadow()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); syncShadow() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); syncShadow() }
    override var alphaValue: CGFloat { didSet { shadowView.alphaValue = alphaValue } }
    override var isHidden: Bool { didSet { syncShadow() } }

    private func syncShadow() {
        let on = castsShadow && hasPage && !transparent && cornerRadius > 0 && !isHidden && superview != nil
        shadowView.isHidden = !on
        guard on else { return }
        shadowView.cornerRadius = cornerRadius
        let f = frame.insetBy(dx: -CardShadowView.pad, dy: -CardShadowView.pad)
        if shadowView.frame != f { shadowView.frame = f }
    }

    /// The card shows another tab now (a tab switch with one pane before and after): the same
    /// card and toolbar follow it.
    func retarget(to id: UUID) {
        tabID = id
        (toolbarHost as? PaneToolbarView)?.paneTabID = id == ShellView.noTabID ? nil : id
        frozenWebBounds = nil
        showsElsewhere = false
        elsewhereSnapshot = nil
        needsLayout = true
    }

    init(tabID: UUID, toolbar: NSView) {
        self.tabID = tabID
        toolbarHost = toolbar
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        webArea.wantsLayer = true
        webArea.autoresizesSubviews = false
        pageBackground.wantsLayer = true
        pageBackground.layer?.cornerCurve = .continuous
        toolbarBackground.wantsLayer = true
        hairline.wantsLayer = true
        hairline.isHidden = true
        elsewhereView.wantsLayer = true
        elsewhereView.layer?.contentsGravity = .resizeAspectFill
        elsewhereView.layer?.cornerCurve = .continuous
        elsewhereView.layer?.masksToBounds = true
        elsewhereView.isHidden = true
        addSubview(pageBackground)
        addSubview(elsewhereView)
        addSubview(webArea)
        addSubview(toolbarBackground)
        addSubview(hairline)
        addSubview(toolbarHost)
        ring.isHidden = true
        ring.layer?.cornerRadius = cornerRadius
        addSubview(ring)
        refreshBackground()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshBackground() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The ring stays the topmost view: the shell docks DevTools into the focused card later.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== ring, ring.superview === self { addSubview(ring, positioned: .above, relativeTo: nil) }
    }

    private func refreshBackground() {
        // Measured on Arc 1.170 (Victor theme, 2x): the empty pane is the
        // gradient plus about +9/+11/+12 per channel, i.e. a white veil at ~0.2.
        layer?.backgroundColor = transparent || hasPage ? NSColor.clear.cgColor : NSColor(white: 1, alpha: isDark ? 0.08 : 0.2).cgColor
        let bar = developerBar ?? toolbarColor.map { NSColor(Color(hex: $0)) } ?? .white
        // A page of Cra's own over the backdrop (an Easel) takes its veil under the toolbar too, as Arc's does.
        let veiled = pageColor == "clear" ? NSColor(white: 0, alpha: 0.5) : bar
        toolbarBackground.layer?.backgroundColor = (hasPage && !transparent ? veiled : NSColor.clear).cgColor
        // "clear": a page of Cra's own that lets the window's backdrop through (an Easel, as in Arc).
        let page = pageColor == "clear" ? NSColor.clear : pageColor.map { NSColor(Color(hex: $0)) } ?? CraBrowser.pageCanvasColor
        pageBackground.layer?.backgroundColor = (hasPage && !transparent ? page : NSColor.clear).cgColor
        hairline.isHidden = hasPage || transparent || !showToolbar
        hairline.layer?.backgroundColor = NSColor(white: isDark ? 1 : 0, alpha: 0.08).cgColor
    }

    override func layout() {
        super.layout()
        let b = bounds
        let th: CGFloat = showToolbar ? toolbarHeight : 0
        toolbarHost.isHidden = th == 0
        toolbarHost.frame = NSRect(x: 0, y: b.height - th, width: b.width, height: th)
        toolbarBackground.frame = toolbarHost.frame
        hairline.frame = NSRect(x: 0, y: b.height - th - 1, width: b.width, height: 1)
        hairline.isHidden = hasPage || transparent || th == 0
        webArea.frame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - th))
        // The page window rounds the card's corners itself. Its stand-in fill keeps 1 pt clear of
        // every rounded edge: the same radius on the inset rect stays at least 1 pt inside the
        // page's curve, so the page's edge pixels only ever blend with the gradient behind the card.
        let rounded = cornerRadius > 0
        let inset: CGFloat = rounded ? 1 : 0
        var fill = webArea.frame.insetBy(dx: inset, dy: 0)
        fill.origin.y += inset
        fill.size.height = max(0, fill.height - (th == 0 ? 2 * inset : inset))
        pageBackground.frame = fill
        pageBackground.layer?.cornerRadius = rounded ? cornerRadius : 0
        pageBackground.layer?.maskedCorners = th == 0 ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                                                      : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        elsewhereView.frame = fill
        elsewhereView.layer?.cornerRadius = pageBackground.layer?.cornerRadius ?? 0
        elsewhereView.layer?.maskedCorners = pageBackground.layer?.maskedCorners ?? []
        let wb = frozenWebBounds ?? webArea.bounds
        EmbeddedPages.place(webArea.subviews, in: wb)
        ring.frame = b
    }

    /// The snapshot (the tab switcher's thumbnail of the top of the page), blurred hard enough
    /// that its low resolution doesn't show, cropped back to its own size so the edges stay opaque.
    private static func blurred(_ image: NSImage) -> CGImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let radius = Double(cg.width) * 0.03
        guard let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: radius]),
              let output = filter.outputImage?.cropped(to: input.extent),
              let result = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return result
    }
}

/// A stroke along its bounds' rounded edge (the layer's border), drawn over the card's other
/// views. One static layer: a focus change recolours or hides it, nothing redraws per frame.
final class FocusRingView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Clicks go to the bar and the page under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Arc's card shadow, fitted to its captures (Arc 1.171, light space, 2x, GitHub #178): a
/// Gaussian edge of 26 % black, 3.6 pt sigma, 0.8 pt low. Core Graphics' blur came out softer and
/// lighter than its nominal sigma (fitted on Cra's own capture), hence 31 % and a 6.5 pt blur. Drawn as a
/// stretchable image, made once per corner radius and scale, so it costs nothing per frame and
/// stretches with the card while its frame animates. The card's own area is cut out: a card
/// whose page has not painted yet shows the window behind it, not the shadow.
final class CardShadowView: NSView {
    static let alpha: CGFloat = 0.31, blur: CGFloat = 6.5, drop: CGFloat = 0.8, sigma: CGFloat = 3.6
    /// How far the shadow reaches past the card.
    static let pad: CGFloat = ceil(3 * sigma + drop)
    var cornerRadius: CGFloat = 0 { didSet { if cornerRadius != oldValue { refresh() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }

    private func refresh() {
        let scale = window?.backingScaleFactor ?? 2
        guard let image = Self.image(radius: cornerRadius, scale: scale) else { layer?.contents = nil; return }
        layer?.contents = image
        layer?.contentsScale = scale
        // The middle stretches: one point between the corners on each axis.
        let side = CGFloat(image.width) / scale, mid = Self.pad + cornerRadius
        layer?.contentsCenter = CGRect(x: mid / side, y: mid / side, width: 1 / side, height: 1 / side)
    }

    private static var cache: [String: CGImage] = [:]

    private static func image(radius: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(radius)@\(scale)"
        if let hit = cache[key] { return hit }
        // The card is the middle (2·radius + 1 pt square), the shadow pad around it.
        let card = 2 * radius + 1, side = card + 2 * pad
        let px = Int(ceil(side * scale))
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let rect = CGRect(x: pad, y: pad, width: card, height: card)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // The blurred rect: Core Graphics' shadow of a shape drawn far off the canvas, so only its
        // shadow lands.
        let far: CGFloat = 10_000
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: far * scale, height: -drop * scale), blur: blur * scale,
                      color: NSColor.black.withAlphaComponent(alpha).cgColor)
        ctx.translateBy(x: -far, y: 0)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        // Cut the card out.
        ctx.setBlendMode(.clear)
        ctx.addPath(path)
        ctx.fillPath()
        let image = ctx.makeImage()
        cache[key] = image
        return image
    }
}
