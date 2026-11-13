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
    var windowFullscreen = false { didSet { if windowFullscreen != oldValue { refreshLift(); needsLayout = true } } }
    /// AppKit's answer to whether the window draws its active look (MainWindowController.materialActiveNow).
    let activeAppearance = ActiveAppearanceProbe()
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
    /// While the Library is in the sidebar, or a swipe is bringing it in: the tab sidebar the page
    /// keeps its width from (nil inside when the Library brought out a hidden sidebar). The page
    /// moves with the Library's edge and past the window's instead of narrowing (LibraryWidth.page, #340).
    var pageBesideLibrary: () -> PageBesideLibrary? = { nil }
    struct PageBesideLibrary { var tabSidebar: CGFloat? }
    /// Off while the Library has the sidebar: its width is not the user's to drag.
    var sidebarResizable = true { didSet { needsLayout = true } }
    var sidebarVisible = true { didSet { needsLayout = true } }
    var floatingSidebar = false { didSet { needsLayout = true } }
    var contentFullscreen = false { didSet { needsLayout = true } }
    /// Settings ▸ "Pages fill the window edge to edge" (GitHub #24): no margin, square cards.
    var edgeToEdge = false { didSet { needsLayout = true } }
    /// The card fills the window: edge to edge, or full screen with the sidebar hidden, as in Arc
    /// (CraCore CardFill, #315), or a page in full screen.
    var fillsWindow: Bool { contentFullscreen || fills(sidebarVisible: sidebarVisible) }
    private func fills(sidebarVisible: Bool) -> Bool {
        CardFill.fillsWindow(edgeToEdge: edgeToEdge, fullScreen: windowFullscreen, sidebarShown: sidebarVisible)
    }
    /// For `cra://debug?windowState`: how far the card sits from the window's left, bottom, right and
    /// top edges, its corner radius and whether it fills the window, e.g. `0,0,0,0 r0 fills=1`.
    var cardReadout: String {
        let f = contentContainer.frame
        return String(format: "%.0f,%.0f,%.0f,%.0f r%.0f fills=%d", f.minX, f.minY, bounds.maxX - f.maxX, bounds.maxY - f.maxY,
                      cardCornerRadius, fillsWindow ? 1 : 0)
    }
    /// Whether a lone page has a bar: the toolbar, or the developer bar on a Developer Mode site
    /// (AppSettings.showsBar(above:), #185).
    var showToolbar = true { didSet { needsLayout = true } }
    /// Whether the cards carry their bars. Arc keeps every pane's bar in a split even with the
    /// toolbar hidden (View ▸ Show Toolbar is disabled while a split is open, GitHub #178).
    var panesShowBars: Bool { barsShown(panes: paneCards.count, fullscreen: contentFullscreen) }
    private func barsShown(panes: Int, fullscreen: Bool) -> Bool { !fullscreen && (showToolbar || panes > 1) }
    /// Settings ▸ Tabs ▸ "Hide the toolbar until the pointer reaches the top of the page", for the
    /// page on screen (AppSettings.hidesToolbar(above:)): a lone card's bar floats over its page and
    /// the pointer at the card's top brings it out (ToolbarAutoHide).
    var autoHideToolbar = false { didSet { if autoHideToolbar != oldValue { needsLayout = true } } }
    /// Whether the card's bar floats over its page instead of sitting above it.
    var toolbarFloats: Bool { floats(panes: paneCards.count, fullscreen: contentFullscreen) }
    private func floats(panes: Int, fullscreen: Bool) -> Bool {
        // With pages in their own windows (embedPages off) the page is a window over the card,
        // as with DevTools open, and a bar in the card can't float over it.
        ToolbarAutoHide.floats(enabled: autoHideToolbar, toolbarShown: barsShown(panes: panes, fullscreen: fullscreen), panes: panes,
                               developerBar: paneCards.first?.developerBar != nil,
                               devToolsOpen: devToolsVisible || !EmbeddedPages.isEnabled, pageFullscreen: fullscreen)
    }
    /// Whether the bars take room above their pages: shown, and not floating over them.
    var barsTakeRoom: Bool { panesShowBars && !toolbarFloats }
    /// What a card's bar takes from the top of its page with that many panes on screen.
    private func barInset(_ c: PaneCardView, panes: Int, fullscreen: Bool) -> CGFloat {
        guard barsShown(panes: panes, fullscreen: fullscreen) else { return 0 }
        return floats(panes: panes, fullscreen: fullscreen) && c.hasPage && !c.transparent ? 0 : c.toolbarHeight
    }
    /// Whether the floating toolbar is out, from where the pointer is and how long it has been there.
    private var toolbarTracker = ToolbarAutoHideTracker()
    /// The pointer is looked at on a timer while the bar floats and Cra is the active app: as for
    /// the floating sidebar, no window of ours reliably gets mouse-moved events over a page.
    private var toolbarPoll: Timer?
    private var toolbarActivation: [NSObjectProtocol] = []
    /// The clock the toolbar's waits run on, and where the pointer is in the shell's coordinates
    /// (nil: nowhere that counts); the tests stand both in.
    var toolbarNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    lazy var toolbarPointer: () -> NSPoint? = { [unowned self] in
        guard let window, NSApp.isActive, window.isVisible, window.isKeyWindow || window.isMainWindow else { return nil }
        return self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }
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

    /// The hudWindow material's capture, as AppKit builds it (probe dump, 5 Nov 2026): an eighth-scale
    /// capture under SDR normalize, a 30 pt blur and saturate 1.6. Cra's own full-scale 40 pt blur was
    /// blurrier and greyer than Arc's over a colourful backdrop, and 64 times the pixels for the window
    /// server to rebuild whenever the capture comes back (the dropout out of Stage Manager, GitHub #156).
    /// Over the plain white and black backdrops the dim and lift were fitted on, it draws the same.
    static let backdropScale = 0.125
    static func makeBackdropFilters() -> [NSObject] {
        guard let blur = makeBackdropBlur(radius: 30) else { return [] }
        let tint = makeTintFilters()
        return tint.count == 2 ? [tint[0], blur, tint[1]] : [blur]
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
            // The desktop tint stays in the tree, as in AppKit's material: at 0.05 windowed, active or not,
            // and in place of the blur in full screen. Only Reduce transparency takes it out. Inserted
            // fresh, it drew nothing until the window server had resolved it (GitHub #156). It sits under
            // the capture and the fill, so at 0.05 it doesn't change the calibrated colours.
            if let tint = desktopTintLayer {
                if reduceTransparency { tint.removeFromSuperlayer() } else if tint.superlayer == nil { backdropHost.layer?.insertSublayer(tint, at: 0) }
                tint.opacity = backdrop.source == .desktopTint ? 1 : 0.05
            }
            // A capture added back on activation draws the substitute colour until it is live, where
            // one kept under the fill showed the window behind sharp for a frame (GitHub #132).
            if let b = backdropLayer, (backdrop.source == .blur) != (b.superlayer != nil) {
                if backdrop.source == .blur { backdropHost.layer?.insertSublayer(b, at: desktopTintLayer?.superlayer == nil ? 0 : 1) } else { b.removeFromSuperlayer() }
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
        addSubview(activeAppearance)
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
           case let filters = ShellView.makeBackdropFilters(), !filters.isEmpty {
            let b = cls.init()
            b.filters = filters
            b.setValue(ShellView.backdropScale, forKey: "scale")
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
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - barInset(c, panes: shownIDs.count, fullscreen: contentFullscreen)))
            c.layoutSubtreeIfNeeded()
        }
        for c in paneCards where oldFrames[c.tabID] != nil {
            guard let f = target.frames[c.tabID] else { continue }
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - barInset(c, panes: shownIDs.count, fullscreen: contentFullscreen)))
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
            let th = barInset(c, panes: paneCards.count, fullscreen: contentFullscreen)
            let bh = c.bottomBarHeight
            var web = NSRect(x: f.minX, y: f.minY + bh, width: f.width, height: max(0, f.height - th - bh))
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
        guard FloatingSidebarGeometry.mayReveal(sidebarShown: sidebarVisible, pageFullscreen: contentFullscreen) else { return }
        if !floatingSidebar, FloatingSidebarGeometry.shouldReveal(at: p, in: bounds, edgeToEdge: fillsWindow) {
            onEdgeHover?(true)
        } else if floatingSidebar, FloatingSidebarGeometry.shouldHide(at: p, in: bounds, sidebarWidth: sidebarWidth,
                                                                     pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: fillsWindow) {
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

    // MARK: Floating toolbar

    /// The card whose bar floats, if one does.
    private var floatingCard: PaneCardView? {
        guard toolbarFloats, let card = paneCards.first, card.toolbarIsFloating else { return nil }
        return card
    }

    /// After a layout: the card shows what the tracker says, a bar that stopped floating forgets
    /// its state, and the pointer is watched only while a bar floats.
    private func syncFloatingToolbar() {
        if let card = floatingCard {
            if card.toolbarRevealed != toolbarTracker.shown { card.setToolbarRevealed(toolbarTracker.shown, animated: false) }
        } else if toolbarTracker != ToolbarAutoHideTracker() {
            toolbarTracker.reset()
        }
        if toolbarActivation.isEmpty, floatingCard != nil {
            toolbarActivation = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.toolbarActivationChanged() }
                }
            }
        }
        syncToolbarPolling()
    }

    private func toolbarActivationChanged() {
        // Another app in front: the bar goes with the pointer's attention, as the floating sidebar does.
        if !NSApp.isActive, toolbarTracker.shown {
            toolbarTracker.reset()
            floatingCard?.setToolbarRevealed(false, animated: true)
        }
        syncToolbarPolling()
    }

    private func syncToolbarPolling() {
        let on = floatingCard != nil && window != nil && NSApp.isActive
        guard on != (toolbarPoll != nil) else { return }
        toolbarPoll?.invalidate()
        toolbarPoll = nil
        guard on else { return }
        // Fired on the main run loop, so no hop to the main actor. It stops with the app's
        // activation and with the setting, so a Cra in the background or with the toolbar above
        // the page wakes for none of this.
        toolbarPoll = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleToolbarPointer() }
        }
        toolbarPoll?.tolerance = 0.015
    }

    /// One look at the pointer.
    func sampleToolbarPointer() {
        guard let card = floatingCard else { return }
        let where_: ToolbarAutoHide.Pointer
        if let p = toolbarPointer() {
            where_ = ToolbarAutoHide.classify(p, card: convert(card.frame, from: card.superview), container: bounds,
                                              barHeight: card.toolbarHeight, shown: toolbarTracker.shown)
        } else {
            where_ = .away
        }
        // A button held down (a drag begun on the bar) or something hanging under the bar keeps it.
        let held = toolbarTracker.shown && (NSEvent.pressedMouseButtons != 0 || somethingHangsFromToolbar(card))
        toolbarTracker.sample(where_, held: held, at: toolbarNow())
        if card.toolbarRevealed != toolbarTracker.shown { card.setToolbarRevealed(toolbarTracker.shown, animated: true) }
    }

    /// A popover or popup of Cra's hangs from the bar (the Site Control Center, an extension's
    /// popup, Translate): the bar stays out under it wherever the pointer goes.
    private func somethingHangsFromToolbar(_ card: PaneCardView) -> Bool {
        guard let window else { return false }
        let cardOnScreen = window.convertToScreen(card.convert(card.bounds, to: nil))
        return (window.childWindows ?? []).contains { child in
            child.isVisible && child.alphaValue > 0
                && ToolbarAutoHide.hangsFromBar(child.frame, card: cardOnScreen, barHeight: card.toolbarHeight)
        }
    }

    /// Something is about to hang under the bar, or asked for it: out now, without the slide, so
    /// what hangs there finds the bar's buttons where they are.
    func bringFloatingToolbarOut() {
        guard let card = floatingCard, !toolbarTracker.shown else { return }
        toolbarTracker.bringOut()
        card.setToolbarRevealed(true, animated: false)
    }

    /// For `cra://debug?toolbar=…`: `out` and `in` put the floating bar there, `sample` looks at
    /// the pointer once, `at:x,y` says what a pointer there would be to the bar; anything else is
    /// a label. Every one answers with the command and where the bar is.
    func debugToolbar(_ command: String) -> String {
        switch command {
        case "out": bringFloatingToolbarOut()
        case "in":
            toolbarTracker.reset()
            floatingCard?.setToolbarRevealed(false, animated: false)
        case "sample": sampleToolbarPointer()
        default: break
        }
        layoutSubtreeIfNeeded()
        let card = paneCards.first
        // at:x,y (from the window's top left, as clickAt takes them): what a pointer there is to the bar.
        if command.hasPrefix("at:"), let card, let window {
            let g = command.dropFirst(3).split(separator: ",").compactMap { Double($0) }
            guard g.count == 2 else { return "toolbar at: x,y" }
            let p = convert(NSPoint(x: g[0], y: window.frame.height - g[1]), from: nil)
            let where_ = ToolbarAutoHide.classify(p, card: convert(card.frame, from: card.superview), container: bounds,
                                                  barHeight: card.toolbarHeight, shown: toolbarTracker.shown)
            return "toolbar \(command): \(where_) out=\(toolbarTracker.shown ? 1 : 0)"
        }
        return "toolbar \(command): floats=\(floatingCard != nil ? 1 : 0) out=\(toolbarTracker.shown ? 1 : 0) "
            + "inset=\(Int(card?.barInset ?? 0)) page=\(Int(card?.webArea.frame.height ?? 0))/\(Int(card?.bounds.height ?? 0)) "
            + "barHidden=\(card?.toolbarHost.isHidden == true ? 1 : 0) polling=\(toolbarPoll != nil ? 1 : 0)"
    }

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
        // corners round it where they meet. Full screen with the sidebar hidden too (Arc, #315).
        let fill = fills(sidebarVisible: sidebarVisible)
        let inset = fill ? 0 : CraMetrics.contentInset
        let radius = fill ? 0 : CraMetrics.contentCornerRadius
        if sidebarVisible {
            var pageWidth = b.width - width - inset
            if let kept = pageBesideLibrary() {
                pageWidth = CGFloat(LibraryWidth.page(window: Double(b.width), library: Double(width),
                                                      tabSidebar: kept.tabSidebar.map(Double.init), inset: Double(inset)))
            }
            let content = NSRect(x: width, y: inset, width: max(0, pageWidth), height: max(0, b.height - 2 * inset))
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
        if !resizeHandle.dragging {
            resizeHandle.frame = f.handle
            resizeHandle.isHidden = f.handle.isEmpty || !sidebarResizable
        }
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
        let floating = toolbarFloats
        let layout = paneLayout(in: cb)
        for c in paneCards {
            c.showToolbar = toolbarVisible
            c.floatsToolbar = floating
            // Arc's cards cast a soft shadow on the window; edge to edge there is no margin for it.
            c.castsShadow = !fillsWindow && !contentFullscreen
            // Several panes: every card is rounded; a single card follows the window state (square in fullscreen).
            // Edge to edge every card is square.
            c.cornerRadius = paneCards.count > 1 && !fillsWindow ? CraMetrics.contentCornerRadius : cardCornerRadius
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
        syncFloatingToolbar()
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
        let th: CGFloat = toolbarVisible ? focus?.barInset ?? CraMetrics.toolbarHeight : 0
        let bh = focus?.bottomBarHeight ?? 0
        let bodyH = max(0, fb.height - th - bh)
        let selfDock = devToolsFrontendDocked
        let showDev = devToolsVisible && hasTab && focus != nil && (selfDock || fb.width > 640)
        let devW: CGFloat = showDev && !selfDock ? min(max(320, devToolsWidth), fb.width * 0.7) : 0
        if let focus, showDev {
            for v in [devToolsHost, devToolsDivider, devToolsHandle] where v.superview !== focus { v.removeFromSuperview(); focus.addSubview(v) }
            focus.webArea.frame = NSRect(x: 0, y: bh, width: fb.width - devW, height: bodyH)
            EmbeddedPages.place(focus.webArea.subviews, in: focus.pageBounds)
        }
        // A frontend-docked DevTools paints its own split; the shell's dock chrome stays hidden.
        devToolsHost.isHidden = !showDev || selfDock
        devToolsDivider.isHidden = !showDev || selfDock
        devToolsHandle.isHidden = !showDev || selfDock
        let devFrame = selfDock ? NSRect(x: 0, y: bh, width: fb.width, height: bodyH)
                                : NSRect(x: fb.width - devW, y: bh, width: devW, height: bodyH)
        devToolsHost.frame = devFrame
        devToolsDivider.frame = NSRect(x: fb.width - devW, y: bh, width: 1, height: bodyH)
        devToolsHandle.frame = NSRect(x: fb.width - devW - 3, y: bh, width: 7, height: bodyH)
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
        // In the overlay panel this fills it: the panel is just this strip of the page (#346).
        statusHost.frame = StatusBubbleStrip.frame(inPage: wb)
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
        sidePanel.cornerRadius = fillsWindow ? 0 : CraMetrics.contentCornerRadius
        sidePanel.castsShadow = !fillsWindow
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

    func animateSidebar(visible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat, duration: TimeInterval = SidebarMotion.duration) {
        let target = frames(sidebarVisible: visible, floating: floating, fullscreen: fullscreen, width: width)
        // Size the pages for their destination once, up front; the cards then just slide over them.
        let targetLayout = paneLayout(in: NSRect(origin: .zero, size: target.content.size))
        var webTargets: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = targetLayout.frames[c.tabID] else { continue }
            var w = f.width
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 { w -= min(max(320, devToolsWidth), f.width * 0.7) }
            let toolbarH = barInset(c, panes: paneCards.count, fullscreen: fullscreen)
            let page = convert(NSRect(x: target.content.minX + f.minX, y: target.content.minY + f.minY, width: w, height: max(0, f.height - toolbarH)), to: nil)
            webTargets[c.tabID] = page
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: w, height: page.height)
            c.frozenPageInWindow = page
        }
        cardCornerRadius = target.cornerRadius
        if paneCards.count == 1, let c = paneCards.first { c.cornerRadius = target.cornerRadius }
        layoutContentChildren()
        startSlideReadout()
        animatingFrames = true
        // Arc 1.172.1's ⌘S at 60 fps (CraCore SidebarMotion): about 43 / 72 / 89 / 97 % of the travel
        // after frames 1–4.
        let c = SidebarMotion.curve
        let timing = CAMediaTimingFunction(controlPoints: Float(c.0), Float(c.1), Float(c.2), Float(c.3))
        onAnimatePaneFrames?(webTargets, duration, timing)
        // Real frames each display frame: a layer animation left the toolbar and page at their final size.
        sidebarSlide = SidebarSlide(fromSidebar: sidebarHost.frame, toSidebar: target.sidebar, fromContent: contentContainer.frame,
                                    toContent: target.content, start: CACurrentMediaTime(), duration: duration,
                                    visible: visible, floating: floating, fullscreen: fullscreen)
        guard duration > 0, window != nil else { return finishSidebarSlide() }
        if sidebarSlideLink == nil {
            let link = displayLink(target: self, selector: #selector(stepSidebarSlide))
            link.add(to: .main, forMode: .common)
            sidebarSlideLink = link
        }
        // A display link stops when the window leaves the screen; the slide still ends.
        let id = sidebarSlide!.start
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) { [weak self] in
            if self?.sidebarSlide?.start == id { self?.finishSidebarSlide() }
        }
    }

    private struct SidebarSlide {
        let fromSidebar: NSRect, toSidebar: NSRect, fromContent: NSRect, toContent: NSRect
        let start: CFTimeInterval, duration: TimeInterval
        let visible: Bool, floating: Bool, fullscreen: Bool
    }

    private var sidebarSlide: SidebarSlide?
    private var sidebarSlideLink: CADisplayLink?
    /// The sidebar is sliding in or out (⌘S): the page area's edge is where the slide has it.
    var slidingSidebar: Bool { sidebarSlide != nil }
    /// Each frame of the slide and its end, once the page area has moved (a Peek follows it, #402).
    var onSidebarSlideFrame: (() -> Void)?

    @objc private func stepSidebarSlide(_ link: CADisplayLink) {
        guard let s = sidebarSlide else { return finishSidebarSlide() }
        let t = link.targetTimestamp - s.start
        guard t < s.duration else { return finishSidebarSlide() }
        let p = SidebarMotion.progress(at: t, duration: s.duration)
        let content = SidebarSlidePage.frame(from: s.fromContent, to: s.toContent, progress: p)
        if !sidebarDetached { sidebarHost.frame = SidebarSlidePage.frame(from: s.fromSidebar, to: s.toSidebar, progress: p) }
        contentContainer.frame = content
        loadingIndicator.frame = loadingIndicatorFrame(over: content)
        layoutContentChildren()
        onSidebarSlideFrame?()
    }

    private func finishSidebarSlide() {
        sidebarSlideLink?.invalidate()
        sidebarSlideLink = nil
        guard let s = sidebarSlide else { return }
        sidebarSlide = nil
        animatingFrames = false
        for c in paneCards { c.frozenWebBounds = nil }
        sidebarVisible = s.visible
        floatingSidebar = s.floating
        contentFullscreen = s.fullscreen
        needsLayout = true
        layoutSubtreeIfNeeded()
        endSlideReadout()
        onSidebarSlideFrame?()
    }

    /// Logged as "sidebar slide: page moved N pt" for the sidebar-slide scenario.
    private var slidingPage: SidebarSlidePage?
    private var slideSampler: Timer?

    private func startSlideReadout() {
        slideSampler?.invalidate()
        slidingPage = SidebarSlidePage()
        let timer = Timer(timeInterval: 1.0 / 240, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSlidingPage() }
        }
        RunLoop.main.add(timer, forMode: .common)
        slideSampler = timer
    }

    private func sampleSlidingPage() {
        guard let layer = focusedCard?.webArea.subviews.first?.layer else { return }
        let drawn = layer.presentation() ?? layer
        slidingPage?.record(drawn.convert(drawn.bounds, to: nil), drawn: drawn.frame == layer.frame)
    }

    private func endSlideReadout() {
        sampleSlidingPage()
        slideSampler?.invalidate()
        slideSampler = nil
        if let slide = slidingPage, !slide.isEmpty { CraLog.note("sidebar slide: page moved \(Int(slide.drift.rounded())) pt over \(slide.samples) frames") }
        slidingPage = nil
    }
}

