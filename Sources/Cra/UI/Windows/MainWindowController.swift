import AppKit
import CraCEF
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, BrowserManagerDelegate {
    unowned let app: AppDelegate
    var store: SidebarStore { app.store }
    let sidebarUI = SidebarUIState()
    let sidebarActions = SidebarActions()
    let overlay = OverlayState()
    let commandBar: CommandBarController
    private(set) var browsers: BrowserManager!
    private(set) var shell: ShellView!
    private var commandPanel: CommandBarPanel!
    private var commandHost: CommandBarView!
    let tabSwitcher = TabSwitcher()
    private let tabSwitcherPanel = TabSwitcherPanel()
    private var spaceEditor: NSWindow?
    private var importWindow: ImportWindowController?
    private var scrollMonitor: Any?
    private var pageTopDragMonitor: Any?
    private var replayingPageClick = false
    private var childClickMonitor: Any?
    private var middleClickMonitor: Any?
    private enum SwipeAxis { case undecided, horizontal, vertical }
    private var swipeAxis = SwipeAxis.vertical
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    /// Points travelled since the space swipe locked, and recent deltas for its release speed.
    private var swipeTravel: CGFloat = 0
    private var swipeSamples: [(time: TimeInterval, dx: CGFloat)] = []
    private var swipeDetent = 0
    /// Shift + wheel over the sidebar adding up toward a space change.
    private var wheelSpaceSwitch = WheelSpaceSwitch()
    /// The Library's reveal a swipe started from: 0 on the first space, 1 in the Library; nil
    /// when the swipe can only page between spaces.
    private var librarySwipeFrom: CGFloat?
    private var librarySettleSpring: (start: CFTimeInterval, from: CGFloat, velocity: CGFloat, target: CGFloat)?
    private var librarySettleLink: CADisplayLink?
    /// Shows the lists' overlay knob again once a swipe's scroller flash has faded.
    private var swipeKnobReveal: DispatchWorkItem?
    private var enteredFullscreenForContent = false
    /// The tab whose page (a video) is in element fullscreen.
    private var contentFullscreenTab: UUID?
    private var lastSidebarVisible = true
    /// The theme the background and placeholder root views were made with.
    private var shownTheme: SpaceTheme?
    private var lastSidebarWidth: CGFloat = 0
    private var commandBarOpenedAt = Date.distantPast
    private var commandBarClosingClick = DismissingClick()
    private let toast = ShinyToast()
    private var commandObserving = false
    /// Closed for good (another window stayed open): it no longer follows the store.
    private var isTornDown = false

    var currentBrowser: CraBrowser? { browsers.visibleRuntime?.browser }

    /// The window's extension side panel (chrome.sidePanel; Chrome's, which Arc lacks).
    private(set) lazy var sidePanel = ExtensionSidePanelController(app: app, shell: shell, owner: self)

    /// The side panel's page window joined this window's children: the overlay panels stay above it.
    func sidePanelPageAttached() { raiseOverlayPanels() }

    /// This window's entry in the store (WindowSession): its space, open tabs, frame.
    let windowID: UUID
    /// Pages load in the off-the-record profile; nothing is saved (WindowSession.isIncognito).
    let isIncognito: Bool
    /// Arc's Blank Window (#220): a sidebar of its own, "This Window", in the normal profile.
    var isBlank: Bool { store.isBlank(window: windowID) }
    /// Shows only a space of its own (incognito or Blank): no other spaces, no space switching.
    var isStandalone: Bool { isIncognito || isBlank }
    var focusedSpaceID: UUID { store.focusedSpaceID(window: windowID) }
    var focusedSpace: Space { store.focusedSpace(window: windowID) }
    var selectedTabID: UUID? { store.selectedTabID(window: windowID) }
    var selectedTab: SidebarItem? { store.selectedTab(window: windowID) }
    var sidebarVisible: Bool {
        get { store.window(windowID).sidebarVisible }
        set { store.updateWindow(windowID) { $0.sidebarVisible = newValue } }
    }

    init(app: AppDelegate, session: WindowSession) {
        self.app = app
        windowID = session.id
        isIncognito = session.isIncognito
        commandBar = CommandBarController(engine: app.engine, store: app.store)
        let frame = session.frame.map { NSRectFromString($0) } ?? NSRect(x: 0, y: 0, width: 1400, height: 880)
        let window = CraWindow(contentRect: frame,
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
        super.init(window: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = "Cra"
        // The initializer can shift a saved global frame onto the current screen.
        // Apply it after construction so a window on another display stays there.
        if session.frame != nil, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        window.delegate = self
        sidebarUI.windowID = session.id

        let store = app.store
        let palette = focusedSpace.theme.palette
        shell = ShellView(frame: window.contentView!.bounds,
                          background: SpaceBackgroundView(store: store, ui: sidebarUI),
                          sidebar: SidebarView(store: store, ui: sidebarUI, actions: sidebarActions, favicons: app.favicons),
                          toolbar: PaneToolbarView(paneTabID: nil, store: store, ui: sidebarUI, actions: sidebarActions),
                          status: StatusBubbleView(overlay: overlay),
                          find: FindBarView(overlay: overlay, onFind: { [weak self] q, fwd in self?.find(q, forward: fwd) },
                                            onClose: { [weak self] in self?.hideFindBar() }))
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        shell.sidebarVisible = sidebarVisible
        shell.showToolbar = store.settings.showsBar(above: selectedTabID.flatMap { store.item($0)?.tab?.url })
        shell.edgeToEdge = store.settings.edgeToEdgeContent
        lastSidebarVisible = sidebarVisible
        window.trafficLightsHidden = !sidebarVisible
        lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
        window.contentView = shell
        window.backgroundColor = NSColor(palette.gradientColors.first ?? .gray)

        browsers = BrowserManager(store: store, favicons: app.favicons, container: shell.parkingView, clock: app.composition.clock)
        // What extensions set for a tab (chrome.action.setIcon with tabId) went with its page.
        browsers.pageClosed = { ExtensionStore.shared.forgetActionTab($0) }
        browsers.delegate = self
        browsers.windowID = session.id
        browsers.takeRuntimeFromOtherWindow = { [weak self] id in
            guard let self else { return nil }
            for other in self.app.mainWindows where other !== self {
                if let rt = other.browsers.release(id) {
                    // The window it came from keeps the tab selected behind a blurred stand-in.
                    DispatchQueue.main.async { [weak other] in other?.refresh() }
                    return rt
                }
            }
            return nil
        }
        // AppKit asks the view under a press whether it may move the window. In the
        // sidebar's list that is SwiftUI's scroll container, which always says yes,
        // so the window's own flag is what keeps a row press for the row's drag.
        sidebarUI.onPointerOverDraggableChange = { [weak window] over in window?.isMovableByWindowBackground = !over }
        browsers.paneHost = { [weak self] id in self?.shell.card(for: id)?.webArea }
        shell.makeToolbar = { [weak self] id in
            guard let self else { return NSView() }
            return PaneToolbarView(paneTabID: id, store: self.store, ui: self.sidebarUI, actions: self.sidebarActions)
        }
        shell.onPaneResizeBegan = { [weak self] in self?.pageWindowsFollowLive = true }
        shell.onPaneResizeEnded = { [weak self] factors in
            guard let self else { return }
            self.pageWindowsFollowLive = false
            if let sel = self.selectedTabID, let split = self.store.splitContaining(sel) {
                self.store.setSplitWidthFactors(split.id, factors.mapValues { Double($0) })
            }
        }

        commandPanel = CommandBarPanel()
        commandHost = CommandBarView(controller: commandBar, favicons: app.favicons)
        commandPanel.contentView = commandHost
        commandPanel.delegate = self
        tabSwitcherPanel.contentView = TabSwitcherView(switcher: tabSwitcher, favicons: app.favicons)
        tabSwitcher.onShow = { [weak self] in self?.showTabSwitcherPanel() }
        tabSwitcher.onHide = { [weak self] in self?.hideTabSwitcherPanel() }
        tabSwitcher.onCommit = { [weak self] id in
            guard let self, id != self.selectedTabID else { return }
            let space = self.focusedSpaceID
            self.store.selectTab(id, window: self.windowID)
            // Arc rings a tab chosen from the keyboard only when it had to change space to show
            // it; within a space the selection alone marks it (issue #12).
            if self.focusedSpaceID != space { self.sidebarUI.keyboardFocusID = id }
        }
        tabSwitcher.direction = { [weak app] event in
            switch app?.bindings.action(for: event)?.id {
            case "recentTab": return 1
            case "recentTabBackward": return -1
            default: return nil
            }
        }

        wireActions()
        shell.resizeHandle.onDrag = { [weak self] dx in
            guard let self else { return }
            let w = min(max(CraMetrics.sidebarMinWidth, shell.sidebarWidth + dx), CraMetrics.sidebarMaxWidth)
            shell.sidebarWidth = w
            shell.layoutSubtreeIfNeeded()
        }
        shell.resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            store.prefs.sidebarWidth = Double(shell.sidebarWidth)
            lastSidebarWidth = shell.sidebarWidth
        }
        shell.onEdgeHover = { [weak self] show in self?.setFloatingSidebar(show) }

        installSwipeMonitor()
        installChildClickMonitor()
        installPageTopDragMonitor()
        installFloatingSidebar()
        observeStore()
        refresh()
        shell.onDevToolsFrame = { [weak self] rect in
            guard let self, let id = self.browsers.visibleTabID else { return }
            self.positionDevToolsWindow(rect, tab: id)
        }
        shell.onPaneFrames = { [weak self] frames in self?.positionPageWindows(frames) }
        shell.onAnimatePaneFrames = { [weak self] frames, d, timing in self?.animatePageWindows(to: frames, duration: d, timing: timing) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshMaterialActive(); self?.sidebarUI.appActive = true }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshMaterialActive(); self?.sidebarUI.appActive = false }
        }
        shell.activeAppearance.onChange = { [weak self] in self?.refreshMaterialActive() }
        // Any window: key and main move between this window, its page windows and other windows.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didResignMainNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMaterialActive() }
            }
        }
    }

    /// The sidebar's material follows this window's active state, as AppKit's does for Arc's sidebar
    /// (SidebarBackdrop.windowActive, GitHub #156). Going inactive waits one turn of the run loop: key
    /// moving between this window and one of its page windows resigns one before the other takes it,
    /// and the sidebar must not flash its flat fill in between.
    private func refreshMaterialActive() {
        if materialActiveNow() { shell.windowActive = true; return }
        guard shell.windowActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.materialActiveNow() else { return }
            self.shell.windowActive = false
        }
    }

    private func materialActiveNow() -> Bool {
        guard let window, !isTornDown else { return false }
        func holds(_ w: NSWindow?) -> Bool {
            var w = w
            while let x = w { if x === window { return true }; w = x.parent }
            return false
        }
        return SidebarBackdrop.windowActive(appActive: NSApp.isActive, miniaturized: window.isMiniaturized,
                                            holdsKeyOrMain: holds(NSApp.keyWindow) || holds(NSApp.mainWindow),
                                            activeAppearance: shell.activeAppearance.isActive ?? false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Wiring

    private func wireActions() {
        sidebarActions.titleBarDoubleClick = { [weak self] in (self?.window as? CraWindow)?.performTitleDoubleClickAction() }
        sidebarActions.openCommandBar = { [weak self] mode in self?.openCommandBar(mode) }
        sidebarActions.closeTab = { [weak self] id in self?.closeTab(id) }
        sidebarActions.moveBlankWindow = { [weak self] space in
            guard let self else { return }
            self.app.moveBlankWindow(self, toSpace: space)
        }
        sidebarActions.tearOffTab = { [weak self] id, point in
            guard let self else { return }
            self.app.tearOffTab(id, at: point, from: self)
        }
        sidebarActions.goBack = { [weak self] in self?.currentBrowser?.goBack() }
        sidebarActions.goForward = { [weak self] in self?.currentBrowser?.goForward() }
        sidebarActions.reload = { [weak self] in
            guard let b = self?.currentBrowser else { return }
            b.isLoading ? b.stopLoading() : b.reload()
        }
        sidebarActions.editSpace = { [weak self] s in self?.showSpaceEditor(space: s) }
        sidebarActions.changeSpaceIcon = { [weak self] s, anchor in self?.showSpaceIconPicker(space: s, anchor: anchor) }
        sidebarActions.editSpaceTheme = { [weak self] s in self?.showSpaceStyleEditor(space: s) }
        sidebarActions.editSpaceThemeBeside = { [weak self] s, card in self?.showSpaceStyleEditor(space: s, beside: card) }
        sidebarActions.newProfile = { [weak self] id in self?.showNewProfileDialog(forSpace: id) }
        sidebarActions.manageSpaces = { [weak self] in self?.showManageSpaces() }
        sidebarActions.deleteSpace = { [weak self] s in self?.app.confirmDeleteSpace(s, in: self?.window) }
        sidebarActions.toggleSidebar = { [weak self] in self?.toggleSidebar() }
        sidebarActions.toggleLibrary = { [weak self] in self?.toggleLibrary() }
        sidebarActions.showLibrary = { [weak self] page in self?.showLibrary(page) }
        sidebarActions.closeLibrary = { [weak self] in self?.closeLibrary() }
        sidebarActions.restoreArchived = { [weak self] id in
            guard let self else { return }
            _ = self.store.restoreArchived(id)
            self.closeLibrary()
        }
        sidebarActions.resetPinnedTab = { [weak self] id in self?.resetPinnedTab(id) }
        sidebarActions.separatePinnedTab = { [weak self] id in self?.separatePinnedTab(id) }
        sidebarActions.editPinnedURL = { [weak self] id in self?.editPinnedURL(id) }
        sidebarActions.showToast = { [weak self] text in self?.showToast(text) }
        sidebarActions.openURL = { [weak self] url in
            guard let self else { return }
            self.store.createTab(url: url, window: self.windowID)
        }
        sidebarActions.loadTyped = { [weak self] typed in
            guard let self else { return }
            let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            self.loadInSelectedTab(SuggestionEngine.looksLikeURL(t) ? SuggestionEngine.urlFromInput(t) : self.commandBar.engine.searchURL(t))
        }
        sidebarActions.openTyped = { [weak self] typed in
            guard let self else { return }
            let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            self.store.createTab(url: SuggestionEngine.looksLikeURL(t) ? SuggestionEngine.urlFromInput(t) : self.commandBar.engine.searchURL(t), window: self.windowID)
        }
        sidebarActions.focusPane = { [weak self] id in
            guard let self, self.selectedTabID != id else { return }
            self.store.selectTab(id, window: windowID)
        }
        sidebarActions.closePane = { [weak self] id in self?.closeSplitPane(id) }
        sidebarActions.separatePane = { [weak self] id in self?.separatePane(id) }
        sidebarActions.paneNavigate = { [weak self] id, what in
            guard let self else { return }
            if self.selectedTabID != id { self.store.selectTab(id, window: windowID) }
            guard let b = self.browsers.runtime(for: id)?.browser else { return }
            switch what {
            case "goBack": b.goBack()
            case "goForward": b.goForward()
            case "reload": b.isLoading ? b.stopLoading() : b.reload()
            default: break
            }
        }
        sidebarActions.editPaneURL = { [weak self] id in
            guard let self else { return }
            if self.selectedTabID != id { self.store.selectTab(id, window: windowID) }
            self.openCommandBar(.editURL)
        }
        // Toolbar buttons are ~34 pt wide and the click lands near the middle: the popup's
        // right edge lines up with the button's (Chrome anchors popups that way).
        sidebarActions.runExtension = { [weak self] id in
            guard let self else { return }
            let button = Self.extensionButtonUnderPointer()
            // A pin in the sidebar's grid (toolbar hidden) hangs its popup under its own button; one in
            // a bar above the page (the toolbar, a split pane's, the developer bar) under that bar.
            let inBar = button.map { self.isInPaneBar($0) } ?? false
            self.runExtensionAction(id, buttonRightX: button?.maxX ?? NSEvent.mouseLocation.x + 17,
                                    buttonBottomY: inBar ? self.toolbarBottomOnScreen()?.y
                                        : self.store.settings.showToolbar == false ? button?.minY : nil)
        }
        sidebarActions.showExtensionsMenu = { [weak self] in self?.showToolbarExtensionsMenu() }
        sidebarActions.paneRunExtension = { [weak self] pane, id in
            guard let self else { return }
            self.focusPaneNow(pane)
            self.sidebarActions.runExtension(id)
        }
        sidebarActions.paneExtensionsMenu = { [weak self] pane in
            self?.focusPaneNow(pane)
            self?.showToolbarExtensionsMenu()
        }
        // Popups from an extension's shortcut or chrome.action.openPopup() hang where the
        // menu bar's do: under the extension's toolbar button, else at the card's right end.
        // Arc puts every popup in one place, whatever opened it.
        ExtensionActions.shared.watchPopups { [weak app] id in
            guard let main = app?.main, let window = main.window, let key = NSApp.keyWindow, key === window || key.parent === window else { return nil }
            return main.extensionPopupAnchor(id)
        }
        ExtensionActions.shared.watchActions { [weak app] in
            app?.mainWindows.flatMap { $0.browsers.runtimes.values.map { (tab: $0.tabID, browser: $0.browser) } } ?? []
        }
        ExtensionActions.shared.sidePanelHandler = { [weak app] request, tab in
            guard let app else { return }
            ExtensionSidePanelController.route(request, tab: tab, app: app)
        }
        browsers.nowPlaying = sidebarUI.nowPlaying
        sidebarUI.nowPlaying.perform = { [weak self] id, action in
            guard let self else { return }
            switch action {
            case .show:
                store.selectTab(id, window: windowID)
                window?.makeKeyAndOrderFront(nil)
            case .toggleMute:
                let muted = !(store.item(id)?.tab?.muted ?? false)
                store.setMuted(id, muted)
                app.runtime(for: id)?.browser.setAudioMuted(muted)
            default:
                browsers.performNowPlaying(id, action)
            }
        }
        sidebarActions.performAction = { [weak self] id in
            if id.hasPrefix("openInSplit:"), let uuid = UUID(uuidString: String(id.dropFirst(12))) {
                self?.openTabInSplit(uuid)
            } else if id.hasPrefix("muteTab:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                let muted = self?.store.item(uuid)?.tab?.muted ?? false
                self?.app.runtime(for: uuid)?.browser.setAudioMuted(muted)
            } else {
                self?.app.perform(id)
            }
        }
        commandBar.onCommit = { [weak self] s, typed, mode in self?.handleCommit(s, typed: typed, mode: mode) }
        commandBar.onOpenInBackground = { [weak self] s, typed in self?.openInBackground(s, typed: typed) ?? false }
        commandBar.onOpenInSplit = { [weak self] s, typed in self?.openInSplit(s, typed: typed) ?? false }
        commandBar.onClose = { [weak self] in self?.hideCommandPanel() }
        commandBar.spaceName = { [weak self] id in self?.store.space(id)?.title ?? "" }
    }

    // MARK: Observation

    private func observeStore() {
        guard !isTornDown else { return }
        withObservationTracking {
            _ = store.revision
            _ = store.prefs
            _ = store.settings
            _ = store.spaces
            _ = SystemAppearance.shared.isDark
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeStore()
            }
        }
    }

    func refresh() {
        guard !isTornDown, !isPutAway else { return }
        let space = focusedSpace
        let palette = space.theme.palette
        // Its extensions belong to the space's profile.
        if siteControlCenter.isShown, siteControlCenterSpaceID != space.id { siteControlCenter.close() }
        // refresh runs on every store change (each page title, each window move). A new root
        // view rebuilds its whole SwiftUI tree, and a new window appearance or background redraws
        // every view, so all of these follow the theme only when it changes. What the root
        // views show beyond the palette they observe themselves.
        if shownTheme != space.theme.shown {
            shownTheme = space.theme.shown
            // A swipe in the floating sidebar changes space under it (issue #12).
            floatingSidebar?.refreshBackdrop()
            shell.placeholderHost.wantsLayer = true
            shell.placeholderHost.layer?.backgroundColor = (palette.isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)).cgColor
            shell.isDarkTheme = palette.isDark
            // The space's light or dark goes to the window's content (sidebar, toolbar, pages'
            // frame), not to the window: AppKit hands a window's appearance to every menu, sheet,
            // alert and popover it presents, and those follow macOS as Arc's do, whatever the
            // space colour (#171).
            shell.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            // The command bar follows macOS (#187); only its highlight is the space's, also when
            // the space changes under an open bar.
            commandBar.highlight = palette.commandHighlight
            // Vibrant themes see through to the desktop like Arc; others are opaque.
            shell.vibrancy.isHidden = !palette.vibrant
            shell.vibrancyLift.isHidden = !palette.vibrant
            shell.setTheme(vibrantDark: palette.isDark, vibrantLight: palette.vibrant && !palette.isDark, solid: palette.solid)
            window?.isOpaque = !palette.vibrant
            window?.backgroundColor = palette.vibrant ? .clear : NSColor(palette.gradientColors.first ?? .gray)
        }

        let ring = NSColor(space.theme.shadedDark)
        if shell.focusRingColor != ring { shell.focusRingColor = ring }
        browsers.pruneMissingTabs()
        let selected = selectedTabID
        // Split view: the selected tab's split decides which panes are on screen.
        let panes = store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID)
        let split = selected.flatMap { store.splitContaining($0) }
        let factors = SplitPaneLayout.normalizedFactors(ids: panes, stored: split?.split?.widthFactors ?? [:])
        let empty = Set(panes.filter { store.item($0)?.isEmptyTab == true })
        // A lone page's bar: the toolbar, or the developer bar on a Developer Mode site (#185).
        let loneBar = store.settings.showsBar(above: panes.count == 1 ? store.item(panes[0])?.tab?.url : nil)
        if shell.showToolbar != loneBar { shell.showToolbar = loneBar }
        if shell.edgeToEdge != store.settings.edgeToEdgeContent { shell.edgeToEdge = store.settings.edgeToEdgeContent }
        // Before setPanes: a pane whose page is not live yet gets its bar colour now, not white.
        let bars = toolbarColors(panes: panes)
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        // The same for the bar itself: retarget builds it at once, before browsers.show makes the
        // pane's page visible, so a live page's colour and buttons must already be there. Without
        // them a switch between loaded tabs drew one frame with Back greyed out, on a white bar when
        // the tab had no saved colour (incognito, or any tab before 0.1.26) (#84).
        syncNavStates(panes)
        shell.setPanes(panes, factors: factors, orientation: split?.split?.orientation ?? .horizontal, focused: selected, empty: empty, animated: true)
        // A page is on screen in one window at a time. Arc keeps the tab selected in every window
        // that has it open: the window in use holds the page, the others show a blurred snapshot
        // until they are used again (windowDidBecomeKey takes the page back).
        let elsewhere = Set(panes.filter(showsElsewhere))
        let live = panes.filter { !elsewhere.contains($0) }
        let liveFocus = selected.flatMap { elsewhere.contains($0) ? nil : $0 }
        for c in shell.paneCards {
            c.showsElsewhere = elsewhere.contains(c.tabID)
            c.elsewhereSnapshot = c.showsElsewhere ? app.runtime(for: c.tabID)?.snapshot : nil
        }
        sidebarUI.splitPaneIDs = panes.count > 1 ? panes : []
        if live != browsers.visibleTabIDs || liveFocus != browsers.visibleTabID
            || live.contains(where: { browsers.runtime(for: $0) == nil && store.item($0)?.isEmptyTab == false }) {
            browsers.show(live, focused: liveFocus, focus: !commandBar.isOpen)
        }
        shell.layoutContentChildren()
        syncPeeks(onScreen: panes)
        syncRingPanel()
        syncSidebarUI()
        window?.title = selectedTab?.displayTitle ?? space.title

        if sidebarVisible != lastSidebarVisible {
            lastSidebarVisible = sidebarVisible
            (window as? CraWindow)?.trafficLightsHidden = !lastSidebarVisible
            // Anchoring while the sidebar floats: bring it home first so it slides from there.
            if lastSidebarVisible { floatingSidebar?.prepareForAnchoring() }
            shell.animateSidebar(visible: lastSidebarVisible, floating: false, fullscreen: shell.contentFullscreen, width: shell.sidebarWidth)
        }
        if CGFloat(store.prefs.sidebarWidth) != lastSidebarWidth {
            lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
            shell.sidebarWidth = sidebarUI.libraryPage.map { libraryWidth($0) } ?? lastSidebarWidth
        }
    }

    /// The browser window the user is in (AppDelegate follows the key window).
    private var isActiveWindow: Bool { store.activeWindowID == windowID }

    /// `cra://debug?dragEnd`: a drag of a row of this window's list let go at a screen point
    /// with nothing taking it, as a drag out of the sidebar ends (#219).
    func testDragEnded(_ id: UUID, at screenPoint: NSPoint) {
        func list(in v: NSView) -> SpaceListView? {
            if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
            return v.subviews.lazy.compactMap { list(in: $0) }.first
        }
        guard let l = window?.contentView.flatMap(list(in:)) else { CraLog.note("dragEnd: no list"); return }
        l.dragEnded(id, at: screenPoint, operation: [])
    }

    /// The tab's page belongs to another window that has it open: the window in use takes it,
    /// others keep it where it is. Windows restored at launch (none has the page yet, and
    /// `app.mainWindows` is still empty) leave it to the window in use, else the first one.
    private func showsElsewhere(_ id: UUID) -> Bool {
        if isActiveWindow || browsers.runtime(for: id) != nil { return false }
        if app.mainWindows.contains(where: { $0 !== self && $0.browsers.runtime(for: id) != nil }) { return true }
        let windows = store.prefs.windows
        let showing = windows.filter { store.visiblePaneTabIDs(in: store.focusedSpaceID(window: $0.id), window: $0.id).contains(id) }
        if showing.contains(where: { $0.id == store.activeWindowID }) { return true }
        return showing.first.map { $0.id != windowID } ?? false
    }

    /// Runs on every page event (progress, title, favicon). An @Observable property notifies
    /// on every assignment, equal or not, and every sidebar row reads some of these, so each
    /// one is assigned only when it changed.
    private func syncSidebarUI() {
        let loaded = Set(app.mainWindows.flatMap { $0.browsers.runtimes.keys })
        if loaded != sidebarUI.loadedTabIDs { sidebarUI.loadedTabIDs = loaded }
        let capturing = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isCapturingMedia }.keys })
        if capturing != sidebarUI.capturingTabIDs { sidebarUI.capturingTabIDs = capturing }
        let audible = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isAudible }.keys })
        if audible != sidebarUI.audibleTabIDs { sidebarUI.audibleTabIDs = audible }
        let b = browsers.visibleRuntime?.browser
        if sidebarUI.canGoBack != (b?.canGoBack ?? false) { sidebarUI.canGoBack = b?.canGoBack ?? false }
        if sidebarUI.canGoForward != (b?.canGoForward ?? false) { sidebarUI.canGoForward = b?.canGoForward ?? false }
        if sidebarUI.isLoading != (b?.isLoading ?? false) { sidebarUI.isLoading = b?.isLoading ?? false }
        shell.setLoading(LoadingIndicator.Phase(isLoading: b?.isLoading ?? false, committed: b?.hasCommittedLoad ?? false),
                         tab: browsers.visibleTabID)
        let themeColor = browsers.visibleRuntime?.themeColor ?? ""
        if sidebarUI.pageThemeColor != themeColor { sidebarUI.pageThemeColor = themeColor }
        for (id, rt) in browsers.runtimes where sidebarUI.progress[id] != rt.progress { sidebarUI.progress[id] = rt.progress }
        syncNavStates(browsers.visibleTabIDs)
    }

    /// Each pane's toolbar state, for the panes whose page is live in this window.
    private func syncNavStates(_ ids: [UUID]) {
        var nav: [UUID: TabNavState] = [:]
        for id in ids {
            guard let rt = browsers.runtime(for: id) else { continue }
            nav[id] = TabNavState(canGoBack: rt.browser.canGoBack, canGoForward: rt.browser.canGoForward, isLoading: rt.browser.isLoading,
                                  themeColor: rt.themeColor, protectedMedia: PageEngines.protectedMediaService(of: rt.browser))
        }
        if nav != sidebarUI.navStates { sidebarUI.navStates = nav }
        if let id = browsers.visibleTabID, let service = nav[id]?.protectedMedia { tellAboutProtectedMedia(service) }
    }

    // MARK: Split view

    /// Arc's "Add Split View" (⌃⇧=): a new empty pane opens after the focused
    /// one, with the command bar ready to fill it.
    func addSplitPane() {
        guard let current = selectedTabID else { openCommandBar(.newTab); return }
        if store.paneTabIDs(for: current).count >= 4 {
            showToast("Cannot Add New Pane")
            return
        }
        guard store.addEmptyPane(nextTo: current) != nil else { return }
        refresh()
        openCommandBar(.editURL)
    }

    /// Arc's "Open in Split View" on a sidebar tab: that tab joins the open one in a split, as the
    /// command bar's split row does with a tab it lists.
    func openTabInSplit(_ id: UUID) {
        guard let current = selectedTabID, current != id, store.item(current)?.isEmptyTab == false else { return }
        if store.paneTabIDs(for: current).contains(id) { store.selectTab(id, window: windowID); return }
        guard store.paneTabIDs(for: current).count < 4 else { showToast("Cannot Add New Pane"); return }
        let split = store.splitContaining(current).map { sp in store.addToSplit(sp.id, tabID: id, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [current, id], at: current)
        store.selectTab(split.flatMap { store.paneID(for: id, in: $0) } ?? id, window: windowID)
    }

    /// Arc's "Close this Split Pane" (⌃⇧-): the pane's tab closes like any tab;
    /// the split keeps the other panes. A pinned split's pane leaves it (closing it
    /// would only unload the whole split).
    func closeSplitPane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { closeTab(id); return }
        if store.item(id)?.isEmptyTab == true || store.isPinned(id) {
            store.archiveTab(id, reason: .manual)
        } else {
            closeTab(id)
        }
    }

    /// Arc's "Separate Page from Split View": the pane becomes a normal tab again.
    func separatePane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { return }
        store.separateFromSplit(id)
        store.selectTab(id, window: windowID)
    }

    func cycleSplitPane(_ delta: Int) {
        guard let current = selectedTabID else { return }
        let panes = store.paneTabIDs(for: current)
        guard panes.count > 1, let idx = panes.firstIndex(of: current) else { return }
        let n = panes.count
        store.selectTab(panes[((idx + delta) % n + n) % n])
    }

    // MARK: BrowserManagerDelegate

    func browserManagerDidUpdate(_ tabID: UUID) {
        syncSidebarUI()
        let colors = browsers.runtimes.compactMapValues { $0.backgroundColor.isEmpty ? nil : $0.backgroundColor }
        if colors != shell.pageColors { shell.pageColors = colors }
        let bars = toolbarColors(panes: shell.paneIDs)
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        if tabID == browsers.visibleTabID { window?.title = store.item(tabID)?.displayTitle ?? "Cra" }
    }

    /// Each live page's and each pane's bar colour, by PaneToolbarView's rule (ToolbarColor):
    /// a pane shows before browsers.show creates its page, so it falls back to what the tab remembers.
    private func toolbarColors(panes: [UUID]) -> [UUID: String] {
        var bars: [UUID: String] = [:]
        for id in Set(browsers.runtimes.keys).union(panes) {
            bars[id] = ToolbarColor.hex(reported: browsers.runtime(for: id)?.themeColor, remembered: store.item(id)?.tab?.themeColor)
        }
        return bars
    }

    func browserManager(statusMessage: String) {
        overlay.status = statusMessage
        shell.statusVisible = !statusMessage.isEmpty
        shell.layoutContentChildren()
    }

    func browserManager(findMatches count: Int, activeMatch: Int) {
        guard overlay.findVisible else { return }
        if count >= 0 { overlay.findMatchCount = count }
        if activeMatch >= 0 { overlay.findActiveMatch = activeMatch }
    }

    func browserManager(download: CraDownloadInfo) {
        let name = (download.fullPath as NSString).lastPathComponent.isEmpty ? download.suggestedName : (download.fullPath as NSString).lastPathComponent
        if let tab = browsers.downloadSourceTab, let item = store.item(tab), let t = item.tab {
            TidyDownloadsService.shared.noteSource(download.identifier, title: item.displayTitle, url: t.url)
        }
        if windowDownloads.insert(download.identifier).inserted {
            ChromeDownloadAnimation.suppress()
            showDownloadInSidebar(download, name: name)
        }
        // Progress and failures show in the downloads list, as in Arc (it has no download toast).
        DownloadHistory.shared.report(id: download.identifier, name: name, path: download.fullPath, received: download.receivedBytes,
                                      total: download.totalBytes, percent: download.percent, complete: download.state == .complete,
                                      cancelled: download.state == .cancelled, failed: download.state == .interrupted)
        updateRecentDownload(download)
        if download.state == .complete, !download.fullPath.isEmpty, finishedDownloads.insert(download.identifier).inserted {
            DownloadHistory.shared.add(path: download.fullPath, profile: browsers.downloadSourceTab.map(store.profileDirectoryName(item:)) ?? profileDirectoryName)
            // The address's scheme only, never the file: scenarios wait for this line.
            CraLog.note("Download finished from a \(URL(string: download.url)?.scheme ?? "unknown"): address")
            let id = download.identifier
            TidyDownloadsService.shared.finished(id, path: download.fullPath, downloadURL: download.url, window: windowID, store: store) { [weak self] path in
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id else { return }
                recent.path = path
                self.sidebarUI.recentDownload = recent
            }
        }
        if download.state == .inProgress, downloadWatchdog == nil {
            downloadWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkStalledDownloads() }
            }
        }
    }

    private var downloadWatchdog: Timer?

    /// Chromium stops reporting a download once the tab that started it is gone (the
    /// download carries on, or ends, silently), which left its row "in progress" for
    /// good. A row that hasn't heard from Chromium for a while reads the file instead:
    /// gone means it ended, the full size with no .crdownload beside it means it's done.
    private func checkStalledDownloads() {
        let inProgress = DownloadHistory.shared.live.filter { $0.running && windowDownloads.contains($0.id) }
        guard !inProgress.isEmpty else {
            downloadWatchdog?.invalidate()
            downloadWatchdog = nil
            return
        }
        let fm = FileManager.default
        for t in inProgress where !t.path.isEmpty && Date().timeIntervalSince(t.updated) > 5 {
            guard !fm.fileExists(atPath: t.path + ".crdownload") else { continue }
            let size = (try? fm.attributesOfItem(atPath: t.path))?[.size] as? Int64
            let state: CraDownloadState
            if size == nil { state = .cancelled }
            else if let size, t.total > 0, size >= t.total { state = .complete }
            else { continue }
            let info = CraDownloadInfo()
            info.identifier = t.id
            info.fullPath = t.path
            info.suggestedName = t.name
            info.totalBytes = t.total
            info.receivedBytes = size ?? 0
            info.percent = state == .complete ? 100 : t.percent
            info.state = state
            browserManager(download: info)
        }
    }

    /// Arc's download animation: the file drops onto the Library button and a download
    /// glyph is thrown at it from the pointer (DownloadFlight). Measured on Arc 1.170: the
    /// file stays 30 s after the glyph lands, then fades out over 0.15 s.
    private func showDownloadInSidebar(_ download: CraDownloadInfo, name: String) {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        sidebarUI.recentDownload = RecentDownload(id: download.identifier, path: download.fullPath,
                                                  image: NSWorkspace.shared.icon(for: type))
        var flight: TimeInterval = 0
        if let window, window.isVisible, let anchor = sidebarUI.libraryAnchor, let host = anchor.window,
           host.isVisible, !anchor.isHiddenOrHasHiddenAncestor {
            // Aim at the bin's centre (screen coordinates are y-up, the offset is SwiftUI's y-down).
            let glyph = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let bin = NSPoint(x: glyph.midX + LibraryButtonView.binOffset.width, y: glyph.midY - LibraryButtonView.binOffset.height)
            flight = DownloadFlight.launch(over: window, from: NSEvent.mouseLocation, to: bin)
        }
        let id = download.identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + flight + 30) { [weak self] in
            guard let self, self.sidebarUI.recentDownload?.id == id else { return }
            withAnimation(.easeOut(duration: 0.15)) { self.sidebarUI.recentDownload = nil }
        }
    }

    private var finishedDownloads: Set<UInt32> = []
    /// Downloads this window's pages started (its flight and stall checks).
    private var windowDownloads: Set<UInt32> = []

    /// Keeps the Library button's file current: its path once known, its Quick Look
    /// thumbnail once the download is complete (Arc showed a text file's page).
    private func updateRecentDownload(_ download: CraDownloadInfo) {
        // Only the first complete update counts; Chromium sends more after it.
        guard var recent = sidebarUI.recentDownload, recent.id == download.identifier,
              !finishedDownloads.contains(download.identifier) else { return }
        if !download.fullPath.isEmpty, recent.path != download.fullPath {
            recent.path = download.fullPath
            sidebarUI.recentDownload = recent
        }
        guard download.state == .complete, !download.fullPath.isEmpty else { return }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: download.fullPath), size: CGSize(width: 32, height: 32),
                                                   scale: window?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let id = download.identifier
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            DispatchQueue.main.async {
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id else { return }
                // The first progress update can lack a filename. Use the finished file's Finder
                // icon if Quick Look has no preview, including after Tidy Downloads renamed it.
                recent.image = image ?? NSWorkspace.shared.icon(forFile: recent.path)
                self.sidebarUI.recentDownload = recent
            }
        }
    }

    func browserManager(fullscreen: Bool, tabID: UUID) {
        guard let window else { return }
        shell.contentFullscreen = fullscreen
        contentFullscreenTab = fullscreen ? tabID : nil
        if fullscreen, !window.styleMask.contains(.fullScreen) {
            enteredFullscreenForContent = true
            window.toggleFullScreen(nil)
        } else if !fullscreen, enteredFullscreenForContent, window.styleMask.contains(.fullScreen) {
            enteredFullscreenForContent = false
            window.toggleFullScreen(nil)
        }
    }

    /// CEF owns the DevTools window (embedding in our NSView trips a Chromium CHECK on macOS).
    /// DevTools docks inside the content card (Chrome's default), to the right of the page.
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView? {
        shell.devToolsVisible = true
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
        return shell.devToolsHost
    }

    // MARK: Chrome-style page windows

    /// Page-sized and always click-through: it covers the whole page, so if it ever took
    /// mouse events every click on the page would land in it. Anything clickable over the
    /// page gets its own panel just its size (the find bar).
    private var overlayPanel: NSPanel?
    private var findPanel: FindBarPanel?
    /// The focused pane's ring while its page is in a window of its own (DevTools docked in it):
    /// that window covers the card, and the card's ring with it (GitHub #178).
    private var ringPanel: NSPanel?
    /// Page area per visible tab, window coordinates (one entry per pane).
    private var lastPaneFrames: [UUID: NSRect] = [:]
    /// While a divider is dragged the page windows follow every mouse move.
    private var pageWindowsFollowLive = false

    private func ensureOverlayPanel() {
        guard overlayPanel == nil, let window else { return }
        func clearPanel() -> NSPanel {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
            return panel
        }
        let panel = clearPanel()
        panel.ignoresMouseEvents = true
        let find = FindBarPanel()
        shell.moveOverlays(to: panel.contentView!, findBar: find)
        window.addChildWindow(panel, ordered: .above)
        overlayPanel = panel
        findPanel = find
        if overlay.findVisible { window.addChildWindow(find, ordered: .above) }
    }

    /// Shows the focused card's ring above its page window while that page is not in the card.
    private func syncRingPanel() {
        guard let window else { return }
        let card = shell.focusedCard
        let tab = browsers.visibleTabID
        let host = tab.flatMap { browsers.runtime(for: $0)?.hostWindow }
        let pageInOwnWindow = host.map { $0.isVisible && !EmbeddedPages.isHost($0) } ?? false
        let devTools = tab.flatMap { browsers.visibleDevToolsWindows[$0] }?.isVisible ?? false
        guard let card, let color = card.focusRing, card.window === window, pageInOwnWindow || devTools else {
            if let panel = ringPanel, panel.parent != nil { window.removeChildWindow(panel); panel.orderOut(nil) }
            return
        }
        let panel = ringPanel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.contentView = FocusRingView(frame: .zero)
            ringPanel = p
            return p
        }()
        let frame = window.convertToScreen(card.convert(card.bounds, to: nil))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if let ring = panel.contentView {
            ring.layer?.borderColor = color.cgColor
            ring.layer?.cornerRadius = card.cornerRadius
        }
        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
            raiseOverlayPanels()
        }
    }

    /// Overlay panel above the page windows (and the floating sidebar), the find bar above it.
    private func raiseOverlayPanels() {
        guard let window else { return }
        var panels: [NSPanel?] = [overlayPanel]
        if let ringPanel, ringPanel.parent != nil { panels.insert(ringPanel, at: 0) }
        if overlay.findVisible { panels.append(findPanel) }
        // A Peek (and its dimming) stays above everything else in the window.
        let wanted = panels.compactMap { $0 } + peeks.flatMap(\.peekWindows)
        // Already the last children, in order, and showing: re-adding each one rebuilt the
        // window's ordering group, a window server round trip, on every tab switch.
        let children = window.childWindows ?? []
        if children.suffix(wanted.count).elementsEqual(wanted, by: ===), wanted.allSatisfy(\.isVisible) { return }
        for panel in wanted {
            window.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    /// The find bar's screen frame: the top trailing corner of the focused page.
    private func findPanelFrame(page: NSRect) -> NSRect {
        let size = CraMetrics.findBarSize, inset = CraMetrics.findBarInset
        return NSRect(x: page.maxX - size.width - inset, y: page.maxY - size.height - inset, width: size.width, height: size.height)
    }

    /// Attaches the visible tabs' Chrome windows over their pane areas, hides the others.
    func browserManagerPageWindowsChanged(focus: Bool) {
        guard let window else { return }
        // A focus still waiting for its page to embed is stale once pages change without one.
        if !focus { embedFocusTab = nil }
        ensureOverlayPanel()
        let visibleIDs = Set(browsers.visibleTabIDs)
        let focused = browsers.visibleRuntime?.hostWindow
        for (id, rt) in browsers.runtimes {
            guard let w = rt.hostWindow else { continue }
            // Chromium never learns that an ordered-out window is hidden (it checks for a hidden
            // NSView ancestor), so hidden tabs stayed "visible": background tabs autoplayed video
            // and ran at full speed. A hidden content view makes the tab hidden like Chrome's
            // background tabs: media waits until the tab is first shown.
            if !visibleIDs.contains(id) {
                w.contentView?.isHidden = true
                // An embedded page leaves the window with its card, so Chromium sees it hidden.
                if EmbeddedPages.isHost(w), let views = EmbeddedPages.pageViews(of: w) {
                    for v in views where v.superview !== w.contentView { v.removeFromSuperview() }
                }
                if w.isVisible {
                    w.orderOut(nil)
                    // A new background page starts in CEF's 10 pt window. Let it lay out at
                    // the pane size before autofocus can scroll its player off the top.
                    let pane = shell.webContainer
                    if w.parent == nil, !pane.bounds.isEmpty {
                        w.setFrame(window.convertToScreen(pane.convert(pane.bounds, to: nil)), display: false)
                    }
                }
                continue
            }
            if w.parent !== window {
                // Borderless: a titled window gets macOS's rounded corners on all four sides,
                // which shows under the toolbar and where the page meets DevTools.
                w.styleMask.remove([.titled, .resizable])
                w.styleMask.insert(.fullSizeContentView)
                ChromiumWindowCorners.setSquare(true, for: w)
                ChromiumChildHover.setDocked(true, for: w)
                ChromiumChildFullscreen.attach(w)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovable = false
                w.hasShadow = false
                w.isOpaque = false
                w.backgroundColor = .clear
                if let cv = w.contentView {
                    cv.wantsLayer = true
                    cv.layer?.cornerRadius = CraMetrics.contentCornerRadius
                    cv.layer?.cornerCurve = .continuous
                    cv.layer?.maskedCorners = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                    cv.layer?.masksToBounds = true
                }
                window.addChildWindow(w, ordered: .above)
            }
            // Hidden pages are not kept in step with the panes, so size this one before it shows.
            positionPageWindows(lastPaneFrames)
            w.contentView?.isHidden = false
            // Shown while drawing for releaseHiddenFrames: opaque and clickable again now.
            if releasingFrames.remove(id) != nil {
                w.alphaValue = 1
                w.ignoresMouseEvents = false
            }
            embedPage(id, from: w)
            // Ordering a window that is already showing is a window server round trip too.
            if !w.isVisible { w.orderFront(nil) }
            if focus, w === focused, EmbeddedPages.isEnabled, browsers.visibleDevToolsWindow == nil {
                // Focus goes to the page inside this window; one not embedded yet takes it when it is.
                embedFocusTab = id
                focusEmbeddedPage(id)
            } else if focus, w === focused {
                w.makeKey()
                devToolsLog("page win \(w.windowNumber) makeKey -> isKey=\(w.isKeyWindow) canBecomeKey=\(w.canBecomeKey) style \(w.styleMask.rawValue)")
            }
        }
        releaseUnfocusedEmbeddedPage()
        syncRingPanel()
        if browsers.visibleDevToolsWindows.values.contains(where: { $0.parent === window }) {
            raisePageWindows()
        } else {
            raiseOverlayPanels()
        }
    }

    /// Page windows drawing once, hidden, so their last frame lets go of an evicted page (#195).
    private var releasingFrames: Set<UUID> = []

    /// A hidden tab's page window is ordered out with its compositor suspended, and its last frame
    /// kept the page's surface, and the page's tiles in the GPU process (~15 MB a tab), alive after
    /// Chromium evicted it: every tab ever shown kept them. Chrome detaches a background tab from its
    /// one window instead. Ordered in for a moment, transparent and below this window, the page
    /// window draws a frame without the page and Chromium frees it (HiddenFrameRelease).
    func releaseHiddenFrames(now: Date) {
        let visible = Set(browsers.visibleTabIDs)
        let hidden = browsers.runtimes.values.compactMap { rt -> HiddenFrameRelease.Tab? in
            guard let at = rt.hiddenAt, rt.hostWindow != nil, !visible.contains(rt.tabID) else { return nil }
            return .init(id: rt.tabID, hiddenAt: at, releasedFor: rt.hiddenFrameReleasedFor)
        }
        guard let window else { return }
        for id in HiddenFrameRelease.due(hidden, visible: visible.count, now: now) {
            guard let rt = browsers.runtime(for: id), let w = rt.hostWindow, !w.isVisible, w.parent == nil,
                  !releasingFrames.contains(id) else { continue }
            rt.hiddenFrameReleasedFor = rt.hiddenAt
            releasingFrames.insert(id)
            w.alphaValue = 0
            w.ignoresMouseEvents = true
            w.order(.below, relativeTo: window.windowNumber)
            // Two or three frames: the compositor unsuspends, paints and commits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak w] in
                guard let self, let w, self.releasingFrames.remove(id) != nil else { return }
                w.alphaValue = 1
                w.ignoresMouseEvents = false
                if !self.browsers.visibleTabIDs.contains(id), w.parent == nil { w.orderOut(nil) }
            }
        }
    }

    /// Moves the page's view from its Chrome window into its card (EmbeddedPages). With its
    /// DevTools open the page goes back: Chrome's docked frontend lays it out in its window.
    private func embedPage(_ id: UUID, from w: NSWindow) {
        guard EmbeddedPages.isEnabled else { return }
        guard let views = EmbeddedPages.pageViews(of: w) else { return }
        let target: NSView
        if browsers.devToolsViews[id]?.window != nil, let cv = w.contentView {
            EmbeddedPages.unmarkHost(w)
            target = cv
        } else if let card = shell.paneCards.first(where: { $0.tabID == id }) {
            EmbeddedPages.markHost(w)
            target = card.webArea
        } else {
            return
        }
        // Compositor first, the page's input view above it.
        if views.contains(where: { $0.superview !== target }) {
            for v in views { target.addSubview(v) }
        }
        let bounds = shell.paneCards.first { $0.webArea === target }?.frozenWebBounds ?? target.bounds
        EmbeddedPages.place(views, in: bounds)
        if embedFocusTab == id { focusEmbeddedPage(id) }
    }

    /// `cra://debug?pageInsets=1`: where the focused page's input view sits against the compositor
    /// that draws the page, after its card lays out again, and the insets Chromium gave it. While
    /// the debugger bar shows, both say the bar's height at the top (#241).
    func pageInsetsReadout() -> String {
        guard let host = browsers.visibleRuntime?.hostWindow, let views = EmbeddedPages.pageViews(of: host),
              let compositor = views.first, let page = views.last, let area = page.superview else { return "page view insets: no page" }
        pageInsetsReadouts += 1
        if let card = shell.paneCards.first(where: { $0.webArea === area }) {
            card.needsLayout = true
            card.layoutSubtreeIfNeeded()
        }
        let c = compositor.frame, p = page.frame
        let top = area.isFlipped ? p.minY - c.minY : c.maxY - p.maxY
        let bottom = area.isFlipped ? c.maxY - p.maxY : p.minY - c.minY
        let chromium = EmbeddedPages.chromiumInsets(of: page).map { "top=\(Int($0.top)) left=\(Int($0.left)) bottom=\(Int($0.bottom)) right=\(Int($0.right))" } ?? "none"
        // The compositor's area from the window's top left, where clickAt points go.
        let inWindow = area.convert(c, to: nil)
        let origin = "\(Int(inWindow.minX)),\(Int((window?.frame.height ?? 0) - inWindow.maxY))"
        return "page view insets \(pageInsetsReadouts): top=\(Int(top)) left=\(Int(p.minX - c.minX)) bottom=\(Int(bottom)) right=\(Int(c.maxX - p.maxX)); Chromium's \(chromium); page area at \(origin) \(Int(c.width))x\(Int(c.height))"
    }

    private var pageInsetsReadouts = 0

    /// `cra://debug?embedDump=1`: where every page view is, for EmbeddedPages work.
    func embeddedPagesDump() -> String {
        func tree(_ v: NSView, _ depth: Int) -> String {
            var s = String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) layer=\(v.layer.map { "\(type(of: $0)) \($0.bounds) hidden=\($0.isHidden) sub=\($0.sublayers?.count ?? 0)" } ?? "nil")\n"
            if depth < 4 { for sub in v.subviews { s += tree(sub, depth + 1) } }
            return s
        }
        var out = "embedded pages (enabled=\(EmbeddedPages.isEnabled)) key=\(window?.isKeyWindow ?? false) fr=\(String(describing: window?.firstResponder))\n"
        for c in shell.paneCards { out += "card \(c.tabID.uuidString.prefix(8)) \(c.frame)\n" + tree(c.webArea, 1) }
        for (id, rt) in browsers.runtimes {
            guard let w = rt.hostWindow else { continue }
            out += "host \(id.uuidString.prefix(8)) win \(w.windowNumber) alpha=\(w.alphaValue) visible=\(w.isVisible) host=\(EmbeddedPages.isHost(w)) frame \(w.frame)\n"
            if let cv = w.contentView { out += tree(cv, 1) }
        }
        return out
    }

    /// An embedded page stays this window's first responder after its pane loses focus (an empty
    /// split pane opened beside it). When the window became key again (the command bar closing)
    /// the page reported focus, which selects its pane, and the URL meant for the empty pane
    /// opened as a new tab. A page window never had that: it was a window of its own.
    private func releaseUnfocusedEmbeddedPage() {
        guard EmbeddedPages.isEnabled, let window, let responder = window.firstResponder as? NSView,
              NSStringFromClass(type(of: responder)) == "RenderWidgetHostViewCocoa" else { return }
        let focused = browsers.visibleTabID.flatMap { browsers.runtime(for: $0)?.hostWindow }.flatMap(EmbeddedPages.pageViews(of:)) ?? []
        // The extension side panel's page keeps the keys it has.
        let panel = sidePanel.isShowing ? sidePanel.embeddedViews : []
        if !(focused + panel).contains(where: { responder.isDescendant(of: $0) }) { window.makeFirstResponder(nil) }
    }

    /// The tab whose embedded page should take keyboard focus once it is in its card.
    private var embedFocusTab: UUID?

    private func focusEmbeddedPage(_ id: UUID) {
        guard let window, let host = browsers.runtime(for: id)?.hostWindow,
              let view = EmbeddedPages.pageViews(of: host)?.last, view.window === window else { return }
        embedFocusTab = nil
        // Never from a panel that has the keys (the command bar filling a split pane, the find bar).
        if let key = NSApp.keyWindow, key !== window, !EmbeddedPages.isHost(key), key.parent === window { return }
        window.makeKey()
        if let render = EmbeddedPages.renderView(in: view) { window.makeFirstResponder(render) }
    }

    /// Diagnostic log shared with the bridge: `defaults write dk.kildahl.cra devToolsLog -bool YES`.
    private static let devToolsLogEnabled = UserDefaults.standard.bool(forKey: "devToolsLog")
    private func devToolsLog(_ message: @autoclosure () -> String) {
        guard Self.devToolsLogEnabled else { return }
        let path = NSTemporaryDirectory() + "cra-devtools.log"
        let line = String(format: "%.3f shell: %@\n", Date().timeIntervalSince1970, message())
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// Every visible page window follows its pane. Hidden tabs are left where they are and
    /// sized when they show (browserManagerPageWindowsChanged): each resize makes Chromium lay
    /// the page out synchronously, ~5 ms a window, which once ran for every loaded tab on
    /// every sidebar toggle and every step of a window resize.
    private func positionPageWindows(_ frames: [UUID: NSRect]) {
        guard let window, !frames.isEmpty else { return }
        lastPaneFrames = frames
        let focusRect = (browsers.visibleTabID.flatMap { frames[$0] }) ?? frames.values.first!
        let focusPage = browsers.visibleTabID.map { pageRect(forBody: focusRect, tab: $0) } ?? focusRect
        let devTools = browsers.visibleDevToolsWindows
        let live = pageWindowsFollowLive || shell.devToolsFrontendDocked || !devTools.isEmpty
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow else { continue }
            let body = frames[id] ?? focusRect
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
            // Chrome's docked frontend spans its pane's body, under the page.
            if devTools[id] != nil, browsers.devToolsDockedState[id] ?? true { positionDevToolsWindow(body, tab: id) }
            if w.frame != target { w.setFrame(target, display: live) }
            updatePageCorners(w, page: page, body: body)
            // A switch can show the page before its card exists; the card is laid out by now.
            embedPage(id, from: w)
            if shell.devToolsFrontendDocked, w.isVisible {
                devToolsLog("page win \(w.windowNumber) '\(w.title)' tab \(id.uuidString.prefix(8)) visible=\(browsers.visibleTabIDs.contains(id)) body \(body) page \(page) style \(w.styleMask.rawValue) parent \(w.parent?.windowNumber ?? -1)")
            }
        }
        let pr: NSRect? = shell.devToolsFrontendDocked ? focusPage : nil
        if shell.frontendPageRect != pr { shell.frontendPageRect = pr }
        let focusOnScreen = window.convertToScreen(focusPage)
        if let panel = overlayPanel, panel.frame != focusOnScreen { panel.setFrame(focusOnScreen, display: true) }
        syncRingPanel()
        if let find = findPanel, find.frame != findPanelFrame(page: focusOnScreen) { find.setFrame(findPanelFrame(page: focusOnScreen), display: true) }
    }

    /// Pages follow their cards without Chromium laying them out on every frame (an animated
    /// window frame resized the page at each step, a synchronous layout each time, and the
    /// page trailed its card). Each page takes its final frame at once; one that grows is
    /// revealed from its old edges by a mask animated in step with the card. One that shrinks
    /// needs nothing: its card, painted in the page's colour, slides under the gap.
    private func animatePageWindows(to frames: [UUID: NSRect], duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard let window, !frames.isEmpty else { return }
        lastPaneFrames = frames
        let focusRect = (browsers.visibleTabID.flatMap { frames[$0] }) ?? frames.values.first!
        let focusPage = browsers.visibleTabID.map { pageRect(forBody: focusRect, tab: $0) } ?? focusRect
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow, let body = frames[id] else { continue }
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
            let from = w.frame
            CATransaction.begin()
            if from != target {
                w.setFrame(target, display: true)
                fillContentView(w)
            }
            updatePageCorners(w, page: page, body: body)
            if w.isVisible, !EmbeddedPages.isHost(w), let cv = w.contentView {
                revealPage(cv, from: from, to: target, duration: duration, timing: timing)
            }
            CATransaction.commit()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            for (id, dev) in browsers.visibleDevToolsWindows where dev.parent === window {
                guard browsers.runtime(for: id)?.hostWindow != nil, let body = frames[id] else { continue }
                dev.animator().setFrame(window.convertToScreen(body), display: true)
            }
            overlayPanel?.animator().setFrame(window.convertToScreen(focusPage), display: true)
            findPanel?.animator().setFrame(findPanelFrame(page: window.convertToScreen(focusPage)), display: true)
        }
    }

    /// Masks a page that just grew from `from` to `to` (screen rects) down to the part it
    /// covered before, then opens the mask to the full page over the card's animation.
    private func revealPage(_ view: NSView, from: NSRect, to: NSRect, duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard duration > 0, let layer = view.layer else { return }
        let shown = from.intersection(to)
        guard !shown.isEmpty, shown.width < to.width - 0.5 || shown.height < to.height - 0.5 else { return }
        let start = NSRect(x: shown.minX - to.minX, y: view.isFlipped ? to.maxY - shown.maxY : shown.minY - to.minY,
                           width: shown.width, height: shown.height)
        let end = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        // The moving edge is the card's edge, rounded like it.
        mask.cornerRadius = layer.cornerRadius
        mask.cornerCurve = .continuous
        mask.maskedCorners = layer.maskedCorners
        mask.frame = end
        layer.mask = mask
        CATransaction.setCompletionBlock { [weak layer, weak mask] in
            if let layer, let mask, layer.mask === mask { layer.mask = nil }
        }
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: NSRect(origin: .zero, size: start.size))
        bounds.toValue = NSValue(rect: NSRect(origin: .zero, size: end.size))
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: NSPoint(x: start.midX, y: start.midY))
        position.toValue = NSValue(point: NSPoint(x: end.midX, y: end.midY))
        let group = CAAnimationGroup()
        group.animations = [bounds, position]
        group.duration = duration
        group.timingFunction = timing
        mask.add(group, forKey: "reveal")
        CATransaction.commit()
    }

    /// Where a page goes inside its pane body: the whole body, or, with Chrome's docked
    /// frontend, the placeholder the frontend reported. The placeholder keeps its offsets
    /// from the body's edges while the body is still resizing, so the page follows at
    /// once instead of waiting for the frontend's next layout.
    private func pageRect(forBody body: NSRect, tab: UUID) -> NSRect {
        guard browsers.devToolsViews[tab] != nil, browsers.runtime(for: tab)?.hostWindow != nil,
              browsers.devToolsDockedState[tab] ?? true,
              let p = browsers.devToolsPlaceholders[tab] else { return body }
        let right = max(0, p.frontendSize.width - p.bounds.maxX)
        let bottom = max(0, p.frontendSize.height - p.bounds.maxY)
        let w = max(1, body.width - p.bounds.minX - right)
        let h = max(1, body.height - p.bounds.minY - bottom)
        let r = NSRect(x: body.minX + p.bounds.minX, y: body.minY + bottom, width: w, height: h).intersection(body)
        return r.isEmpty ? body : r
    }

    /// Only the page corners that are card corners get rounded (a page docked beside
    /// DevTools meets it with a straight edge, like Arc).
    private func updatePageCorners(_ w: NSWindow, page: NSRect, body: NSRect) {
        guard let cv = w.contentView, let layer = cv.layer else { return }
        fillContentView(w)
        // Chromium can restore its own style mask (fullscreen, display changes), which brings
        // back macOS's rounded window corners on all four sides: square the window again.
        if w.styleMask.contains(.titled) || w.styleMask.contains(.resizable) {
            w.styleMask.remove([.titled, .resizable])
            ChromiumWindowCorners.setSquare(true, for: w)
        }
        // Chromium's content view is flipped, so its layer's MinY edge is the top.
        let bottomLeft: CACornerMask = cv.isFlipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner
        let bottomRight: CACornerMask = cv.isFlipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner
        let topLeft: CACornerMask = cv.isFlipped ? .layerMinXMinYCorner : .layerMinXMaxYCorner
        let topRight: CACornerMask = cv.isFlipped ? .layerMaxXMinYCorner : .layerMaxXMaxYCorner
        // The whole mask, not only the corner set: a rebuilt layer would otherwise keep
        // whatever radius and clipping it came with.
        if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
        if !layer.masksToBounds { layer.masksToBounds = true }
        // Edge to edge the card is square, but a page window is not clipped by the main
        // window: where it meets the window's corners it takes their radius.
        if shell.edgeToEdge {
            roundAtWindowCorners(layer, rect: page, flipped: cv.isFlipped)
            return
        }
        let radius = shell.contentFullscreen ? 0 : CraMetrics.contentCornerRadius
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        var corners: CACornerMask = []
        // A fullscreen card is square.
        if !shell.contentFullscreen, abs(page.minY - body.minY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(bottomLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(bottomRight) }
        }
        // Without the toolbar the page's top edge is the card's top edge too.
        if !shell.contentFullscreen, !shell.panesShowBars, abs(page.maxY - body.maxY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(topLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(topRight) }
        }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    /// Edge to edge: a child window (page or DevTools) is not clipped by the main window, so
    /// the corners of `rect` (window coordinates) that sit on the window's corners take its radius.
    private func roundAtWindowCorners(_ layer: CALayer, rect: NSRect, flipped: Bool) {
        guard let window else { return }
        let radius = window.styleMask.contains(.fullScreen) || shell.contentFullscreen ? 0 : LittleWindow.cornerRadius(of: window)
        let w = shell.bounds
        var corners: CACornerMask = []
        if abs(rect.minY - w.minY) < 0.5 {
            if abs(rect.minX - w.minX) < 0.5 { corners.insert(flipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner) }
            if abs(rect.maxX - w.maxX) < 0.5 { corners.insert(flipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner) }
        }
        if abs(rect.maxY - w.maxY) < 0.5 {
            if abs(rect.minX - w.minX) < 0.5 { corners.insert(flipped ? .layerMinXMinYCorner : .layerMinXMaxYCorner) }
            if abs(rect.maxX - w.maxX) < 0.5 { corners.insert(flipped ? .layerMaxXMinYCorner : .layerMaxXMaxYCorner) }
        }
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    /// Chromium lays its frameless window's content view out below a 22 pt title bar
    /// that Cra hides, leaving a blank band over the page; make it fill the window.
    private func fillContentView(_ w: NSWindow) {
        guard let cv = w.contentView else { return }
        let full = NSRect(origin: .zero, size: w.frame.size)
        if cv.frame != full { cv.frame = full }
    }

    /// Shows the visible tabs' DevTools windows (each split pane keeps its own) and hides
    /// the other tabs'. Chrome-style pages get Chrome's dockable frontend (see CraCEF's
    /// DevToolsClient): its window spans the pane's body under the page, which is laid
    /// over the placeholder it reports. Alloy pages keep the shell's own split with CEF's
    /// window on the right, for the focused tab only.
    func browserManagerDevToolsChanged() {
        BoostEditorController.shared.devToolsChanged()
        guard let window else { return }
        let visible = browsers.visibleDevToolsWindow
        let shown = browsers.visibleDevToolsWindows
        for (_, view) in browsers.devToolsViews {
            if let w = view.window, !shown.values.contains(where: { $0 === w }) { w.orderOut(nil) }
        }
        let selfDock = visible != nil && browsers.visibleRuntime?.hostWindow != nil
        let docked = browsers.visibleTabID.flatMap { browsers.devToolsDockedState[$0] } ?? true
        devToolsLog("devToolsChanged visible=\(visible?.windowNumber ?? -1) selfDock=\(selfDock) docked=\(docked) visibleTabs=\(browsers.visibleTabIDs.map { $0.uuidString.prefix(8) }) overlay=\(overlayPanel?.windowNumber ?? -1)")
        // This runs on every tab switch; the shell is laid out again only when the dock changed.
        let devToolsVisible = visible != nil && (docked || !selfDock)
        if visible != nil || shell.devToolsFrontendDocked != selfDock || shell.devToolsVisible != devToolsVisible {
            shell.devToolsFrontendDocked = selfDock
            shell.devToolsVisible = devToolsVisible
            shell.needsLayout = true
            shell.layoutSubtreeIfNeeded()
        }
        if visible == nil, shell.frontendPageRect != nil { shell.frontendPageRect = nil }
        var attached = false
        for id in browsers.visibleTabIDs {
            guard let w = shown[id] else { continue }
            let chrome = browsers.runtime(for: id)?.hostWindow != nil
            if chrome, browsers.devToolsDockedState[id] == false {
                detachDevToolsWindow(w, tab: id)
                continue
            }
            attachDevToolsWindow(w, selfDock: chrome, tab: id)
            // Chrome's frontend spans its pane's body (positionPageWindows keeps it there);
            // Alloy's sits in the shell's dock.
            if !chrome { positionDevToolsWindow((shell.devToolsHost.superview ?? shell.contentContainer).convert(shell.devToolsHost.frame, to: nil), tab: id) }
            w.orderFront(nil)
            attached = true
        }
        if attached { raisePageWindows() }
        positionPageWindows(lastPaneFrames)
    }

    /// The docked frontend moved its placeholder (also streamed while its splitter is dragged).
    func browserManagerDevToolsPageBoundsChanged() {
        positionPageWindows(lastPaneFrames)
        if Self.devToolsLogEnabled, devToolsTreeDumps < 2 {
            devToolsTreeDumps += 1
            if let dev = browsers.visibleDevToolsWindow { devToolsLog("devtools win \(dev.windowNumber) style \(dev.styleMask.rawValue) close=\(buttonState(dev)) opaque=\(dev.isOpaque)\n" + viewTree(dev.contentView)) }
            if let page = browsers.visibleRuntime?.hostWindow { devToolsLog("page win \(page.windowNumber) style \(page.styleMask.rawValue) close=\(buttonState(page)) opaque=\(page.isOpaque) key=\(page.isKeyWindow)\n" + viewTree(page.contentView)) }
            if let panel = overlayPanel { devToolsLog("overlay \(panel.windowNumber) style \(panel.styleMask.rawValue) frame \(panel.frame)\n" + viewTree(panel.contentView, max: 1)) }
        }
    }
    private var devToolsTreeDumps = 0
    private func buttonState(_ w: NSWindow) -> String {
        guard let b = w.standardWindowButton(.closeButton) else { return "none" }
        return "hidden=\(b.isHidden) alpha=\(b.alphaValue) frame=\(b.frame) superHidden=\(b.superview?.isHidden ?? false)"
    }
    private func viewTree(_ v: NSView?, depth: Int = 0, max: Int = 3) -> String {
        guard let v else { return "(nil)\n" }
        var s = String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden)\n"
        if depth < max { for sub in v.subviews { s += viewTree(sub, depth: depth + 1, max: max) } }
        return s
    }

    private func attachDevToolsWindow(_ w: NSWindow, selfDock: Bool, tab: UUID) {
        guard let window else { return }
        if w.parent !== window {
            // CEF made a normal window; strip its chrome so only the DevTools content shows.
            // Not resizable: the edge zone outside a resizable window would take drags
            // meant for the frontend's splitter (undocking makes it resizable again).
            w.styleMask.remove([.titled, .resizable])
            w.styleMask.insert(.fullSizeContentView)
            ChromiumWindowCorners.setSquare(true, for: w)
            ChromiumChildHover.setDocked(true, for: w)
            w.styleMask.remove([.closable, .miniaturizable])
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = true }
            w.hasShadow = false
            w.isMovable = false
            w.isMovableByWindowBackground = false
            w.isOpaque = false
            w.backgroundColor = .clear
            window.addChildWindow(w, ordered: .above)
            fillContentView(w)
            if selfDock { setDevToolsTitleBarInset(nil, tab: tab) }
        }
        updateDevToolsCorners(w, tab: tab)
    }

    private func updateDevToolsCorners(_ w: NSWindow, tab: UUID) {
        guard let cv = w.contentView else { return }
        cv.wantsLayer = true
        guard let layer = cv.layer else { return }
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        if shell.edgeToEdge, let window {
            roundAtWindowCorners(layer, rect: window.convertFromScreen(w.frame), flipped: cv.isFlipped)
            return
        }
        layer.cornerRadius = CraMetrics.contentCornerRadius
        // Frontend-docked: the window spans the card body, so both bottom corners are
        // card corners, and the top ones too without the toolbar (else they showed past the
        // page's rounded top corners). Shell-docked (Alloy): it sits right of the page.
        let selfDock = browsers.runtime(for: tab)?.hostWindow != nil
        let bottom: CACornerMask = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = selfDock ? (shell.panesShowBars ? bottom : all) : [.layerMaxXMaxYCorner, .layerMaxXMinYCorner]
    }

    /// "Undock into separate window": the frontend's window becomes a floating window of its own.
    private func detachDevToolsWindow(_ w: NSWindow, tab: UUID) {
        guard let window else { return }
        guard w.parent === window else {
            // Already floating: show it again after a tab switch without taking the keys.
            if !w.isVisible { w.orderFront(nil) }
            return
        }
        window.removeChildWindow(w)
        // A normal titled window, like Chrome's undocked "DevTools - <url>" (the
        // frontend draws under a real title bar; attach strips all of this again).
        w.styleMask.remove(.fullSizeContentView)
        w.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        ChromiumWindowCorners.setSquare(false, for: w)
        ChromiumChildHover.setDocked(false, for: w)
        w.titlebarAppearsTransparent = false
        w.titleVisibility = .visible
        if let url = browsers.runtime(for: tab)?.browser.currentURL, !url.isEmpty {
            w.title = "DevTools - " + url.replacingOccurrences(of: "^[a-z]+://", with: "", options: .regularExpression)
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = false }
        w.hasShadow = true
        w.isMovable = true
        w.isOpaque = true
        w.backgroundColor = .windowBackgroundColor
        if let cv = w.contentView {
            cv.layer?.cornerRadius = 0
            cv.layer?.masksToBounds = false
        }
        let f = window.frame
        let size = NSSize(width: min(1100, f.width * 0.8), height: min(760, f.height * 0.8))
        w.setFrame(NSRect(x: f.midX - size.width / 2 + 40, y: f.midY - size.height / 2 - 20, width: size.width, height: size.height), display: true)
        setDevToolsTitleBarInset(w, tab: tab)
        w.makeKeyAndOrderFront(nil)
    }

    /// CEF's frame view keeps a frameless window's content view at full window size, so
    /// the undocked window's title bar covers the top of the frontend; move the
    /// frontend's layout down by the title bar's height instead (0 when docked).
    private func setDevToolsTitleBarInset(_ w: NSWindow?, tab: UUID) {
        let inset = w.map { max(0, $0.frame.height - $0.contentLayoutRect.height) } ?? 0
        let css = inset > 0 ? "body{margin-top:\(Int(inset))px!important;height:calc(100% - \(Int(inset))px)!important}" : ""
        browsers.runtime(for: tab)?.browser.executeJavaScript("(function(){var s=document.getElementById('cra-titlebar-inset');"
            + "if(!s){s=document.createElement('style');s.id='cra-titlebar-inset';document.head.appendChild(s);}"
            + "s.textContent='\(css)';})();", inDevTools: true)
    }

    /// Page windows go above the DevTools windows (each spans its pane's body when the
    /// frontend docks), and the overlay panel above everything.
    private func raisePageWindows() {
        guard let window else { return }
        // Child windows ignore orderWindow:relativeTo:; re-adding a child puts it above its siblings.
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow, w.parent === window else { continue }
            window.removeChildWindow(w)
            window.addChildWindow(w, ordered: .above)
            w.orderFront(nil)
        }
        raiseOverlayPanels()
    }

    private func positionDevToolsWindow(_ rectInWindow: NSRect, tab id: UUID) {
        guard let window, let v = browsers.devToolsViews[id], let w = v.window, w.parent === window else { return }
        let onScreen = window.convertToScreen(rectInWindow)
        if w.frame != onScreen { w.setFrame(onScreen, display: true) }
        fillContentView(w)
        updateDevToolsCorners(w, tab: id)
        if let cv = w.contentView, v.frame != cv.bounds {
            v.frame = cv.bounds
        }
    }

    func browserManagerHandleKey(_ event: NSEvent) -> Bool {
        // Chrome: Escape leaves a page's element fullscreen, before the page sees the key.
        // Chrome's own handling never got it here: the video stayed fullscreen.
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let id = contentFullscreenTab, let browser = browsers.runtime(for: id)?.browser {
            browser.exitFullscreen()
            return true
        }
        return app.handleReservedKey(event)
    }
    func browserManagerHandleUnhandledKey(_ event: NSEvent) -> Bool { app.handleUnhandledKey(event) }
    /// A hidden page asked for focus: the Picture in Picture window's "back to tab" button.
    func browserManagerFocusedBrowser(_ tabID: UUID) {
        guard tabID != browsers.visibleTabID else { return }
        // Split view: clicking into another pane focuses it (Arc: focusedContentID
        // follows the click); its toolbar gets the options button and shortcuts act on it.
        if browsers.visibleTabIDs.contains(tabID) {
            store.selectTab(tabID, window: windowID)
            return
        }
        guard browsers.runtime(for: tabID)?.browser.isInPictureInPicture == true else { return }
        store.selectTab(tabID, window: windowID)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func browserManagerPageClosedTab(_ tabID: UUID) { closeTab(tabID) }

    /// An extension brought one of this window's tabs to the front (SwitchyOmega's Options with
    /// its settings tab already open): selected, as in Arc (GitHub #38). A page that asked
    /// (Chromium allows that after a click on its notification, or from its opener) also
    /// brings the window and Cra to the front, like Arc: Messenger's chat opens on a click.
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool) {
        store.selectTab(tabID, window: windowID)
        if byPage, !HitchMonitor.background {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if NSApp.isActive, window?.isKeyWindow == false {
            showWindow(nil)
        }
    }

    /// Arc's Peek (PeekTrigger): the link opens over the window and the tab stays put.
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool, newTab: Bool) -> Bool {
        guard !isIncognito, PeekTrigger.opens(url, from: pageURL, shiftClick: shiftClick, newTab: newTab,
                                               fromPinned: store.isPinned(tabID), settings: store.settings) else { return false }
        app.openPeek(url: url, over: self, fromTab: tabID)
        return true
    }

    func browserManagerCaptureImage(at point: NSPoint, tabID: UUID) {
        guard tabID == browsers.visibleTabID else { return }
        capturePage(liftImageAt: point)
    }

    func browserManagerOpenLink(_ url: String, in kind: CraLinkWindow, space: UUID?, fromIncognito: Bool) {
        app.openLink(url, in: kind, space: space, fromIncognito: fromIncognito)
    }

    /// The area Arc's Peek is centred on (window coordinates): right of the sidebar to the
    /// window's edge, top to bottom; the whole window with the sidebar out of the way.
    private func peekAreaInWindow() -> NSRect {
        guard let window else { return .zero }
        return PeekLayout.area(window: window.frame.size, contentMinX: peekContentMinX())
    }

    /// Where the sidebar ends (window coordinates), 0 with it hidden.
    private func peekContentMinX() -> CGFloat {
        // Asked from windowDidResize, before the shell has laid out at the new size.
        shell.layoutSubtreeIfNeeded()
        let content = shell.convert(shell.contentContainer.frame, to: nil)
        let sidebarShown = store.window(windowID).sidebarVisible && content.minX > CraMetrics.contentInset
        return sidebarShown ? content.minX : 0
    }

    /// Where a click closes a Peek (screen coordinates): the page area, not the sidebar, whose rows
    /// still open their tabs (#242).
    func peekDismissArea() -> NSRect {
        guard let window else { return .zero }
        return PeekLayout.dismissArea(covering: window.frame, contentMinX: peekContentMinX())
    }

    /// cra://debug?peekCatcher: whether the shown Peek's click catcher leaves the sidebar's rows to
    /// the sidebar (#242).
    func peekCatcherReadout() -> String {
        guard let window, let dim = peeks.first(where: { !$0.isParked })?.dimFrame else { return "none" }
        let sidebar = window.convertToScreen(shell.sidebarHost.convert(shell.sidebarHost.bounds, to: nil))
        let covered = !store.window(windowID).sidebarVisible ? "hidden" : dim.intersects(sidebar.insetBy(dx: 0.5, dy: 0.5)) ? "covered" : "clear"
        return "sidebar=\(covered)"
    }

    /// The whole area, where a Peek grows from and goes back to (screen coordinates).
    func peekArea() -> NSRect { window?.convertToScreen(peekAreaInWindow()) ?? .zero }

    /// Arc's Peek card (screen coordinates).
    func peekFrame() -> NSRect { window?.convertToScreen(PeekLayout.card(in: peekAreaInWindow())) ?? .zero }

    /// Close, Expand and Add To Split beside the card, top first (screen coordinates).
    func peekButtonFrames() -> [NSRect] {
        guard let window else { return [] }
        return PeekLayout.buttons(beside: PeekLayout.card(in: peekAreaInWindow())).map { window.convertToScreen($0) }
    }

    /// The link a Peek opens from (GitHub #204): Arc grows the card out of it and closes it back in.
    /// The link under the pointer in `tabID`'s page, else the page's focused link, found by
    /// PeekLayout's script in Cra's isolated world, with a picture of it cut from Chromium's
    /// screenshot. Answers within `PeekSource.wait` whatever Chromium does: nil without a link (the
    /// Peek then grows from the whole area), no picture when the screenshot is late.
    func peekSource(fromTab tabID: UUID?, completion: @escaping (PeekSource?) -> Void) {
        guard let tabID, let window, let rt = browsers.runtimes[tabID], let host = rt.hostWindow, host.parent === window,
              host.isVisible, rt.browser.isCreated, !rt.browser.isClosed else {
            CraLog.note("peek: from the whole area (no page to find the link in)")
            completion(nil)
            return
        }
        let completion: (PeekSource?) -> Void = { source in
            CraLog.note(source.map { "peek: from a link at \(Int($0.rect.minX)),\(Int($0.rect.minY)) \(Int($0.rect.width))×\(Int($0.rect.height))\($0.image == nil ? ", no picture" : "")" }
                ?? "peek: from the whole area (no link under the pointer or focused)")
            completion(source)
        }
        let pageFrame = host.frame
        let m = NSEvent.mouseLocation
        let pointer = pageFrame.contains(m)
            ? CGPoint(x: (m.x - pageFrame.minX) / pageFrame.width, y: (pageFrame.maxY - m.y) / pageFrame.height) : nil
        var fraction: CGRect??
        var picture: CGImage??
        var answered = false
        let finish: (Bool) -> Void = { [weak window] timedOut in
            guard !answered, let window else { return }
            guard case .some(let found) = fraction else {
                if timedOut { answered = true; completion(nil) }
                return
            }
            if picture == nil, !timedOut { return }
            answered = true
            guard let found, let rect = PeekLayout.source(fraction: found, in: window.convertFromScreen(pageFrame)) else { completion(nil); return }
            let image = (picture ?? nil).flatMap { PeekSource.crop($0, to: found) }
            completion(PeekSource(tabID: tabID, rect: rect, image: image))
        }
        let script = PeekLayout.sourceScript(pointer: pointer)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, _ in
            let found = PeekSource.value(result).flatMap(PeekLayout.fraction(fromScript:))
            DispatchQueue.main.async { if fraction == nil { fraction = .some(found) }; finish(false) }
        }
        rt.browser.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","optimizeForSpeed":true}"#) { shot, _ in
            let image = PeekSource.image(fromScreenshot: shot)
            DispatchQueue.main.async { if picture == nil { picture = .some(image) }; finish(false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekSource.wait) { finish(true) }
    }

    /// Where the link a Peek came from is now (the page may have scrolled), in this window's
    /// coordinates; nil when it's gone, off the page or Chromium doesn't answer in time.
    func peekSourceAgain(_ source: PeekSource, completion: @escaping (NSRect?) -> Void) {
        guard let window, let rt = browsers.runtimes[source.tabID], let host = rt.hostWindow, host.parent === window,
              host.isVisible, rt.browser.isCreated, !rt.browser.isClosed else { completion(nil); return }
        var answered = false
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": PeekLayout.sourceAgainScript, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak window, weak host] result, _ in
            let found = PeekSource.value(result).flatMap(PeekLayout.fraction(fromScript:))
            DispatchQueue.main.async {
                guard !answered else { return }
                answered = true
                guard let window, let host, let found else { completion(nil); return }
                completion(PeekLayout.source(fraction: found, in: window.convertFromScreen(host.frame)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekSource.wait) {
            guard !answered else { return }
            answered = true
            completion(nil)
        }
    }

    /// Arc fades the page under a Peek to 28 % over the window's background, its sidebar as it is;
    /// Cra also draws it back a little unless it fills the window edge to edge (PR #221).
    /// `PeekVeil` says which Peek it is veiled for, so a Peek that ended early never veils it and
    /// one whose close already fades it back doesn't snap that fade.
    private var peekVeil = PeekVeil()

    /// `peek` is opening over this window, or back with its tab (`animated` false, #242).
    func showPeekVeil(for peek: UUID, animated: Bool = true) {
        guard peekVeil.show(for: peek) else { return }
        if animated { applyPeekVeil(duration: PeekLayout.openVeilDuration, timing: PeekTransition.easeOutCubic) } else { applyPeekVeil(duration: 0) }
    }

    /// `peek` waits on its tab while another is on screen (#242): the page snaps back, and the
    /// Peek can veil it again.
    func parkPeekVeil(for peek: UUID) {
        guard peekVeil.hide(for: peek) else { return }
        applyPeekVeil(duration: 0)
    }

    /// `peek` is closing: the page comes back over Arc's 0.2 s while the card lands.
    func hidePeekVeil(for peek: UUID) {
        guard peekVeil.hide(for: peek) else { return }
        applyPeekVeil(duration: PeekLayout.closeVeilDuration, timing: PeekTransition.easeOutCubic)
    }

    /// `peek`'s window is gone (Expand and Add To Split don't animate): the page snaps back.
    func endPeekVeil(for peek: UUID) {
        guard peekVeil.end(for: peek) else { return }
        applyPeekVeil(duration: 0)
    }

    /// cra://debug?peekShown: the page behind a Peek as it is set now (the peek-backdrop scenario).
    func peekBackdropShown() -> String {
        func scale(_ v: NSView?) -> String {
            String(format: "%.3f", v?.layer.map { CATransform3DGetAffineTransform($0.sublayerTransform).a } ?? 1)
        }
        let content = shell.contentContainer
        // Pages in their own windows (DevTools docked, or CRA_EMBED_PAGES=0); embedded ones go with the content.
        let pages = browsers.runtimes.values.compactMap(\.hostWindow).filter { $0.parent === window && !EmbeddedPages.isHost($0) }
        return String(format: "veiled=%d alpha=%.2f scale=%@ windows=%@", peekVeil.isOn ? 1 : 0, content.alphaValue, scale(content),
                      pages.map { String(format: "%.2f@", $0.alphaValue) + scale($0.contentView) }.joined(separator: ","))
    }

    private func applyPeekVeil(duration: TimeInterval, timing: CAMediaTimingFunction? = nil) {
        let look = PeekLayout.backdrop(veiled: peekVeil.isOn, edgeToEdge: shell.edgeToEdge)
        let content = shell.contentContainer
        let center = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        PeekTransition.scaleBackdrop(content, around: center, to: look.scale, duration: duration, timing: timing)
        let pages = browsers.runtimes.values.compactMap(\.hostWindow).filter { $0.parent === window }
        if let window {
            // Each page window shrinks around the same point on screen as the page's card.
            let screenCenter = window.convertPoint(toScreen: content.convert(center, to: nil))
            for page in pages where !EmbeddedPages.isHost(page) {
                guard let view = page.contentView else { continue }
                let pageCenter = view.convert(page.convertPoint(fromScreen: screenCenter), from: nil)
                PeekTransition.scaleBackdrop(view, around: pageCenter, to: look.scale, duration: duration, timing: timing)
            }
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            content.animator().alphaValue = look.alpha
            for w in pages { w.animator().alphaValue = look.alpha }
        }
    }

    /// Add To Split from a Peek: the peeked page, a new tab, joins `source` as a pane (Arc's
    /// openInSplit), or a toast when the split is full.
    func canAddPane(to source: UUID) -> Bool { store.paneTabIDs(for: source).count < 4 }

    func joinSplit(_ tabID: UUID, with source: UUID) {
        let split = store.splitContaining(source).map { sp in store.addToSplit(sp.id, tabID: tabID, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [source, tabID], at: source)
        store.selectTab(split.flatMap { store.paneID(for: tabID, in: $0) } ?? tabID, window: windowID)
    }

    private var peeks: [LittleWindowController] { app.littleWindows.filter { $0.peekParent === self } }

    /// Arc keeps a Peek per tab (#242): each shows while its tab is on screen here, waits out of
    /// sight while another is, and goes with its tab (PeekPresence).
    private func syncPeeks(onScreen panes: [UUID]) {
        for p in peeks {
            switch PeekPresence.of(peekFrom: p.peekSourceTab, onScreen: panes, tabExists: p.peekSourceTab.map { store.item($0) != nil } ?? false) {
            case .shown:
                p.unparkPeek()
                // The sidebar shown or hidden under it: the catcher follows the page area.
                if let f = p.dimFrame, f != peekDismissArea() { p.repositionPeek() }
            case .parked: p.parkPeek()
            case .dropped: p.dropPeek()
            }
        }
    }

    /// `tab`'s page closed (a pinned tab's ⌘W keeps its row): its Peek goes with it (#242).
    func dropPeeks(from tab: UUID) {
        for p in peeks where p.peekSourceTab == tab { p.dropPeek() }
    }

    /// cra://debug?peeks: this window's Peeks, on screen or not, and their pages (#242).
    func peeksShown() -> String {
        let list = peeks.map { p in "\(p.window.map { $0.isVisible && $0.alphaValue > 0 } == true ? "shown" : "hidden") \(p.currentURL)" }
        return list.isEmpty ? "none" : list.joined(separator: ", ")
    }

    /// The Peek closed last over this window and the tab it came from: Arc's ⇧⌘T brings it back
    /// when nothing was archived after it.
    var closedPeek: (url: String, tabID: UUID?, at: Date)?

    // MARK: Tabs

    /// cra://debug?devtoolsjs=…: run script in the current tab's DevTools frontend.
    func debugRunInDevTools(_ script: String) { currentBrowser?.executeJavaScript(script, inDevTools: true) }

    func closeCurrentTab() {
        // ⌘W with tabs picked in the sidebar takes all of them. As in Arc (SidebarClose.commandW),
        // a Today tab among them archives them all, pinned ones too; otherwise they all keep
        // their place and unload.
        let ids = sidebarUI.multiSelection.isEmpty ? selectedTabID.map { [$0] } ?? [] : Array(sidebarUI.multiSelection)
        guard !ids.isEmpty else { return }
        sidebarUI.clearPicks()
        let action = SidebarClose.commandW(anyToday: ids.contains { !store.isPinned($0) })
        // The open tab goes last so closing it doesn't hop through tabs about to close.
        let open = selectedTabID
        for id in ids.filter({ $0 != open }) + ids.filter({ $0 == open }) {
            if action == .keep || !store.isPinned(id) {
                closeTab(id)
            } else {
                // A pinned split goes as one, as it closes as one.
                for p in store.paneTabIDs(for: id) { store.archiveTab(p, reason: .manual) }
            }
        }
    }

    /// Today tabs are archived. Pinned tabs and favorites stay; they unload
    /// and return to their pinned page (Arc's close-on-pinned behaviour).
    func closeTab(_ id: UUID) {
        guard let item = store.item(id), item.isTab else { return }
        if store.isPinned(id) {
            // A pinned split closes as one: every pane unloads and goes back to its page.
            let panes = store.paneTabIDs(for: id)
            let wasSelected = selectedTabID.map(panes.contains) ?? false
            for p in panes {
                _ = store.resetPinnedTab(p)
                for w in app.mainWindows { w.browsers.unload(p); w.dropPeeks(from: p) }
            }
            // Arc goes back to the tab shown before this one if its page is still loaded, and
            // otherwise shows nothing (CloseSuccessor). The panes were just unloaded, so they
            // don't count.
            if wasSelected { store.selectTab(store.closeSuccessor(ofPinned: id, window: windowID), window: windowID) }
        } else {
            store.archiveTab(id, reason: .manual)
        }
    }

    /// The space's open tabs, the latest first. A pinned tab that was closed (unloaded) isn't
    /// open: ⌃Tab doesn't list it.
    private func openRecentTabs(limit: Int) -> [UUID] {
        Array(store.recentTabs(in: focusedSpaceID, limit: .max)
            .filter { $0 == selectedTabID || !store.isPinned($0) || app.runtime(for: $0) != nil }
            .prefix(limit))
    }

    func resetPinnedTab(_ id: UUID) {
        guard let home = store.resetPinnedTab(id) else { return }
        app.runtime(for: id)?.browser.loadURL(home)
    }

    /// Arc's ⌘-click on the favicon of a pinned tab away from its page ("Separate From Pinned
    /// Tab", GitHub #139): the page moves to a new Today tab at the top, the pinned tab goes back
    /// to its page and stays open.
    func separatePinnedTab(_ id: UUID) {
        guard let t = store.item(id)?.tab, store.isPinned(id), t.url != t.savedURL else { return }
        _ = store.createTab(url: t.url, title: t.savedTitle, in: store.spaceID(ofItem: id), select: false, index: 0)
        resetPinnedTab(id)
        store.selectTab(id, window: windowID)
    }

    /// Edit Pinned URL… (#54): Arc's dialog with the pinned URL. A page showing the old
    /// pinned URL loads the new one; one navigated away stays where it is.
    func editPinnedURL(_ id: UUID) {
        guard let window, let tab = store.item(id)?.tab, store.isPinned(id), tab.liveItemURL == nil else { return }
        DialogPanel.present(over: window) { [weak self] close in
            EditPinnedURLDialog(url: tab.savedURL, onSave: { url in
                close()
                guard let self, let before = self.store.item(id)?.tab, self.store.setPinnedURL(id, to: url),
                      before.url == before.savedURL, before.url != url else { return }
                self.app.runtime(for: id)?.browser.loadURL(url)
            }, onCancel: close)
        }
    }

    func cycleTab(_ delta: Int) {
        let tabs = store.visibleTabs(in: focusedSpaceID)
        guard !tabs.isEmpty else { return }
        let idx = selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? -1
        let n = tabs.count
        store.selectTab(tabs[((idx + delta) % n + n) % n].id)
    }

    func zoom(by delta: Double) {
        guard let b = currentBrowser else { return }
        b.setZoomLevel(b.zoomLevel() + delta)
    }

    /// Arc's Capture (⇧⌘2 again closes it): the page dims, a click takes the element under the
    /// pointer and a drag a rectangle, then a menu copies, saves or sends it (CaptureOverlay).
    /// Chromium draws the picture it works on (Page.captureScreenshot), so it holds the page
    /// whatever display the window is on and whatever is in front of it.
    /// `liftImageAt` (Capture Image… on an image, page points from its top left): the image there
    /// is taken at once and moves to the middle of the page with the menu beside it, as in Arc.
    func capturePage(liftImageAt point: NSPoint? = nil) {
        if let open = captureOverlay, open.isOpen {
            open.close()
            if point == nil { return }
        }
        guard !captureStarting, let rt = browsers.visibleRuntime, rt.browser.isCreated, !rt.browser.isClosed,
              pageScreenRect(rt) != nil else { return }
        let b = rt.browser
        captureStarting = true
        guard let point else { takeCapture(b, liftImageAt: nil); return }
        // Where the image is first: the picture is taken with the menu already closed.
        let scale = window?.backingScaleFactor ?? 2
        let script = ContentCapture.imageRectScript(x: point.x * scale, y: point.y * scale)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        b.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                guard let self, let b else { return }
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { ($0["result"] as? [String: Any])?["value"] as? [String: Any] }
                guard let value, let rt = self.browsers.visibleRuntime, rt.browser === b, let page = self.pageScreenRect(rt),
                      let rect = ContentCapture.elementRect(fromPicker: value, scale: scale, pageBounds: CGRect(origin: .zero, size: page.size))
                else { self.captureStarting = false; return }
                self.takeCapture(b, liftImageAt: rect)
            }
        }
    }

    private func takeCapture(_ b: CraBrowser, liftImageAt image: CGRect?) {
        let lift = image
        b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","captureBeyondViewport":false}"#) { [weak self, weak b] shot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.captureStarting = false
                guard let b, let window = self.window, let rt = self.browsers.visibleRuntime, rt.browser === b,
                      let rect = self.pageScreenRect(rt) else { return }
                guard let image = Self.screenshotImage(shot) else {
                    NSLog("Cra: capture failed: %@", error ?? "no data")
                    self.showToast("Capture Failed")
                    return
                }
                let overlay = CaptureOverlay(over: window, pageRect: rect, shot: image, browser: b)
                overlay.onFinish = { [weak self] action, png in self?.captureFinished(action, png) }
                self.captureOverlay = overlay
                if let lift { overlay.lift(lift) }
            }
        }
    }

    private var captureOverlay: CaptureOverlay?
    private var captureStarting = false

    /// The focused page on screen, whether its view is embedded in the card or in its own window.
    private func pageScreenRect(_ rt: TabRuntime) -> NSRect? {
        let view = rt.hostWindow.flatMap { EmbeddedPages.pageViews(of: $0)?.last } ?? rt.browser.containerView
        guard let w = view.window, !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        return w.convertToScreen(view.convert(view.bounds, to: nil))
    }

    static func screenshotImage(_ shot: String?) -> CGImage? {
        guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
              let b64 = o["data"] as? String, let png = Data(base64Encoded: b64),
              let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Send To… an easel: the capture goes on it, under what is there, and its tab comes forward
    /// (a new one when it has none open).
    private func sendCapture(_ png: Data, toEasel id: UUID) {
        guard EaselFiles.add(picture: png, to: id) else { return }
        CraLog.note("capture sent to an easel, which now holds \(EaselFiles.load(id).items.count) items")
        let url = Easel(id: id).url
        if let tab = store.allTabs().first(where: { $0.tab?.url == url }) {
            browsers.unload(tab.id)  // opened again from the file, picture included
            store.selectTab(tab.id, window: windowID)
            refresh()
        } else {
            _ = store.createTab(url: url, title: EaselFiles.load(id).title, select: true, window: windowID)
        }
    }

    /// Testing without the pointer (cra://debug?captureToEasel=1): the visible page captured and
    /// the capture menu's New Easel chosen.
    func debugCaptureToEasel(send: Bool = false) {
        currentBrowser?.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png"}"#) { [weak self] shot, _ in
            MainActor.assumeIsolated {
                let o = shot.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let png = (o?["data"] as? String).flatMap { Data(base64Encoded: $0) }
                // send: Send To… the easel edited last, as if picked from its menu.
                if send, let png, let last = EaselFiles.all().first { self?.sendCapture(png, toEasel: last.id); return }
                self?.captureFinished(.newEasel, png)
            }
        }
    }

    /// The capture menu's choice, once the overlay is down.
    private func captureFinished(_ action: CaptureOverlay.Action?, _ png: Data?) {
        captureOverlay = nil
        if action != nil || NSApp.isActive, window?.isVisible == true {
            window?.makeKey()
            currentBrowser?.setFocused(true)
        }
        switch action {
        case .copy?:
            guard let png else { return }
            copyCapture(png)
            showToast("Screenshot Copied to Clipboard")
        case .save?:
            if let png { saveCapture(png) }
        case .message?:
            if let png { sendCaptureViaMessages(png) }
        case .newEasel?:
            guard let png, let easel = EaselFiles.create(withPicture: png) else { return }
            _ = store.createTab(url: easel.url, title: easel.title, select: true, window: windowID)
        case .sendToEasel?:
            guard let png else { return }
            let easels = EaselFiles.all()
            guard !easels.isEmpty else {
                if let easel = EaselFiles.create(withPicture: png) { _ = store.createTab(url: easel.url, title: easel.title, select: true, window: windowID) }
                return
            }
            let menu = NSMenu()
            for e in easels {
                MenuItems.add(menu, e.title) { [weak self] in self?.sendCapture(png, toEasel: e.id) }
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        case .retake?:
            capturePage()
        case nil:
            break
        }
    }

    private func copyCapture(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// Arc's "Send via iMessage…": Messages' compose sheet with the capture attached.
    private func sendCaptureViaMessages(_ png: Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Cra Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.captureFileName())
        guard (try? png.write(to: url)) != nil, let service = NSSharingService(named: .composeMessage),
              service.canPerform(withItems: [url]) else {
            showToast("Messages Isn't Available")
            return
        }
        service.perform(withItems: [url])
    }

    private static func captureFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cra Capture \(f.string(from: Date())).png"
    }

    // MARK: Sidebar

    func toggleSidebar() {
        if sidebarUI.libraryPage != nil {
            // The Library brought the sidebar out: leaving it hides the sidebar again.
            let showed = libraryShowedSidebar
            closeLibrary()
            if showed { return }
        }
        sidebarVisible.toggle()
        if !sidebarVisible { setFloatingSidebar(false) }
    }

    // MARK: Library

    /// Set when the Library brought a hidden sidebar out; leaving it hides the sidebar again.
    private var libraryShowedSidebar = false

    /// Arc's Library button and ⇧⌘L: open the Library on the page last shown, or leave it. In a
    /// docked sidebar it slides in and out like the swipe into it (LibrarySwipe).
    func toggleLibrary() {
        let opening = librarySettleSpring.map { $0.target < 1 } ?? (sidebarUI.libraryPage == nil)
        if librarySwipeFrom == nil, !shell.floatingSidebar, shell.sidebarVisible, !libraryShowedSidebar {
            slideLibrary(to: opening ? 1 : 0)
        } else if opening {
            showLibrary(sidebarUI.lastLibraryPage)
        } else {
            closeLibrary()
        }
    }

    /// The Library takes over the sidebar, which widens for its page rail (LibraryView).
    func showLibrary(_ page: LibraryPage) {
        sidebarUI.lastLibraryPage = page
        let opening = sidebarUI.libraryPage == nil
        let resize = !opening && sidebarUI.libraryPage.map(libraryWidth) != libraryWidth(page)
        withAnimation(.easeOut(duration: 0.05)) { sidebarUI.libraryPage = page }
        if resize {
            shell.sidebarWidth = libraryWidth(page)
            shell.animateSidebar(visible: true, floating: false, fullscreen: shell.contentFullscreen, width: shell.sidebarWidth, duration: 0.1)
        }
        guard opening else { return }
        sidebarUI.downloadsListOpen = false
        commandBar.close()
        shell.sidebarResizable = false
        let width = libraryWidth(page)
        if sidebarVisible {
            shell.sidebarWidth = width
            shell.animateSidebar(visible: true, floating: false, fullscreen: shell.contentFullscreen, width: width)
        } else {
            setFloatingSidebar(false)
            libraryShowedSidebar = true
            shell.sidebarWidth = width
            sidebarVisible = true
        }
        window?.makeKey()
    }

    /// The sidebar's width with the Library in it: 70 pt wider for the rail, or on the Spaces page
    /// wide enough for every space's card, leaving the page 56 pt (Arc 1.171; the cards scroll
    /// sideways when they don't fit).
    private func libraryWidth(_ page: LibraryPage) -> CGFloat {
        let base = CGFloat(store.prefs.sidebarWidth) + LibraryMetrics.extraWidth
        guard page == .spaces else { return base }
        let n = store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.count
        let room = (window?.frame.width ?? 1280) - SpacesManagerMetrics.pageRoom
        return max(base, min(SpacesManagerMetrics.width(spaces: n), room))
    }

    func closeLibrary() {
        guard sidebarUI.libraryPage != nil else { return }
        withAnimation(.easeOut(duration: 0.1)) { sidebarUI.libraryPage = nil }
        shell.sidebarResizable = true
        let width = CGFloat(store.prefs.sidebarWidth)
        shell.sidebarWidth = width
        if libraryShowedSidebar {
            libraryShowedSidebar = false
            sidebarVisible = false
        } else {
            shell.animateSidebar(visible: shell.sidebarVisible, floating: false, fullscreen: shell.contentFullscreen, width: width, duration: 0.1)
        }
        currentBrowser?.setFocused(true)
    }

    /// Arc's floating sidebar lives in its own panel above the page windows (see FloatingSidebarController).
    private(set) var floatingSidebar: FloatingSidebarController?

    private func setFloatingSidebar(_ show: Bool) {
        guard let floatingSidebar else { return }
        if show { if !sidebarVisible, floatingSidebar.isKey { floatingSidebar.show() } } else { floatingSidebar.hide(animated: true) }
    }

    private func installFloatingSidebar() {
        guard let window, floatingSidebar == nil else { return }
        let f = FloatingSidebarController(shell: shell, window: window, palette: { [weak self] in
            self?.focusedSpace.theme.palette ?? SpaceTheme.presets[0].palette
        })
        f.sidebarHidden = { [weak self] in self.map { !$0.sidebarVisible } ?? false }
        f.staysShown = { FolderPreviewController.shared.isOpen }
        f.didAttachPanel = { [weak self] in
            // Keep the find bar above the floating sidebar.
            self?.raiseOverlayPanels()
        }
        f.install()
        floatingSidebar = f
    }

    /// Pages and DevTools are separate Chromium child windows, and Chromium drops a
    /// click on a window that isn't key. In Chrome they share one window, so moving
    /// between the page and DevTools never costs a click: make the target key first.
    /// Only while focus is already inside this window; a click into an inactive Cra
    /// still just activates it, like Chrome.
    private func installChildClickMonitor() {
        childClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let window = self.window, let target = event.window, target.parent === window,
                  target !== self.overlayPanel, !target.isKeyWindow, target.canBecomeKey, NSApp.isActive,
                  let key = NSApp.keyWindow, key === window || key.parent === window else { return event }
            target.makeKey()
            return event
        }
        // A mouse's back and forward buttons over the sidebar switch spaces, like Arc's
        // SidebarView (issue #233); over a page they stay Chromium's history back and forward.
        // Middle-click on a sidebar tab closes it, like Arc and Chrome. Anywhere else, a page
        // included, the click goes on to whatever is under it. The row is found under the click
        // itself: a remembered hover outlived its row when the tab joined a split, and a middle
        // click inside a split pane closed that tab (GitHub #208).
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self else { return event }
            if self.mouseButtonSwitchesSpace(event.buttonNumber, event) { return nil }
            guard event.buttonNumber == 2, let window = self.window, let target = event.window,
                  target === window || target.parent === window,
                  let id = SpaceListView.tabID(under: event) else { return event }
            self.middleClickClose(id)
            return nil
        }
    }

    /// Arc's "Allow window dragging from the top of webpages" (PageTopDrag): with no bar above the
    /// page, a plain click in its top 56 pt waits. Moved past the slop, the window moves with the
    /// pointer; let go first, the page gets the click as it was, from the press on.
    private func installPageTopDragMonitor() {
        pageTopDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, !self.replayingPageClick, let window = self.window, let target = event.window,
                  !window.styleMask.contains(.fullScreen), let depth = self.depthIntoPage(event, in: target, of: window) else { return event }
            let modifiers = !event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            guard PageTopDrag.holds(enabled: self.store.settings.pageTopWindowDrag,
                                    barAbovePage: self.store.settings.showToolbar || self.shell.panesShowBars,
                                    depthIntoPage: depth, clickCount: event.clickCount, modifiers: modifiers) else { return event }
            self.trackPageTopPress(event, page: target, owner: window)
            return nil
        }
    }

    /// How far below the top of the page under it a press is, or nil when it isn't on a page:
    /// a Chrome-style page's own child window, or a page view inside this window.
    private func depthIntoPage(_ event: NSEvent, in target: NSWindow, of window: NSWindow) -> Double? {
        if target.parent === window {
            return CraCEFRuntime.isPageWindow(target) ? target.frame.height - event.locationInWindow.y : nil
        }
        guard target === window, let content = window.contentView,
              var view = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return nil }
        // Chromium's page view, reparented into the pane card (Chrome-style hosting): its
        // WebContentsViewCocoa is the page's frame.
        while NSStringFromClass(type(of: view)) != "WebContentsViewCocoa" {
            guard let up = view.superview else { return nil }
            view = up
        }
        return view.convert(view.bounds, to: nil).maxY - event.locationInWindow.y
    }

    private func trackPageTopPress(_ down: NSEvent, page: NSWindow, owner: NSWindow) {
        let start = NSEvent.mouseLocation
        var last = start, dragging = false
        var up: NSEvent?
        page.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { stop.pointee = true; return }
            if event.type == .leftMouseUp { up = event; stop.pointee = true; return }
            let now = NSEvent.mouseLocation
            if !dragging, PageTopDrag.isDrag(dx: now.x - start.x, dy: now.y - start.y) { dragging = true }
            if dragging { owner.setFrameOrigin(NSPoint(x: owner.frame.minX + now.x - last.x, y: owner.frame.minY + now.y - last.y)) }
            last = now
        }
        CraLog.note("page-top press: \(dragging ? "moved the window" : "a click for the page")")
        guard !dragging else { return }
        // A click after all: the page gets the press and the release, in its own window.
        replayingPageClick = true
        if !page.isKeyWindow, page.canBecomeKey { page.makeKey() }
        page.sendEvent(down)
        if let up { page.sendEvent(up) }
        replayingPageClick = false
    }

    /// What the row's hover button does: close every picked tab when this is one of them;
    /// the open pinned tab unloads and stays pinned, another pinned tab is archived.
    private func middleClickClose(_ id: UUID) {
        let group = sidebarUI.group(for: id, in: store)
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            if group.count == 1, store.isPinned(id), selectedTabID != id {
                store.archiveTab(id, reason: .manual)
            } else {
                let open = selectedTabID
                for t in group.filter({ $0 != open }) + group.filter({ $0 == open }) { closeTab(t) }
                sidebarUI.multiSelection.subtract(group)
            }
        }
    }

    /// Two-finger swipes over the sidebar page between spaces the way Dia does
    /// (ARCUI.PageSwipeController): the sidebar strip and the window tint follow the
    /// fingers 1:1, rubber-band past the first and last space, tick a haptic detent at
    /// each page, and on release a zero-bounce spring carries the release speed onto a
    /// page. A gesture locks to one axis early, so vertical list scrolling is untouched.
    private func installSwipeMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            // Any new gesture ends the last space swipe. Pages are child windows (and every
            // main window has this monitor), so a scroll that starts there never reaches the
            // phase switch below; a stale .horizontal would eat the page's momentum and
            // scrolling would stop dead the moment the fingers lift.
            if event.phase == .began || event.phase == .mayBegin { self.swipeAxis = .vertical }
            // A mouse wheel only ever scrolls.
            if !event.hasPreciseScrollingDeltas { self.showListKnobs() }
            // The momentum tail of a space swipe belongs to the swipe, not the tab list.
            if !event.momentumPhase.isEmpty { return self.swipeAxis == .horizontal ? nil : event }
            // A wheel turned sideways, or with Shift (which macOS turns sideways), pages
            // between spaces over the sidebar like Arc (issue #93).
            if !event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                return self.wheelSwitchesSpace(event) ? nil : event
            }
            // The floating sidebar is in its own panel (FloatingSidebarController): its swipes
            // come from that window.
            let host = self.shell.sidebarHost
            guard event.window === self.window || (event.window != nil && event.window === host.window),
                  event.hasPreciseScrollingDeltas else { return event }
            switch event.phase {
            case .mayBegin, .began:
                let inSidebar = (self.shell.sidebarVisible || self.shell.floatingSidebar) && event.window === host.window
                    && host.bounds.contains(host.convert(event.locationInWindow, from: nil))
                // In the Library a swipe can only take it back out; on the Spaces page the cards
                // scroll first, and only a swipe that starts with them at their end leaves (Arc).
                var overSidebar = inSidebar
                if inSidebar, let page = self.sidebarUI.libraryPage {
                    overSidebar = page != .spaces || self.spacesStripAtEnd(event)
                }
                self.swipeAxis = overSidebar ? .undecided : .vertical
                if overSidebar { self.hideListKnobs() }
                self.swipeX = 0
                self.swipeY = 0
                return event
            case .changed:
                switch self.swipeAxis {
                case .vertical:
                    return event
                case .undecided:
                    self.swipeX += event.scrollingDeltaX
                    self.swipeY += event.scrollingDeltaY
                    guard max(abs(self.swipeX), abs(self.swipeY)) > 6 else { return event }
                    // One space still swipes into the Library.
                    guard abs(self.swipeX) > abs(self.swipeY) * 1.2, !self.isStandalone,
                          self.store.spaceOrder.count > 1 || !self.shell.floatingSidebar,
                          // At the Spaces page's end a swipe back along the cards scrolls them.
                          !(self.sidebarUI.libraryPage == .spaces && self.swipeX > 0) else {
                        self.swipeAxis = .vertical
                        self.showListKnobs()
                        return event
                    }
                    self.swipeAxis = .horizontal
                    HitchMonitor.mark("swipe-begin")
                    self.beginSpaceSwipe()
                    self.trackSpaceSwipe(by: self.swipeX, at: event.timestamp)
                    return nil
                case .horizontal:
                    self.trackSpaceSwipe(by: event.scrollingDeltaX, at: event.timestamp)
                    return nil
                }
            case .ended, .cancelled:
                if self.swipeAxis != .vertical { self.showListKnobs(after: 1) }
                guard self.swipeAxis == .horizontal else { return event }
                self.endSpaceSwipe()
                return nil
            default:
                return event
            }
        }
    }

    private func hideListKnobs() {
        swipeKnobReveal?.cancel()
        swipeKnobReveal = nil
        SidebarScroller.hiddenForSwipe = true
    }

    /// After `delay` seconds: by then the knob AppKit flashed at the touch has faded out.
    private func showListKnobs(after delay: TimeInterval = 0) {
        swipeKnobReveal?.cancel()
        guard delay > 0 else { SidebarScroller.hiddenForSwipe = false; return }
        let work = DispatchWorkItem { SidebarScroller.hiddenForSwipe = false }
        swipeKnobReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginSpaceSwipe() {
        swipeTravel = 0
        swipeSamples = []
        swipeDetent = 0
        sidebarUI.spaceSettleVelocity = 0
        // A swipe during a Library settle picks it up where it shows.
        stopLibrarySettle()
        let shown = sidebarUI.libraryReveal
        librarySwipeFrom = nil
        guard !shell.floatingSidebar, shell.sidebarVisible || sidebarUI.libraryPage != nil else { return }
        if let page = sidebarUI.libraryPage {
            prepareLibraryReveal(page)
            librarySwipeFrom = shown ?? 1
        } else if shown != nil || store.spaceOrder.first == focusedSpaceID {
            // The Library button slides it in from any space.
            prepareLibraryReveal(sidebarUI.lastLibraryPage)
            librarySwipeFrom = shown ?? 0
        }
    }

    // MARK: Swiping into the Library (LibrarySwipe)

    private func prepareLibraryReveal(_ page: LibraryPage) {
        sidebarUI.libraryRevealPage = page
        sidebarUI.libraryRevealWidth = libraryWidth(page)
        sidebarUI.libraryRevealBase = CGFloat(store.prefs.sidebarWidth)
    }

    /// Shows reveal `r`, and like Arc the sidebar widens with it, from its own width to the
    /// Library's, so the Library lands at its width with nothing left to resize.
    private func setLibraryReveal(_ r: CGFloat) {
        // Embedded pages keep their size under their cards until the swipe lands.
        if sidebarUI.libraryReveal == nil, EmbeddedPages.isEnabled { shell.freezePages() }
        sidebarUI.libraryReveal = r
        shell.sidebarWidth = LibrarySwipe.sidebarWidth(reveal: r, base: sidebarUI.libraryRevealBase, library: sidebarUI.libraryRevealWidth)
    }

    /// Past the first space the fingers pull the Library in like the page before it; in the
    /// Library they push it back out. Returns false when the swipe is one between spaces.
    private func trackLibrarySwipe() -> Bool {
        guard let from = librarySwipeFrom else { return false }
        guard let r = LibrarySwipe.reveal(from: from, travel: swipeTravel, width: sidebarUI.libraryRevealWidth) else {
            // Back on the space and beyond: the swipe heads for the next space instead.
            if sidebarUI.libraryReveal != nil {
                setLibraryReveal(0)
                sidebarUI.libraryReveal = nil
                shell.thawPages()
            }
            return false
        }
        if sidebarUI.spaceSwipe != 0 { sidebarUI.spaceSwipe = 0 }
        setLibraryReveal(r)
        return true
    }

    /// The release settles on the space swipe's spring, frame by frame on the display link.
    private func endLibrarySwipe(_ r: CGFloat) {
        librarySwipeFrom = nil
        let width = sidebarUI.libraryRevealWidth
        let velocity = LibrarySwipe.velocity(samples: swipeSamples, width: width)
        settleLibrary(from: r, velocity: velocity, to: LibrarySwipe.target(reveal: r, velocity: velocity))
    }

    /// The Library button: the same spring from rest, or turned around from where a settle is.
    private func slideLibrary(to target: CGFloat) {
        if let s = librarySettleSpring {
            let t = CGFloat(CACurrentMediaTime() - s.start)
            let r = LibrarySwipe.settle(from: s.from, velocity: s.velocity, to: s.target, at: t)
            settleLibrary(from: r, velocity: LibrarySwipe.settleVelocity(from: s.from, velocity: s.velocity, to: s.target, at: t), to: target)
            return
        }
        let from: CGFloat = sidebarUI.libraryPage == nil ? 0 : 1
        guard from != target else { return }
        prepareLibraryReveal(sidebarUI.libraryPage ?? sidebarUI.lastLibraryPage)
        setLibraryReveal(from)
        settleLibrary(from: from, velocity: 0, to: target)
    }

    private func settleLibrary(from r: CGFloat, velocity: CGFloat, to target: CGFloat) {
        librarySettleSpring = (start: CACurrentMediaTime(), from: r, velocity: velocity, target: target)
        if librarySettleLink == nil {
            let link = shell.displayLink(target: self, selector: #selector(stepLibrarySettle))
            link.add(to: .main, forMode: .common)
            librarySettleLink = link
        }
    }

    @objc private func stepLibrarySettle(_ link: CADisplayLink) {
        guard let s = librarySettleSpring else { return stopLibrarySettle() }
        let t = CGFloat(link.targetTimestamp - s.start)
        if LibrarySwipe.isSettled(from: s.from, velocity: s.velocity, to: s.target, at: t, width: sidebarUI.libraryRevealWidth) {
            stopLibrarySettle()
            finishLibrarySwipe(at: s.target)
        } else {
            setLibraryReveal(LibrarySwipe.settle(from: s.from, velocity: s.velocity, to: s.target, at: t))
        }
    }

    private func stopLibrarySettle() {
        librarySettleSpring = nil
        librarySettleLink?.invalidate()
        librarySettleLink = nil
    }

    /// Landed: the window is in the Library or on the space, at the width the swipe ends on.
    private func finishLibrarySwipe(at target: CGFloat) {
        var instant = Transaction()
        instant.disablesAnimations = true
        let width: CGFloat
        if target >= 1 {
            let page = sidebarUI.libraryPage ?? sidebarUI.libraryRevealPage
            if sidebarUI.libraryPage == nil {
                sidebarUI.lastLibraryPage = page
                sidebarUI.downloadsListOpen = false
                commandBar.close()
                shell.sidebarResizable = false
                withTransaction(instant) { sidebarUI.libraryPage = page }
                window?.makeKey()
            }
            width = libraryWidth(page)
        } else {
            if sidebarUI.libraryPage != nil {
                withTransaction(instant) { sidebarUI.libraryPage = nil }
                shell.sidebarResizable = true
                currentBrowser?.setFocused(true)
            }
            width = CGFloat(store.prefs.sidebarWidth)
        }
        sidebarUI.libraryReveal = nil
        shell.sidebarWidth = width
        shell.thawPages()
    }

    /// The Spaces page's cards under the pointer are scrolled to their end (or there are none).
    private func spacesStripAtEnd(_ event: NSEvent) -> Bool {
        // Arc ignores a swipe over the Library's rail.
        guard let strip = spacesStrip(at: event) else { return false }
        let clip = strip.contentView
        return clip.bounds.minX >= (strip.documentView?.frame.width ?? 0) - clip.bounds.width - 1
    }

    /// Whether the Spaces page's cards under the pointer can still scroll the way a wheel of `dx`
    /// moves them (a negative `dx` toward the last card, as the scroll view applies it).
    private func spacesStripCanScroll(_ event: NSEvent, dx: CGFloat) -> Bool {
        guard let strip = spacesStrip(at: event) else { return false }
        return dx < 0 ? !spacesStripAtEnd(event) : strip.contentView.bounds.minX > 1
    }

    /// The Spaces page's row of cards under the pointer.
    private func spacesStrip(at event: NSEvent) -> NSScrollView? {
        guard let root = shell.sidebarHost.window?.contentView?.superview else { return nil }
        var v = root.hitTest(event.locationInWindow)
        while let view = v, !(view is NSScrollView && (view as? NSScrollView)?.hasHorizontalScroller == true) { v = view.superview }
        return v as? NSScrollView
    }

    /// A mouse's back or forward button released over the sidebar: the previous or next space,
    /// wrapping as Spaces ▸ Previous/Next Space do (Arc's SidebarView, issue #233). Returns false
    /// for any other button, or one released anywhere else.
    func mouseButtonSwitchesSpace(_ button: Int, _ event: NSEvent) -> Bool {
        guard let offset = MouseButtonSpaceSwitch.offset(buttonNumber: button), isOverSidebar(event) else { return false }
        store.focusSpace(offset: offset, window: windowID)
        return true
    }

    /// Whether `event` is over this window's sidebar, docked or floating, in a window that has
    /// spaces to switch (not a Little Window).
    private func isOverSidebar(_ event: NSEvent) -> Bool {
        let host = shell.sidebarHost
        return (shell.sidebarVisible || shell.floatingSidebar) && event.window != nil && event.window === host.window
            && host.bounds.contains(host.convert(event.locationInWindow, from: nil)) && !isStandalone
    }

    /// Shift + wheel, or a sideways wheel, over the sidebar: past a flick the next or previous
    /// space comes in on the space change's spring, and before the first space the Library
    /// slides in, as a swipe would bring it (Arc 1.171, WheelSpaceSwitch). Returns false for a
    /// wheel the sidebar doesn't take.
    private func wheelSwitchesSpace(_ event: NSEvent) -> Bool {
        guard isOverSidebar(event) else { return false }
        let dx = event.scrollingDeltaX
        // On the Spaces page the cards scroll first; once they can't scroll that way the wheel pages,
        // which leaves the Library when it heads for the next space, and over the rail it leaves at
        // once (Arc).
        if sidebarUI.libraryPage == .spaces, spacesStripCanScroll(event, dx: dx) { return false }
        let step = wheelSpaceSwitch.step(dx: dx, inverted: event.isDirectionInvertedFromDevice, at: event.timestamp)
        guard step != 0 else { return true }
        let order = store.spaceOrder
        // Where the Library is headed, if it is sliding.
        let inLibrary = librarySettleSpring.map { $0.target >= 1 } ?? (sidebarUI.libraryPage != nil)
        switch WheelSpaceSwitch.target(step: step, index: order.firstIndex(of: focusedSpaceID) ?? 0, count: order.count,
                                       inLibrary: inLibrary, libraryAllowed: !shell.floatingSidebar && shell.sidebarVisible) {
        case .space(let i): store.focusSpace(order[i], window: windowID)
        case .openLibrary, .closeLibrary: toggleLibrary()
        case nil: break
        }
        return true
    }

    /// A space swipe of `steps` trackpad samples `dx` apart, 8 ms apart (cra://debug?swipe=).
    func debugSpaceSwipe(dx: CGFloat, steps: Int) {
        beginSpaceSwipe()
        for i in 1...max(1, steps) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(i)) { [weak self] in
                self?.trackSpaceSwipe(by: dx, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(steps + 1)) { [weak self] in self?.endSpaceSwipe() }
    }

    private func trackSpaceSwipe(by dx: CGFloat, at time: TimeInterval) {
        let width = max(1, shell.sidebarWidth)
        swipeTravel += dx
        swipeSamples.append((time, dx))
        swipeSamples.removeAll { time - $0.time > 0.08 }
        if trackLibrarySwipe() { return }
        let index = CGFloat(store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0)
        let first = -index, last = CGFloat(store.spaceOrder.count - 1) - index
        // Content follows the fingers (natural scrolling: fingers left = next space).
        var pages = max(-1, min(1, -swipeTravel / width))
        // Rubber band past either end, with the resistance curve AppKit scroll views use.
        func band(_ x: CGFloat) -> CGFloat { 1 - 1 / (x * 0.55 + 1) }
        if pages < first { pages = first - band(first - pages) * 0.5 }
        if pages > last { pages = last + band(pages - last) * 0.5 }
        sidebarUI.spaceSwipe = pages
        // Dia: performsPageDetentHaptics, a tick each time the nearest page changes.
        let detent = Int(pages.rounded())
        if detent != swipeDetent, detent >= Int(first), detent <= Int(last) {
            swipeDetent = detent
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func endSpaceSwipe() {
        HitchMonitor.mark("swipe-lift")
        if let r = sidebarUI.libraryReveal, librarySwipeFrom != nil { return endLibrarySwipe(r) }
        librarySwipeFrom = nil
        let width = max(1, shell.sidebarWidth)
        let pages = sidebarUI.spaceSwipe
        let span = (swipeSamples.last?.time ?? 0) - (swipeSamples.first?.time ?? 0)
        let moved = swipeSamples.reduce(0) { $0 + $1.dx }
        // Pages per second; a lone sample carries no timing, so treat it as a slow lift.
        let velocity = span > 0.004 ? -moved / CGFloat(span) / width : 0
        let index = store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0
        var step = 0
        if abs(velocity) > 0.8 { step = velocity > 0 ? 1 : -1 } else if abs(pages) > 0.5 { step = pages > 0 ? 1 : -1 }
        if !(0..<store.spaceOrder.count).contains(index + step) { step = 0 }
        let remaining = CGFloat(step) - pages
        sidebarUI.spaceSettleVelocity = abs(remaining) > 0.001 ? Double(max(-4, min(12, velocity / remaining))) : 0
        // The new space becomes the strip's page at once and the swipe returns to rest; the space
        // pager and the window tint spring from where they show to the page in Core Animation
        // (SpacePagerView, PagedGradientView), so a busy main thread doesn't stop the settle.
        if step != 0 {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                // The space first: the strip and the tint read what's left of the swipe
                // against the space shown.
                store.focusSpace(store.spaceOrder[index + step], window: windowID)
                sidebarUI.spaceSwipe = pages - CGFloat(step)
            }
        }
        sidebarUI.spaceSwipe = 0
        // Clicks and shortcuts that switch spaces later start from rest.
        DispatchQueue.main.async { [weak self] in self?.sidebarUI.spaceSettleVelocity = 0 }
    }

    // MARK: Extensions

    private let siteControlCenter = SiteControlCenterPopover()
    /// The space the Site Control Center was opened in.
    private var siteControlCenterSpaceID: UUID?

    /// Screen y of the focused card's toolbar bottom (its top edge when the toolbar is hidden),
    /// and the card's right edge.
    fileprivate func toolbarBottomOnScreen() -> (y: CGFloat, cardMaxX: CGFloat)? {
        guard let window else { return nil }
        let card = shell.focusedCard.map { shell.contentContainer.convert($0.frame, to: nil) }
            ?? shell.convert(shell.contentContainer.frame, to: nil)
        let onScreen = window.convertToScreen(card)
        let bar = shell.focusedCard?.toolbarHeight ?? CraMetrics.toolbarHeight
        return (onScreen.maxY - (shell.panesShowBars ? bar : 0), onScreen.maxX)
    }

    /// Where a popup from a URL-bar button hangs: under the toolbar, or, with the toolbar
    /// hidden, under the sidebar's URL pill (also while the sidebar floats in its panel).
    private func urlBarBottomOnScreen() -> CGFloat? {
        guard !store.settings.showToolbar else { return toolbarBottomOnScreen()?.y }
        let host = shell.sidebarHost
        guard let w = host.window else { return nil }
        let rect = w.convertToScreen(host.convert(host.bounds, to: nil))
        // SidebarTopBar: title area, 2 pt, then the 36 pt pill.
        return rect.maxY - CraMetrics.titleAreaHeight - 2 - 36
    }

    /// Whether a button (screen rect) sits in a bar above a page rather than in the sidebar.
    private func isInPaneBar(_ button: NSRect) -> Bool {
        guard shell.panesShowBars, let window else { return false }
        let mid = NSPoint(x: button.midX, y: button.midY)
        return shell.paneCards.contains { card in
            window.convertToScreen(card.toolbarHost.convert(card.toolbarHost.bounds, to: nil)).contains(mid)
        }
    }

    /// Under the extension's pinned toolbar button when the toolbar shows one, else under the
    /// toolbar at the card's right end.
    fileprivate func extensionPopupAnchor(_ id: String) -> NSPoint? {
        guard let bar = toolbarBottomOnScreen() else { return nil }
        if shell.panesShowBars, let button = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.extensionButtonFrameOnScreen(id) {
            return NSPoint(x: button.maxX, y: bar.y)
        }
        return NSPoint(x: bar.cardMaxX - 8, y: bar.y)
    }

    /// Runs an extension's toolbar action on the focused page, like Arc's toolbar buttons and
    /// Dia's Extensions menu. The popup hangs under the toolbar, its right edge at `buttonRightX`
    /// (screen x of the clicked button; nil = the extension's toolbar button or the card's right end),
    /// its top at `buttonBottomY` (nil = under the URL bar).
    func runExtensionAction(_ id: String, buttonRightX: CGFloat? = nil, buttonBottomY: CGFloat? = nil) {
        let bar = toolbarBottomOnScreen()
        let browser = currentBrowser
        let anchor = bar.map { bar in
            // Under the URL bar, or under a grid pin lower down.
            buttonRightX.map { x in NSPoint(x: x, y: buttonBottomY ?? urlBarBottomOnScreen() ?? bar.y) } ?? extensionPopupAnchor(id) ?? NSPoint(x: bar.cardMaxX - 8, y: bar.y)
        }
        let available = profileExtensions
        switch ExtensionLaunch.decide(id, available: available, hasPage: bar != nil && browser != nil) {
        case .nothing: return
        case .runAction:
            guard let browser, let anchor else { return }
            let inDefaultProfile = profileDirectoryName == "Default"
            Task {
                if await !ExtensionActions.shared.run(id, on: browser, anchor: anchor, inDefaultProfile: inDefaultProfile),
                   let e = available.first(where: { $0.id == id }) {
                    self.perform(ExtensionLaunch.fallback(e), anchor: anchor)
                }
            }
        case let fallback: perform(fallback, anchor: anchor)
        }
    }

    /// The extensions installed in the focused page's profile, turned on or not.
    private var profileExtensions: [ExtensionLaunch.Extension] {
        let profile = profileDirectoryName
        return ExtensionStore.shared.entries.filter { $0.isInstalled(inProfile: profile) }.map {
            ExtensionLaunch.Extension(id: $0.extensionID, popupPath: $0.popupPath, optionsPath: $0.optionsPath, enabled: $0.isEnabled(inProfile: profile))
        }
    }

    /// The Chromium profile folder the focused page loads in.
    var profileDirectoryName: String { selectedTabID.map(store.profileDirectoryName(item:)) ?? store.profileDirectoryName(space: focusedSpaceID) }

    /// The extensions installed in the focused page's profile.
    var extensionEntries: [ExtensionStore.Entry] { ExtensionStore.shared.entries(inProfile: profileDirectoryName) }

    /// The pinned-extension button under the pointer (screen rect), in the toolbar or the
    /// sidebar's grid (also in the floating sidebar's panel), so a popup hangs from the same
    /// place wherever the button was clicked (GitHub #8).
    private static func extensionButtonUnderPointer() -> NSRect? {
        buttonFrameUnderPointer { $0 is ToolbarGlyphButton }
    }

    /// The button under the pointer (screen rect): the one just clicked.
    private static func buttonFrameUnderPointer(_ isButton: (NSView) -> Bool) -> NSRect? {
        let mouse = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        guard let w = NSApp.window(withWindowNumber: number), let content = w.contentView else { return nil }
        let p = w.convertPoint(fromScreen: mouse)
        var v = content.hitTest(content.superview?.convert(p, from: nil) ?? p)
        while let view = v, !isButton(view) { v = view.superview }
        return v.map { w.convertToScreen($0.convert($0.bounds, to: nil)) }
    }

    /// No page for Chrome's popup to attach to (no tab open, no DevTools pipe, a page it
    /// cannot reach): ExtensionLaunch picks the popup page in a popup-sized window under the
    /// button, else the options page, else Chrome's details page for the extension.
    private func perform(_ launch: ExtensionLaunch, anchor: NSPoint?) {
        switch launch {
        case .nothing, .runAction: break
        case .popupWindow(let url):
            let fallback = window.map { NSPoint(x: $0.frame.maxX - 16, y: $0.frame.maxY - CraMetrics.toolbarHeight) } ?? .zero
            ExtensionPageWindow.open(url: url, anchor: anchor ?? fallback, app: app)
        case .openTab(let url):
            app.openExtensionPage(url, window: windowID)
        }
    }

    func debugSiteControls() { showToolbarExtensionsMenu() }

    func debugTabSwitcher() {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tabSwitcher.isDark = dark
        tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
        tabSwitcher.palette = theme.palette
        tabSwitcher.debugOpen(openRecentTabs(limit: TabSwitcherMetrics.maxItems).compactMap { id in
            guard let it = store.item(id), let tab = it.tab else { return nil }
            return TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot)
        })
    }

    /// Selects a split pane and brings the shell along at once (refresh otherwise runs on the next
    /// turn), so the focused card, the visible page and the profile are that pane's when the
    /// caller reads them.
    private func focusPaneNow(_ id: UUID) {
        guard selectedTabID != id else { return }
        store.selectTab(id, window: windowID)
        refresh()
    }

    /// Arc's sliders button (toolbar and URL pill): the Site Control Center, hung under the
    /// button that was clicked (buttons are 32 × 28), not wherever the pointer is in it.
    /// The Site Control Center as if its sliders button was clicked, wherever the request came from
    /// (the protected media toast's Why?): under the toolbar's button, else under the sidebar's URL
    /// field at its right end, where that button sits. The arrow shows where to find it next time.
    func showSiteControlsFromTheirButton() {
        if let button = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.siteControlsButtonFrameOnScreen() {
            return showToolbarExtensionsMenu(from: button, inToolbar: true)
        }
        guard let button = (shell.sidebarHost as? SidebarView)?.siteControlsButtonFrameOnScreen else { return showToolbarExtensionsMenu() }
        showToolbarExtensionsMenu(from: button, inToolbar: false)
    }

    private func showToolbarExtensionsMenu(from anchor: NSRect? = nil, inToolbar: Bool = false) {
        // Decided now, while the click is the current event: the page is asked a question below.
        if siteControlCenter.closesInstead() { return }
        // A split pane's bar has the sliders even with the toolbar hidden: hang under that bar then.
        let pressed = anchor.map { inToolbar ? $0 : nil } ?? Self.buttonFrameUnderPointer { $0 is ToolbarGlyphButton }
        guard let window, let content = window.contentView,
              let y = pressed != nil && shell.panesShowBars ? toolbarBottomOnScreen()?.y : urlBarBottomOnScreen() else { return }
        ExtensionStore.shared.reload()
        let midX = (anchor ?? pressed ?? Self.buttonFrameUnderPointer { $0 is SidebarGlyphButton })?.midX ?? NSEvent.mouseLocation.x
        // Arc's popover overlaps the bar by 4 pt (popover top 71 under a bar ending at 75).
        let onScreen = NSRect(x: midX - 16, y: y + 4, width: 32, height: 28)
        let rect = content.convert(window.convertFromScreen(onScreen), from: nil)
        let url = selectedTabID.flatMap { store.item($0)?.tab?.url } ?? ""
        var actions = SiteControlCenterActions()
        actions.share = { [weak self] anchor in self?.shareCurrentPage(from: anchor) }
        actions.copyURL = { [weak self] in self?.app.perform("copyURL") }
        actions.capture = { [weak self] in self?.capturePage() }
        actions.captureFullPage = { [weak self] in self?.captureFullPage() }
        actions.runExtension = { [weak self] id in self?.runExtensionAction(id) }
        actions.addExtension = { [weak self] in self?.openTab("https://chromewebstore.google.com/category/extensions") }
        actions.manageExtensions = { [weak self] in self?.openTab("chrome://extensions") }
        actions.clearCache = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: false) }
        actions.clearCookies = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: true) }
        let ssl = currentBrowser?.sslStatus()
        let secure = ConnectionSecurity.isSecure(url: url, status: ssl.map {
            ConnectionSecurity.Status(secureConnection: $0.secureConnection, certStatus: $0.certStatus, contentStatus: $0.contentStatus)
        })
        if ssl?.certificates.isEmpty == false { actions.showCertificate = { [weak self] in self?.showCertificate() } }
        actions.siteSettings = { [weak self] in
            guard let origin = URL(string: url).flatMap({ u in u.host.map { "\(u.scheme ?? "https")://\($0)" } }) else { return }
            self?.openTab("chrome://settings/content/siteDetails?site=" + (origin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? origin))
        }
        actions.learnAboutProtectedMedia = { [weak self] in self?.openTab(Self.protectedMediaHelp) }
        actions.chooseSafariEngine = { [weak self] on in self?.chooseSafariEngine(on, for: url) }
        siteControlCenterSpaceID = focusedSpaceID
        let show = { [weak self] (safariEngine: Bool?) in
            guard let self, let window = self.window, window.isVisible else { return }
            self.siteControlCenter.show(relativeTo: rect, of: content, url: url, secure: secure, dark: SystemAppearance.shared.isDark,
                                        profile: self.profileDirectoryName, tab: self.selectedTabID,
                                        protectedMedia: self.browsers.visibleTabID.flatMap { self.sidebarUI.navState(for: $0).protectedMedia },
                                        safariEngine: safariEngine, toggleChecked: true, store: self.store, actions: actions)
        }
        // The Safari's Engine switch: on for a WebKit page; for a Chromium page only once it asked
        // for Widevine (PageScript's `drm`), else no switch. Asked in Cra's world; a page that
        // doesn't answer within 0.3 s opens without it.
        guard let b = currentBrowser, url.hasPrefix("http") else { return show(nil) }
        if b is WebKitBrowser { return show(true) }
        var shown = false
        let once = { (value: Bool?) in if !shown { shown = true; show(value) } }
        b.evaluate(inIsolatedWorld: PageScript.world, params: #"{"expression":"window.__cra?.drm === true","returnByValue":true}"#) { result, _ in
            let drm = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { $0["result"] as? [String: Any] }?["value"] as? Bool == true
            DispatchQueue.main.async { once(drm ? false : nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { once(nil) }
    }

    func debugChooseSafariEngine(_ on: Bool) {
        if let url = currentBrowser?.currentURL { chooseSafariEngine(on, for: url) }
    }

    /// The Site Control Center's Safari's Engine switch: the site plays in WebKit (or Chromium)
    /// from now on, and the focused page opens again there. Choosing it is knowing about it: no toast.
    private func chooseSafariEngine(_ on: Bool, for url: String) {
        PageEngines.choose(on ? .webKit : .chromium, for: url)
        if on, let service = PageEngines.sites.serviceName(for: url) { PageEngines.told(service) }
        if let id = browsers.visibleTabID { browsers.reopenInItsEngine(id) }
    }

    /// The help centre's page on why Spotify, Netflix and the others play in Safari's engine.
    static let protectedMediaHelp = SiteLinks.tagged("https://crabrowser.app/help/protected-media", from: .protectedMedia)

    func debugSiteControlsShown() -> Bool { siteControlCenter.isShown
    }

    /// Scenario hooks (#226): the sidebar's URL field hovered, its buttons logged as
    /// "url field: copyURL extensions" ("url field: none" while the toolbar has the address).
    func debugURLFieldHover(_ on: Bool) {
        let items = (shell.sidebarHost as? SidebarView)?.debugURLFieldHover(on)
        CraLog.note("url field: " + (items.map { $0.map(Self.debugName).joined(separator: " ") } ?? "none"))
    }

    /// A press on the URL field's button by name ("siteControls", "copyURL"), then whether the
    /// Site Control Center is open once it had time to (it waits up to 0.3 s on the page).
    func debugURLFieldPress(_ name: String) {
        let item: ToolbarComposition.Item = name == "copyURL" ? .copyURL : .extensions
        let pressed = (shell.sidebarHost as? SidebarView)?.debugURLFieldPress(item) == true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            CraLog.note("url field press \(name): pressed \(pressed), site control center \(self?.siteControlCenter.isShown == true ? "shown" : "not shown")")
        }
    }

    private static func debugName(_ item: ToolbarComposition.Item) -> String {
        switch item {
        case .pinnedExtension(let id): return "pin:" + id
        case .copyURL: return "copyURL"
        case .extensions: return "siteControls"
        default: return String(describing: item)
        }
    }

    private func openTab(_ url: String) {
        store.createTab(url: url, select: true, window: windowID)
        showWindow(nil)
    }

    /// The share list over the Site Control Center's Share button; the control center stays
    /// open behind it, as in Arc.
    private func shareCurrentPage(from anchor: NSView) {
        guard let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }).flatMap(URL.init(string:)) else { return }
        siteControlCenter.holdOpen(true)
        SharePicker.shared.show(url, relativeTo: anchor) { [weak self] chose in
            self?.siteControlCenter.holdOpen(false)
            // The service's own window (Mail, AirDrop) takes over.
            if chose { self?.siteControlCenter.close() }
        }
    }

    /// The lock in the Site Control Center: the certificate of the page on screen.
    private func showCertificate() {
        guard let b = currentBrowser, let window else { return }
        let host = URL(string: b.currentURL)?.host ?? ""
        guard let certificates = b.sslStatus()?.certificates, !certificates.isEmpty else { return }
        CertificateWindow.show(certificates, host: host, over: window)
    }

    /// Arc's "Capture the full page": the whole document, beyond the viewport, as a PNG.
    // MARK: Boosts

    /// Arc's New Boost: the open site's boost (made if it has none) in the editor beside the page.
    func openBoostEditor() {
        guard let window, let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }),
              let boost = BoostStore.shared.boostForSite(of: url) else { showToast("Boosts Work on Websites"); return }
        BoostEditorController.shared.open(boost, over: window, page: .init(
            zap: { [weak self] on in self?.setZapping(on) },
            pick: { [weak self] on in self?.setPicking(on) },
            toggleDevTools: { [weak self] in self?.browsers.runDevTools(.toggle) },
            devToolsOpen: { [weak self] in self?.browsers.visibleTabHasDevTools ?? false },
            reload: { [weak self] in self?.currentBrowser?.reload() }))
    }

    /// The code panel's eyedropper (BoostPicker): the page outlines the element under the pointer
    /// and the ones like it, and holds a click; Cra polls for it and offers Arc's menu there. The
    /// poll puts the picker back after a navigation.
    /// Testing without the pointer (cra://debug?boostPick=1|0|copyThis|copyRelated|zapRelated):
    /// on (answering the menu with that action) or off.
    func debugPick(_ value: String) {
        pickAnswer = BoostPicker.Action(rawValue: value)
        setPicking(value != "0")
    }

    private func setPicking(_ on: Bool) {
        pickTimer?.invalidate()
        pickTimer = nil
        pickBrowser?.executeJavaScript(BoostPicker.stopExpression)
        pickBrowser = nil
        guard on, let b = currentBrowser else { return }
        pickBrowser = b
        b.executeJavaScript(BoostPicker.script)
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollPick() } }
        RunLoop.main.add(t, forMode: .common)
        pickTimer = t
    }

    private func pollPick() {
        guard let b = pickBrowser else { return }
        guard b === currentBrowser else { setPicking(false); BoostEditorController.shared.stopPicking(); return }
        let expression = BoostPicker.script + ";" + BoostPicker.takeExpression
        guard let data = try? JSONSerialization.data(withJSONObject: ["expression": expression, "returnByValue": true]),
              let params = String(data: data, encoding: .utf8) else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: params) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                guard let self, let b, b === self.pickBrowser,
                      let pick = BoostPicker.parse((o?["result"] as? [String: Any])?["value"] as? String ?? "") else { return }
                self.offerPick(pick, on: b)
            }
        }
    }

    /// Arc's menu after a click with the picker: copy this element's selector, or the related
    /// ones', or zap them all.
    private func offerPick(_ pick: BoostPicker.Pick, on b: CraBrowser) {
        CraLog.note("boost pick this=\(pick.this) related=\(pick.related) (\(pick.relatedCount))")
        defer { b.executeJavaScript(BoostPicker.resumeExpression) }
        if let answer = pickAnswer { runPick(answer, pick); return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in BoostPicker.Action.allCases {
            let item = BlockMenuItem(title: action.title) { [weak self] in self?.runPick(action, pick) }
            item.isEnabled = action.isEnabled(for: pick)
            menu.addItem(item)
        }
        let view = b.containerView
        let p = pick.point(inViewWidth: view.bounds.width)
        menu.popUp(positioning: nil, at: NSPoint(x: p.x, y: view.isFlipped ? p.y : view.bounds.height - p.y), in: view)
    }

    private func runPick(_ action: BoostPicker.Action, _ pick: BoostPicker.Pick) {
        guard action.isEnabled(for: pick) else { return }
        let selector = action.selector(for: pick)
        switch action {
        case .copyThis, .copyRelated:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selector, forType: .string)
            CraLog.note("boost pick copied \(selector)")
        case .zapRelated:
            BoostEditorController.shared.addZapped([selector])
        }
    }

    /// Zap: the page outlines what's under the pointer, and a click hides it and keeps a selector
    /// for it; when Zap ends the selectors go into the boost.
    /// Testing without the pointer (cra://debug?boostZap=1|0): Zap on or off, as its button does.
    func debugZap(_ on: Bool) { setZapping(on) }

    private func setZapping(_ on: Bool) {
        guard let b = currentBrowser else { return }
        if on { b.executeJavaScript(Self.zapScript); return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"(()=>{const z=window.__craZap;if(!z)return '[]';z.stop();return JSON.stringify(z.hidden)})()","returnByValue":true}"#) { result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = (o?["result"] as? [String: Any])?["value"] as? String ?? "[]"
                let selectors = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String]) ?? []
                BoostEditorController.shared.addZapped(selectors)
            }
        }
    }

    private var pickTimer: Timer?
    private weak var pickBrowser: CraBrowser?
    private var pickAnswer: BoostPicker.Action?

    static let zapScript = """
    (()=>{if(window.__craZap)return;const hidden=[];let over=null;
    const sel=e=>{if(e.id)return '#'+CSS.escape(e.id);const p=[];for(let n=e;n&&n.nodeType===1&&n!==document.body&&p.length<5;n=n.parentElement){
    if(n.id){p.unshift('#'+CSS.escape(n.id));break}let i=1;for(let s=n.previousElementSibling;s;s=s.previousElementSibling)if(s.tagName===n.tagName)i++;
    p.unshift(n.tagName.toLowerCase()+':nth-of-type('+i+')')}return (p[0]&&p[0][0]==='#'?'':'body > ')+p.join(' > ')};
    const mark=e=>{if(over)over.style.outline=over.__craOutline||'';over=e;if(e){e.__craOutline=e.style.outline;e.style.outline='2px solid #ff3b30'}};
    const page=t=>t===document.body||t===document.documentElement;
    const move=ev=>mark(page(ev.target)?null:ev.target);
    const click=ev=>{ev.preventDefault();ev.stopPropagation();const t=ev.target;if(page(t))return;mark(null);hidden.push(sel(t));t.style.display='none'};
    document.addEventListener('mouseover',move,true);document.addEventListener('click',click,true);
    window.__craZap={hidden,stop(){document.removeEventListener('mouseover',move,true);document.removeEventListener('click',click,true);mark(null);delete window.__craZap}}})()
    """

    // MARK: Arc parity (docs/arc-parity.md)

    /// Arc's Window ▸ Stay On Top: the window floats over other apps' windows.
    var staysOnTop: Bool { window?.level == .floating }
    func toggleStayOnTop() { window?.level = staysOnTop ? .normal : .floating }

    /// Arc's Reveal Tab in Sidebar / Reveal Current Tab (⌃Space): the sidebar comes out with the
    /// open tab's folders and pinned section open, and scrolls to it.
    func revealSelectedTab() {
        guard let id = selectedTabID else { return }
        store.revealInSidebar(store.splitContaining(id)?.id ?? id)
        if sidebarUI.libraryPage != nil { closeLibrary() }
        if !sidebarVisible { toggleSidebar() }
        let ui = sidebarUI, space = focusedSpaceID
        DispatchQueue.main.async { SpaceListView.jumpToSelected(for: ui, space: space) }
    }

    /// Arc's Switch to Split View 1–4 (⌃⇧1…4): the n-th pane of the open split.
    func selectSplitPane(_ n: Int) {
        guard let current = selectedTabID else { return }
        let panes = store.paneTabIDs(for: current)
        guard panes.count > 1, n >= 1, n <= panes.count else { return }
        store.selectTab(panes[n - 1], window: windowID)
    }

    /// Chrome's extensions page, as the Site Control Center's Manage Extensions… opens it.
    func openExtensionsPage() { openTab("chrome://extensions") }

    /// Arc's Open Extensions (⌘E): the Site Control Center, as if its sliders were clicked.
    func openSiteControls() { showSiteControlsFromTheirButton() }

    /// Arc's Tabs ▸ Reset all tabs in this Space: every pinned tab away from its page goes back.
    func resetAllPinnedTabs() {
        guard !isStandalone else { return }
        let space = store.focusedSpace(window: windowID)
        for t in store.tabs(under: space.pinnedContainerID) where t.tab.map({ $0.url != $0.savedURL }) == true {
            resetPinnedTab(t.id)
        }
    }

    /// Arc's Edit ▸ Copy URL as Quote (⌃⇧⌘C): the page's selection in quotes with a link that
    /// scrolls to it (CleanURL.quote; Arc's own link goes through arc.net).
    func copyURLAsQuote() {
        guard let b = currentBrowser, let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }) else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self] result, _ in
            MainActor.assumeIsolated {
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = (value?["result"] as? [String: Any])?["value"] as? String ?? ""
                guard let quote = CleanURL.quote(text, url: url) else { self?.showToast("Select Text to Copy as a Quote"); return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(quote, forType: .string)
                self?.showToast("Copied URL as Quote")
            }
        }
    }

    /// Arc's File ▸ Save Page As (⇧⌘S): Chrome's two formats, a single-file web archive or the
    /// page's HTML.
    func savePageAs() {
        guard let b = currentBrowser, let window, let tab = selectedTabID.flatMap({ store.item($0) }) else { return }
        let panel = NSSavePanel()
        let format = SavePageFormat(panel: panel)
        panel.accessoryView = format.view
        let base = tab.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = (base.isEmpty ? "Page" : base) + ".mhtml"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            let single = format.singleFile
            let (method, params) = single
                ? ("Page.captureSnapshot", #"{"format":"mhtml"}"#)
                : ("Runtime.evaluate", #"{"expression":"'<!DOCTYPE html>\n'+document.documentElement.outerHTML","returnByValue":true}"#)
            b.sendDevToolsMethod(method, params: params) { result, error in
                MainActor.assumeIsolated {
                    let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    let text = single ? o?["data"] as? String : (o?["result"] as? [String: Any])?["value"] as? String
                    guard let text, (try? Data(text.utf8).write(to: dest, options: .atomic)) != nil else {
                        NSLog("Cra: save page failed: %@", error ?? "no data")
                        self?.showToast("Couldn’t Save the Page")
                        return
                    }
                    self?.showToast("Page Saved")
                }
            }
        }
    }

    func captureFullPage() {
        captureOverlay?.close()
        guard let b = currentBrowser else { return }
        showToast("Capture in Progress")
        // Both completions come on the main queue.
        b.sendDevToolsMethod("Page.getLayoutMetrics", params: "{}") { [weak self] result, error in
            guard let result, let m = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                  let size = (m["cssContentSize"] ?? m["contentSize"]) as? [String: Any],
                  let w = size["width"] as? Double, let h = size["height"] as? Double else {
                MainActor.assumeIsolated { self?.finishCapture(nil, error: error) }
                return
            }
            let params = #"{"format":"png","captureBeyondViewport":true,"clip":{"x":0,"y":0,"width":\#(w),"height":\#(min(h, 16384)),"scale":1}}"#
            b.sendDevToolsMethod("Page.captureScreenshot", params: params) { shot, error in
                MainActor.assumeIsolated { self?.finishCapture(shot, error: error) }
            }
        }
    }

    /// Arc's File ▸ Capture in Portrait Mode: the page laid out at a phone's width (390 × 844 pt,
    /// the layout a site gives an iPhone 15) and captured at 3x, then put back as it was.
    func capturePortrait() {
        captureOverlay?.close()
        guard let b = currentBrowser else { return }
        showToast("Capture in Progress")
        let metrics = #"{"width":390,"height":844,"deviceScaleFactor":3,"mobile":true}"#
        b.sendDevToolsMethod("Emulation.setDeviceMetricsOverride", params: metrics) { [weak self] _, error in
            MainActor.assumeIsolated {
                guard error == nil else { self?.finishCapture(nil, error: error); return }
                // A layout pass and a paint at the new width before the shot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png"}"#) { shot, error in
                        b.sendDevToolsMethod("Emulation.clearDeviceMetricsOverride", params: "{}") { _, _ in }
                        MainActor.assumeIsolated { self?.finishCapture(shot, error: error) }
                    }
                }
            }
        }
    }

    /// As Arc does with a capture: the image goes on the clipboard with the shutter sound, and
    /// the toast's Save puts it in a file. Finder stays where it is (GitHub #90).
    private func finishCapture(_ shot: String?, error: String?) {
        guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
              let b64 = o["data"] as? String, let png = Data(base64Encoded: b64), NSImage(data: png) != nil else {
            NSLog("Cra: capture failed: %@", error ?? "no data")
            showToast("Capture Failed")
            return
        }
        copyCapture(png)
        CaptureSound.play()
        showToast("Screenshot Copied to Clipboard", action: ShinyToast.Action(title: "Save") { [weak self] in self?.saveCapture(png) })
    }

    /// The toast's Save: Arc's "Save Capture Image" panel, in Downloads.
    private func saveCapture(_ png: Data) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "Save Capture Image"
        panel.nameFieldStringValue = Self.captureFileName()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                NSLog("Cra: saving a capture failed: %@", error.localizedDescription)
                self?.showToast("Failed to Save Capture")
            }
        }
    }

    // MARK: Tab switcher

    /// ⌃Tab / ⌃⇧Tab: Arc's switcher over the space's recent tabs.
    func cycleRecentTabs(_ delta: Int, event: NSEvent?) {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !tabSwitcher.isOpen {
            tabSwitcher.isDark = dark
            tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
            tabSwitcher.palette = theme.palette
        }
        tabSwitcher.cycle(delta, event: event) {
            openRecentTabs(limit: TabSwitcherMetrics.maxItems).compactMap { id in
                guard let it = store.item(id), let tab = it.tab else { return nil }
                return TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot)
            }
        }
        // The page on screen is the freshest thumbnail there is: retake it for its card.
        guard tabSwitcher.isOpen, let current = browsers.visibleTabID else { return }
        browsers.captureSnapshot(current) { [weak self] in
            guard let self else { return }
            self.tabSwitcher.updateSnapshot(current, self.browsers.runtime(for: current)?.snapshot)
        }
    }

    /// Centred on the whole window, like Arc (sidebar included).
    private func showTabSwitcherPanel() {
        guard let window else { return }
        let size = TabSwitcherMetrics.windowSize(count: tabSwitcher.items.count)
        let wf = window.frame
        tabSwitcherPanel.setFrame(NSRect(x: (wf.midX - size.width / 2).rounded(.down), y: (wf.midY - size.height / 2).rounded(.down),
                                         width: size.width, height: size.height), display: true)
        if tabSwitcherPanel.parent !== window { window.addChildWindow(tabSwitcherPanel, ordered: .above) }
        tabSwitcherPanel.orderFront(nil)
    }

    private func hideTabSwitcherPanel() {
        if tabSwitcherPanel.parent != nil { window?.removeChildWindow(tabSwitcherPanel) }
        tabSwitcherPanel.orderOut(nil)
    }

    // MARK: Command bar

    func openCommandBar(_ mode: CommandBarMode) {
        guard let window else { return }
        // A click on the address that closed the bar leaves it closed (Arc, GitHub #88).
        if mode == .editURL, NSApp.currentEvent?.type == .leftMouseUp,
           commandBarClosingClick.isClosingClick(lastMouseDown: ProcessInfo.processInfo.systemUptime
                - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)) {
            return
        }
        // An empty split pane gets Arc's "Search or Enter URL…" bar; the result fills the pane.
        let fillingEmptyPane = selectedTab?.isEmptyTab == true
        let prefill = mode == .editURL && !fillingEmptyPane ? selectedTab?.tab?.url : nil
        let effectiveMode: CommandBarMode = (mode == .editURL && (selectedTab == nil || fillingEmptyPane)) ? .newTab : mode
        commandBar.highlight = focusedSpace.theme.palette.commandHighlight
        commandBar.focusedSpaceID = focusedSpaceID
        commandBar.open(mode: effectiveMode, prefill: prefill)
        // Arc draws the New Tab row as the active one while the bar makes a new tab; the
        // sidebar scrolls to it (SpaceListView.revealActiveRow).
        sidebarUI.newTabPlaceholderActive = effectiveMode == .newTab && !fillingEmptyPane
        // Always centred in the window, also when opened from the toolbar.
        commandBar.attached = false
        commandBar.panelWidth = min(CraMetrics.commandBarWidth, window.frame.width - 80)
        // The panel keeps no appearance of its own, so it follows macOS like the menus, sheets and
        // popovers (#171): Arc's bar is dark over a light space while the Mac runs dark (#187).
        positionCommandPanel()
        if commandPanel.parent == nil { window.addChildWindow(commandPanel, ordered: .above) }
        commandBarOpenedAt = Date()
        if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
        // Key immediately (typing never waits); CommandBarView fades itself in.
        commandPanel.makeKeyAndOrderFront(nil)
        observeCommandBar()
    }

    private func observeCommandBar() {
        guard !commandObserving else { return }
        commandObserving = true
        withObservationTracking {
            _ = commandBar.result.items.count
            _ = commandBar.isOpen
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.commandObserving = false
                guard let self, self.commandBar.isOpen else { return }
                self.positionCommandPanel()
                self.observeCommandBar()
            }
        }
    }

    private func positionCommandPanel() {
        guard let window else { return }
        let rows = commandBar.result.items.count
        let h = CommandBarView.height(forRows: rows)
        let w = commandBar.panelWidth
        let wf = window.frame
        // The field stays put and rows hang below it: centred as a full bar would be, so a
        // shorter list while typing doesn't move what you type into.
        let top = wf.midY + CommandBarView.height(forRows: SuggestionEngine.maxRows) / 2 + 40
        commandPanel.setFrame(NSRect(x: wf.midX - w / 2, y: top - h, width: w, height: h), display: true)
    }

    private func hideCommandPanel() {
        sidebarUI.newTabPlaceholderActive = false
        if commandPanel.parent != nil { window?.removeChildWindow(commandPanel) }
        let panel = commandPanel!
        // Let CommandBarView's fade-out (0.08 s) play before the panel goes away.
        panel.orderOut(nil)
        window?.makeKeyAndOrderFront(nil)
        currentBrowser?.setFocused(true)
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            let fillsEmptyPane = selectedTab?.isEmptyTab == true
            // A pinned tab keeps to its host: another host's address opens a Today tab (Arc).
            let leavesPinned = !fillsEmptyPane && selectedTabID.map(store.isPinned) == true
                && PinnedNavigation.typedURLOpensNewTab(url, from: selectedTab?.tab?.url ?? "")
            if mode == .editURL || fillsEmptyPane, selectedTabID != nil, !leavesPinned {
                loadInSelectedTab(url)
            } else {
                store.createTab(url: url, window: windowID)
            }
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed))
            return
        }
        switch s.kind {
        case .switchToTab(let id):
            store.recordQuerySelection(query: query, url: s.url ?? "")
            store.selectTab(id, window: windowID)
        case .archived(let id):
            store.restoreArchived(id)
        case .navigate:
            let url = typed == commandBar.query ? (s.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed)
            open(url)
        case .search:
            open(s.url ?? commandBar.engine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            store.focusSpace(id, window: windowID)
        case .moveToSpace(let id):
            if let t = selectedTabID { store.moveTabAndFollow(t, toSpace: id, window: windowID) }
        case .moveToFolder(let id):
            if let t = selectedTabID { store.moveItem(t, to: id, index: nil) }
        }
    }

    /// ⌘Return in the bar (Arc): the row's page in a new background tab, the current tab staying
    /// in front; an open tab's row opens its address again rather than switching (GitHub #85).
    private func openInBackground(_ s: Suggestion?, typed: String) -> Bool {
        guard let url = pageURL(s, typed: typed) else { return false }
        store.recordQuerySelection(query: commandBar.query, url: url)
        let tab = store.createTab(url: url, select: false, window: windowID)
        store.markUnread(tab.id, false)  // Arc saves these read, unlike a link opened in the background
        // Creating the page takes key from the bar; it takes key back and stays open, as while
        // opening (windowDidResignKey).
        commandBarOpenedAt = Date()
        browsers.ensureRuntime(for: tab.id)  // load it so the title and favicon fill in
        // With the sidebar out the new row shows there; hidden, Arc says so in a toast.
        if !sidebarVisible { showToast("New Tab Created") }
        return true
    }

    /// ⌥Return in the bar: the row opens as a split pane beside the current tab instead of in its
    /// place, an open tab of this space joining the split as it is. False takes it as Return: no
    /// tab to split, an empty one (the row fills it), a tab in another space, a row with no page.
    private func openInSplit(_ s: Suggestion?, typed: String) -> Bool {
        guard let current = selectedTabID, store.item(current)?.isEmptyTab == false else { return false }
        if case .switchToTab(let id)? = s?.kind {
            guard id != current, store.spaceID(ofItem: id) == store.spaceID(ofItem: current) else { return false }
            if store.paneTabIDs(for: current).contains(id) {
                store.selectTab(id, window: windowID)
                return true
            }
        }
        guard store.paneTabIDs(for: current).count < 4 else {
            showToast("Cannot Add New Pane")
            return true
        }
        if case .switchToTab(let id)? = s?.kind {
            store.recordQuerySelection(query: commandBar.query, url: s?.url ?? "")
            let split = store.splitContaining(current).map { sp in store.addToSplit(sp.id, tabID: id, at: nil); return store.item(sp.id) }
                ?? store.createSplit(with: [current, id], at: current)
            store.selectTab(split.flatMap { store.paneID(for: id, in: $0) } ?? id, window: windowID)
            return true
        }
        guard let url = pageURL(s, typed: typed) else { return false }
        store.recordQuerySelection(query: commandBar.query, url: url)
        guard store.addEmptyPane(nextTo: current, url: url) != nil else { return false }
        refresh()
        return true
    }

    /// The page a row opens anew (⌘Return, ⌥Return), nil for rows that open none.
    private func pageURL(_ s: Suggestion?, typed: String) -> String? {
        let url: String?
        switch s?.kind {
        case nil:
            url = typed.isEmpty ? nil : SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed)
        case .navigate?:
            url = typed == commandBar.query ? (s?.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed)
        case .search?:
            url = s?.url ?? commandBar.engine.searchURL(typed)
        case .switchToTab?, .archived?, .history?, .topDomain?:
            url = s?.url
        default:
            url = nil
        }
        return url?.isEmpty == false ? url : nil
    }

    /// The first time a service plays in a WebKit page (docs/protected-media.md): "Spotify plays
    /// with Safari's engine", with Why? (the Site Control Center says what that means). It stays
    /// until its ✕ is pressed, Why? included, so Cra knows it was seen; only then is the service told
    /// for good. Shown once a session per service: one left open shows again next launch.
    private func tellAboutProtectedMedia(_ service: String) {
        guard !PageEngines.wasTold(service), !offeredProtectedMedia.contains(service), window?.isVisible == true else { return }
        offeredProtectedMedia.insert(service)
        let told = { PageEngines.told(service) }
        // A moment after the page shows, so it isn't lost in the tab switch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let window = self.window, let id = self.browsers.visibleTabID,
                  self.sidebarUI.navState(for: id).protectedMedia == service else {
                self?.offeredProtectedMedia.remove(service)
                return
            }
            let page = self.shell.webContainer.convert(self.shell.webContainer.bounds, to: nil)
            self.toast.show("\(service) plays with Safari's engine",
                            action: ShinyToast.Action(title: "Why?") { [weak self] in self?.showSiteControlsFromTheirButton() },
                            page: page, in: window, theme: self.focusedSpace.theme, onClose: told)
        }
    }

    /// Services whose toast was offered this session (they show once a session until answered).
    private var offeredProtectedMedia: Set<String> = []

    /// Arc's toast at the top right of the page (ShinyToast): Cra's confirmations.
    func showToast(_ text: String, action: ShinyToast.Action? = nil) {
        guard let window else { return }
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        toast.show(text, action: action, page: page, in: window, theme: focusedSpace.theme)
    }

    /// Navigate the focused tab (an empty split pane gets its first page here).
    func loadInSelectedTab(_ url: String) {
        guard let id = selectedTabID else { return }
        let wasEmpty = store.item(id)?.isEmptyTab == true
        store.updateTab(id, url: url)
        if let rt = browsers.ensureRuntime(for: id), !wasEmpty { rt.browser.loadURL(url) }
        refresh()
        browsers.show(store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID), focused: id, focus: true)
    }

    // MARK: Find

    func showFindBar() {
        overlay.findVisible = true
        overlay.findFocusToken += 1
        shell.findVisible = true
        shell.layoutContentChildren()
        if let window, let find = findPanel {
            if find.parent !== window { window.addChildWindow(find, ordered: .above) }
            find.makeKeyAndOrderFront(nil)
        }
    }

    func hideFindBar() {
        overlay.findVisible = false
        overlay.findMatchCount = nil
        shell.findVisible = false
        currentBrowser?.stopFinding(true)
        shell.layoutContentChildren()
        if let find = findPanel, let window {
            // Typing goes back to the page, unless focus already moved elsewhere.
            if find.isKeyWindow { browsers.visibleRuntime?.hostWindow?.makeKey() }
            window.removeChildWindow(find)
            find.orderOut(nil)
        }
        currentBrowser?.setFocused(true)
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Use Selection to Find: the page's selection becomes the
    /// search, on the find pasteboard too as macOS apps share it, and the bar finds it.
    func useSelectionForFind() {
        guard let b = currentBrowser else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = ((o?["result"] as? [String: Any])?["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self, !text.isEmpty else { return }
                let pb = NSPasteboard(name: .find)
                pb.clearContents()
                pb.setString(text, forType: .string)
                self.overlay.findQuery = text
                self.showFindBar()
                self.find(text, forward: true)
            }
        }
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection (⌘J): the page scrolls its selection into view.
    func jumpToSelection() {
        currentBrowser?.executeJavaScript("(()=>{const s=getSelection();if(!s.rangeCount)return;const n=s.getRangeAt(0).startContainer;"
            + "(n.nodeType===1?n:n.parentElement)?.scrollIntoView({block:'center'});})()")
    }

    func findNext(forward: Bool) {
        if !overlay.findVisible { showFindBar(); return }
        find(overlay.findQuery, forward: forward)
    }

    /// Always a follow-up find: CEF restarts the search when the text changes, and
    /// unlike a first request that selects a match (Chrome's find bar does this while
    /// typing), so the bar shows "1/3" rather than "0/3".
    private func find(_ q: String, forward: Bool) {
        guard let b = currentBrowser else { return }
        if q.isEmpty { overlay.findMatchCount = nil; b.stopFinding(true); return }
        b.findText(q, forward: forward, matchCase: false, findNext: true)
    }

    // MARK: Sheets

    func showSpaceEditor(space: Space?) {
        guard let window else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 651, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        // Arc's New Space starts on the profile of the space it was opened from.
        let initialProfile = space == nil && !isStandalone ? SpaceProfiles.forNewSpace(from: store.focusedSpace, profiles: store.profiles) : nil
        let store = self.store
        let view = SpaceEditorView(existing: space, profiles: store.profiles, initialProfile: initialProfile, onSave: { [weak panel] title, icon, theme, profile, newName in
            let id: UUID
            if let sid = space?.id, var s = store.space(sid) {
                s.title = title; s.icon = icon; s.theme = theme
                store.updateSpace(s)
                id = s.id
            } else {
                id = store.createSpace(title: title, emoji: icon.emoji, symbol: icon.symbol, theme: theme).id
            }
            switch profile {
            case .existing(let p): store.setProfile(p, forSpace: id)
            case .new: store.setProfile(store.createProfile(name: newName).id, forSpace: id)
            }
            if let panel { window.endSheet(panel) }
        }, onCancel: { [weak panel] in if let panel { window.endSheet(panel) } }, onPreview: { theme in
            // A new space has nothing to draw on yet; the sheet's own preview shows it.
            if let sid = space?.id { store.previewTheme(theme, forSpace: sid) }
        })
        panel.contentView = NSHostingView(rootView: view)
        spaceEditor = panel
        window.beginSheet(panel) { [weak self] _ in
            // Closed without Save (Cancel, Escape, cra://dismiss): the stored theme comes back.
            // Save already wrote it, so this does nothing then.
            if let sid = space?.id { store.endThemePreview(forSpace: sid, keep: false) }
            self?.spaceEditor = nil
        }
    }

    /// Dia-style import window (UI/Onboarding): browser, spaces, extensions, progress.
    /// `firstRun` makes it the onboarding: shown instead of this window, not closable.
    func showImport(firstRun: Bool = false) {
        if let existing = importWindow { existing.window?.makeKeyAndOrderFront(nil); return }
        let controller = ImportWindowController(store: store, favicons: app.favicons, firstRun: firstRun,
                                                onFinish: { [weak self] outcome in self?.app.importFinished(outcome, firstRun: firstRun) },
                                                onClosed: { [weak self] in self?.importWindow = nil })
        importWindow = controller
        controller.show(over: firstRun ? nil : window)
    }

    /// Brings the import window forward if one is open (Dock clicks during onboarding).
    func raiseImport() -> Bool {
        guard let w = importWindow?.window else { return false }
        w.makeKeyAndOrderFront(nil)
        return true
    }

    var isImportVisible: Bool { importWindow?.window?.isVisible == true }

    /// Close whatever transient UI is up (used by cra://dismiss for scripting).
    func dismissTransientUI() {
        if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
        importWindow?.close()
        commandBar.close()
        if overlay.findVisible { hideFindBar() }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // Arc's Spaces page keeps the page its 56 pt while the window resizes.
        if sidebarUI.libraryPage == .spaces, sidebarUI.libraryReveal == nil { shell.sidebarWidth = libraryWidth(.spaces) }
        shell.needsLayout = true
        browsers.layoutVisible()
        if commandBar.isOpen { positionCommandPanel() }
        floatingSidebar?.reposition()
        for p in peeks { p.repositionPeek() }
        // A toast that stays (the protected media one) follows the page's corner, once laid out.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            // The page behind a Peek shrinks around its new centre.
            if self.peekVeil.isOn { self.applyPeekVeil(duration: 0) }
            self.toast.follow(page: self.shell.webContainer.convert(self.shell.webContainer.bounds, to: nil), in: window)
        }
        saveFrame()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // The area under the pages shows while they catch up; make sure it has their current colour.
        for id in browsers.visibleTabIDs { browsers.runtime(for: id)?.browser.probeBackgroundColor() }
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        if commandBar.isOpen { positionCommandPanel() }
        floatingSidebar?.reposition()
        saveFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        refreshMaterialActive()
        browsers.windowVisibilityChanged(covered: false)
        reclaimPages()
    }

    func windowDidBecomeMain(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        reclaimPages()
    }

    /// Back in this window: pages that moved to another window come back (Arc's untargeted
    /// reparenting). After AppDelegate has made this the active window.
    /// This window shows the tab's blurred stand-in while another window holds its page.
    func isShowingElsewhere(_ tabID: UUID) -> Bool {
        !isTornDown && shell.paneCards.contains { $0.tabID == tabID && $0.showsElsewhere }
    }

    /// A page handed over by a window that is closing.
    func takePage(_ rt: TabRuntime) {
        browsers.adopt(rt.browser, for: rt.tabID, from: "another window's")
        refresh()
    }

    private func reclaimPages() {
        guard shell.paneCards.contains(where: \.showsElsewhere) else { return }
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { leaveIfCovered() }
        guard (notification.object as? NSWindow) === commandPanel, commandBar.isOpen else { return }
        if Date().timeIntervalSince(commandBarOpenedAt) < 0.6 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandPanel.makeKeyAndOrderFront(nil)
            }
            return
        }
        let event = NSApp.currentEvent
        commandBarClosingClick.panelClosed(byMouseDownAt: event?.type == .leftMouseDown ? event?.timestamp : nil)
        commandBar.close()
    }

    // The sidebar header's toggle moves into the traffic lights' place while they are gone (Arc).
    func windowWillEnterFullScreen(_ notification: Notification) { sidebarUI.windowFullscreen = true; shell.windowFullscreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { sidebarUI.windowFullscreen = false; shell.windowFullscreen = false }
    func windowDidEnterFullScreen(_ notification: Notification) { shell.needsLayout = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        // Left with the green button or ⌃⌘F while a video was fullscreen: the page leaves too.
        if let id = contentFullscreenTab { browsers.runtime(for: id)?.browser.exitFullscreen() }
        contentFullscreenTab = nil
        if shell.contentFullscreen { shell.contentFullscreen = false }
        enteredFullscreenForContent = false
        shell.needsLayout = true
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        leaveIfCovered()
    }

    /// Arc's autoPictureInPictureOnWindowOccluded: a window that isn't key and is completely out
    /// of sight (another app or desktop in front, minimised) sends its video to Picture in
    /// Picture, checked when it resigns key and when what covers it changes; the video comes home
    /// when the window is key again (windowDidBecomeKey). Arc 1.171, 2 Nov 2026: hiding an Arc that
    /// had not been active opened nothing; losing focus with its window on another desktop did.
    /// A locked screen covers every window and leaves nothing.
    private func leaveIfCovered() {
        guard let window, !window.isKeyWindow, !window.occlusionState.contains(.visible), !Self.screenIsLocked else { return }
        browsers.windowVisibilityChanged(covered: true)
    }

    /// Asked once, then kept by the system's lock and unlock notifications: the session query is a
    /// WindowServer round trip, and every occlusion change of a fullscreen window asked it (#136).
    private static let screenLock = ScreenLockState()
    private static var screenIsLocked: Bool { screenLock.isLocked }

    @MainActor private final class ScreenLockState {
        private(set) var isLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        private var observers: [NSObjectProtocol] = []

        init() {
            let center = DistributedNotificationCenter.default()
            observers = [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)].map { name, locked in
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.isLocked = locked }
                }
            }
        }
    }

    /// The frame lives in the store's observed prefs, which every sidebar row reads (selection):
    /// it is stored once a resize or move settles, not on every step of it.
    private func saveFrame() {
        frameSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveFrameNow() }
        frameSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private var frameSaveWork: DispatchWorkItem?

    /// Quit can arrive before the move/resize debounce fires.
    func saveFrameNow() {
        frameSaveWork?.cancel()
        frameSaveWork = nil
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        store.updateWindow(windowID) { $0.frame = NSStringFromRect(window.frame) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { commandBar.close() }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        tabSwitcher.cancel()
        app.mainWindowWillClose(self)
    }

    override func showWindow(_ sender: Any?) {
        app.browserWindowWillShow(self)
        super.showWindow(sender)
    }

    /// ⌘Q put Cra in the menu bar (#231): the window is out of sight and its pages are closed, as
    /// on a quit; the tabs stay. No page opens until `bringBack`.
    private(set) var isPutAway = false

    func putAway() {
        guard !isPutAway else { return }
        isPutAway = true
        dismissTransientUI()
        sidePanel.hide()
        for p in peeks { p.closeWindow() }
        browsers.closeAll()
        guard let window else { return }
        // Out of full screen first: a full-screen window ordered out leaves its Space behind.
        if window.styleMask.contains(.fullScreen) {
            fullScreenExit = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.orderOutPutAway() }
            }
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
        }
    }

    private var fullScreenExit: NSObjectProtocol?

    private func orderOutPutAway() {
        if let fullScreenExit { NotificationCenter.default.removeObserver(fullScreenExit) }
        fullScreenExit = nil
        if isPutAway { window?.orderOut(nil) }
    }

    /// Back from the menu bar: the open tab's page loads again, as after a launch.
    func bringBack() {
        guard isPutAway else { return }
        isPutAway = false
        refresh()
    }

    /// The window closed while others stay open: its pages close (the tabs stay in
    /// the sidebar) and it lets go of everything that would keep it alive.
    func tearDown() {
        isTornDown = true
        dismissTransientUI()
        sidePanel.hide()
        for p in peeks { p.closeWindow() }
        // A page another window shows behind its blurred stand-in moves there with its history
        // and state; closed with this window, that window loaded it again from scratch.
        for id in Array(browsers.runtimes.keys) {
            guard let other = app.mainWindows.first(where: { $0 !== self && $0.isShowingElsewhere(id) }),
                  let rt = browsers.release(id) else { continue }
            other.takePage(rt)
        }
        browsers.closeAll()
        for monitor in [scrollMonitor, childClickMonitor, middleClickMonitor, pageTopDragMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        pageTopDragMonitor = nil
        scrollMonitor = nil
        childClickMonitor = nil
        middleClickMonitor = nil
        floatingSidebar?.hide(animated: false)
        floatingSidebar = nil
        for child in window?.childWindows ?? [] {
            window?.removeChildWindow(child)
            child.orderOut(nil)
        }
    }
}


