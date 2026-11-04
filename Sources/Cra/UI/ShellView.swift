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
    /// In fullscreen there is nothing behind the window to capture (the backdrop read black),
    /// so NSVisualEffectView, and with it Arc's sidebar, swaps its capture for the desktop
    /// tint (CAChameleonLayer). We do the same (GitHub #83).
    private var desktopTintLayer: CALayer?
    var windowFullscreen = false { didSet { if windowFullscreen != oldValue { refreshLift() } } }
    private var loggedBackdrop: String?
    private let dimLayer = CALayer()
    private let liftLayer = CAGradientLayer()
    /// Light theme that wants the blur path (setTheme).
    private(set) var vibrantLight = false
    /// Arc's one-colour themes, light or dark: the blur under SpacePalette.solidAlpha's material.
    private(set) var solidBackdrop = false
    /// System Settings ▸ Accessibility ▸ Display ▸ Reduce transparency (or Increase contrast):
    /// AppKit's materials, and Arc's sidebar, go opaque. The backdrop layer path follows (GitHub #156).
    private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var usesBackdropLayer: Bool { (solidBackdrop || vibrantLight && !vibrantDark) && backdropLayer != nil }
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
    /// An extension's side panel (chrome.sidePanel) right of the panes, Chrome's place for it.
    let sidePanel = ExtensionSidePanelCard()
    let sidePanelHandle = DevToolsResizeHandle()
    /// The panel's width; 0 = no panel.
    var sidePanelWidth: CGFloat = 0 { didSet { if sidePanelWidth != oldValue { needsLayout = true } } }
    /// The panel page's area (window coordinates), nil while no panel shows.
    var onSidePanelFrame: ((NSRect?) -> Void)?
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
    /// Where the status bubble and find bar live (the content container, or an
    /// overlay panel's content view when pages are separate windows).
    private(set) var overlayParent: NSView
    /// Set while the sidebar/card frames are being animated; layout() then leaves them alone.
    private var animatingFrames = false
    /// Set while panes animate open/closed; layout() keeps their frames.
    private var animatingPanes = false
    /// Arc's faint card over the gradient while no tab is selected.
    let placeholderHost = NSView()
    /// Arc's loading bar in the margin above the card, for the front tab.
    let loadingIndicator = LoadingIndicatorView()
    private var loadingTabID: UUID?
    let statusHost: NSView
    let findHost: NSView

    /// Stand-in pane id for the no-tab state (toolbar on the gradient, no card).
    static let noTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private(set) var paneIDs: [UUID] = []
    private(set) var paneFactors: [UUID: CGFloat] = [:]
    private(set) var splitOrientation: SplitOrientation = .horizontal
    private(set) var focusedPaneID: UUID?
    /// Panes without a page (Arc's tinted "Search or Enter URL…" pane).
    private(set) var emptyPaneIDs: Set<UUID> = []
    var isDarkTheme = false {
        didSet {
            for c in paneCards { c.isDark = isDarkTheme }
            loadingIndicator.isDark = isDarkTheme
        }
    }
    /// The ring around the focused split pane: the space's shadedDark (PaneCardView.focusRing).
    var focusRingColor: NSColor? { didSet { if focusRingColor != oldValue { updateFocusRings() } } }
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
    /// Whether the cards carry their bars. Arc keeps every pane's bar in a split even with the
    /// toolbar hidden (View ▸ Show Toolbar is disabled while a split is open, GitHub #178).
    var panesShowBars: Bool { barsShown(panes: paneCards.count, fullscreen: contentFullscreen) }
    private func barsShown(panes: Int, fullscreen: Bool) -> Bool { !fullscreen && (showToolbar || panes > 1) }
    var hasTab = false { didSet { needsLayout = true } }
    var onEdgeHover: ((Bool) -> Void)?
    /// Set again each time the window becomes key; only a change rebuilds the backdrop.
    var windowActive = true {
        didSet { if windowActive != oldValue { refreshLift() } }
    }

    /// Dark vibrant themes keep the earlier calibration (underWindowBackground + 15% lift).
    private(set) var vibrantDark = false

    /// A space's theme in one refresh: set one flag at a time, a switch from a vibrant to a solid
    /// space drew a frame with the vibrant calibration (two cra.log lines, dim 0.36 then 0.30).
    func setTheme(vibrantDark: Bool, vibrantLight: Bool, solid: Bool) {
        self.vibrantDark = vibrantDark
        self.vibrantLight = vibrantLight
        solidBackdrop = solid
        refreshLift()
    }

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

    /// The hudWindow material's filters on its desktop tint: SDR normalize, saturate 1.6.
    static func makeTintFilters() -> [NSObject] {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return [] }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel) else { return [] }
        let make = { (type: String) in cls.perform(sel, with: type)?.takeUnretainedValue() as? NSObject }
        guard let normalize = make("sdrNormalize"), let saturate = make("colorSaturate") else { return [] }
        saturate.setValue(1.6, forKey: "inputAmount")
        return [normalize, saturate]
    }

    /// Which blur path this run takes, once: scenarios run both (CRA_FLAGS) and the
    /// log says which one a crash or a stall happened on.
    private static var loggedBackdropPath = false
    private static func logBackdropPath(layer: Bool) {
        guard !loggedBackdropPath else { return }
        loggedBackdropPath = true
        let why = FeatureFlags.current.backdrop == .material ? "CRA_FLAGS" : "no CABackdropLayer or CAFilter"
        CraLog.note("sidebar backdrop: " + (layer ? "layer" : "material (\(why))"))
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
            let backdrop = SidebarBackdrop.resolve(
                solid: solidBackdrop, active: windowActive, fullscreen: windowFullscreen,
                reduceTransparency: reduceTransparency, tintAvailable: desktopTintLayer != nil,
                vibrant: .init(dim: t.blurDim, liftTop: t.liftActive, liftBottom: t.liftActiveBottom,
                               dimInactive: t.blurDimInactive, liftInactive: t.liftInactive))
            dimLayer.opacity = Float(backdrop.dim)
            // A capture added back on activation draws the substitute colour until it is live, where
            // one kept under the fill showed the window behind sharp for a frame (GitHub #132).
            let source: CALayer? = switch backdrop.source {
            case .none: nil
            case .blur: backdropLayer
            case .desktopTint: desktopTintLayer
            }
            for l in [backdropLayer, desktopTintLayer].compactMap({ $0 }) where (l === source) != (l.superlayer != nil) {
                if l === source { backdropHost.layer?.insertSublayer(l, at: 0) } else { l.removeFromSuperlayer() }
            }
            liftLayer.colors = [NSColor(white: 1, alpha: backdrop.liftTop).cgColor, NSColor(white: 1, alpha: backdrop.liftBottom).cgColor]
            CATransaction.commit()
            let state = backdrop.logLine(active: windowActive, reduceTransparency: reduceTransparency)
            if state != loggedBackdrop {
                loggedBackdrop = state
                CraLog.note("sidebar backdrop: " + state)
            }
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
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, background: NSView, sidebar: NSView, toolbar: NSView, status: NSView, find: NSView) {
        backgroundHost = background
        sidebarHost = sidebar
        statusHost = status
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
        // The window server only keeps a behind-window capture live for a layer that is
        // window-server aware in AppKit's capture group (NSVisualEffectView's own settings);
        // without them the blur showed only while the window was redrawing (GitHub #37).
        if FeatureFlags.current.backdrop == .layer,
           let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let blur = ShellView.makeBackdropBlur(radius: 40) {
            let b = cls.init()
            b.filters = [blur]
            b.setValue(true, forKey: "windowServerAware")
            b.setValue("NSCGSWindowBehindWindowCaptureBackdropGroup", forKey: "groupName")
            // While the window server rebuilds the capture (activation, a Space switch) the
            // layer showed the stale, unblurred backdrop: the window behind, sharp (GitHub
            // #83). NSVisualEffectView's own layer allows a substitute colour for that time.
            if b.responds(to: NSSelectorFromString("setAllowsSubstituteColor:")) { b.setValue(true, forKey: "allowsSubstituteColor") }
            backdropHost.layer?.addSublayer(b)
            backdropLayer = b
            // AppKit's tint carries the material's colour filters, not the blur (hudWindow). Bare,
            // it skipped the SDR normalize and the saturate: the fullscreen sidebar came out greyer
            // than Arc's, and dark on the display in GitHub #132.
            if let tintClass = NSClassFromString("CAChameleonLayer") as? CALayer.Type {
                let t = tintClass.init()
                t.filters = ShellView.makeTintFilters()
                desktopTintLayer = t
            }
        }
        dimLayer.backgroundColor = NSColor.black.cgColor
        backdropHost.layer?.addSublayer(dimLayer)
        liftLayer.startPoint = CGPoint(x: 0.5, y: 1)
        liftLayer.endPoint = CGPoint(x: 0.5, y: 0)
        backdropHost.layer?.addSublayer(liftLayer)
        backdropHost.isHidden = true
        addSubview(backdropHost)
        Self.logBackdropPath(layer: backdropLayer != nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        vibrancyLift.wantsLayer = true
        vibrancyLift.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        vibrancyLift.isHidden = true
        addSubview(vibrancyLift)
        addSubview(backgroundHost)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentContainer)
        addSubview(loadingIndicator)
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
        sidePanel.isHidden = true
        sidePanelHandle.isHidden = true
        contentContainer.addSubview(sidePanel)
        contentContainer.addSubview(sidePanelHandle)
        for h in [statusHost, findHost] as [NSView] {
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

    @objc private func accessibilityDisplayOptionsChanged() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        guard reduce != reduceTransparency else { return }
        reduceTransparency = reduce
        refreshLift()
    }

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
        // A click into another pane changes only the focus; the ring moves in the same pass.
        defer { updateFocusRings() }
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
                card.showToolbar = barsShown(panes: shownIDs.count, fullscreen: contentFullscreen)
                card.onToolbarHeightChange = { [weak self] in self?.needsLayout = true }
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

    /// Arc rings the focused pane while the window shows several; one pane fills the window
    /// unmarked. A page in full screen has no card around it.
    private func updateFocusRings() {
        let ringed = paneCards.count > 1 && !contentFullscreen
        for c in paneCards {
            let ring = ringed && c.tabID == focusedPaneID ? focusRingColor : nil
            if c.focusRing != ring { c.focusRing = ring }
        }
    }

    /// The side panel's width in `bounds` (the content area), 0 when none shows: none open, a
    /// page in full screen, or no room beside the page.
    private func sidePanelShownWidth(in bounds: NSRect) -> CGFloat {
        let gap = Double(SplitPaneLayout.Constants.gap)
        let pages = sidePanelPageMinimum
        guard sidePanelWidth > 0, hasTab, !contentFullscreen,
              ExtensionSidePanelWidth.fits(container: Double(bounds.width), gap: gap, pages: pages) else { return 0 }
        return CGFloat(ExtensionSidePanelWidth.clamp(Double(sidePanelWidth), container: Double(bounds.width), gap: gap, pages: pages)).rounded()
    }

    /// What the panes need beside the side panel: each split pane keeps its minimum.
    var sidePanelPageMinimum: Double {
        ExtensionSidePanelWidth.pageMinimum(panes: paneCards.count, paneMinimum: Double(SplitPaneLayout.Constants.minimumPaneLength),
                                            gap: Double(SplitPaneLayout.Constants.gap), sideBySide: splitOrientation == .horizontal)
    }

    /// The panes' share of `bounds`: all of it, less the side panel and its gap on the right.
    private func paneArea(in bounds: NSRect) -> NSRect {
        let w = sidePanelShownWidth(in: bounds)
        guard w > 0 else { return bounds }
        return NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width - w - SplitPaneLayout.Constants.gap, height: bounds.height)
    }

    private func paneLayout(in bounds: NSRect) -> SplitPaneLayout.Result {
        let ids = paneCards.map(\.tabID)
        let panes = ids.map { SplitPaneLayout.Pane(id: $0, factor: paneFactors[$0] ?? (1 / CGFloat(max(1, ids.count)))) }
        var layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: paneArea(in: bounds).size)
        layout.backingScaleFactor = window?.backingScaleFactor ?? 2
        return layout.compute()
    }

    /// Each pane's page area in window coordinates, for the given card frames.
    private func paneWebFrames(_ layout: SplitPaneLayout.Result) -> [UUID: NSRect] {
        var out: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = layout.frames[c.tabID] else { continue }
            let th: CGFloat = panesShowBars ? c.toolbarHeight : 0
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
        let layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: paneArea(in: contentContainer.bounds).size)
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
        desktopTintLayer?.frame = backdropHost.bounds
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
        placeLoadingIndicator(over: f.content)
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

    /// Centred over the card, in the margin above it; hidden where there is none (edge to
    /// edge, fullscreen).
    private func placeLoadingIndicator(over content: NSRect) {
        let margin = bounds.maxY - content.maxY
        loadingIndicator.isHidden = margin < CGFloat(LoadingIndicator.height) + 2
        loadingIndicator.frame = loadingIndicatorFrame(over: content)
    }

    private func loadingIndicatorFrame(over content: NSRect) -> NSRect {
        let w = CGFloat(LoadingIndicator.trackWidth) + 2
        return NSRect(x: (content.midX - w / 2).rounded(), y: content.maxY, width: w, height: bounds.maxY - content.maxY)
    }

    /// The front tab's loading state. Another tab coming to the front shows its state at once.
    func setLoading(_ phase: LoadingIndicator.Phase, tab: UUID?) {
        let sameTab = tab == loadingTabID
        loadingTabID = tab
        loadingIndicator.setPhase(phase, animated: sameTab)
    }

    func layoutContentChildren(animated: Bool = false) {
        let cb = contentContainer.bounds
        updateFocusRings()
        let toolbarVisible = panesShowBars
        let layout = paneLayout(in: cb)
        for c in paneCards {
            c.showToolbar = toolbarVisible
            // Arc's cards cast a soft shadow on the window; edge to edge there is no margin for it.
            c.castsShadow = !edgeToEdge && !contentFullscreen
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
        layoutSidePanel(in: cb)
        // The no-tab card is rounded like a page's (GitHub #6: a new window showed a square one).
        placeholderHost.layer?.cornerRadius = cardCornerRadius
        placeholderHost.layer?.cornerCurve = .continuous
        parkingView.frame = cb

        // DevTools docks inside the focused card, right of its page.
        let focus = focusedCard
        let fb = focus?.bounds ?? .zero
        let th: CGFloat = toolbarVisible ? focus?.toolbarHeight ?? CraMetrics.toolbarHeight : 0
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
            for h in [statusHost, findHost] where contentContainer.subviews.last !== h {
                contentContainer.addSubview(h, positioned: .above, relativeTo: nil)
            }
        }
        statusHost.isHidden = !statusVisible
        statusHost.frame = NSRect(x: wb.minX, y: wb.minY, width: min(540, wb.width), height: 34)
        if findHost.superview === overlayParent {
            let size = CraMetrics.findBarSize, inset = CraMetrics.findBarInset
            findHost.isHidden = !findVisible
            findHost.frame = NSRect(x: wb.maxX - size.width - inset, y: wb.maxY - size.height - inset, width: size.width, height: size.height)
        }
        if !animatingPanes, paneCards.allSatisfy({ $0.frozenWebBounds == nil }) { onPaneFrames?(paneWebFrames(layout)) }
    }

    private func layoutSidePanel(in cb: NSRect) {
        let w = sidePanelShownWidth(in: cb)
        sidePanel.isHidden = w == 0
        sidePanelHandle.isHidden = w == 0
        guard w > 0 else { onSidePanelFrame?(nil); return }
        let gap = SplitPaneLayout.Constants.gap
        let f = NSRect(x: cb.maxX - w, y: cb.minY, width: w, height: cb.height)
        if sidePanel.frame != f { sidePanel.frame = f }
        sidePanel.cornerRadius = edgeToEdge ? 0 : CraMetrics.contentCornerRadius
        sidePanel.castsShadow = !edgeToEdge
        sidePanel.layoutSubtreeIfNeeded()
        // The handle covers the gap and reaches a little into the cards on both sides.
        sidePanelHandle.frame = NSRect(x: f.minX - gap - 3, y: cb.minY, width: gap + 6, height: cb.height)
        onSidePanelFrame?(contentContainer.convert(sidePanel.convert(sidePanel.pageArea.frame, to: contentContainer), to: nil))
    }

    /// Chrome-style hosting: the status bubble moves into a click-through panel above the
    /// page windows; the find bar, which takes clicks, into its own panel just its size, which
    /// the window controller places.
    func moveOverlays(to view: NSView, findBar: NSPanel) {
        overlayParent = view
        statusHost.removeFromSuperview()
        view.addSubview(statusHost)
        findHost.removeFromSuperview()
        findHost.isHidden = false
        findHost.autoresizingMask = [.width, .height]
        findHost.frame = findBar.contentView!.bounds
        findBar.contentView!.addSubview(findHost)
        needsLayout = true
    }

    /// Animate between sidebar states by interpolating frames.
    /// While the sidebar's width follows the fingers (a Library swipe) the pages keep their size
    /// and their cards move over them: resizing a page makes Chromium lay it out again, and once
    /// per event that stalled the swipe. `thawPages` gives them the size they end up with, once.
    func freezePages() {
        for c in paneCards where c.frozenWebBounds == nil { c.frozenWebBounds = NSRect(origin: .zero, size: c.webArea.bounds.size) }
    }

    func thawPages() {
        guard paneCards.contains(where: { $0.frozenWebBounds != nil }) else { return }
        for c in paneCards { c.frozenWebBounds = nil }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func animateSidebar(visible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat, duration: TimeInterval = 0.085) {
        let target = frames(sidebarVisible: visible, floating: floating, fullscreen: fullscreen, width: width)
        // Size the pages for their destination once, up front; the cards then just slide over them.
        let targetLayout = paneLayout(in: NSRect(origin: .zero, size: target.content.size))
        var webTargets: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = targetLayout.frames[c.tabID] else { continue }
            var w = f.width
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 { w -= min(max(320, devToolsWidth), f.width * 0.7) }
            let toolbarH: CGFloat = barsShown(panes: paneCards.count, fullscreen: fullscreen) ? c.toolbarHeight : 0
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
            loadingIndicator.animator().frame = loadingIndicatorFrame(over: target.content)
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
    private var dragging = false
    private var tracking: NSTrackingArea?

    /// The window is movable by its background; this strip must own its drags.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    /// A page window or the floating sidebar's panel is usually not key, so track
    /// always and set the cursor ourselves.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }

    override func mouseDown(with event: NSEvent) { lastX = event.locationInWindow.x; dragging = true }
    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        onDrag?(x - lastX)
        lastX = x
        NSCursor.resizeLeftRight.set()
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        onEnd?()
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    }
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
