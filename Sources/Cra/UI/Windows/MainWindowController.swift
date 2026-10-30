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
    private var enteredFullscreenForContent = false
    /// The tab whose page (a video) is in element fullscreen.
    private var contentFullscreenTab: UUID?
    private var lastSidebarVisible = true
    /// The theme the background and placeholder root views were made with.
    private var shownTheme: SpaceTheme?
    private var lastSidebarWidth: CGFloat = 0
    private var commandBarOpenedAt = Date.distantPast
    private var commandObserving = false
    /// Closed for good (another window stayed open): it no longer follows the store.
    private var isTornDown = false

    var currentBrowser: CraBrowser? { browsers.visibleRuntime?.browser }

    /// This window's entry in the store (WindowSession): its space, open tabs, frame.
    let windowID: UUID
    /// Pages load in the off-the-record profile; nothing is saved (WindowSession.isIncognito).
    let isIncognito: Bool
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
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = "Cra"
        if session.frame == nil { window.center() }
        sidebarUI.windowID = session.id

        let store = app.store
        let palette = focusedSpace.theme.palette
        shell = ShellView(frame: window.contentView!.bounds,
                          background: SpaceBackgroundView(store: store, ui: sidebarUI),
                          sidebar: SidebarView(store: store, ui: sidebarUI, actions: sidebarActions, favicons: app.favicons),
                          toolbar: PaneToolbarView(paneTabID: nil, store: store, ui: sidebarUI, actions: sidebarActions),
                          status: StatusBubbleView(overlay: overlay),
                          toasts: ToastStackView(overlay: overlay, onDismiss: { [weak self] id in self?.removeToast(id) }),
                          find: FindBarView(overlay: overlay, onFind: { [weak self] q, fwd in self?.find(q, forward: fwd) },
                                            onClose: { [weak self] in self?.hideFindBar() }))
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        shell.sidebarVisible = sidebarVisible
        shell.showToolbar = store.settings.showToolbar
        lastSidebarVisible = sidebarVisible
        window.trafficLightsHidden = !sidebarVisible
        lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
        window.contentView = shell
        window.backgroundColor = NSColor(palette.gradientColors.first ?? .gray)

        browsers = BrowserManager(store: store, favicons: app.favicons, container: shell.parkingView)
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
        installFloatingSidebar()
        observeStore()
        refresh()
        shell.onDevToolsFrame = { [weak self] rect in self?.positionDevToolsWindow(rect) }
        shell.onPaneFrames = { [weak self] frames in self?.positionPageWindows(frames) }
        shell.onAnimatePaneFrames = { [weak self] frames, d, timing in self?.animatePageWindows(to: frames, duration: d, timing: timing) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.shell.windowActive = true; self?.sidebarUI.appActive = true }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.shell.windowActive = false; self?.sidebarUI.appActive = false }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Wiring

    private func wireActions() {
        sidebarActions.titleBarDoubleClick = { [weak self] in (self?.window as? CraWindow)?.performTitleDoubleClickAction() }
        sidebarActions.openCommandBar = { [weak self] mode in self?.openCommandBar(mode) }
        sidebarActions.closeTab = { [weak self] id in self?.closeTab(id) }
        sidebarActions.goBack = { [weak self] in self?.currentBrowser?.goBack() }
        sidebarActions.goForward = { [weak self] in self?.currentBrowser?.goForward() }
        sidebarActions.reload = { [weak self] in
            guard let b = self?.currentBrowser else { return }
            b.isLoading ? b.stopLoading() : b.reload()
        }
        sidebarActions.editSpace = { [weak self] s in self?.showSpaceEditor(space: s) }
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
        sidebarActions.openURL = { [weak self] url in
            guard let self else { return }
            self.store.createTab(url: url, window: self.windowID)
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
        sidebarActions.runExtension = { [weak self] id in self?.runExtensionAction(id, buttonRightX: Self.extensionButtonRightX()) }
        sidebarActions.showExtensionsMenu = { [weak self] in self?.showToolbarExtensionsMenu() }
        // Popups from an extension's shortcut or chrome.action.openPopup() hang where the
        // menu bar's do: under the extension's toolbar button, else at the card's right end.
        // Arc puts every popup in one place, whatever opened it.
        ExtensionActions.shared.watchPopups { [weak app] id in
            guard let main = app?.main, let window = main.window, let key = NSApp.keyWindow, key === window || key.parent === window else { return nil }
            return main.extensionPopupAnchor(id)
        }
        sidebarActions.performAction = { [weak self] id in
            if id.hasPrefix("muteTab:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                let muted = self?.store.item(uuid)?.tab?.muted ?? false
                self?.app.runtime(for: uuid)?.browser.setAudioMuted(muted)
            } else {
                self?.app.perform(id)
            }
        }
        commandBar.onCommit = { [weak self] s, typed, mode, force in self?.handleCommit(s, typed: typed, mode: mode, forceNewTab: force) }
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
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeStore()
            }
        }
    }

    func refresh() {
        guard !isTornDown else { return }
        let space = focusedSpace
        let palette = space.theme.palette
        // Its extensions belong to the space's profile.
        if siteControlCenter.isShown, siteControlCenterSpaceID != space.id { siteControlCenter.close() }
        // refresh runs on every store change (each page title, each window move). A new root
        // view rebuilds its whole SwiftUI tree, and a new window appearance or background redraws
        // every view, so all of these follow the theme only when it changes. What the root
        // views show beyond the palette they observe themselves.
        if shownTheme != space.theme {
            shownTheme = space.theme
            // A swipe in the floating sidebar changes space under it (issue #12).
            floatingSidebar?.refreshBackdrop()
            shell.placeholderHost.wantsLayer = true
            shell.placeholderHost.layer?.backgroundColor = (palette.isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)).cgColor
            shell.isDarkTheme = palette.isDark
            window?.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            // Vibrant themes see through to the desktop like Arc; others are opaque.
            shell.vibrancy.isHidden = !palette.vibrant
            shell.vibrancyLift.isHidden = !palette.vibrant
            shell.vibrantDark = palette.isDark
            shell.vibrantLight = palette.vibrant && !palette.isDark
            shell.refreshLift()
            window?.isOpaque = !palette.vibrant
            window?.backgroundColor = palette.vibrant ? .clear : NSColor(palette.gradientColors.first ?? .gray)
        }

        browsers.pruneMissingTabs()
        let selected = selectedTabID
        // Split view: the selected tab's split decides which panes are on screen.
        let panes = store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID)
        let split = selected.flatMap { store.splitContaining($0) }
        let factors = SplitPaneLayout.normalizedFactors(ids: panes, stored: split?.split?.widthFactors ?? [:])
        let empty = Set(panes.filter { store.item($0)?.isEmptyTab == true })
        if shell.showToolbar != store.settings.showToolbar { shell.showToolbar = store.settings.showToolbar }
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
            shell.sidebarWidth = lastSidebarWidth + (sidebarUI.libraryPage != nil ? LibraryMetrics.extraWidth : 0)
        }
    }

    /// The browser window the user is in (AppDelegate follows the key window).
    private var isActiveWindow: Bool { store.activeWindowID == windowID }

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
        let b = browsers.visibleRuntime?.browser
        if sidebarUI.canGoBack != (b?.canGoBack ?? false) { sidebarUI.canGoBack = b?.canGoBack ?? false }
        if sidebarUI.canGoForward != (b?.canGoForward ?? false) { sidebarUI.canGoForward = b?.canGoForward ?? false }
        if sidebarUI.isLoading != (b?.isLoading ?? false) { sidebarUI.isLoading = b?.isLoading ?? false }
        let themeColor = browsers.visibleRuntime?.themeColor ?? ""
        if sidebarUI.pageThemeColor != themeColor { sidebarUI.pageThemeColor = themeColor }
        for (id, rt) in browsers.runtimes where sidebarUI.progress[id] != rt.progress { sidebarUI.progress[id] = rt.progress }
        var nav: [UUID: TabNavState] = [:]
        for id in browsers.visibleTabIDs {
            guard let rt = browsers.runtime(for: id) else { continue }
            nav[id] = TabNavState(canGoBack: rt.browser.canGoBack, canGoForward: rt.browser.canGoForward, isLoading: rt.browser.isLoading, themeColor: rt.themeColor)
        }
        if nav != sidebarUI.navStates { sidebarUI.navStates = nav }
    }

    // MARK: Split view

    /// Arc's "Add Split View" (⌃⇧=): a new empty pane opens after the focused
    /// one, with the command bar ready to fill it.
    func addSplitPane() {
        guard let current = selectedTabID else { openCommandBar(.newTab); return }
        if store.paneTabIDs(for: current).count >= 4 {
            sidebarUI.flashStatus("Cannot Add New Pane", symbol: "rectangle.portrait.split.2x1.slash")
            return
        }
        guard store.addEmptyPane(nextTo: current) != nil else { return }
        refresh()
        openCommandBar(.editURL)
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
        // Same rule as PaneToolbarView's bar colour.
        let bars = browsers.runtimes.compactMapValues { rt in HexColor.components(rt.themeColor) != nil ? rt.themeColor : nil }
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        if tabID == browsers.visibleTabID { window?.title = store.item(tabID)?.displayTitle ?? "Cra" }
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
        let toast = DownloadToast(id: download.identifier, name: name, percent: download.percent, state: download.state.rawValue,
                                  path: download.fullPath, totalBytes: download.totalBytes)
        if let i = overlay.toasts.firstIndex(where: { $0.id == toast.id }) { overlay.toasts[i] = toast } else {
            overlay.toasts.append(toast)
            ChromeDownloadAnimation.suppress()
            showDownloadInSidebar(download, name: name)
        }
        updateRecentDownload(download)
        if download.state == .complete, !download.fullPath.isEmpty, finishedDownloads.insert(download.identifier).inserted {
            DownloadHistory.shared.add(path: download.fullPath)
        }
        layoutToasts()
        if download.state != .inProgress {
            let id = toast.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.removeToast(id) }
        } else if downloadWatchdog == nil {
            downloadWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkStalledDownloads() }
            }
        }
    }

    private func removeToast(_ id: UInt32) {
        guard overlay.toasts.contains(where: { $0.id == id }) else { return }
        overlay.toasts.removeAll { $0.id == id }
        layoutToasts()
    }

    private func layoutToasts() {
        shell.toastCount = overlay.toasts.count
        shell.layoutContentChildren()
        layoutToastPanel()
    }

    private var downloadWatchdog: Timer?

    /// Chromium stops reporting a download once the tab that started it is gone (the
    /// download carries on, or ends, silently), which left its toast "in progress" for
    /// good. A toast that hasn't heard from Chromium for a while reads the file instead:
    /// gone means it ended, the full size with no .crdownload beside it means it's done.
    private func checkStalledDownloads() {
        let inProgress = overlay.toasts.filter { $0.state == CraDownloadState.inProgress.rawValue }
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
            else if let size, t.totalBytes > 0, size >= t.totalBytes { state = .complete }
            else { continue }
            let info = CraDownloadInfo()
            info.identifier = t.id
            info.fullPath = t.path
            info.suggestedName = t.name
            info.totalBytes = t.totalBytes
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
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id else { return }
                recent.image = image
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
    /// page gets its own panel just its size (the find bar, the toasts).
    private var overlayPanel: NSPanel?
    private var findPanel: FindBarPanel?
    private var toastPanel: NSPanel?
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
        let toasts = clearPanel()
        shell.moveOverlays(to: panel.contentView!, findBar: find, toasts: toasts)
        window.addChildWindow(panel, ordered: .above)
        overlayPanel = panel
        findPanel = find
        toastPanel = toasts
        if overlay.findVisible { window.addChildWindow(find, ordered: .above) }
        layoutToastPanel()
    }

    /// The toast panel is on screen only while there are toasts, sized to the stack in the
    /// bottom trailing corner of the focused page (the overlay panel's frame).
    private func layoutToastPanel() {
        guard let window, let panel = toastPanel, let page = overlayPanel?.frame else { return }
        guard !overlay.toasts.isEmpty else {
            if panel.parent != nil { window.removeChildWindow(panel) }
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let frame = toastPanelFrame(page: page)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
    }

    private func toastPanelFrame(page: NSRect) -> NSRect {
        let size = ShellView.toastStackSize(count: overlay.toasts.count)
        return NSRect(x: page.maxX - size.width, y: page.minY, width: size.width, height: size.height)
    }

    /// Overlay panel above the page windows (and the floating sidebar), the find bar above it.
    private func raiseOverlayPanels() {
        guard let window else { return }
        var panels: [NSPanel?] = [overlayPanel]
        if !overlay.toasts.isEmpty { panels.append(toastPanel) }
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
                if w.isVisible { w.orderOut(nil) }
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
        if let dev = browsers.visibleDevToolsWindow, dev.parent === window {
            raisePageWindows(above: dev)
        } else {
            raiseOverlayPanels()
        }
    }

    /// Moves the page's view from its Chrome window into its card (EmbeddedPages). With
    /// DevTools open the page goes back: Chrome's docked frontend lays it out in its window.
    private func embedPage(_ id: UUID, from w: NSWindow) {
        guard EmbeddedPages.isEnabled else { return }
        guard let views = EmbeddedPages.pageViews(of: w) else { return }
        let target: NSView
        if browsers.visibleDevToolsWindow != nil, let cv = w.contentView {
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
        for v in views where v.frame != bounds { v.frame = bounds }
        if embedFocusTab == id { focusEmbeddedPage(id) }
    }

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
        if !focused.contains(where: { responder.isDescendant(of: $0) }) { window.makeFirstResponder(nil) }
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
        let live = pageWindowsFollowLive || shell.devToolsFrontendDocked
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow else { continue }
            let body = frames[id] ?? focusRect
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
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
        if let find = findPanel, find.frame != findPanelFrame(page: focusOnScreen) { find.setFrame(findPanelFrame(page: focusOnScreen), display: true) }
        layoutToastPanel()
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
            if shell.devToolsFrontendDocked, let dev = browsers.visibleDevToolsWindow, dev.parent === window,
               let focusID = browsers.visibleTabID, let body = frames[focusID] {
                dev.animator().setFrame(window.convertToScreen(body), display: true)
            }
            overlayPanel?.animator().setFrame(window.convertToScreen(focusPage), display: true)
            findPanel?.animator().setFrame(findPanelFrame(page: window.convertToScreen(focusPage)), display: true)
            if !overlay.toasts.isEmpty { toastPanel?.animator().setFrame(toastPanelFrame(page: window.convertToScreen(focusPage)), display: true) }
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
        guard tab == browsers.visibleTabID, shell.devToolsFrontendDocked,
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
        // The whole mask, not only the corner set: a rebuilt layer would otherwise keep
        // whatever radius and clipping it came with.
        let radius = shell.contentFullscreen ? 0 : CraMetrics.contentCornerRadius
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
        if !layer.masksToBounds { layer.masksToBounds = true }
        // Chromium's content view is flipped, so its layer's MinY edge is the top.
        let bottomLeft: CACornerMask = cv.isFlipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner
        let bottomRight: CACornerMask = cv.isFlipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner
        let topLeft: CACornerMask = cv.isFlipped ? .layerMinXMinYCorner : .layerMinXMaxYCorner
        let topRight: CACornerMask = cv.isFlipped ? .layerMaxXMinYCorner : .layerMaxXMaxYCorner
        var corners: CACornerMask = []
        // A fullscreen card is square.
        if !shell.contentFullscreen, abs(page.minY - body.minY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(bottomLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(bottomRight) }
        }
        // Without the toolbar the page's top edge is the card's top edge too.
        if !shell.contentFullscreen, !shell.showToolbar, abs(page.maxY - body.maxY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(topLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(topRight) }
        }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    /// Chromium lays its frameless window's content view out below a 22 pt title bar
    /// that Cra hides, leaving a blank band over the page; make it fill the window.
    private func fillContentView(_ w: NSWindow) {
        guard let cv = w.contentView else { return }
        let full = NSRect(origin: .zero, size: w.frame.size)
        if cv.frame != full { cv.frame = full }
    }

    /// Shows the visible tab's DevTools window and hides the other tabs'. Chrome-style
    /// pages get Chrome's dockable frontend (see CraCEF's DevToolsClient): its window
    /// spans the card body under the page, which is laid over the placeholder it
    /// reports. Alloy pages keep the shell's own split with CEF's window on the right.
    func browserManagerDevToolsChanged() {
        guard let window else { return }
        let visible = browsers.visibleDevToolsWindow
        for (_, view) in browsers.devToolsViews {
            if let w = view.window, w !== visible { w.orderOut(nil) }
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
        guard let w = visible else {
            if shell.frontendPageRect != nil { shell.frontendPageRect = nil }
            positionPageWindows(lastPaneFrames)
            return
        }
        if selfDock && !docked {
            detachDevToolsWindow(w)
            positionPageWindows(lastPaneFrames)
            return
        }
        attachDevToolsWindow(w, selfDock: selfDock)
        positionDevToolsWindow((shell.devToolsHost.superview ?? shell.contentContainer).convert(shell.devToolsHost.frame, to: nil))
        w.orderFront(nil)
        raisePageWindows(above: w)
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

    private func attachDevToolsWindow(_ w: NSWindow, selfDock: Bool) {
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
            if selfDock { setDevToolsTitleBarInset(nil) }
        }
        if let cv = w.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = CraMetrics.contentCornerRadius
            cv.layer?.cornerCurve = .continuous
            // Frontend-docked: the window spans the card body, so both bottom corners are
            // card corners. Shell-docked (Alloy): it sits right of the page.
            let bottom: CACornerMask = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cv.layer?.maskedCorners = selfDock ? bottom : [.layerMaxXMaxYCorner, .layerMaxXMinYCorner]
            cv.layer?.masksToBounds = true
        }
    }

    /// "Undock into separate window": the frontend's window becomes a floating window of its own.
    private func detachDevToolsWindow(_ w: NSWindow) {
        guard let window else { return }
        if w.parent === window {
            window.removeChildWindow(w)
            // A normal titled window, like Chrome's undocked "DevTools - <url>" (the
            // frontend draws under a real title bar; attach strips all of this again).
            w.styleMask.remove(.fullSizeContentView)
            w.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
            ChromiumWindowCorners.setSquare(false, for: w)
            ChromiumChildHover.setDocked(false, for: w)
            w.titlebarAppearsTransparent = false
            w.titleVisibility = .visible
            if let url = selectedTab?.tab?.url {
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
            setDevToolsTitleBarInset(w)
        }
        w.makeKeyAndOrderFront(nil)
    }

    /// CEF's frame view keeps a frameless window's content view at full window size, so
    /// the undocked window's title bar covers the top of the frontend; move the
    /// frontend's layout down by the title bar's height instead (0 when docked).
    private func setDevToolsTitleBarInset(_ w: NSWindow?) {
        let inset = w.map { max(0, $0.frame.height - $0.contentLayoutRect.height) } ?? 0
        let css = inset > 0 ? "body{margin-top:\(Int(inset))px!important;height:calc(100% - \(Int(inset))px)!important}" : ""
        currentBrowser?.executeJavaScript("(function(){var s=document.getElementById('cra-titlebar-inset');"
            + "if(!s){s=document.createElement('style');s.id='cra-titlebar-inset';document.head.appendChild(s);}"
            + "s.textContent='\(css)';})();", inDevTools: true)
    }

    /// Page windows go above the DevTools window (which spans the body when the frontend
    /// docks), and the overlay panel above everything.
    private func raisePageWindows(above dev: NSWindow) {
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

    private func positionDevToolsWindow(_ rectInWindow: NSRect) {
        guard let window, let w = browsers.visibleDevToolsWindow, w.parent === window else { return }
        let onScreen = window.convertToScreen(rectInWindow)
        if w.frame != onScreen { w.setFrame(onScreen, display: true) }
        fillContentView(w)
        if let cv = w.contentView, let id = browsers.visibleTabID, let v = browsers.devToolsViews[id], v.frame != cv.bounds {
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

    /// Arc's Peek (Settings ▸ Tabs ▸ Links): a link to another site clicked in a favorite or
    /// pinned tab, or any Shift-clicked link, opens over the window and the tab stays put.
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool) -> Bool {
        guard !isIncognito, let target = SiteKey.site(of: url) else { return false }
        if shiftClick {
            guard store.settings.peekOnShiftClick else { return false }
        } else {
            guard store.settings.peekLinksToOtherSites, store.isPinned(tabID),
                  let here = SiteKey.site(of: pageURL), here != target else { return false }
        }
        app.openPeek(url: url, over: self)
        return true
    }

    /// Arc's Peek covers the page area less a margin, inside this window.
    func peekFrame() -> NSRect {
        guard let window else { return .zero }
        // Asked from windowDidResize, before the shell has laid out at the new size.
        shell.layoutSubtreeIfNeeded()
        let r = window.convertToScreen(shell.convert(shell.contentContainer.frame, to: nil))
        return r.insetBy(dx: max(24, (r.width * 0.06).rounded()), dy: max(20, (r.height * 0.05).rounded()))
    }

    private var peeks: [LittleWindowController] { app.littleWindows.filter { $0.peekParent === self } }

    // MARK: Tabs

    /// cra://debug?devtoolsjs=…: run script in the current tab's DevTools frontend.
    func debugRunInDevTools(_ script: String) { currentBrowser?.executeJavaScript(script, inDevTools: true) }

    func closeCurrentTab() {
        // ⌘W with tabs picked in the sidebar closes all of them.
        if !sidebarUI.multiSelection.isEmpty {
            let ids = sidebarUI.multiSelection
            sidebarUI.clearPicks()
            for id in ids where id != selectedTabID { closeTab(id) }
            if let open = selectedTabID, ids.contains(open) { closeTab(open) }
            return
        }
        guard let id = selectedTabID else { return }
        closeTab(id)
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
                for w in app.mainWindows { w.browsers.unload(p) }
            }
            if wasSelected {
                // Arc goes back to the tab used before this one, if it is still open. A pinned
                // tab that was closed (unloaded) doesn't count: two of them would otherwise hand
                // the selection back and forth on every ⌘W, reloading each other.
                let back = store.recentTabs(in: focusedSpaceID, limit: .max)
                    .first { !panes.contains($0) && (!store.isPinned($0) || app.runtime(for: $0) != nil) }
                store.selectTab(back, window: windowID)
            }
        } else {
            store.archiveTab(id, reason: .manual)
        }
    }

    func resetPinnedTab(_ id: UUID) {
        guard let home = store.resetPinnedTab(id) else { return }
        app.runtime(for: id)?.browser.loadURL(home)
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

    /// Arc's Capture: save a PNG of the page area to ~/Downloads.
    func capturePage() {
        guard let window else { return }
        let rectInWindow = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        var screenRect = window.convertToScreen(rectInWindow)
        // CGWindowList uses top-left origin.
        if let screen = NSScreen.screens.first {
            screenRect.origin.y = screen.frame.height - screenRect.maxY
        }
        let captureWindow = browsers.visibleRuntime?.hostWindow ?? window
        guard let image = CGWindowListCreateImage(screenRect, .optionIncludingWindow, CGWindowID(captureWindow.windowNumber), [.bestResolution]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cra Capture \(f.string(from: Date())).png")
        try? png.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

    /// Arc's Library button and ⇧⌘L: open the Library on the page last shown, or leave it.
    func toggleLibrary() {
        if sidebarUI.libraryPage != nil { closeLibrary() } else { showLibrary(sidebarUI.lastLibraryPage) }
    }

    /// The Library takes over the sidebar, which widens for its page rail (LibraryView).
    func showLibrary(_ page: LibraryPage) {
        sidebarUI.lastLibraryPage = page
        let opening = sidebarUI.libraryPage == nil
        withAnimation(.easeOut(duration: 0.05)) { sidebarUI.libraryPage = page }
        guard opening else { return }
        sidebarUI.downloadsListOpen = false
        commandBar.close()
        shell.sidebarResizable = false
        let width = CGFloat(store.prefs.sidebarWidth) + LibraryMetrics.extraWidth
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
        if show { if !sidebarVisible { floatingSidebar.show() } } else { floatingSidebar.hide(animated: true) }
    }

    private func installFloatingSidebar() {
        guard let window, floatingSidebar == nil else { return }
        let f = FloatingSidebarController(shell: shell, window: window, palette: { [weak self] in
            self?.focusedSpace.theme.palette ?? SpaceTheme.presets[0].palette
        })
        f.sidebarHidden = { [weak self] in self.map { !$0.sidebarVisible } ?? false }
        f.didAttachPanel = { [weak self] in
            // Keep toasts and the find bar above the floating sidebar.
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
        // Middle-click on a sidebar tab closes it, like Arc and Chrome (SwiftUI has no
        // gesture for the middle button; rows report the hovered tab instead).
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self, event.buttonNumber == 2, let window = self.window, let target = event.window,
                  target === window || target.parent === window, !CraCEFRuntime.isPageWindow(target),
                  let id = self.sidebarUI.hoveredTabID else { return event }
            self.middleClickClose(id)
            return nil
        }
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
            // The momentum tail of a space swipe belongs to the swipe, not the tab list.
            if !event.momentumPhase.isEmpty { return self.swipeAxis == .horizontal ? nil : event }
            // The floating sidebar is in its own panel (FloatingSidebarController): its swipes
            // come from that window.
            let host = self.shell.sidebarHost
            guard event.window === self.window || (event.window != nil && event.window === host.window),
                  event.hasPreciseScrollingDeltas else { return event }
            switch event.phase {
            case .mayBegin, .began:
                // The Library's lists don't page between spaces.
                let overSidebar = (self.shell.sidebarVisible || self.shell.floatingSidebar) && event.window === host.window
                    && host.bounds.contains(host.convert(event.locationInWindow, from: nil))
                    && self.sidebarUI.libraryPage == nil
                self.swipeAxis = overSidebar ? .undecided : .vertical
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
                    guard abs(self.swipeX) > abs(self.swipeY) * 1.2, self.store.spaceOrder.count > 1, !self.isIncognito else {
                        self.swipeAxis = .vertical
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
                guard self.swipeAxis == .horizontal else { return event }
                self.endSpaceSwipe()
                return nil
            default:
                return event
            }
        }
    }

    private func beginSpaceSwipe() {
        swipeTravel = 0
        swipeSamples = []
        swipeDetent = 0
        sidebarUI.spaceSettleVelocity = 0
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
        return (onScreen.maxY - (store.settings.showToolbar ? CraMetrics.toolbarHeight : 0), onScreen.maxX)
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

    /// Under the extension's pinned toolbar button when the toolbar shows one, else under the
    /// toolbar at the card's right end.
    fileprivate func extensionPopupAnchor(_ id: String) -> NSPoint? {
        guard let bar = toolbarBottomOnScreen() else { return nil }
        if store.settings.showToolbar, let button = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.extensionButtonFrameOnScreen(id) {
            return NSPoint(x: button.maxX, y: bar.y)
        }
        return NSPoint(x: bar.cardMaxX - 8, y: bar.y)
    }

    /// Runs an extension's toolbar action on the focused page, like Arc's toolbar buttons and
    /// Dia's Extensions menu. The popup hangs under the toolbar, its right edge at `buttonRightX`
    /// (screen x of the clicked button; nil = the extension's toolbar button or the card's right end).
    func runExtensionAction(_ id: String, buttonRightX: CGFloat? = nil) {
        guard extensionEntries.contains(where: { $0.extensionID == id }) else { return }
        guard let bar = toolbarBottomOnScreen() else { openExtensionPopupPage(id, anchor: nil); return }
        let anchor = buttonRightX.map { NSPoint(x: $0, y: urlBarBottomOnScreen() ?? bar.y) }
            ?? extensionPopupAnchor(id) ?? NSPoint(x: bar.cardMaxX - 8, y: bar.y)
        guard let browser = currentBrowser else { openExtensionPopupPage(id, anchor: anchor); return }
        Task {
            if await !ExtensionActions.shared.run(id, on: browser, anchor: anchor) { self.openExtensionPopupPage(id, anchor: anchor) }
        }
    }

    /// The Chromium profile folder the focused page loads in.
    var profileDirectoryName: String { selectedTabID.map(store.profileDirectoryName(item:)) ?? store.profileDirectoryName(space: focusedSpaceID) }

    /// The extensions installed in the focused page's profile.
    var extensionEntries: [ExtensionStore.Entry] { ExtensionStore.shared.entries(inProfile: profileDirectoryName) }

    /// The right edge (screen x) of the pinned-extension button under the pointer, in the
    /// toolbar or the sidebar's URL pill (also in the floating sidebar's panel), so a popup
    /// hangs from the same place wherever the button was clicked (GitHub #8).
    private static func extensionButtonRightX() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        if let w = NSApp.window(withWindowNumber: number), let content = w.contentView {
            let p = w.convertPoint(fromScreen: mouse)
            var v = content.hitTest(content.superview?.convert(p, from: nil) ?? p)
            while let view = v, !(view is ToolbarGlyphButton) { v = view.superview }
            if let button = v { return w.convertToScreen(button.convert(button.bounds, to: nil)).maxX }
        }
        return mouse.x + 17
    }

    /// No page for Chrome's popup to attach to (no tab open, no DevTools pipe, a page it
    /// cannot reach): the popup page in a popup-sized window under the button, else the
    /// options page, else Chrome's details page for the extension.
    private func openExtensionPopupPage(_ id: String, anchor: NSPoint?) {
        guard let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) else { return }
        let base = "chrome-extension://\(id)/"
        if let popup = e.popupPath {
            let fallback = window.map { NSPoint(x: $0.frame.maxX - 16, y: $0.frame.maxY - CraMetrics.toolbarHeight) } ?? .zero
            ExtensionPageWindow.open(url: base + popup, anchor: anchor ?? fallback, app: app)
        } else {
            store.createTab(url: e.optionsPath.map { base + $0 } ?? "chrome://extensions/?id=\(id)", select: true, window: windowID)
        }
    }

    func debugSiteControls() { showToolbarExtensionsMenu() }

    func debugTabSwitcher() {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tabSwitcher.isDark = dark
        tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
        tabSwitcher.palette = theme.palette
        tabSwitcher.debugOpen(store.recentTabs(in: focusedSpaceID, limit: TabSwitcherMetrics.maxItems).compactMap { id in
            guard let it = store.item(id), let tab = it.tab else { return nil }
            return TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot)
        })
    }

    /// Arc's sliders button (toolbar and URL pill): the Site Control Center, hung under the
    /// button the pointer is on (buttons are 32 × 28).
    private func showToolbarExtensionsMenu() {
        guard let window, let content = window.contentView, let y = urlBarBottomOnScreen() else { return }
        ExtensionStore.shared.reload()
        let mouse = NSEvent.mouseLocation
        // Arc's popover overlaps the bar by 4 pt (popover top 71 under a bar ending at 75).
        let onScreen = NSRect(x: mouse.x - 16, y: y + 4, width: 32, height: 28)
        let rect = content.convert(window.convertFromScreen(onScreen), from: nil)
        let url = selectedTabID.flatMap { store.item($0)?.tab?.url } ?? ""
        var actions = SiteControlCenterActions()
        actions.share = { [weak self] in self?.shareCurrentPage(from: rect, in: content) }
        actions.copyURL = { [weak self] in self?.app.perform("copyURL") }
        actions.capture = { [weak self] in self?.capturePage() }
        actions.captureFullPage = { [weak self] in self?.captureFullPage() }
        actions.runExtension = { [weak self] id in self?.runExtensionAction(id) }
        actions.addExtension = { [weak self] in self?.openTab("https://chromewebstore.google.com/category/extensions") }
        actions.manageExtensions = { [weak self] in self?.openTab("chrome://extensions") }
        actions.clearCache = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: false) }
        actions.clearCookies = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: true) }
        actions.siteSettings = { [weak self] in
            guard let origin = URL(string: url).flatMap({ u in u.host.map { "\(u.scheme ?? "https")://\($0)" } }) else { return }
            self?.openTab("chrome://settings/content/siteDetails?site=" + (origin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? origin))
        }
        siteControlCenterSpaceID = focusedSpaceID
        siteControlCenter.show(relativeTo: rect, of: content, url: url, dark: focusedSpace.theme.palette.isDark,
                               profile: profileDirectoryName, store: store, actions: actions)
    }

    private func openTab(_ url: String) {
        store.createTab(url: url, select: true, window: windowID)
        showWindow(nil)
    }

    private func shareCurrentPage(from rect: NSRect, in view: NSView) {
        guard let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }).flatMap(URL.init(string:)) else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    /// Arc's "Capture the full page": the whole document (beyond the viewport) as a PNG in Downloads.
    func captureFullPage() {
        guard let b = currentBrowser else { return }
        b.sendDevToolsMethod("Page.getLayoutMetrics", params: "{}") { result, _ in
            guard let result, let m = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                  let size = (m["cssContentSize"] ?? m["contentSize"]) as? [String: Any],
                  let w = size["width"] as? Double, let h = size["height"] as? Double else { return }
            let params = #"{"format":"png","captureBeyondViewport":true,"clip":{"x":0,"y":0,"width":\#(w),"height":\#(min(h, 16384)),"scale":1}}"#
            b.sendDevToolsMethod("Page.captureScreenshot", params: params) { shot, error in
                guard let shot, let o = try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any],
                      let b64 = o["data"] as? String, let png = Data(base64Encoded: b64) else {
                    NSLog("Cra: full-page capture failed: %@", error ?? "no data")
                    return
                }
                DispatchQueue.main.async {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                    let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Cra Capture \(f.string(from: Date())).png")
                    try? png.write(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
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
            store.recentTabs(in: focusedSpaceID, limit: TabSwitcherMetrics.maxItems).compactMap { id in
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
        // An empty split pane gets Arc's "Search or Enter URL…" bar; the result fills the pane.
        let fillingEmptyPane = selectedTab?.isEmptyTab == true
        let prefill = mode == .editURL && !fillingEmptyPane ? selectedTab?.tab?.url : nil
        let effectiveMode: CommandBarMode = (mode == .editURL && (selectedTab == nil || fillingEmptyPane)) ? .newTab : mode
        commandBar.highlight = focusedSpace.theme.palette.commandHighlight
        commandBar.focusedSpaceID = focusedSpaceID
        commandBar.open(mode: effectiveMode, prefill: prefill)
        // Always centred in the window, also when opened from the toolbar.
        commandBar.attached = false
        commandBar.panelWidth = min(CraMetrics.commandBarWidth, window.frame.width - 80)
        commandPanel.appearance = nil
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
        if commandPanel.parent != nil { window?.removeChildWindow(commandPanel) }
        let panel = commandPanel!
        // Let CommandBarView's fade-out (0.08 s) play before the panel goes away.
        panel.orderOut(nil)
        window?.makeKeyAndOrderFront(nil)
        currentBrowser?.setFocused(true)
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode, forceNewTab: Bool) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            let fillsEmptyPane = selectedTab?.isEmptyTab == true
            if (mode == .editURL || fillsEmptyPane) && !forceNewTab, selectedTabID != nil {
                loadInSelectedTab(url)
            } else {
                store.createTab(url: url, window: windowID)
            }
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : store.settings.searchEngine.searchURL(typed))
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
            open(s.url ?? store.settings.searchEngine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            store.focusSpace(id, window: windowID)
        case .moveToSpace(let id):
            if let t = selectedTabID { store.moveTab(t, toSpace: id) }
        case .moveToFolder(let id):
            if let t = selectedTabID { store.moveItem(t, to: id, index: nil) }
        }
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        let view = SpaceEditorView(existing: space, profiles: store.profiles, onSave: { [weak self, weak panel] title, emoji, theme, profile, newName in
            guard let self else { return }
            let id: UUID
            if var s = space {
                s.title = title; s.emoji = emoji; s.theme = theme
                self.store.updateSpace(s)
                id = s.id
            } else {
                id = self.store.createSpace(title: title, emoji: emoji, theme: theme).id
            }
            switch profile {
            case .existing(let p): self.store.setProfile(p, forSpace: id)
            case .new: self.store.setProfile(self.store.createProfile(name: newName).id, forSpace: id)
            }
            if let panel { window.endSheet(panel) }
        }, onCancel: { [weak panel] in if let panel { window.endSheet(panel) } })
        panel.contentView = NSHostingView(rootView: view)
        spaceEditor = panel
        window.beginSheet(panel) { [weak self] _ in self?.spaceEditor = nil }
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
        shell.needsLayout = true
        browsers.layoutVisible()
        if commandBar.isOpen { positionCommandPanel() }
        floatingSidebar?.reposition()
        for p in peeks { p.repositionPeek() }
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
        shell.windowActive = true
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
        browsers.adopt(rt.browser, for: rt.tabID)
        refresh()
    }

    private func reclaimPages() {
        guard shell.paneCards.contains(where: \.showsElsewhere) else { return }
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === commandPanel, commandBar.isOpen else { return }
        if Date().timeIntervalSince(commandBarOpenedAt) < 0.6 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandPanel.makeKeyAndOrderFront(nil)
            }
            return
        }
        commandBar.close()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { shell.needsLayout = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        // Left with the green button or ⌃⌘F while a video was fullscreen: the page leaves too.
        if let id = contentFullscreenTab { browsers.runtime(for: id)?.browser.exitFullscreen() }
        contentFullscreenTab = nil
        if shell.contentFullscreen { shell.contentFullscreen = false }
        enteredFullscreenForContent = false
        shell.needsLayout = true
    }

    /// The frame lives in the store's observed prefs, which every sidebar row reads (selection):
    /// it is stored once a resize or move settles, not on every step of it.
    private func saveFrame() {
        frameSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, !window.styleMask.contains(.fullScreen) else { return }
            self.store.updateWindow(self.windowID) { $0.frame = NSStringFromRect(window.frame) }
        }
        frameSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private var frameSaveWork: DispatchWorkItem?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { commandBar.close() }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        tabSwitcher.cancel()
        app.mainWindowWillClose(self)
    }

    /// The window closed while others stay open: its pages close (the tabs stay in
    /// the sidebar) and it lets go of everything that would keep it alive.
    func tearDown() {
        isTornDown = true
        dismissTransientUI()
        for p in peeks { p.closeWindow() }
        // A page another window shows behind its blurred stand-in moves there with its history
        // and state; closed with this window, that window loaded it again from scratch.
        for id in Array(browsers.runtimes.keys) {
            guard let other = app.mainWindows.first(where: { $0 !== self && $0.isShowingElsewhere(id) }),
                  let rt = browsers.release(id) else { continue }
            other.takePage(rt)
        }
        browsers.closeAll()
        for monitor in [scrollMonitor, childClickMonitor, middleClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
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
    private static let titleStripHeight = CraMetrics.contentInset + 4

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !styleMask.contains(.fullScreen),
           let content = contentView, event.locationInWindow.y >= content.bounds.height - Self.titleStripHeight,
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