/// Window with Arc's taller title row: the traffic lights sit 24pt from the top.
/// They always show in colour, like Dia (Arc mutes them to grey discs until hovered).
final class CraWindow: NSWindow {
    /// AppKit's private per-button hook: the window buttons keep their colours
    /// while the window or the app is inactive. Nothing else about the window's
    /// inactive look changes.
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton type: UInt) -> Bool { true }

    /// The real title bar is hidden under the content, so double-clicks on the
    /// header strip never reach AppKit's zoom handling. The SwiftUI header rows
    /// call this on a double-click of their empty parts; it performs the system
    /// "double-click a window's title bar" action from System Settings.
    func performTitleDoubleClickAction() {
        guard !styleMask.contains(.fullScreen) else { return }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "None": break
        case "Minimize": miniaturize(nil)
        default: zoom(nil)   // "Maximize" and "Fill"
        }
    }

    /// The strip above the content card (the window's inset margin) stands in for the
    /// title bar there. It reaches 4 pt into the toolbar card, above its buttons, so a
    /// press just past the card's edge still counts. Movable-by-background only drags,
    /// and the toolbar takes a click as "edit URL", so the strip's presses are handled
    /// here: a double-click runs the title bar action, anything else drags the window.
    /// Edge to edge there is no margin, so only the 4 pt reaching into the toolbar (or the page) is left.
    private var titleStripHeight: CGFloat {
        (contentView as? ShellView)?.edgeToEdge == true ? 4 : CraMetrics.contentInset + 4
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !styleMask.contains(.fullScreen),
           let content = contentView, event.locationInWindow.y >= content.bounds.height - titleStripHeight,
           isTitleStrip(content.hitTest(content.convert(event.locationInWindow, from: nil))) {
            if event.clickCount == 2 { performTitleDoubleClickAction() } else { performDrag(with: event) }
            return
        }
        super.sendEvent(event)
    }

    /// False over the sidebar (its header handles its own clicks) and while the page
    /// fills the window (no margin, no toolbar).
    private func isTitleStrip(_ view: NSView?) -> Bool {
        var v = view
        while let current = v {
            if current is SidebarView { return false }
            if let shell = current as? ShellView, shell.contentFullscreen { return false }
            v = current.superview
        }
        return view != nil
    }

    /// Arc hides the traffic lights with the sidebar; the floating sidebar carries its
    /// own set (FloatingSidebarController). Full screen keeps them in the revealed title bar.
    var trafficLightsHidden = false {
        didSet { if trafficLightsHidden != oldValue { updateTrafficLights(animated: isVisible) } }
    }
    private var appliedTrafficLightsHidden = false

    private func updateTrafficLights(animated: Bool) {
        let hide = trafficLightsHidden && !styleMask.contains(.fullScreen)
        guard hide != appliedTrafficLightsHidden else { return }
        appliedTrafficLightsHidden = hide
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        // Hidden buttons rest at alpha 1: AppKit refuses to miniaturize a window whose
        // minimize button has alpha 0 (⌘M and the floating sidebar's yellow button did nothing).
        guard animated else {
            for b in buttons { b.alphaValue = 1; b.isHidden = hide }
            return
        }
        if !hide { for b in buttons where b.isHidden { b.alphaValue = 0; b.isHidden = false } }
        // Same timing as the sidebar's slide (ShellView.animateSidebar).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.085
            for b in buttons { b.animator().alphaValue = hide ? 0 : 1 }
        } completionHandler: { [weak self] in
            guard let self, self.appliedTrafficLightsHidden == hide else { return }
            for b in buttons { b.isHidden = hide; b.alphaValue = 1 }
        }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
        updateTrafficLights(animated: false)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard !styleMask.contains(.fullScreen) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, type) in buttons.enumerated() {
            guard let b = standardWindowButton(type), let sv = b.superview else { continue }
            let x: CGFloat = 13 + CGFloat(i) * 24
            let y = sv.bounds.height - CraMetrics.titleRowCenter - b.frame.height / 2
            let target = NSPoint(x: x, y: y)
            if abs(b.frame.origin.x - target.x) > 0.5 || abs(b.frame.origin.y - target.y) > 0.5 {
                b.setFrameOrigin(target)
            }
        }
    }
}

/// Save Page As's Format pop-up (Chrome's "Web Page, Single File" and "Web Page, HTML Only");
/// switching it swaps the name's extension.
@MainActor
private final class SavePageFormat: NSObject {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var panel: NSSavePanel?
    var singleFile: Bool { popup.indexOfSelectedItem == 0 }

    init(panel: NSSavePanel) {
        self.panel = panel
        let label = NSTextField(labelWithString: "Format:")
        popup.addItems(withTitles: ["Web Page, Single File", "Web Page, HTML Only"])
        let row = NSStackView(views: [label, popup])
        row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view = row
        super.init()
        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        guard let panel else { return }
        let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = name + (singleFile ? ".mhtml" : ".html")
    }
}
