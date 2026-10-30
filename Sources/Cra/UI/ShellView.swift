import AppKit
import SwiftUI

/// The window's content view: gradient background, sidebar (anchored,
/// hidden, or floating over the content on hover), a resize handle, and the
/// content area: one rounded card per pane (Arc's toolbar strip on top, the
/// Chromium view below) with dragger handles in the gaps between panes. With
/// no tab selected there is no card, just the toolbar on the gradient.
final class ShellView: NSView {
    /// Behind-window blur for vibrant (Arc-style) themes.
    let vibrancy = NSVisualEffectView()
    /// Light vibrant themes: an untinted behind-window blur (CABackdropLayer) under a
    /// black dim and a white lift gradient. The system materials all tint and cap the
    /// backdrop pass-through, so Arc's measured intercept and slope were unreachable with
    /// them (docs, 25 Oct 2026). Falls back to `vibrancy` when the layer class is missing.
    let backdropHost = NSView()
    private var backdropLayer: CALayer?
    private let dimLayer = CALayer()
    private let liftLayer = CAGradientLayer()
    /// Set by the window controller: light theme that wants the blur path.
    var vibrantLight = false { didSet { refreshLift() } }
    var usesBackdropLayer: Bool { vibrantLight && !vibrantDark && backdropLayer != nil }
    /// Lifts the dark blur toward Arc's mid-grey base before the gradient goes on.
    let vibrancyLift = NSView()
    let backgroundHost: NSView
    let sidebarHost: NSView
    let resizeHandle = ResizeHandleView()
    /// The content area (card minus nothing): holds the pane cards and handles.
    let contentContainer = NSView()
    /// Pane cards in pane order (one card, `noTabID`, when nothing is selected).
    private(set) var paneCards: [PaneCardView] = []
    private var handles: [SplitDraggerHandleView] = []
    /// Keeps Alloy-hosted Chromium views that no pane shows right now.
    let parkingView = NSView()
    /// DevTools dock on the right of the focused page, like Chrome's default.
    let devToolsHost = NSView()
    let devToolsDivider = NSView()
    let devToolsHandle = DevToolsResizeHandle()
    var devToolsVisible = false { didSet { needsLayout = true } }
    var devToolsWidth: CGFloat = 460 { didSet { needsLayout = true } }
    /// Chrome-style DevTools: the frontend draws the dock split itself (can_dock), so its
    /// window covers the whole card body and the page is laid over its placeholder.
    var devToolsFrontendDocked = false { didSet { needsLayout = true } }
    /// The page rect (window coordinates) the frontend-docked layout produced; overlays follow it.
    var frontendPageRect: NSRect? { didSet { if oldValue != frontendPageRect { needsLayout = true } } }
    /// Reports the dock area (window coordinates) so the DevTools child window follows it.
    var onDevToolsFrame: ((NSRect) -> Void)?
    /// Reports each pane's page area (window coordinates) so Chrome-style page windows follow it.
    var onPaneFrames: (([UUID: NSRect]) -> Void)?
    /// Animated transitions (sidebar, pane add/remove): target page areas + duration, so page windows animate alongside.
    var onAnimatePaneFrames: (([UUID: NSRect], TimeInterval, CAMediaTimingFunction) -> Void)?
    /// The user dragged a divider and let go: new width factors per pane.
    var onPaneResizeEnded: (([UUID: CGFloat]) -> Void)?
    var onPaneResizeBegan: (() -> Void)?
    /// Builds a pane's toolbar (the window controller owns the environment).
    var makeToolbar: ((UUID?) -> NSView)?
    /// Where the status bubble, toasts and find bar live (the content container, or an
    /// overlay panel's content view when pages are separate windows).
    private(set) var overlayParent: NSView
    /// Set while the sidebar/card frames are being animated; layout() then leaves them alone.
    private var animatingFrames = false
    /// Set while panes animate open/closed; layout() keeps their frames.
    private var animatingPanes = false
    /// Arc's faint card over the gradient while no tab is selected.
    let placeholderHost = NSView()
    let statusHost: NSView
    let toastHost: NSView
    let findHost: NSView

