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
    var cornerRadius: CGFloat = CraMetrics.contentCornerRadius { didSet { layer?.cornerRadius = cornerRadius; needsLayout = true } }
    /// White page card, or Arc's tinted translucent empty pane.
    var hasPage = true { didSet { refreshBackground() } }
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
    var transparent = false { didSet { refreshBackground() } }
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
        refreshBackground()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshBackground() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshBackground() {
        // Measured on Arc 1.170 (Victor theme, 2x): the empty pane is the
        // gradient plus about +9/+11/+12 per channel, i.e. a white veil at ~0.2.
        layer?.backgroundColor = transparent || hasPage ? NSColor.clear.cgColor : NSColor(white: 1, alpha: isDark ? 0.08 : 0.2).cgColor
        let bar = developerBar ?? toolbarColor.map { NSColor(Color(hex: $0)) } ?? .white
        toolbarBackground.layer?.backgroundColor = (hasPage && !transparent ? bar : NSColor.clear).cgColor
        let page = pageColor.map { NSColor(Color(hex: $0)) } ?? CraBrowser.pageCanvasColor
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
        for sub in webArea.subviews where sub.frame != wb { sub.frame = wb }
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