/// Thin vertical strip between sidebar and content that drags the width.
final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    /// A press on the strip; `onResize` then gets the whole drag.
    var onBegin: (() -> Void)?
    /// Points from where the press began (+ wider) and the pointer's speed in points a second;
    /// called instead of `onDrag` when set (the sidebar, #287: Arc keeps the edge under the
    /// pointer, snaps at slow speeds and hides the sidebar when dragged far enough).
    var onResize: ((_ translation: CGFloat, _ speed: CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var lastX: CGFloat = 0
    private var startX: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var speed: CGFloat = 0
    /// A press on the strip is in progress. The shell keeps the strip in place meanwhile, even
    /// when the drag hides the sidebar: a hidden view gets no more of the drag (#287).
    private(set) var dragging = false
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

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
        startX = lastX
        lastTime = event.timestamp
        speed = 0
        dragging = true
        onBegin?()
    }
    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        let dt = event.timestamp - lastTime
        // Smoothed like a pan recognizer's velocity, so one quick event doesn't read as a fling.
        if dt > 0 { speed = speed * 0.5 + (x - lastX) / CGFloat(dt) * 0.5 }
        if let onResize { onResize(x - startX, speed) } else { onDrag?(x - lastX) }
        lastX = x
        lastTime = event.timestamp
        NSCursor.resizeLeftRight.set()
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        onEnd?()
        superview?.needsLayout = true
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