    /// Stand-in pane id for the no-tab state (toolbar on the gradient, no card).
    static let noTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private(set) var paneIDs: [UUID] = []
    private(set) var paneFactors: [UUID: CGFloat] = [:]
    private(set) var splitOrientation: SplitOrientation = .horizontal
    private(set) var focusedPaneID: UUID?
    /// Panes without a page (Arc's tinted "Search or Enter URL…" pane).
    private(set) var emptyPaneIDs: Set<UUID> = []
    var isDarkTheme = false { didSet { for c in paneCards { c.isDark = isDarkTheme } } }
    /// Each tab's page background ("#RRGGBB"), painted under its page window (PaneCardView.pageColor).
    var pageColors: [UUID: String] = [:] {
        didSet { for c in paneCards where c.pageColor != pageColors[c.tabID] { c.pageColor = pageColors[c.tabID] } }
    }
    /// Each tab's toolbar colour ("#RRGGBB"), painted behind its toolbar (PaneCardView.toolbarColor).
    var toolbarColors: [UUID: String] = [:] {
        didSet { for c in paneCards where c.toolbarColor != toolbarColors[c.tabID] { c.toolbarColor = toolbarColors[c.tabID] } }
    }

    var sidebarWidth: CGFloat = CraMetrics.sidebarDefaultWidth { didSet { needsLayout = true } }
    /// Off while the Library has the sidebar: its width is not the user's to drag.
    var sidebarResizable = true { didSet { needsLayout = true } }
    var sidebarVisible = true { didSet { needsLayout = true } }
    var floatingSidebar = false { didSet { needsLayout = true } }
    var contentFullscreen = false { didSet { needsLayout = true } }
    /// Settings ▸ "Pages fill the window edge to edge" (GitHub #24): no margin, square cards.
    var edgeToEdge = false { didSet { needsLayout = true } }
    var showToolbar = true { didSet { needsLayout = true } }
    var hasTab = false { didSet { needsLayout = true } }
    var onEdgeHover: ((Bool) -> Void)?
    var windowActive = true {
        didSet { refreshLift() }
    }

    /// Dark vibrant themes keep the earlier calibration (underWindowBackground + 15% lift).
    var vibrantDark = false { didSet { refreshLift() } }

    /// Core Animation's gaussian blur (the filter NSVisualEffectView uses), built
    /// through its private class; nil when the runtime does not provide it.
    static func makeBackdropBlur(radius: Double) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel), let filter = cls.perform(sel, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    func refreshLift() {
        let t = CraTuning.shared
        let lift = vibrantDark ? (windowActive ? 0.15 : 0.93) : (windowActive ? t.liftActive : t.liftInactive)
        vibrancyLift.layer?.backgroundColor = NSColor(white: 1, alpha: lift).cgColor
        if usesBackdropLayer {
            vibrancy.isHidden = true
            vibrancyLift.isHidden = true
            backdropHost.isHidden = false
            CATransaction.begin(); CATransaction.setDisableActions(true)
            dimLayer.opacity = Float(windowActive ? t.blurDim : t.blurDimInactive)
            let top = windowActive ? t.liftActive : t.liftInactive
            let bottom = windowActive ? t.liftActiveBottom : t.liftInactive
            liftLayer.colors = [NSColor(white: 1, alpha: top).cgColor, NSColor(white: 1, alpha: bottom).cgColor]
            CATransaction.commit()
        } else {
            backdropHost.isHidden = true
            vibrancyLift.isHidden = false
            vibrancy.isHidden = !(vibrantLight || vibrantDark)
        }
        vibrancy.material = vibrantDark ? .underWindowBackground : t.material
        vibrancy.state = (t.forceActiveBlur || windowActive) ? .active : .inactive
        vibrancy.appearance = NSAppearance(named: t.darkBlur ? .darkAqua : .aqua)
    }
    var statusVisible = false
    var findVisible = false
    var toastCount = 0
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, background: NSView, sidebar: NSView, toolbar: NSView, status: NSView, toasts: NSView, find: NSView) {
        backgroundHost = background
        sidebarHost = sidebar
        statusHost = status
        toastHost = toasts
        findHost = find
        overlayParent = contentContainer
        super.init(frame: frame)
        wantsLayer = true

        vibrancy.blendingMode = .behindWindow
        vibrancy.material = .underWindowBackground
        vibrancy.state = .active
        vibrancy.isHidden = true
        addSubview(vibrancy)
        backdropHost.wantsLayer = true
        // A CABackdropLayer only blurs what is behind the window through Core
        // Animation's own filters (private CAFilter "gaussianBlur"); a CIFilter in
        // `filters` is ignored for the backdrop capture, which left the sidebar fully
        // see-through (25 Oct 2026). Without the filter class we keep the NSVisualEffectView path.
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let blur = ShellView.makeBackdropBlur(radius: 40) {
            let b = cls.init()
            b.filters = [blur]
            b.setValue(true, forKey: "allowsGroupBlending")
            backdropHost.layer?.addSublayer(b)
            backdropLayer = b
        }
        dimLayer.backgroundColor = NSColor.black.cgColor
        backdropHost.layer?.addSublayer(dimLayer)
        liftLayer.startPoint = CGPoint(x: 0.5, y: 1)
        liftLayer.endPoint = CGPoint(x: 0.5, y: 0)
        backdropHost.layer?.addSublayer(liftLayer)
        backdropHost.isHidden = true
        addSubview(backdropHost)
        vibrancyLift.wantsLayer = true
        vibrancyLift.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        vibrancyLift.isHidden = true
        addSubview(vibrancyLift)
        addSubview(backgroundHost)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentContainer)
        parkingView.isHidden = true
        parkingView.autoresizesSubviews = false
        contentContainer.addSubview(parkingView)
        devToolsHost.wantsLayer = true
        devToolsHost.layer?.backgroundColor = NSColor.white.cgColor
        devToolsHost.isHidden = true
        devToolsDivider.wantsLayer = true
        devToolsDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        devToolsDivider.isHidden = true
        devToolsHandle.isHidden = true
        devToolsHandle.onDrag = { [weak self] dx in
            guard let self else { return }
            self.devToolsWidth = min(max(320, self.devToolsWidth - dx), self.contentContainer.bounds.width * 0.7)
            self.layoutSubtreeIfNeeded()
        }
        contentContainer.addSubview(placeholderHost)
        for h in [statusHost, toastHost, findHost] as [NSView] {
            h.isHidden = true
            contentContainer.addSubview(h)
        }
        // Start with the no-tab card so the toolbar exists from the first frame.
        let card = PaneCardView(tabID: ShellView.noTabID, toolbar: toolbar)
        card.hasPage = false
        card.transparent = true
        contentContainer.addSubview(card)
        paneCards = [card]
        paneIDs = []
        sidebarHost.wantsLayer = true
        sidebarHost.layer?.cornerCurve = .continuous
        addSubview(sidebarHost)
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: Panes

    var focusedCard: PaneCardView? {
        if let id = focusedPaneID, let c = paneCards.first(where: { $0.tabID == id }) { return c }
        return paneCards.first
    }
    func card(for id: UUID) -> PaneCardView? { paneCards.first { $0.tabID == id } }
    /// The focused pane's page area; the parking view when there is none.
    var webContainer: NSView { (hasTab ? focusedCard?.webArea : nil) ?? parkingView }

    /// Show these panes (tab ids in pane order). Empty = the no-tab state.
    /// Adding or removing panes animates like Arc (collapsed ↔ expanded).
    func setPanes(_ ids: [UUID], factors: [UUID: CGFloat], orientation: SplitOrientation, focused: UUID?, empty: Set<UUID>, animated: Bool) {
        let shownIDs = ids.isEmpty ? [ShellView.noTabID] : ids
        let previous = paneCards.map(\.tabID)
        let structural = previous != shownIDs || orientation != splitOrientation
        paneIDs = ids
        paneFactors = factors
        splitOrientation = orientation
        focusedPaneID = focused ?? ids.first
        emptyPaneIDs = empty
        hasTab = !ids.isEmpty
        for h in handles { h.orientation = orientation }

        guard structural else {
            for c in paneCards { c.hasPage = c.tabID != ShellView.noTabID && !empty.contains(c.tabID) }
            needsLayout = true
            return
        }

        // One pane before and after, a plain tab switch: the card follows the tab.
        if paneCards.count == 1, shownIDs.count == 1, let card = paneCards.first,
           (card.tabID == ShellView.noTabID) == (shownIDs[0] == ShellView.noTabID) {
            let id = shownIDs[0]
            card.retarget(to: id)
            card.pageColor = pageColors[id]
            card.toolbarColor = toolbarColors[id]
            card.hasPage = id != ShellView.noTabID && !empty.contains(id)
            needsLayout = true
            return
        }

        let oldFrames = Dictionary(uniqueKeysWithValues: paneCards.map { ($0.tabID, $0.frame) })
        var cards: [PaneCardView] = []
        for id in shownIDs {
            if let existing = paneCards.first(where: { $0.tabID == id }) {
                cards.append(existing)
            } else {
                let card = PaneCardView(tabID: id, toolbar: makeToolbar?(id == ShellView.noTabID ? nil : id) ?? NSView())
                card.isDark = isDarkTheme
                card.pageColor = pageColors[id]
                card.toolbarColor = toolbarColors[id]
                card.transparent = id == ShellView.noTabID
                card.showToolbar = showToolbar && !contentFullscreen
                contentContainer.addSubview(card, positioned: .below, relativeTo: placeholderHost)
                cards.append(card)
            }
        }
        let removed = paneCards.filter { c in !shownIDs.contains(c.tabID) }
        paneCards = cards
        for c in paneCards {
            c.hasPage = c.tabID != ShellView.noTabID && !empty.contains(c.tabID)
        }
        while handles.count < max(0, paneCards.count - 1) {
            let h = SplitDraggerHandleView(frame: .zero)
            h.orientation = orientation
            let index = handles.count
            h.onDragBegan = { [weak self] in self?.beginPaneDrag(index) }
            h.onDrag = { [weak self] d in self?.dragPane(index, delta: d) }
            h.onDragEnded = { [weak self] in self?.endPaneDrag() }
            h.onDoubleClick = { [weak self] in self?.resetPaneWidths() }
            contentContainer.addSubview(h, positioned: .below, relativeTo: placeholderHost)
            handles.append(h)
        }
        while handles.count > max(0, paneCards.count - 1) { handles.removeLast().removeFromSuperview() }

        let target = paneLayout(in: contentContainer.bounds)
        // Observed on Arc 1.170 (per-window frames at 27 fps): a new pane
        // appears fully laid out within one frame; only the command bar fades in.
        guard animated, SplitPaneLayout.Constants.transitionDuration > 0, !oldFrames.isEmpty, window != nil else {
            for c in removed { c.removeFromSuperview() }
            needsLayout = true
            layoutSubtreeIfNeeded()
            return
        }

        // New panes grow from a collapsed sliver at their slot; closing panes shrink to one.
        let horizontal = orientation == .horizontal
        for c in paneCards where oldFrames[c.tabID] == nil {
            guard let f = target.frames[c.tabID] else { continue }
            c.frame = horizontal ? NSRect(x: f.minX, y: f.minY, width: 0, height: f.height) : NSRect(x: f.minX, y: f.maxY, width: f.width, height: 0)
            c.alphaValue = 0
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - (c.showToolbar ? c.toolbarHeight : 0)))
            c.layoutSubtreeIfNeeded()
        }
        for c in paneCards where oldFrames[c.tabID] != nil {
            guard let f = target.frames[c.tabID] else { continue }
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - (c.showToolbar ? c.toolbarHeight : 0)))
        }
        animatingPanes = true
        let webTargets = paneWebFrames(target)
        onAnimatePaneFrames?(webTargets, SplitPaneLayout.Constants.transitionDuration, SplitPaneLayout.Constants.transitionTiming)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = SplitPaneLayout.Constants.transitionDuration
            ctx.timingFunction = SplitPaneLayout.Constants.transitionTiming
            ctx.allowsImplicitAnimation = true
            for c in paneCards {
                if let f = target.frames[c.tabID] { c.animator().frame = f }
                c.animator().alphaValue = 1
            }
            for c in removed {
                let f = c.frame
                c.animator().frame = horizontal ? NSRect(x: f.minX, y: f.minY, width: 0, height: f.height) : NSRect(x: f.minX, y: f.maxY, width: f.width, height: 0)
                c.animator().alphaValue = 0
            }
            for (i, h) in handles.enumerated() where i < target.gaps.count {
                h.animator().frame = target.gaps[i]
            }
        } completionHandler: { [weak self] in
            guard let self else { return }
            for c in removed { c.removeFromSuperview() }
            self.animatingPanes = false
            for c in self.paneCards { c.frozenWebBounds = nil }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }

    private func paneLayout(in bounds: NSRect) -> SplitPaneLayout.Result {
        let ids = paneCards.map(\.tabID)
        let panes = ids.map { SplitPaneLayout.Pane(id: $0, factor: paneFactors[$0] ?? (1 / CGFloat(max(1, ids.count)))) }
        var layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: bounds.size)
        layout.backingScaleFactor = window?.backingScaleFactor ?? 2
        return layout.compute()
    }

    /// Each pane's page area in window coordinates, for the given card frames.
    private func paneWebFrames(_ layout: SplitPaneLayout.Result) -> [UUID: NSRect] {
        var out: [UUID: NSRect] = [:]
        let th: CGFloat = (showToolbar && !contentFullscreen) ? CraMetrics.toolbarHeight : 0
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = layout.frames[c.tabID] else { continue }
            var web = NSRect(x: f.minX, y: f.minY, width: f.width, height: max(0, f.height - th))
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 {
                web.size.width -= min(max(320, devToolsWidth), f.width * 0.7)
            }
            out[c.tabID] = contentContainer.convert(web, to: nil)
        }
        return out
    }

    // MARK: Divider drags

    private var dragStartFactors: [UUID: CGFloat] = [:]

    private func beginPaneDrag(_ index: Int) {
        dragStartFactors = paneFactors
        for c in paneCards { c.frozenWebBounds = nil }
        onPaneResizeBegan?()
    }

    private func dragPane(_ index: Int, delta: CGFloat) {
        let ids = paneCards.map(\.tabID)
        let panes = ids.map { SplitPaneLayout.Pane(id: $0, factor: dragStartFactors[$0] ?? (1 / CGFloat(max(1, ids.count)))) }
        let layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: contentContainer.bounds.size)
        paneFactors = layout.dragging(dividerAfter: index, by: delta).factors
        layoutContentChildren()
    }

    private func endPaneDrag() {
        onPaneResizeEnded?(paneFactors)
    }

    private func resetPaneWidths() {
        let n = CGFloat(max(1, paneCards.count))
        for c in paneCards { paneFactors[c.tabID] = 1 / n }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = SplitPaneLayout.Constants.transitionTiming
            ctx.allowsImplicitAnimation = true
            layoutContentChildren(animated: true)
        }
        onPaneResizeEnded?(paneFactors)
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        // activeAlways: the key window is usually a Chromium page window, and the
        // edge hover must still follow the pointer over the shell.
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        guard !sidebarVisible, !contentFullscreen else { return }
        if !floatingSidebar, FloatingSidebarGeometry.shouldReveal(at: p, in: bounds, edgeToEdge: edgeToEdge) {
            onEdgeHover?(true)
        } else if floatingSidebar, FloatingSidebarGeometry.shouldHide(at: p, in: bounds, sidebarWidth: sidebarWidth,
                                                                     pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: edgeToEdge) {
            onEdgeHover?(false)
        }
    }

    /// Leaving the shell no longer hides the floating sidebar: the pointer moving onto
    /// the floating panel or a page window counts as an exit here, so the window
    /// controller's pointer monitor decides instead.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }

    /// While the sidebar floats in its own panel (Chrome-style hosting puts page
    /// windows above the shell), the shell leaves `sidebarHost`'s frame alone.
    var sidebarDetached = false

    // MARK: Layout

    struct Frames {
        var sidebar: NSRect
        var handle: NSRect
        var content: NSRect
        var cornerRadius: CGFloat
        var sidebarCorner: CGFloat
    }

    func frames(sidebarVisible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat) -> Frames {
        let b = bounds
        if fullscreen {
            return Frames(sidebar: NSRect(x: -width, y: 0, width: width, height: b.height),
                          handle: .zero, content: b, cornerRadius: 0, sidebarCorner: 0)
        }
        // Edge to edge the card fills what the sidebar leaves, square; the window's own
        // corners round it where they meet.
        let inset = edgeToEdge ? 0 : CraMetrics.contentInset
        let radius = edgeToEdge ? 0 : CraMetrics.contentCornerRadius
        if sidebarVisible {
            let content = NSRect(x: width, y: inset, width: max(0, b.width - width - inset), height: max(0, b.height - 2 * inset))
            return Frames(sidebar: NSRect(x: 0, y: 0, width: width, height: b.height),
                          handle: NSRect(x: width - 4, y: 0, width: 8, height: b.height),
                          content: content, cornerRadius: radius, sidebarCorner: 0)
        }
        if floating {
            // The floating sidebar hovers over the page; the card does not move (Arc).
            let m = FloatingSidebarGeometry.margin
            return Frames(sidebar: NSRect(x: m, y: m, width: width, height: b.height - 2 * m),
                          handle: .zero, content: b.insetBy(dx: inset, dy: inset), cornerRadius: radius, sidebarCorner: 12)
        }
        // Sidebar hidden: Arc keeps the rounded card floating in its inset (measured 25 Oct:
        // card edge 10 pt from the window edge after ⌘S), with a sidebar toggle in the bar.
        return Frames(sidebar: NSRect(x: -width - 20, y: 0, width: width, height: b.height),
                      handle: .zero, content: b.insetBy(dx: inset, dy: inset), cornerRadius: radius, sidebarCorner: 0)
    }

    private var cardCornerRadius: CGFloat = CraMetrics.contentCornerRadius

    override func layout() {
        super.layout()
        vibrancy.frame = bounds
        backdropHost.frame = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdropLayer?.frame = backdropHost.bounds
        dimLayer.frame = backdropHost.bounds
        liftLayer.frame = backdropHost.bounds
        CATransaction.commit()
        vibrancyLift.frame = bounds
        backgroundHost.frame = bounds
        if animatingFrames { layoutContentChildren(); return }
        let f = frames(sidebarVisible: sidebarVisible, floating: floatingSidebar, fullscreen: contentFullscreen, width: sidebarWidth)
        apply(f)
    }

    func apply(_ f: Frames) {
        if !sidebarDetached { sidebarHost.frame = f.sidebar }
        resizeHandle.frame = f.handle
        resizeHandle.isHidden = f.handle.isEmpty || !sidebarResizable
        contentContainer.frame = f.content
        cardCornerRadius = f.cornerRadius
        sidebarHost.layer?.cornerRadius = f.sidebarCorner
        if f.sidebarCorner > 0 {
            sidebarHost.shadow = NSShadow()
            sidebarHost.shadow?.shadowBlurRadius = 24
            sidebarHost.shadow?.shadowOffset = NSSize(width: 0, height: -6)
            sidebarHost.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.3)
        } else {
            sidebarHost.shadow = nil
        }
        layoutContentChildren()
    }

    func layoutContentChildren(animated: Bool = false) {
        let cb = contentContainer.bounds
        let toolbarVisible = showToolbar && !contentFullscreen
        let layout = paneLayout(in: cb)
        for c in paneCards {
            c.showToolbar = toolbarVisible
            // Several panes: every card is rounded; a single card follows the window state (square in fullscreen).
            // Edge to edge every card is square.
            c.cornerRadius = paneCards.count > 1 && !edgeToEdge ? CraMetrics.contentCornerRadius : cardCornerRadius
            if !animatingPanes, let f = layout.frames[c.tabID] {
                if animated { c.animator().frame = f } else if c.frame != f { c.frame = f }
            }
            c.layoutSubtreeIfNeeded()
        }
        for (i, h) in handles.enumerated() {
            h.isHidden = i >= layout.gaps.count
            if !animatingPanes, i < layout.gaps.count {
                if animated { h.animator().frame = layout.gaps[i] } else { h.frame = layout.gaps[i] }
            }
        }
        placeholderHost.frame = cb
        placeholderHost.isHidden = hasTab
        // The no-tab card is rounded like a page's (GitHub #6: a new window showed a square one).
        placeholderHost.layer?.cornerRadius = cardCornerRadius
        placeholderHost.layer?.cornerCurve = .continuous
        parkingView.frame = cb

        // DevTools docks inside the focused card, right of its page.
        let focus = focusedCard
        let fb = focus?.bounds ?? .zero
        let th: CGFloat = toolbarVisible ? CraMetrics.toolbarHeight : 0
        let bodyH = max(0, fb.height - th)
        let selfDock = devToolsFrontendDocked
        let showDev = devToolsVisible && hasTab && focus != nil && (selfDock || fb.width > 640)
        let devW: CGFloat = showDev && !selfDock ? min(max(320, devToolsWidth), fb.width * 0.7) : 0
        if let focus, showDev {
            for v in [devToolsHost, devToolsDivider, devToolsHandle] where v.superview !== focus { v.removeFromSuperview(); focus.addSubview(v) }
            focus.webArea.frame = NSRect(x: 0, y: 0, width: fb.width - devW, height: bodyH)
            for sub in focus.webArea.subviews where sub.frame != focus.webArea.bounds { sub.frame = focus.frozenWebBounds ?? focus.webArea.bounds }
        }
        // A frontend-docked DevTools paints its own split; the shell's dock chrome stays hidden.
        devToolsHost.isHidden = !showDev || selfDock
        devToolsDivider.isHidden = !showDev || selfDock
        devToolsHandle.isHidden = !showDev || selfDock
        let devFrame = selfDock ? NSRect(x: 0, y: 0, width: fb.width, height: bodyH)
                                : NSRect(x: fb.width - devW, y: 0, width: devW, height: bodyH)
        devToolsHost.frame = devFrame
        devToolsDivider.frame = NSRect(x: fb.width - devW, y: 0, width: 1, height: bodyH)
        devToolsHandle.frame = NSRect(x: fb.width - devW - 3, y: 0, width: 7, height: bodyH)
        for sub in devToolsHost.subviews { sub.frame = devToolsHost.bounds }
        if showDev, let focus { onDevToolsFrame?(focus.convert(devFrame, to: nil)) }

        // Overlays sit over the focused page (in the container, or in the overlay panel).
        var webInContainer = focus.map { contentContainer.convert($0.webArea.frame, from: $0) } ?? cb
        if showDev, selfDock, let pr = frontendPageRect { webInContainer = contentContainer.convert(pr, from: nil) }
        let wb = overlayParent === contentContainer ? webInContainer : NSRect(origin: .zero, size: webInContainer.size)
        if overlayParent === contentContainer {
            for h in [statusHost, toastHost, findHost] where contentContainer.subviews.last !== h {
                contentContainer.addSubview(h, positioned: .above, relativeTo: nil)
            }
        }
        statusHost.isHidden = !statusVisible
        statusHost.frame = NSRect(x: wb.minX, y: wb.minY, width: min(540, wb.width), height: 34)
        if toastHost.superview === overlayParent {
            let size = Self.toastStackSize(count: toastCount)
            toastHost.isHidden = toastCount == 0
            toastHost.frame = NSRect(x: wb.maxX - size.width, y: wb.minY, width: size.width, height: size.height)
        }
        if findHost.superview === overlayParent {
            let size = CraMetrics.findBarSize, inset = CraMetrics.findBarInset
            findHost.isHidden = !findVisible
            findHost.frame = NSRect(x: wb.maxX - size.width - inset, y: wb.maxY - size.height - inset, width: size.width, height: size.height)
        }
        if !animatingPanes, paneCards.allSatisfy({ $0.frozenWebBounds == nil }) { onPaneFrames?(paneWebFrames(layout)) }
    }

    /// The download toast stack, bottom trailing over the focused page.
    static func toastStackSize(count: Int) -> NSSize {
        NSSize(width: 330, height: CGFloat(count) * 76 + 20)
    }

    /// Chrome-style hosting: the status bubble moves into a click-through panel above the
    /// page windows; the find bar and the toasts, which take clicks, each into their own
    /// panel just their size, which the window controller places.
    func moveOverlays(to view: NSView, findBar: NSPanel, toasts: NSPanel) {
        overlayParent = view
        statusHost.removeFromSuperview()
        view.addSubview(statusHost)
        for (host, panel) in [(findHost, findBar), (toastHost, toasts)] {
            host.removeFromSuperview()
            host.isHidden = false
            host.autoresizingMask = [.width, .height]
            host.frame = panel.contentView!.bounds
            panel.contentView!.addSubview(host)
        }
        needsLayout = true
    }

    /// Animate between sidebar states by interpolating frames.
    func animateSidebar(visible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat, duration: TimeInterval = 0.085) {
        let target = frames(sidebarVisible: visible, floating: floating, fullscreen: fullscreen, width: width)
        // Size the pages for their destination once, up front; the cards then just slide over them.
        let toolbarH: CGFloat = (showToolbar && !fullscreen) ? CraMetrics.toolbarHeight : 0
        let targetLayout = paneLayout(in: NSRect(origin: .zero, size: target.content.size))
        var webTargets: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = targetLayout.frames[c.tabID] else { continue }
            var w = f.width
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 { w -= min(max(320, devToolsWidth), f.width * 0.7) }
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: w, height: max(0, f.height - toolbarH))
            webTargets[c.tabID] = convert(NSRect(x: target.content.minX + f.minX, y: target.content.minY + f.minY, width: w, height: max(0, f.height - toolbarH)), to: nil)
        }
        layoutContentChildren()
        animatingFrames = true
        // Fast start, soft landing: feels immediate without a visible snap.
        // Fitted to Arc 1.170's ⌘S hide at 60 fps: 66 / 87 / 96 / 99 % of the travel after
        // frames 1–4 (card edge 568 → 204 → 90 → 42 → 24 → 20 px).
        let timing = CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.3, 1)
        onAnimatePaneFrames?(webTargets, duration, timing)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            ctx.allowsImplicitAnimation = true
            if !sidebarDetached { sidebarHost.animator().frame = target.sidebar }
            contentContainer.animator().frame = target.content
            cardCornerRadius = target.cornerRadius
            if paneCards.count == 1, let c = paneCards.first { c.cornerRadius = target.cornerRadius }
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.animatingFrames = false
            for c in self.paneCards { c.frozenWebBounds = nil }
            self.sidebarVisible = visible
            self.floatingSidebar = floating
            self.contentFullscreen = fullscreen
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }
}

/// Thin vertical strip between sidebar and content that drags the width.
final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var lastX: CGFloat = 0

    /// The window is movable by its background; this strip must own its drags.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) { lastX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        onDrag?(x - lastX)
        lastX = x
    }
    override func mouseUp(with event: NSEvent) { onEnd?() }
}


/// Thin vertical grab area on the DevTools divider.
final class DevToolsResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX) }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
}
