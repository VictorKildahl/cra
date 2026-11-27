import AppKit
import CraCEF
import ObjectiveC
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, BrowserManagerDelegate {
    unowned let app: AppDelegate
    /// Back and Forward's history menu (#416).
    let backForwardMenu = SidebarCreationMenuController()
    var store: SidebarStore { app.store }
    let sidebarUI = SidebarUIState()
    let sidebarActions = SidebarActions()
    let overlay = OverlayState()
    private var debugFindResults = false
    let commandBar: CommandBarController
    private(set) var browsers: BrowserManager!
    private(set) var shell: ShellView!
    private var commandPanel: CommandBarPanel!
    /// The ⌘T bar's panel while it is open: where a scripted key press goes (cra://debug?key=…).
    var openCommandPanel: NSWindow? { commandBar.isOpen ? commandPanel : nil }
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
    /// A space or Library swipe is under the fingers: begun, its release not yet seen.
    private var swipeTracking = false
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    /// Points travelled since the space swipe locked, and recent deltas for its release speed.
    private var swipeTravel: CGFloat = 0
    private var swipeSamples: [(time: TimeInterval, dx: CGFloat)] = []
    /// The trackpad ticks of the swipe: Arc's page detent, and one on release (issue #260).
    private var swipeHaptics = PageDetentHaptics()
    /// Shift + wheel over the sidebar adding up toward a space change.
    private var wheelSpaceSwitch = WheelSpaceSwitch()
    /// The Library's reveal a swipe started from: 0 on the first space, 1 in the Library; nil
    /// when the swipe can only page between spaces.
    private var librarySwipeFrom: CGFloat?
    /// Where the Library was sliding when the swipe caught it (LibrarySwipe.reveal's `toward`).
    private var librarySwipeToward: CGFloat?
    private var librarySettleSpring: (clock: SettleClock, from: CGFloat, velocity: CGFloat, target: CGFloat)?
    /// The frames a Library settle has drawn so far.
    private var librarySettleFrames = 0
    private var librarySettleLink: CADisplayLink?
    /// Frames of the Library's slide on which the space pages' mask was still easing after the column (#717).
    private var libraryMaskTrailFrames = 0
    /// Shows the lists' overlay knob again once a swipe's scroller flash has faded.
    private var swipeKnobReveal: DispatchWorkItem?
    /// Whether a touch over the sidebar hides the lists' knob (#77), or leaves it showing (#544).
    private var listKnob = ListKnobGate()
    /// Whether the window is full screen for a page's own (a video's), and leaves it with the page (#636).
    private var pageFullscreenWindow = PageFullscreenWindow()
    /// The tab whose page (a video) is in element fullscreen.
    private var contentFullscreenTab: UUID?
    /// Esc in a page's full screen while the page holds the keyboard (Arc: "[⎋] again to exit fullscreen").
    private var keyboardLockEscape = KeyboardLockEscape()
    /// A page's notice that came while the window was still going full screen: shown once it is there.
    private var pendingNoticeToast: ExclusiveAccessNotice.Toast?
    private var lastSidebarVisible = true
    /// The theme the window's root views were made with.
    private var shownTheme: SpaceTheme?
    /// Settings ▸ Tabs ▸ "Translucent sidebar" as the window last drew it (#366).
    private var shownGlass: Bool?
    private var shownLightMaterial: Bool?
    private var lastSidebarWidth: CGFloat = 0
    private var commandBarOpenedAt = Date.distantPast
    /// The sidebar address the open bar hangs from (#663), nil while it is the centred bar.
    private var commandBarAnchor: NSRect?
    /// ⌘L opened Arc's panel over the focused page's developer bar (#663 follow-up).
    private var commandBarOverDeveloperBar = false
    private var commandBarClosingClick = DismissingClick()
    /// The window that took the keys from the bar and closed it (#429); nil when the bar closed itself.
    private var commandBarLostKeysTo: CommandBarClosing.KeyHolder?
    private let toast = ShinyToast()
    /// Each live tab's wait for its first response (GitHub #256), the tab whose notice the toast
    /// shows (nil once another toast took its place), and the check when the next one is due.
    private var slowResponses: [UUID: SlowResponseNotice] = [:]
    private var slowResponseToastTab: UUID?
    /// The page whose protected-video prompt this window last showed (its tab and page key), and
    /// whether the toast still shows it (false once another toast took its place or it was answered).
    private var protectedVideoPrompt: (tab: UUID, key: String)?
    private var protectedVideoPromptUp = false
    private var slowResponseCheck: ScheduledWork?
    /// releaseHiddenFrames, HiddenFrameRelease.afterPageChange after the last page change.
    private var frameReleaseAfterChange: ScheduledWork?
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
    /// The link preview over the page's bottom left (#689).
    private(set) var statusBubble: StatusBubbleView?
    /// Arc's Blank Window (#220): a sidebar of its own, "This Window", in the normal profile.
    var isBlank: Bool { store.isBlank(window: windowID) }
    /// Shows only a space of its own (incognito or Blank): no other spaces, no space switching.
    var isStandalone: Bool { isIncognito || isBlank }
    var focusedSpaceID: UUID { store.focusedSpaceID(window: windowID) }
    var focusedSpace: Space { store.focusedSpace(window: windowID) }
    var selectedTabID: UUID? { store.selectedTabID(window: windowID) }
    /// A sidebar tab or a link dragged over the panes (#419).
    private(set) lazy var splitDrop = PageSplitDrop(owner: self)
    /// The sidebar holds the content area's edge on its side: shown and docked, not floating over the page.
    var sidebarDocked: Bool { sidebarVisible && !shell.floatingSidebar }
    /// How this window presents its sidebar now, from what it shows (CraCore SidebarPresentation).
    var sidebarPresentation: SidebarPresentation {
        SidebarPresentation(sidebarVisible: sidebarVisible, hasSelectedTab: selectedTabID != nil,
                            folderPreviewOpen: FolderPreviewController.shared.isOpen, pageFullscreen: shell.contentFullscreen)
    }
    var selectedTab: SidebarItem? { store.selectedTab(window: windowID) }
    var sidebarVisible: Bool {
        get { store.window(windowID).sidebarVisible }
        set { store.updateWindow(windowID) { $0.sidebarVisible = newValue } }
    }

    /// A new window's size with nothing to go by.
    static let defaultSize = CGSize(width: 1400, height: 880)

    init(app: AppDelegate, session: WindowSession) {
        self.app = app
        windowID = session.id
        isIncognito = session.isIncognito
        commandBar = CommandBarController(engine: app.engine, store: app.store)
        let frame = session.frame.map { NSRectFromString($0) } ?? NSRect(origin: .zero, size: Self.defaultSize)
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
        // A test instance (CRA_TEST_SCREEN) keeps every window on its display.
        if TestScreen.screen != nil {
            if session.frame == nil { window.centerOnTestScreen() } else { window.setFrame(TestScreen.place(frame), display: false) }
        } else if session.frame != nil, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        window.delegate = self
        sidebarUI.windowID = session.id

        let store = app.store
        SidebarGlassSetting.shared.isOn = store.settings.translucentSidebar
        let palette = focusedSpace.theme.palette
        let statusBubble = StatusBubbleView(overlay: overlay)
        self.statusBubble = statusBubble
        shell = ShellView(frame: window.contentView!.bounds,
                          background: SpaceBackgroundView(store: store, ui: sidebarUI),
                          sidebar: SidebarView(store: store, ui: sidebarUI, actions: sidebarActions, favicons: app.favicons),
                          toolbar: PaneToolbarView(paneTabID: nil, store: store, ui: sidebarUI, actions: sidebarActions),
                          status: statusBubble,
                          // In a conversation Ask on Page's field only asks: typing doesn't find.
                          find: FindBarView(overlay: overlay, onFind: { [weak self] q, fwd in
                                                guard let self, self.askOnPage.findsWhileTyping else { return }
                                                self.find(q, forward: fwd)
                                            },
                                            onClose: { [weak self] in self?.hideFindBar() }))
        // ⇧ over a link says "in Peek" only where a Shift-click peeks (browserManagerOpensPeek, #689).
        statusBubble.peekOnShiftClick = { [weak self] in
            guard let self else { return false }
            return !self.isIncognito && self.app.store.settings.peekOnShiftClick
        }
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        shell.sidebarVisible = sidebarVisible
        shell.showToolbar = store.settings.showsBar(above: selectedTabID.flatMap { store.item($0)?.tab?.url })
        shell.autoHideToolbar = store.settings.hidesToolbar(above: selectedTabID.flatMap { store.item($0)?.tab?.url })
        shell.edgeToEdge = store.settings.edgeToEdgeContent
        shell.edgeToEdgeRoundedCorners = store.settings.edgeToEdgeRoundedCorners
        shell.pageMargin = store.settings.pageMargin
        shell.sidebarSide = store.settings.sidebarSide
        lastSidebarVisible = sidebarVisible
        window.trafficLightsHidden = !sidebarVisible
        lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
        window.contentView = shell
        // Tab (with Full Keyboard Access) goes through the views there are now: toolbars come and go with
        // the cards, and their buttons with the page (ToolbarKeyboard).
        window.autorecalculatesKeyViewLoop = true
        window.backgroundColor = NSColor(palette.gradientColors.first ?? .gray)

        browsers = BrowserManager(store: store, favicons: app.favicons, container: shell.parkingView, clock: app.composition.clock)
        // What extensions set for a tab (chrome.action.setIcon with tabId) went with its page.
        browsers.pageClosed = { ExtensionStore.shared.forgetActionTab($0) }
        browsers.delegate = self
        // A split pane's thumbnail is taken in its place's shape on the split's switcher card (#554).
        browsers.snapshotAspect = { [weak self] id in
            guard let self, let split = self.store.item(id)?.parentID.flatMap(self.store.item), split.isSplit,
                  let pane = split.children.firstIndex(of: id) else { return nil }
            let factors = SplitPaneLayout.normalizedFactors(ids: split.children, stored: split.split?.widthFactors ?? [:])
            return SwitcherSplitLayout.paneAspect(in: TabSwitcherMetrics.thumbnail, widths: split.children.map { factors[$0] ?? 0 }, pane: pane)
        }
        overlay.onFindQueryChange = { [weak self] query in
            guard let self else { return }
            if self.overlay.findVisible, self.askOnPage.findsWhileTyping { self.find(query, forward: true) }
            else { self.browsers.prepareFind(query) }
        }
        browsers.windowID = session.id
        browsers.pageAdopted = { [weak self] tab, previousWindow in
            guard let self else { return }
            let downloads = TidyDownloadsService.shared.transferSources(tab: tab, from: previousWindow, to: self.windowID)
            self.windowDownloads.formUnion(downloads)
            if !downloads.isEmpty { self.watchDownloads() }
            self.app.mainWindows.first(where: { $0.windowID == previousWindow })?.windowDownloads.subtract(downloads)
        }
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
        shell.dropTarget = splitDrop
        shell.registerForSplitDrops()
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
            case "recentTab", "recentTabAllSpaces": return 1
            case "recentTabBackward", "recentTabAllSpacesBackward": return -1
            default: return nil
            }
        }

        wireActions()
        // Arc's drag of the sidebar's edge (#287, SidebarResize): the edge stays under the pointer,
        // a slow drag snaps to 228 pt with a haptic tick, and the sidebar hides under 82 pt and
        // comes back at 164 if the drag returns before letting go.
        shell.resizeHandle.onBegin = { [weak self] in
            guard let self else { return }
            sidebarResize = SidebarResize(startWidth: Double(shell.sidebarWidth))
            hiddenByResize = false
        }
        shell.resizeHandle.onResize = { [weak self] translation, speed in
            guard let self, var resize = sidebarResize else { return }
            let wasSnapped = resize.isSnapped
            let outcome = resize.update(translation: Double(translation), speed: Double(speed))
            sidebarResize = resize
            switch outcome {
            case .hidden where !shell.floatingSidebar:
                // Hidden this way, it keeps the width the drag started from (Arc: ⌘S brings back
                // a 200 pt sidebar dragged shut from 200).
                shell.sidebarWidth = CGFloat(resize.startWidth)
                if sidebarVisible {
                    store.chooseSidebar(visible: false, window: windowID)
                    hiddenByResize = true
                }
            case .hidden:
                shell.sidebarWidth = CGFloat(SidebarWidth.minimum)
            case .width(let w):
                shell.sidebarWidth = CGFloat(w)
                if hiddenByResize {
                    hiddenByResize = false
                    store.chooseSidebar(visible: true, window: windowID)
                }
            }
            shell.layoutSubtreeIfNeeded()
            if resize.isSnapped, !wasSnapped {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        shell.resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            sidebarResize = nil
            // The first time a drag hides the sidebar, Arc's tip says how to get it back
            // (hasHiddenSidebarWithGesture: once, never again).
            if hiddenByResize, !UserDefaults.standard.bool(forKey: Self.hiddenSidebarByDragKey) {
                UserDefaults.standard.set(true, forKey: Self.hiddenSidebarByDragKey)
                let keys = KeyBindingRegistry.shared.action("toggleSidebar")?.primary?.display ?? "⌘S"
                showToast("You can use", keyCap: (keys, "to easily show and hide your Sidebar!"))
            }
            hiddenByResize = false
            store.prefs.sidebarWidth = Double(shell.sidebarWidth)
            lastSidebarWidth = shell.sidebarWidth
        }
        // Arc: a double click on the edge gives the sidebar its default width, 228 pt (#819).
        shell.resizeHandle.onDoubleClick = { [weak self] in
            guard let self, sidebarResize == nil else { return }
            let width = CGFloat(SidebarResize.doubleClickWidth)
            shell.sidebarWidth = width
            shell.layoutSubtreeIfNeeded()
            store.prefs.sidebarWidth = Double(width)
            lastSidebarWidth = width
            CraLog.note("sidebar edge double click: \(Int(width)) pt")
        }
        shell.onEdgeHover = { [weak self] inStrip in
            if inStrip { self?.floatingSidebar?.edgeHovered() } else { self?.floatingSidebar?.edgeLeft() }
        }

        installSwipeMonitor()
        installChildClickMonitor()
        installFloatingSidebar()
        observeStore()
        refresh()
        shell.onDevToolsFrame = { [weak self] rect in
            guard let self, let id = self.browsers.visibleTabID else { return }
            self.positionDevToolsWindow(rect, tab: id)
        }
        shell.onPaneFrames = { [weak self] frames in self?.positionPageWindows(frames) }
        // The find bar hangs under the floating toolbar and keeps it while the pointer is on it.
        shell.onFloatingToolbarChange = { [weak self] animated in self?.refitFindPanel(followingToolbar: animated) }
        shell.toolbarFollowers = { [weak self] in
            guard let self, let find = findPanel, overlay.findVisible else { return [] }
            return [find]
        }
        // Only an embedded page is cut off by the window; one in its own window would show past it.
        shell.pageBesideLibrary = { [weak self] in
            guard let self, EmbeddedPages.isEnabled, sidebarUI.libraryPage != nil || sidebarUI.libraryReveal != nil else { return nil }
            return .init(tabSidebar: libraryShowedSidebar ? nil : CGFloat(store.prefs.sidebarWidth))
        }
        shell.onAnimatePaneFrames = { [weak self] frames, d, timing in self?.animatePageWindows(to: frames, duration: d, timing: timing) }
        // A Peek keeps to the page area while the sidebar slides in or out under it (#402).
        shell.onSidebarSlideFrame = { [weak self] in self?.peeks.filter { !$0.isParked }.forEach { $0.repositionPeek() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commandBarCraCameBack() }
            Task { @MainActor in self?.refreshMaterialActive(); self?.sidebarUI.appActive = true }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMaterialActive()
                self?.sidebarUI.appActive = false
                if let self { LinkSummaryPreviewController.shared.stop(windowID: self.windowID) }
            }
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
        sidebarActions.openCommandBar = { [weak self] mode in
            // A click on the address field while it shows a Peek edits the Peek's address, as ⌘L there does (#648).
            if mode == .editURL, let peek = self?.sidebarPeek { peek.openCommandBar() } else { self?.openCommandBar(mode) }
        }
        sidebarActions.openAddressPanel = { [weak self] mode in
            if mode == .editURL, let peek = self?.sidebarPeek { peek.openCommandBar() } else { self?.openCommandBar(mode, fromSidebarAddress: true) }
        }
        sidebarActions.closeTab = { [weak self] id in self?.closeTab(id) }
        sidebarActions.closeTabFromItsMenu = { [weak self] id in self?.closeTab(id, fromItsMenu: true) }
        sidebarActions.moveBlankWindow = { [weak self] space in
            guard let self else { return }
            self.app.moveBlankWindow(self, toSpace: space)
        }
        sidebarActions.tearOffTab = { [weak self] id, point in
            guard let self else { return }
            self.app.tearOffTab(id, at: point, from: self)
        }
        // The sidebar's ← → ↻ act on the Peek its address field shows (#648), else on the tab.
        // The click made this window key: the keys go back to the Peek, so ⌘[ and ⌘R carry on there.
        // ⌘-click opens the page that way in a new tab instead (#797).
        sidebarActions.goBack = { [weak self] in
            guard let self else { return }
            guard let peek = self.sidebarPeek else { self.commandClicked ? self.openHistoryInNewTab(.back) : self.goBack(); return }
            peek.goBack()
            peek.focusPage()
        }
        sidebarActions.goForward = { [weak self] in
            guard let self else { return }
            guard let peek = self.sidebarPeek else {
                if self.commandClicked { self.openHistoryInNewTab(.forward) } else { self.currentBrowser?.goForward() }
                return
            }
            peek.browser?.goForward()
            peek.focusPage()
        }
        sidebarActions.showBackForwardMenu = { [weak self] tab, direction, anchor in
            self?.showBackForwardMenu(tab: tab, direction: direction, anchor: anchor)
        }
        sidebarActions.reload = { [weak self] in
            let peek = self?.sidebarPeek
            guard let b = peek?.browser ?? self?.currentBrowser else { return }
            b.isLoading ? b.stopLoading() : b.reload()
            peek?.focusPage()
        }
        // A new space is made in the sidebar (Arc's Create a Space page); an existing one keeps the sheet.
        sidebarActions.editSpace = { [weak self] s in
            if let s { self?.showSpaceEditor(space: s) } else { self?.beginSpaceCreation() }
        }
        sidebarActions.cancelSpaceCreation = { [weak self] in self?.cancelSpaceCreation() }
        sidebarActions.commitSpaceCreation = { [weak self] in self?.commitSpaceCreation() }
        sidebarActions.chooseCreationTheme = { [weak self] row in self?.showCreationThemeEditor(beside: row) }
        sidebarActions.newProfileForCreation = { [weak self] in
            guard let self, let window = self.window else { return }
            self.showNewProfileDialog(over: window)
        }
        sidebarActions.closeCreationPanels = { [weak self] in self?.closeCreationPanels() }
        sidebarActions.newSpaceWith = { [weak self] ids in
            self?.beginSpaceCreation { space in
                guard let self else { return }
                for id in ids { self.store.moveTab(id, toSpace: space, window: self.windowID) }
                self.sidebarUI.clearPicks()
            }
        }
        sidebarActions.changeSpaceIcon = { [weak self] s, anchor in self?.showSpaceIconPicker(space: s, anchor: anchor) }
        sidebarActions.editSpaceTheme = { [weak self] s in self?.showSpaceStyleEditor(space: s) }
        sidebarActions.editSpaceThemeBeside = { [weak self] s, card in self?.showSpaceStyleEditor(space: s, beside: card) }
        sidebarActions.newProfile = { [weak self] id in self?.showNewProfileDialog(forSpace: id) }
        sidebarActions.manageSpaces = { [weak self] in self?.showManageSpaces() }
        sidebarActions.deleteSpace = { [weak self] s in self?.app.confirmDeleteSpace(s, in: self?.window) }
        sidebarActions.toggleSidebar = { [weak self] in self?.toggleSidebar() }
        sidebarActions.toggleLibrary = { [weak self] in self?.toggleLibrary() }
        sidebarActions.showLibrary = { [weak self] page in self?.showLibrary(page) }
        sidebarActions.closeLibrary = { [weak self] in self?.leaveLibrary() }
        sidebarActions.restoreArchived = { [weak self] id in
            guard let self else { return }
            _ = self.store.restoreArchived(id)
            self.closeLibrary()
        }
        sidebarActions.resetPinnedTab = { [weak self] id in self?.resetPinnedTab(id) }
        sidebarActions.shareTabInstead = { [weak self] id in self?.shareTabInstead(id) }
        sidebarActions.separatePinnedTab = { [weak self] id in self?.separatePinnedTab(id) }
        sidebarActions.separateFavorite = { [weak self] id in self?.separateFavorite(id) }
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
        sidebarActions.commitAddress = { [weak self] typed in
            guard let self else { return }
            // Edited in place while the field shows a Peek: the Peek loads it (#648).
            if let peek = self.sidebarPeek {
                if case .load(let url) = SidebarAddressEdit.commit(typed: typed, currentURL: peek.currentURL, pinned: false,
                                                                   searchURL: self.commandBar.engine.searchURL) {
                    peek.navigate(url)
                }
                return
            }
            guard let id = self.selectedTabID else { return }
            self.commitAddress(typed, in: id)
        }
        sidebarActions.commitTabAddress = { [weak self] id, typed in self?.commitAddress(typed, in: id) }
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
            case "goBack": self.commandClicked ? self.openHistoryInNewTab(.back, from: id) : self.goBack(id)
            case "goForward": self.commandClicked ? self.openHistoryInNewTab(.forward, from: id) : b.goForward()
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
        sidebarActions.showTranslate = { [weak self] id, anchor in self?.showTranslate(id, from: anchor) }
        sidebarActions.showBlockedPopups = { [weak self] id, anchor in self?.showBlockedPopups(id, from: anchor) }
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
            // The window in use is Cra's main window or one of its children at any depth: a popup Chrome opens
            // (chrome.action.openPopup()) is key itself, a child of the page's host strip, a child of the window.
            guard let main = app?.main, let window = main.window, var key = NSApp.keyWindow else { return nil }
            while key !== window {
                guard let parent = key.parent else { return nil }
                key = parent
            }
            return main.extensionPopupAnchor(id)
        }
        // Chromium's install and removal prompts come without a parent window (#349): they hang
        // over the browser window in use, where a sheet does.
        ChromiumDialogs.start { [weak app] in app?.main?.window }
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
            } else if id.hasPrefix("castTab:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                self?.castTab(uuid)
            } else if id.hasPrefix("muteTab:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                let muted = self?.store.item(uuid)?.tab?.muted ?? false
                self?.app.runtime(for: uuid)?.browser.setAudioMuted(muted)
            } else if id == "copyURL", let peek = self?.sidebarPeek {
                // The address field's link button while the field shows a Peek copies the Peek's (#648).
                peek.copyURL()
            } else {
                self?.app.perform(id)
            }
        }
        commandBar.onCommit = { [weak self] s, typed, mode in self?.handleCommit(s, typed: typed, mode: mode) }
        commandBar.onOpenInBackground = { [weak self] s, typed in self?.openInBackground(s, typed: typed) ?? false }
        commandBar.onOpenInSplit = { [weak self] s, typed in self?.openInSplit(s, typed: typed) ?? false }
        commandBar.onInstantLinks = { [weak self] phrase, engine in self?.runInstantLinks(phrase, engine: engine) }
        commandBar.onClose = { [weak self] in self?.hideCommandPanel() }
        commandBar.onNoticeSettings = { [weak self] in self?.app.showSettingsWindow(on: .profiles) }
        commandBar.onNoticeLearnMore = { [weak self] in self?.openTab(Self.privacyPage) }
        commandBar.spaceName = { [weak self] id in self?.store.space(id)?.title ?? "" }
    }

    // MARK: Observation

    private func observeStore() {
        guard !isTornDown else { return }
        withObservationTracking {
            _ = store.revision
            _ = store.prefs
            _ = store.settings
            _ = TidyTabsService.shared.modelAvailable
            _ = store.spaces
            _ = SystemAppearance.shared.isDark
            _ = TidyTabsService.shared.modelAvailable
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeStore()
            }
        }
    }

    func refresh() {
        LinkSummaryPreviewController.shared.validate(windowID: windowID)
        guard !isTornDown, !isPutAway else { return }
        let space = focusedSpace
        // Every palette reads the setting; the store's change reaches the windows here (SidebarGlassSetting).
        if SidebarGlassSetting.shared.isOn != store.settings.translucentSidebar { SidebarGlassSetting.shared.isOn = store.settings.translucentSidebar }
        let palette = space.theme.palette
        // Its extensions belong to the space's profile.
        if siteControlCenter.isShown, siteControlCenterSpaceID != space.id { siteControlCenter.close() }
        // A space change under an open ⌘T bar lists that space's tabs, as Arc's bar does (#721).
        commandBar.follow(space: space.id)
        // refresh runs on every store change (each page title, each window move). A new root
        // view rebuilds its whole SwiftUI tree, and a new window appearance or background redraws
        // every view, so all of these follow the theme only when it changes. What the root
        // views show beyond the palette they observe themselves.
        // The material too: View ▸ Appearance picks it for every space without changing the theme (#700).
        if shownTheme != space.theme.shown || shownGlass != palette.glass || shownLightMaterial != palette.lightMaterial {
            shownTheme = space.theme.shown
            shownGlass = palette.glass
            shownLightMaterial = palette.lightMaterial
            // A swipe in the floating sidebar changes space under it (issue #12).
            floatingSidebar?.refreshBackdrop()
            shell.isDarkTheme = palette.isDark
            shell.cardGround = (space.theme.appearance, CardVeil.lightness(of: space.theme.shown.colors))
            // The space's light or dark goes to the window's content (sidebar, toolbar, pages'
            // frame), not to the window: AppKit hands a window's appearance to every menu, sheet,
            // alert and popover it presents, and those follow macOS as Arc's do, whatever the
            // space colour (#171).
            shell.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            // The command bar follows macOS (#187); only its selected row and info badge take the
            // space's palette, also when the space changes under an open bar.
            commandBar.theme = space.theme.shown
            // Vibrant themes see through to the desktop like Arc; others are opaque.
            shell.vibrancy.isHidden = !palette.vibrant
            shell.vibrancyLift.isHidden = !palette.vibrant
            shell.setTheme(vibrantDark: palette.isDark, vibrantLight: palette.vibrant && !palette.isDark, solid: palette.solid,
                           lightMaterial: palette.lightMaterial, darkGradient: palette.darkGradient, glass: palette.glass)
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
        // That bar floats over the page when the setting says so (ToolbarAutoHide); a split's bars never do.
        let hidesBar = store.settings.hidesToolbar(above: panes.count == 1 ? store.item(panes[0])?.tab?.url : nil)
        if shell.autoHideToolbar != hidesBar { shell.autoHideToolbar = hidesBar }
        if shell.edgeToEdge != store.settings.edgeToEdgeContent { shell.edgeToEdge = store.settings.edgeToEdgeContent }
        shell.edgeToEdgeRoundedCorners = store.settings.edgeToEdgeRoundedCorners
        shell.pageMargin = store.settings.pageMargin
        if shell.sidebarSide != store.settings.sidebarSide { moveSidebar(to: store.settings.sidebarSide) }
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
        // Arc keeps the find bar with the tab it was opened on: it goes when you switch away (before
        // browsers.show, so the old page stops finding) and comes back when you return.
        let findReturns = findParked && !overlay.findVisible && selected != nil && selected == findTabID
        if overlay.findVisible, selected != findTabID { hideFindBar(); findParked = true }
        if live != browsers.visibleTabIDs || liveFocus != browsers.visibleTabID
            || live.contains(where: { browsers.runtime(for: $0) == nil && store.item($0)?.isEmptyTab == false })
            || live.contains(where: browsers.waitsForItsPane) {
            // Arc: a tab switch puts a playing video in Picture in Picture, a space switch doesn't (#703).
            let autoPiP = AutoPictureInPictureMoment.opensOnLeaving(from: pagesShownForSpace, to: focusedSpaceID)
            browsers.show(live, focused: liveFocus, focus: !commandBar.isOpen, autoPictureInPicture: autoPiP)
        } else if pagesShownForSpace != focusedSpaceID {
            browsers.spaceChanged(to: focusedSpaceID)
        }
        pagesShownForSpace = focusedSpaceID
        if overlay.findVisible { syncAskOnPage() } else { askOnPage.service.refresh() }
        shell.layoutContentChildren()
        // After browsers.show: the bar finds on the page now in front (showFindBar does). Typing stays with the page.
        if findReturns { showFindBar(focus: false) }
        syncPeeks(onScreen: panes)
        syncRingPanel()
        syncSidebarUI()
        window?.title = selectedTab?.displayTitle ?? space.title

        // Another space came to the front (a shortcut, the menu) while one was being made: the page goes.
        if let origin = creationOrigin, sidebarUI.spaceCreation != nil, focusedSpaceID != origin { cancelSpaceCreation() }
        if sidebarVisible != lastSidebarVisible {
            lastSidebarVisible = sidebarVisible
            if lastSidebarVisible, !shell.contentFullscreen, let floating = floatingSidebar, floating.beginDock() {
                // Docking the sidebar while it is out over the window: it grows into place on the
                // window's own slide, and the window's buttons come back once it is docked, as the floating
                // sidebar's stand-ins go. A page in full screen docks it out of sight, the old way.
                shell.animateSidebar(visible: true, floating: false, fullscreen: shell.contentFullscreen, width: shell.sidebarWidth,
                                     alongside: { floating.dockProgress($0) },
                                     completion: { [weak self] in
                                         if floating.finishDock() {
                                             let drift = self?.shell.lastSidebarSlidePageDrift.map { ": page moved \($0) pt" } ?? ""
                                             CraLog.note("sidebar docked in place\(drift)")
                                         }
                                         guard let self else { return }
                                         (self.window as? CraWindow)?.trafficLightsHidden = !self.lastSidebarVisible
                                     })
            } else {
                (window as? CraWindow)?.trafficLightsHidden = !lastSidebarVisible
                // Anchoring while the sidebar floats: bring it home first so it slides from there.
                if lastSidebarVisible { floatingSidebar?.prepareForAnchoring() }
                // Hidden in a window with no tab, the sidebar is held open over it (#483): the shell lays
                // out for a floating sidebar, so its flags match the panel the sidebar is about to be in.
                let heldOpen = sidebarPresentation.mode == .heldOpen
                shell.animateSidebar(visible: lastSidebarVisible, floating: heldOpen, fullscreen: shell.contentFullscreen, width: shell.sidebarWidth)
            }
            floatingSidebar?.sidebarVisibilityChanged()
        }
        holdSidebarOpenIfEmpty()
        if CGFloat(store.prefs.sidebarWidth) != lastSidebarWidth {
            lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
            shell.sidebarWidth = sidebarUI.libraryPage.map { libraryWidth($0) } ?? lastSidebarWidth
        }
    }

    /// The browser window the user is in (AppDelegate follows the key window).
    private var isActiveWindow: Bool { store.activeWindowID == windowID }

    /// `cra://debug?tabIcon=` (#640): "picker" opens Change Icon…'s picker over the selected tab's row, as the
    /// menu row does; "emoji:<e>", "symbol:<name>" or "none" picks that, as the picker does. Then logs the tab's
    /// custom icon ("tab icon <step>: key=custom-emoji- dark=-" or "key=none").
    func testTabIcon(_ step: String) {
        guard let id = selectedTabID else { return CraLog.note("tab icon \(step): no tab") }
        if step == "picker" {
            func list(in v: NSView) -> SpaceListView? {
                if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
                return v.subviews.lazy.compactMap { list(in: $0) }.first
            }
            guard let l = window?.contentView.flatMap(list(in:)) else { return CraLog.note("tab icon picker: no list") }
            l.showTabIconPicker(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CraLog.note("tab icon picker: \(TabIconPicker.shown?.isShown == true ? "shown" : "not shown")")
            }
            return
        }
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let icon: SpaceIcon = parts.first == "emoji" && parts.count == 2 ? .emoji(parts[1])
            : parts.first == "symbol" && parts.count == 2 ? .symbol(parts[1]) : .none
        TabIconPicker.apply(icon, to: id, store: store, favicons: app.favicons)
        let key = store.item(id)?.tab?.customIconKey
        let prefix = key.map { k in ["custom-emoji-", "custom-symbol-", "custom-"].first { k.hasPrefix($0) } ?? k } ?? "none"
        let dark = app.favicons.glyphIsDark(forKey: key).map { $0 ? "1" : "0" } ?? "-"
        let image = key.flatMap { app.favicons.image(forKey: $0) } != nil ? 1 : 0
        CraLog.note("tab icon \(step): key=\(prefix) dark=\(dark) image=\(image)")
    }

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

    /// `cra://debug?sidebarEdge=doubleClick`: a double click's two presses sent to the sidebar's edge as AppKit sends
    /// them (#819), then the sidebar's width.
    func testSidebarEdgeDoubleClick() {
        let handle = shell.resizeHandle
        guard let window, handle.window === window else { CraLog.note("sidebar edge: no handle"); return }
        let at = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        CraLog.note("sidebar edge before: \(Int(shell.sidebarWidth)) pt")
        for (type, clicks) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2)] {
            guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { continue }
            if type == .leftMouseDown { handle.mouseDown(with: e) } else { handle.mouseUp(with: e) }
        }
        CraLog.note("sidebar edge after: \(Int(shell.sidebarWidth)) pt, saved \(Int(store.prefs.sidebarWidth)) pt")
    }

    /// `cra://debug?edgeDrag`: the focused space's list held at the sidebar's edge for `hold`
    /// seconds as a row's drag would be; logs the space before and after (#499).
    func testEdgeDrag(_ direction: SidebarEdgeDrag.Direction, hold: TimeInterval) {
        func list(in v: NSView) -> SpaceListView? {
            if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
            return v.subviews.lazy.compactMap { list(in: $0) }.first
        }
        guard let l = window?.contentView.flatMap(list(in:)) else { CraLog.note("edgeDrag: no list"); return }
        let from = focusedSpace.title
        l.testEdgeDrag(direction, hold: hold) { [weak self] in
            guard let self else { return }
            CraLog.note("edgeDrag: \(direction) \(String(format: "%.1f", hold))s from=\(from) to=\(self.focusedSpace.title)")
        }
    }

    /// `cra://debug?dropLink`: a link from a page or another app let go on the focused space's list
    /// (#419), from a pasteboard holding what Mail or a page's link drag holds: its address and,
    /// with `name`, its text. It goes through the drop's own pasteboard read, placement and tab.
    func testDropLink(_ url: String, name: String?, row text: String?, onto: Bool) {
        func list(in v: NSView) -> SpaceListView? {
            if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
            return v.subviews.lazy.compactMap { list(in: $0) }.first
        }
        guard let l = window?.contentView.flatMap(list(in:)) else { CraLog.note("dropLink: no list"); return }
        let pb = NSPasteboard(name: .init("dk.kildahl.cra.test-drop-link"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(url, forType: .URL)
        if let name { item.setString(name, forType: .urlName) }
        pb.writeObjects([item])
        guard let link = SpaceListView.link(on: pb) else { CraLog.note("dropLink: refused \(url)"); return }
        guard let point = l.testDropPoint(row: text, onto: onto) else { CraLog.note("dropLink: no row with \(text ?? "")"); return }
        let drop = l.resolve(dragged: SidebarListDrop.link, at: point)
        CraLog.note("dropLink: line \(l.testLineInsets(drop))")
        // Where the tab landed, read back from the store: its folder's name, or its section, and its place there.
        guard let tab = l.dropLink(link, drop: drop), let parent = tab.parentID.flatMap(store.item) else {
            CraLog.note("dropLink: refused \(link.url)"); return
        }
        let place = parent.isFolder ? (parent.title ?? "folder") : (store.isPinned(tab.id) ? "Pinned" : "Today")
        CraLog.note("dropLink: opened \(link.url) in \(place) at \(parent.children.firstIndex(of: tab.id) ?? -1)")
    }

    /// `cra://debug?pickedMenu=<n>`: picks the focused space's first n listed tabs, as ⌘-click does,
    /// and logs the menu a right-click on the first one opens (#356): "|" between rows, "──" for a
    /// separator, "▸" after a submenu, " (off)" after a dimmed row. `run` picks the row (or a submenu's
    /// row) with that title (its "…" may be left off) and logs what it copied; the clipboard gets its
    /// old contents back.
    func testPickedMenu(count: Int, label: String, run: String?) {
        func rows(in v: NSView) -> [TabRowView] {
            (v as? TabRowView).map { [$0] } ?? v.subviews.flatMap { rows(in: $0) }
        }
        let listed = store.listedTabIDs(in: focusedSpaceID)
        guard listed.count >= count, let first = listed.first,
              let row = window?.contentView.flatMap(rows(in:))?.first(where: { $0.model?.id == first })
        else { CraLog.note("picked menu \(label): no row"); return }
        sidebarUI.multiSelection = Set(listed.prefix(count))
        guard let menu = row.contextMenu(at: .zero) else { CraLog.note("picked menu \(label): no menu"); return }
        CraLog.note("picked menu \(label): \(Self.menuReadout(menu))")
        let rows = menu.items + menu.items.flatMap { $0.submenu?.items ?? [] }
        guard let run, let item = rows.first(where: { $0.title == run || $0.title == run + "…" }), let owner = item.menu else { return }
        let copied = Self.probeClipboard { owner.performActionForItem(at: owner.index(of: item)) }
        CraLog.note("picked menu \(label) ran \(run): \(copied) picks=\(sidebarUI.multiSelection.count)")
    }

    /// For test hooks: a menu's rows, "|" between rows, "──" for a separator, "▸" after a submenu,
    /// " (off)" after a dimmed row, " ⌥" after a row ⌥ shows in place of the one before it.
    static func menuReadout(_ menu: NSMenu) -> String {
        menu.items.map { item -> String in
            if item.isSeparatorItem { return "──" }
            return item.title + (item.submenu != nil ? " ▸" : "") + (item.isEnabled ? "" : " (off)") + (item.isAlternate ? " ⌥" : "")
        }.joined(separator: "|")
    }

    /// `cra://debug?tabMenu=<n>`: logs the menu a right-click on the focused space's n-th listed tab
    /// opens, nothing picked (rows as menuReadout writes them, then its Edit Pinned Page and Move to
    /// submenus). `run` picks a row by title, in a submenu too, and logs the space's pinned and Today
    /// rows (page queries) and the open tab (#600).
    func testTabMenu(_ n: Int, label: String, run: String?, split: Bool = false, folder: Bool = false) {
        let kind = folder ? "folder menu" : split ? "split menu" : "tab menu"
        func rows(in v: NSView) -> [SidebarRowView] {
            if let r = v as? TabRowView, !split, !folder { return [r] }
            if let r = v as? FolderRowView, folder, !r.isHiddenOrHasHiddenAncestor { return [r] }
            if let r = v as? SplitRowView, split, !r.isHiddenOrHasHiddenAncestor { return [r] }
            return v.subviews.flatMap { rows(in: $0) }
        }
        let found = window?.contentView.flatMap(rows(in:)) ?? []
        let row: SidebarRowView?
        if folder {
            let folders = found.compactMap { $0 as? FolderRowView }.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
            row = folders.indices.contains(n - 1) ? folders[n - 1] : nil
        } else if split {
            // The n-th split row from the top of the list.
            let splits = found.compactMap { $0 as? SplitRowView }.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
            row = splits.indices.contains(n - 1) ? splits[n - 1] : nil
        } else {
            let listed = store.listedTabIDs(in: focusedSpaceID)
            row = listed.indices.contains(n - 1) ? found.first { ($0 as? TabRowView)?.model?.id == listed[n - 1] } : nil
        }
        guard let row else { CraLog.note("\(kind) \(label): no row \(n)"); return }
        sidebarUI.clearPicks()
        guard let menu = row.contextMenu(at: .zero) else { CraLog.note("\(kind) \(label): no menu"); return }
        CraLog.note("\(kind) \(label): \(Self.menuReadout(menu))")
        for item in menu.items where item.submenu != nil && (["Edit Pinned Page", "Move to"].contains(item.title) || split) {
            CraLog.note("\(kind) \(label) \(item.title): \(Self.menuReadout(item.submenu!))")
        }
        let all = menu.items + menu.items.flatMap { $0.submenu?.items ?? [] }
        guard let run, let item = all.first(where: { $0.title == run }), let owner = item.menu else { return }
        owner.performActionForItem(at: owner.index(of: item))
        guard let space = store.space(focusedSpaceID) else { return }
        let query = { (id: UUID) in self.store.item(id)?.tab.flatMap { URL(string: $0.url)?.query } ?? "-" }
        let list = { (container: UUID) in
            self.store.children(of: container).map { $0.isSplit ? $0.children.map(query).joined(separator: "+") : query($0.id) }.joined(separator: " ")
        }
        let open = store.selectedTabID(window: windowID).map(query) ?? "-"
        CraLog.note("\(kind) \(label) ran \(run): pinned: \(list(space.pinnedContainerID)) today: \(list(space.todayContainerID)) open: \(open)")
    }

    /// `cra://debug?spaceMenu=<label>`: logs the menu a right-click on the open space's header
    /// opens, rows as menuReadout writes them (#413: no Set Profile in an incognito window).
    func testSpaceMenu(label: String) {
        var headers: [SpaceHeaderView] = []
        func collect(_ v: NSView) {
            if let h = v as? SpaceHeaderView, !h.isHiddenOrHasHiddenAncestor { headers.append(h) }
            v.subviews.forEach(collect)
        }
        window?.contentView.map(collect)
        guard let menu = headers.first?.makeSpaceMenu() else { CraLog.note("space menu \(label): no header"); return }
        CraLog.note("space menu \(label): \(Self.menuReadout(menu))")
    }

    /// `cra://debug?favoriteMenu=<n>`: logs the menu a right-click on the n-th favorite tile opens
    /// (grid order, rows as menuReadout writes them). `run` picks the row with that title and logs
    /// the tile's tab after it: muted as saved and as Chromium has the page (#387).
    func testFavoriteMenu(tile n: Int, label: String, run: String?) {
        var tiles: [FavoriteTileView] = []
        func collect(_ v: NSView) {
            if let t = v as? FavoriteTileView, !t.isHiddenOrHasHiddenAncestor { tiles.append(t) }
            v.subviews.forEach(collect)
        }
        window?.contentView.map(collect)
        tiles.sort { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        guard tiles.indices.contains(n - 1), let menu = tiles[n - 1].contextMenu() else {
            CraLog.note("favorite menu \(label): no tile \(n)"); return
        }
        CraLog.note("favorite menu \(label): \(Self.menuReadout(menu))")
        guard let run else { return }
        // A row the menu doesn't have (run=-) runs nothing: the lists below are read as they are (#806).
        if let index = menu.items.firstIndex(where: { $0.title == run }) {
            menu.performActionForItem(at: index)
            let id = tiles[n - 1].itemID
            let page = app.runtime(for: id).map { $0.browser.isAudioMuted() ? "muted" : "unmuted" } ?? "not loaded"
            CraLog.note("favorite menu \(label) ran \(run): saved=\(store.item(id)?.tab?.muted == true ? "muted" : "unmuted") page=\(page)")
        }
        // The space's favorites and Today after the row ran, a split as its panes' pages joined by +, and the open tab (#600).
        guard let space = store.space(focusedSpaceID) else { return }
        let query = { (id: UUID) in self.store.item(id)?.tab.flatMap { URL(string: $0.url)?.query } ?? "-" }
        let list = { (container: UUID) in
            self.store.children(of: container).map { $0.isSplit ? $0.children.map(query).joined(separator: "+") : query($0.id) }.joined(separator: " ")
        }
        let open = store.selectedTabID(window: windowID).map(query) ?? "-"
        CraLog.note("favorite menu \(label) favorites: \(list(space.favoritesContainerID)) today: \(list(space.todayContainerID)) open: \(open)")
    }

    /// For test hooks: runs `action` and returns what it put on the clipboard ("-" for nothing, line
    /// breaks as ⏎), then puts the clipboard's old contents back.
    static func probeClipboard(_ action: () -> Void) -> String {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let before = pb.changeCount
        action()
        guard pb.changeCount != before else { return "-" }
        let copied = (pb.string(forType: .string) ?? "").replacingOccurrences(of: "\n", with: "⏎")
        pb.clearContents()
        pb.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
        return copied
    }

    /// `cra://debug?pickedCopy=<clicks>`: clicks rows of the focused space's list as the pointer
    /// would, "c2" ⌘-clicking the second listed tab and "s3" ⇧-clicking the third (an empty list
    /// picks nothing), then presses ⇧⌘C as a key event, so the menu's key equivalent runs as
    /// typed, and logs what reached the clipboard (#322). The clipboard gets its old contents back.
    func testPickedCopy(clicks: String, label: String) {
        let listed = store.listedTabIDs(in: focusedSpaceID)
        sidebarUI.clearPicks()
        for click in clicks.split(separator: ",") {
            guard let n = Int(click.dropFirst()), listed.indices.contains(n - 1) else { CraLog.note("picked copy \(label): no row \(click)"); return }
            sidebarUI.pick(listed[n - 1], range: click.first == "s", in: store)
        }
        guard let window else { return }
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let before = pb.changeCount
        TestGesture.key("C", keyCode: 8, modifiers: [.command, .shift], in: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let copied = pb.changeCount != before ? pb.string(forType: .string) ?? "" : "-"
            CraLog.note("picked copy \(label): \(copied.replacingOccurrences(of: "\n", with: "⏎")) picks=\(self?.sidebarUI.multiSelection.count ?? 0)")
            guard pb.changeCount != before else { return }
            pb.clearContents()
            pb.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
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
        syncTabSharing()
        let audible = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isAudible }.keys })
        if audible != sidebarUI.audibleTabIDs { sidebarUI.audibleTabIDs = audible }
        let soundPlaying = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.soundPlaying }.keys })
        if soundPlaying != sidebarUI.soundPlayingTabIDs { sidebarUI.soundPlayingTabIDs = soundPlaying }
        let b = browsers.visibleRuntime?.browser
        let canGoBack = canNavigateBack(browsers.visibleTabID, b)
        if sidebarUI.canGoBack != canGoBack { sidebarUI.canGoBack = canGoBack }
        if sidebarUI.canGoForward != (b?.canGoForward ?? false) { sidebarUI.canGoForward = b?.canGoForward ?? false }
        if sidebarUI.isLoading != (b?.isLoading ?? false) { sidebarUI.isLoading = b?.isLoading ?? false }
        shell.setLoading(LoadingIndicator.Phase(isLoading: b?.isLoading ?? false, committed: b?.hasCommittedLoad ?? false),
                         tab: browsers.visibleTabID)
        let themeColor = browsers.visibleRuntime?.themeColor ?? ""
        if sidebarUI.pageThemeColor != themeColor { sidebarUI.pageThemeColor = themeColor }
        for (id, rt) in browsers.runtimes where sidebarUI.progress[id] != rt.progress { sidebarUI.progress[id] = rt.progress }
        syncNavStates(browsers.visibleTabIDs)
        syncSlowResponse()
    }

    /// The front tab still waiting for its first response after ten seconds says so in the toast,
    /// with Stop Loading (SlowResponseNotice, GitHub #256). Runs on every page event and when the
    /// front tab's notice falls due.
    private func syncSlowResponse() {
        let now = app.composition.clock.now
        var next: [UUID: SlowResponseNotice] = [:]
        for (id, rt) in browsers.runtimes {
            var n = slowResponses[id] ?? SlowResponseNotice()
            n.update(LoadingIndicator.Phase(isLoading: rt.browser.isLoading, committed: rt.browser.hasCommittedLoad),
                     navigation: rt.browser.navigationStarts, now: now)
            next[id] = n
        }
        slowResponses = next
        let id = browsers.visibleTabID
        let notice = id.flatMap { next[$0] }
        slowResponseCheck?.cancel()
        slowResponseCheck = nil
        if let due = notice?.showsAt, due > now {
            slowResponseCheck = app.composition.clock.after(due.timeIntervalSince(now)) { [weak self] in self?.syncSlowResponse() }
        }
        if let id, notice?.isShown(at: now) == true {
            if slowResponseToastTab != id { showSlowResponse(id) }
        } else if let shown = slowResponseToastTab {
            slowResponseToastTab = nil
            CraLog.note("page \(slowResponseLogHost(shown)) no longer waiting: notice gone (navigation \(browsers.runtime(for: shown)?.browser.navigationStarts ?? 0))")
            toast.dismiss()
        }
    }

    private func showSlowResponse(_ id: UUID) {
        guard let window, let browser = browsers.runtime(for: id)?.browser else { return }
        let url = browser.navigatingURL ?? store.item(id)?.tab?.url ?? ""
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        protectedVideoPromptUp = false
        toast.show(SlowResponseNotice.message(for: url),
                   action: ShinyToast.Action(title: "Stop Loading") { [weak self] in
                       CraLog.note("page \(self?.slowResponseLogHost(id) ?? "") stopped from the notice")
                       self?.browsers.runtime(for: id)?.browser.stopLoading()
                   },
                   page: page, in: window, theme: focusedSpace.theme,
                   onClose: { [weak self] in
                       // ✕: the page goes on waiting, without the notice.
                       self?.slowResponses[id]?.close()
                       if self?.slowResponseToastTab == id { self?.slowResponseToastTab = nil }
                   })
        slowResponseToastTab = id
        CraLog.note("page \(slowResponseLogHost(id)) still waiting for a response: notice shown (navigation \(browser.navigationStarts))")
    }

    /// The host for log lines, as CraLog writes pages.
    private func slowResponseLogHost(_ id: UUID) -> String {
        guard let browser = browsers.runtime(for: id)?.browser else { return "?" }
        return browser.isIncognito ? "(incognito)" : CraLog.host(browser.navigatingURL ?? store.item(id)?.tab?.url ?? "")
    }

    /// Each pane's toolbar state, for the panes whose page is live in this window.
    private func syncNavStates(_ ids: [UUID]) {
        var nav: [UUID: TabNavState] = [:]
        for id in ids {
            guard let rt = browsers.runtime(for: id) else { continue }
            nav[id] = TabNavState(canGoBack: canNavigateBack(id, rt.browser), canGoForward: rt.browser.canGoForward, isLoading: rt.browser.isLoading,
                                  themeColor: rt.themeColor, protectedMedia: PageEngines.protectedMediaService(of: rt.browser),
                                  translation: rt.translation, blockedPopups: rt.blockedPopups.waiting.count)
        }
        if nav != sidebarUI.navStates { sidebarUI.navStates = nav }
        // A page switched for one video was just answered for: no "plays with Safari's engine" toast on top.
        if let id = browsers.visibleTabID, let service = nav[id]?.protectedMedia, PageEngines.videoPages.switched[id] == nil {
            tellAboutProtectedMedia(service)
        }
        syncProtectedVideoPrompt()
    }

    // MARK: Protected videos on mixed sites (docs/protected-media.md)

    func browserManagerProtectedVideoPromptChanged(_ tabID: UUID) { syncProtectedVideoPrompt() }

    /// A Chromium page of a mixed site (YouTube) asked for Widevine: while that page is in front
    /// the toast offers Safari's engine, Once or Always, and its ✕ leaves the page in Chromium.
    /// It goes with the page (another tab in front, another video) and comes back with it until
    /// it is answered. Another toast may take its place; the Site Control Center's row still offers it.
    private func syncProtectedVideoPrompt() {
        let sites = PageEngines.sites
        var wanted: (tab: UUID, key: String)?, prompt: ProtectedVideoPrompt?
        if let id = browsers.visibleTabID, let browser = browsers.runtime(for: id)?.browser, PageEngines.engine(of: browser) == .chromium,
           let key = sites.pageKey(for: browser.currentURL),
           let p = PageEngines.videoPages.prompt(tab: id, url: browser.currentURL, incognito: browser.isIncognito, sites: sites) {
            wanted = (id, key)
            prompt = p
        }
        guard wanted?.tab != protectedVideoPrompt?.tab || wanted?.key != protectedVideoPrompt?.key else { return }
        if protectedVideoPromptUp {
            protectedVideoPromptUp = false
            toast.dismiss()
        }
        protectedVideoPrompt = wanted
        guard let wanted, let prompt, let window, window.isVisible else { return protectedVideoPrompt = nil }
        let answer = { [weak self] (choice: ProtectedVideoPrompt.Choice?) in
            ShinyToast.Action(title: choice?.rawValue ?? "", run: { self?.answerProtectedVideo(wanted.tab, choice) }, answers: true)
        }
        slowResponseToastTab = nil
        toast.show(ProtectedVideoPrompt.text, action: prompt.choices.first.map(answer),
                   second: prompt.choices.count > 1 ? answer(prompt.choices[1]) : nil,
                   page: shell.webContainer.convert(shell.webContainer.bounds, to: nil), in: window, theme: focusedSpace.theme,
                   onClose: { [weak self] in self?.answerProtectedVideo(wanted.tab, nil) })
        protectedVideoPromptUp = true
        CraLog.note("protected video prompt shown: \(toast.debugButtons)")
    }

    /// Once: this page moves. Always: the site's protected videos move from now on, this one
    /// first. nil is the ✕: this page stays in Chromium and isn't asked about again.
    private func answerProtectedVideo(_ id: UUID, _ choice: ProtectedVideoPrompt.Choice?) {
        protectedVideoPromptUp = false
        guard let browser = browsers.runtime(for: id)?.browser else { return }
        let url = browser.currentURL
        CraLog.note("protected video prompt answered: \(choice?.rawValue ?? "✕")")
        switch choice {
        case nil:
            PageEngines.videoPages.declining(tab: id, url: url, sites: PageEngines.sites)
        case .once?:
            browsers.switchToSafariEngine(id, how: .once)
        case .always?:
            if let site = PageEngines.sites.mixedSite(for: url) { PageEngines.switchProtectedVideos(true, on: site) }
            browsers.switchToSafariEngine(id, how: .always)
        }
    }

    /// The Safari's Engine row of the focused page as the Site Control Center would show it,
    /// `drm` being what a Chromium page off the mixed sites answered about Widevine.
    private func safariEngineRow(askedForWidevine drm: Bool = false) -> SafariEngineRow? {
        guard let id = browsers.visibleTabID, let browser = browsers.runtime(for: id)?.browser, !(browser is NativePage) else { return nil }
        return PageEngines.videoPages.row(tab: id, url: browser.currentURL, engine: PageEngines.engine(of: browser), askedForWidevine: drm,
                                          sites: PageEngines.sites, choices: PageEngines.choices)
    }

    /// The row's click. On and Off are the whole site's, as before; the others are a mixed site's.
    private func pressSafariEngine(_ row: SafariEngineRow, for url: String) {
        guard let id = browsers.visibleTabID, let browser = browsers.runtime(for: id)?.browser else { return }
        let sites = PageEngines.sites
        switch row {
        case .on: chooseSafariEngine(false, for: url)
        case .off: chooseSafariEngine(true, for: url)
        case .protectedVideos:
            // The switched page's site (the page may be signing in elsewhere), else the address's.
            let site = PageEngines.videoPages.switched[id].flatMap { page in sites.mixedSites.first { $0.host == page.site } }
                ?? sites.mixedSite(for: browser.currentURL)
            if let site { PageEngines.switchProtectedVideos(false, on: site) }
            browsers.returnToChromium(id)
        case .thisVideo:
            browsers.returnToChromium(id)
        case .videosOff:
            // An incognito page moves without the site being written down.
            let how = ProtectedVideoPages.rowSwitch(incognito: browser.isIncognito)
            if how == .always, let site = sites.mixedSite(for: browser.currentURL) { PageEngines.switchProtectedVideos(true, on: site) }
            browsers.switchToSafariEngine(id, how: how)
        }
    }

    /// Scenario hook: `cra://debug?protectedVideo=state&step=<label>` logs "protected video state
    /// <label>: prompt Once|Always|✕, engine chromium, row Off, always 127.0.0.1"; `=Once`,
    /// `=Always` and `=close` press the prompt's buttons as a click would, and `=row` presses the
    /// row as the Site Control Center does.
    func debugProtectedVideo(_ step: String, label: String) {
        if step == "row" {
            guard let row = safariEngineRow() else { return CraLog.note("protected video row: none") }
            CraLog.note("protected video row pressed: \(row.state)")
            return pressSafariEngine(row, for: currentBrowser?.currentURL ?? "")
        }
        if step != "state" {
            let pressed = protectedVideoPromptUp && toast.debugPress(step == "close" ? "✕" : step)
            return CraLog.note("protected video \(step): pressed \(pressed)")
        }
        let engine = currentBrowser.map { PageEngines.engine(of: $0) == .webKit ? "webkit" : "chromium" } ?? "none"
        CraLog.note("protected video state \(label): prompt \(protectedVideoPromptUp && toast.isShown ? toast.debugButtons : "none"), engine \(engine), "
            + "row \(safariEngineRow()?.state ?? "none"), always \(PageEngines.choices.protectedVideos.joined(separator: ","))")
    }

    // MARK: Split view

    /// Arc's "Add Split View" (⌃⇧=): a new empty pane opens after the focused
    /// one, with the command bar ready to fill it.
    func addSplitPane() {
        guard let current = selectedTabID else { openCommandBar(.newTab); return }
        if store.paneTabIDs(for: current).count >= store.splitPaneLimit {
            showToast("Cannot Add New Pane")
            return
        }
        guard store.addEmptyPane(nextTo: current) != nil else { return }
        refresh()
        openCommandBar(.editURL)
    }

    /// A sidebar tab's Cast… (Cra's row, not Arc's): the tab shows, then Chrome's Cast dialog opens for its
    /// page, as View ▸ Cast… does for the tab in front. A sleeping tab's page is made by the refresh.
    func castTab(_ id: UUID) {
        if selectedTabID != id {
            store.selectTab(id, window: windowID)
            refresh()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let browser = app.runtime(for: id)?.browser ?? currentBrowser
            if browser?.runChromeCommand("IDC_ROUTE_MEDIA") != true { showToast("Nothing to Cast") }
        }
    }

    /// Arc's "Open in Split View" on a sidebar tab: that tab joins the open one in a split, as the
    /// command bar's split row does with a tab it lists.
    func openTabInSplit(_ id: UUID) {
        guard let current = selectedTabID, current != id, store.item(current)?.isEmptyTab == false else { return }
        if store.paneTabIDs(for: current).contains(id) { store.selectTab(id, window: windowID); return }
        guard store.paneTabIDs(for: current).count < store.splitPaneLimit else { showToast("Cannot Add New Pane"); return }
        let split = store.splitContaining(current).map { sp in store.addToSplit(sp.id, tabID: id, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [current, id], at: current)
        store.selectTab(split.flatMap { store.paneID(for: id, in: $0) } ?? id, window: windowID)
    }

    /// An open tab picked for Add Split View's empty pane (#645): it takes that pane's place, as a tab
    /// dropped on a pane does, and is the open pane. A pinned tab stays where it is and a copy joins.
    private func fillEmptyPane(_ empty: UUID, with id: UUID) {
        guard let split = store.splitContaining(empty), let index = store.item(split.id)?.children.firstIndex(of: empty) else {
            store.selectTab(id, window: windowID)
            return
        }
        store.addToSplit(split.id, tabID: id, at: index, replacing: empty)
        guard let joined = store.splitContaining(empty), let pane = store.paneID(for: id, in: joined) else {
            store.selectTab(id, window: windowID)
            return
        }
        store.selectTab(pane, window: windowID)
        closeSplitPane(empty)
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

    /// Arc's View ▸ Expand Current Split: the pane takes the window and the other panes keep the
    /// minimum width, stored as the split's width factors like a divider drag (SplitPaneLayout.expanding).
    /// Arc lays it out in one frame; a double-click on a divider or a drag brings the panes back.
    func expandSplitPane(_ id: UUID) {
        guard let split = store.splitContaining(id) else { return }
        let factors = SplitPaneLayout.expanding(id, in: store.paneTabIDs(for: id))
        store.setSplitWidthFactors(split.id, factors.mapValues { Double($0) })
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
        LinkSummaryPreviewController.shared.validate(windowID: windowID)
        syncSidebarUI()
        let colors = browsers.runtimes.compactMapValues { $0.backgroundColor.isEmpty ? nil : $0.backgroundColor }
        if colors != shell.pageColors { shell.pageColors = colors }
        let bars = toolbarColors(panes: shell.paneIDs)
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        if tabID == browsers.visibleTabID { window?.title = store.item(tabID)?.displayTitle ?? "Cra" }
        if overlay.findVisible, tabID == browsers.visibleTabID { syncAskOnPage() }
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

    func browserManager(statusMessage: String, tabID: UUID?) {
        overlay.status = statusMessage
        shell.statusVisible = !statusMessage.isEmpty
        shell.layoutContentChildren()
        linkHovered(statusMessage, tabID: tabID)
    }

    /// 5-Second Previews: the hovered link, with the page it is on and the profile that would load
    /// it. Incognito spaces get no previews: their pages load in no profile a fetch could use.
    private func linkHovered(_ link: String, tabID: UUID?) {
        let previews = LinkSummaryPreviewController.shared
        previews.validate(windowID: windowID)
        guard store.settings.fiveSecondPreviews, LinkSummaryService.shared.isAvailable else {
            previews.stop(windowID: windowID)
            return
        }
        guard let tabID, let rt = browsers.runtime(for: tabID), browsers.visibleTabIDs.contains(tabID) else { return }
        let space = store.spaceID(ofItem: tabID) ?? focusedSpaceID
        guard !store.isIncognito(space: space) else { previews.stop(windowID: windowID); return }
        let page = URL(string: rt.browser.currentURL)
        guard let url = URL(string: link), LinkSummaryPolicy.canPreview(link: url, page: page) else {
            previews.pointerLeftLink(windowID: windowID, tabID: tabID)
            return
        }
        let request = LinkSummaryService.request(link: url, profilePath: store.profilePath(item: tabID),
                                                 httpsOnly: store.settings.httpsOnly, searchQuery: LinkSummaryPolicy.searchQuery(page: page))
        let revision = rt.navigationRevision
        let focused = selectedTabID
        let focusedSpace = focusedSpaceID
        let isCurrent = { [weak self, weak rt] in
            guard let self, let rt, !self.isTornDown, !self.isPutAway, self.window?.isVisible == true,
                  self.store.settings.fiveSecondPreviews, LinkSummaryService.shared.isAvailable,
                  self.selectedTabID == focused, self.focusedSpaceID == focusedSpace,
                  self.browsers.runtime(for: tabID) === rt, self.browsers.visibleTabIDs.contains(tabID),
                  rt.navigationRevision == revision, rt.browser.currentURL == page?.absoluteString,
                  !self.store.isIncognito(space: self.store.spaceID(ofItem: tabID) ?? self.focusedSpaceID) else { return false }
            return LinkSummaryService.request(link: url, profilePath: self.store.profilePath(item: tabID),
                                              httpsOnly: self.store.settings.httpsOnly,
                                              searchQuery: LinkSummaryPolicy.searchQuery(page: page)) == request
        }
        let pointerInPage = { (f: NSRect) -> CGPoint? in
            let m = NSEvent.mouseLocation
            return f.contains(m) ? CGPoint(x: (m.x - f.minX) / f.width, y: (f.maxY - m.y) / f.height) : nil
        }
        let site = LinkSummaryPolicy.autoSite(page: page)
        previews.linkHoverChanged(.init(
            context: .init(request: request, page: page, windowID: windowID, tabID: tabID,
                           runtimeID: ObjectIdentifier(rt), navigationRevision: revision), window: window,
            theme: store.spaces[space]?.theme ?? self.focusedSpace.theme,
            shiftHeld: NSEvent.modifierFlags.contains(.shift),
            favicon: app.favicons.image(for: url.absoluteString)
                ?? FaviconKey.key(for: url.absoluteString).flatMap { app.favicons.image(forKey: FaviconKey.siteKey(of: $0)) },
            isCurrent: isCurrent,
            inspect: { [weak rt] done in
                // The link under the pointer, its frame, and whether it is one of Arc's (LinkSummaryPolicy.hoverScript).
                guard isCurrent(), let rt, let frame = rt.pageScreenFrame, let pointer = pointerInPage(frame) else { done(nil); return }
                let params = (try? JSONSerialization.data(withJSONObject: [
                    "expression": LinkSummaryPolicy.hoverScript(pointer: pointer, site: site), "returnByValue": true]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak rt] result, _ in
                    let value = PeekSource.value(result)
                    DispatchQueue.main.async {
                        guard isCurrent(), let frame = rt?.pageScreenFrame, let value, let href = value["href"] as? String,
                              let foundURL = URL(string: href) else { done(nil); return }
                        let rect = PeekLayout.fraction(fromScript: value).flatMap { PeekLayout.source(fraction: $0, in: frame) }
                        done(.init(rect: rect, arcLink: value["arc"] as? Bool ?? false, link: foundURL))
                    }
                }
            }))
    }

    func browserManager(findState state: AskOnPage.FindState) {
        if debugFindResults { logFindState() }
        guard overlay.findVisible else { return }
        overlay.findMatchCount = state.count
        overlay.findActiveMatch = state.activeMatch
    }

    func browserManager(findAction action: CraFindAction) {
        if debugFindResults { CraLog.note("find nativeAction=\(action.rawValue)") }
        switch action {
        case .show: showFindBar()
        case .next: findNext(forward: true)
        case .previous: findNext(forward: false)
        @unknown default: break
        }
    }

    func browserManager(download: CraDownloadInfo) {
        let name = (download.fullPath as NSString).lastPathComponent.isEmpty ? download.suggestedName : (download.fullPath as NSString).lastPathComponent
        if download.state == .inProgress, !finishedDownloads.contains(download.identifier),
           let tab = browsers.downloadSourceTab, let item = store.item(tab), let t = item.tab {
            TidyDownloadsService.shared.noteSource(download.identifier, window: windowID, tabID: tab, tab: t,
                referrer: t.referrerID.flatMap { store.item($0)?.tab })
        }
        let known = DownloadHistory.shared.live.first { $0.id == download.identifier }
        if download.state == .inProgress, known == nil || (known?.path.isEmpty == true && !download.fullPath.isEmpty) {
            // Each step once, for a diagnostics report (#491). Ids and sizes only, never the file.
            CraLog.note("Download \(download.identifier) \(known == nil ? "started" : "got its file name"): "
                + "\(download.fullPath.isEmpty ? "no file name yet" : "has its file name"), \(download.receivedBytes) of \(download.totalBytes) bytes")
        } else if download.state == .cancelled || download.state == .interrupted, known?.running == true {
            CraLog.note("Download \(download.identifier) \(download.state == .cancelled ? "cancelled" : "failed"): \(download.receivedBytes) of \(download.totalBytes) bytes")
        }
        if windowDownloads.insert(download.identifier).inserted {
            ChromeDownloadAnimation.suppress()
            showDownloadInSidebar(download, name: name)
        }
        // Progress and failures show in the downloads list, as in Arc (it has no download toast).
        DownloadHistory.shared.report(id: download.identifier, name: name, path: download.fullPath, received: download.receivedBytes,
                                      total: download.totalBytes, percent: download.percent, complete: download.state == .complete,
                                      cancelled: download.state == .cancelled, failed: download.state == .interrupted,
                                      paused: download.paused)
        updateRecentDownload(download)
        if download.state == .cancelled || download.state == .interrupted || (download.state == .complete && download.fullPath.isEmpty) {
            TidyDownloadsService.shared.cancel(download.identifier, window: windowID)
        }
        if download.state == .complete, !download.fullPath.isEmpty, finishedDownloads.insert(download.identifier).inserted {
            DownloadHistory.shared.add(path: download.fullPath, profile: browsers.downloadSourceTab.map(store.profileDirectoryName(item:)) ?? profileDirectoryName)
            // The address's scheme only, never the file: scenarios wait for this line.
            CraLog.note("Download finished from a \(URL(string: download.url)?.scheme ?? "unknown"): address")
            let id = download.identifier
            TidyDownloadsService.shared.finished(id, path: download.fullPath, downloadURL: download.url, window: windowID, store: store,
                ownerEligible: { [weak self] in self?.window != nil && self?.isPutAway == false }) { [weak self] path in
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id, recent.path == download.fullPath else { return }
                recent.path = path
                self.sidebarUI.recentDownload = recent
            }
        }
        if download.state == .inProgress { watchDownloads() }
    }

    private func watchDownloads() {
        guard downloadWatchdog == nil else { return }
        downloadWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStalledDownloads() }
        }
    }

    private var downloadWatchdog: Timer?
    /// Downloads logged as stuck, once each.
    private var stuckDownloads: Set<UInt32> = []

    /// CEF stops reporting a download once the tab that started it is gone (the download
    /// carries on, or ends, silently), which left its row "in progress" for good. A row that
    /// hasn't heard from Chromium for a while reads the file instead (DownloadList.quietEnding):
    /// the full size with no .crdownload beside it means it's done; gone means it ended on CEF
    /// only, since the engine writes a running download to "Unconfirmed <n>.crdownload" (#895).
    private func checkStalledDownloads() {
        // A paused download hears nothing from Chromium until it resumes, and isn't stalled.
        let inProgress = DownloadHistory.shared.live.filter { $0.running && windowDownloads.contains($0.id) }
        guard !inProgress.isEmpty else {
            downloadWatchdog?.invalidate()
            downloadWatchdog = nil
            return
        }
        // Where a download stopped, for a diagnostics report: a row that never got a file name sat
        // at "0 bytes" for good (#491). Ids and sizes only, never the file.
        for t in inProgress where !t.paused && Date().timeIntervalSince(t.moved) >= DownloadList.stuckAfter
            && stuckDownloads.insert(t.id).inserted {
            CraLog.note("Download \(t.id) stuck for \(Int(DownloadList.stuckAfter)) s: \(t.path.isEmpty ? "no file name yet" : "has its file name"), \(t.received) of \(t.total) bytes")
        }
        let fm = FileManager.default
        for t in inProgress where !t.paused && !t.path.isEmpty && Date().timeIntervalSince(t.updated) > 5 {
            let size = (try? fm.attributesOfItem(atPath: t.path))?[.size] as? Int64
            guard let ending = DownloadList.quietEnding(total: t.total, partialBesideIt: fm.fileExists(atPath: t.path + ".crdownload"),
                                                        size: size, chromiumEngine: EngineFramework.isChromiumEngine) else { continue }
            let state: CraDownloadState = ending == .complete ? .complete : .cancelled
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
        putAwayBin(download.identifier, after: flight + 30)
    }

    /// The bin leaves 30 s after it lands, but not while a download runs: its badge is how a
    /// running download shows without hovering (#272). It goes 30 s after the last one ends, or
    /// once the ones left have stopped receiving (DownloadList.holdsBin, #491).
    private func putAwayBin(_ id: UInt32, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sidebarUI.recentDownload?.id == id else { return }
            // A download that stopped receiving doesn't hold it (#491).
            if DownloadList.holdsBin(DownloadHistory.shared.live, now: Date()) { self.putAwayBin(id, after: 5); return }
            if let ended = DownloadHistory.shared.lastEnded, Date().timeIntervalSince(ended) < 30 {
                self.putAwayBin(id, after: 30 - Date().timeIntervalSince(ended))
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { self.sidebarUI.recentDownload = nil }
        }
    }

    private var finishedDownloads: Set<UInt32> = []
    /// For `cra://debug?downloadState`: downloads this window was told finished, in this launch.
    var finishedDownloadCount: Int { finishedDownloads.count }
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
        // A sidebar that came out over the page's full screen goes home when the shown one comes back (#315).
        if !fullscreen, sidebarVisible { floatingSidebar?.hide(animated: false) }
        shell.contentFullscreen = fullscreen
        floatingSidebar?.sidebarVisibilityChanged()
        contentFullscreenTab = fullscreen ? tabID : nil
        if !fullscreen {
            keyboardLockEscape.reset()
            pendingNoticeToast = nil
        }
        // Arc's "To exit full screen, press ⎋." Cra takes a page full screen itself (cra-fullscreen-status.patch),
        // so Chrome's own notice for it never comes; it shows once the window is full screen.
        if fullscreen, let toast = ExclusiveAccessNotice.fullscreen.toast(inLittleWindow: false) {
            if window.styleMask.contains(.fullScreen) { showNoticeToast(toast) } else { pendingNoticeToast = toast }
        }
        switch pageFullscreenWindow.page(fullscreen: fullscreen, windowFullscreen: window.styleMask.contains(.fullScreen),
                                         closing: isTornDown || isPutAway) {
        case .enter, .leave: window.toggleFullScreen(nil)
        case .stay: break
        }
    }

    /// Arc's toast for what the page took: "To exit full screen, press ⎋." or "Your cursor is hidden…", over
    /// the page it is about (docs/web-features.md). In the middle of going full screen it waits for the window.
    func browserManager(exclusiveAccessToast toast: ExclusiveAccessNotice.Toast, tabID: UUID) {
        guard let window, browsers.visibleTabIDs.contains(tabID) || contentFullscreenTab == tabID else { return }
        if contentFullscreenTab == tabID, !window.styleMask.contains(.fullScreen) {
            pendingNoticeToast = toast
            return
        }
        showNoticeToast(toast)
    }

    private func showNoticeToast(_ toast: ExclusiveAccessNotice.Toast) {
        CraLog.note("page notice: \(toast.text)")
        showToast(toast.text)
    }

    /// CEF owns the DevTools window (embedding in our NSView trips a Chromium CHECK on macOS).
    /// DevTools docks inside the content card (Chrome's default), to the right of the page.
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView? {
        // The engine's frontend docks in the card itself (EmbeddedDevTools): no room is made beside the page.
        if EmbeddedDevTools.applies(to: browsers.runtime(for: tabID)?.browser) { return nil }
        shell.devToolsVisible = true
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
        return shell.devToolsHost
    }

    // MARK: Chrome-style page windows

    /// The link status bubble's panel, over the focused page's bottom left and always
    /// click-through: a click on a link under the bubble goes to the page. Anything clickable over
    /// the page gets its own panel just its size (the find bar). Only the bubble's strip, not
    /// the page: screenshot apps take the front window under the pointer, and a page-sized clear
    /// panel made every shot of the page blank white (#346).
    private var overlayPanel: NSPanel?
    private var findPanel: FindBarPanel?
    /// The tab selected when the find bar opened.
    private var findTabID: UUID?
    /// The find bar went away because that tab was switched away from, and comes back with it.
    private var findParked = false
    /// The space whose pages the last refresh put on screen: a refresh for another space is a space switch (#703).
    private var pagesShownForSpace: UUID?
    /// The focused page's screen rect the find panel was last placed on.
    private var lastFindPage: NSRect?
    /// Arc Max's Ask on Page: with the setting on, the find bar's panel shows this card instead (#393).
    private(set) lazy var askOnPage: AskOnPageController = {
        let service = AskOnPageService(browsers: browsers, settingsStore: store, enabled: { [weak self] in self?.store.settings.askOnPage == true },
                                       clock: app.composition.clock)
        let c = AskOnPageController(overlay: overlay, service: service)
        c.onFind = { [weak self] q, forward in self?.find(q, forward: forward) }
        c.onClose = { [weak self] in self?.hideFindBar() }
        c.canAskFromFind = { [weak self] query, forward in
            self?.browsers.canAskFind(query: query, enabled: true, forward: forward) ?? false
        }
        c.onResize = { [weak self] in self?.refitFindPanel() }
        return c
    }()
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
        let ask = askOnPage.view
        ask.frame = find.contentView!.bounds
        ask.autoresizingMask = [.width, .height]
        ask.isHidden = true
        find.contentView!.addSubview(ask)
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

    /// A Peek's windows went on the window above its other children (opened, or back with its tab):
    /// the floating sidebar goes back in front of them (#295).
    func peekWindowsAttached() {
        guard let window else { return }
        for panel in floatingSidebar?.attachedPanels ?? [] {
            window.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    /// Overlay panel above the page windows (and the floating sidebar), the find bar above it.
    private func raiseOverlayPanels() {
        guard let window else { return }
        var panels: [NSPanel?] = [overlayPanel]
        if let ringPanel, ringPanel.parent != nil { panels.insert(ringPanel, at: 0) }
        if overlay.findVisible { panels.append(findPanel) }
        // A Peek (and its dimming) stays above everything else in the window but the hidden sidebar
        // slid out at the edge: that one is the sidebar, whose rows stay in reach of a Peek (#242, #295).
        // The command bar ⌘T opened from a Peek stays above the Peek (#379).
        let bar: [NSWindow] = commandBar.isOpen && commandPanel.parent === window ? [commandPanel] : []
        let wanted = panels.compactMap { $0 } + peeks.flatMap(\.peekWindows) + (floatingSidebar?.attachedPanels ?? [])
            + AgentCursor.panels(over: window) + AgentPill.panels(over: window) + ChromiumDialogs.dialogs(over: window) + PermissionPopover.panels(over: window) + bar
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

    /// The status bubble's screen frame: its strip at the focused page's bottom left.
    private func overlayPanelFrame(page: NSRect) -> NSRect {
        StatusBubbleStrip.frame(inPage: page)
    }

    /// The find bar's screen frame: the top trailing corner of the focused page, of the part the
    /// window shows when the page goes past its edge beside the Library (#340), and under the
    /// floating toolbar while that is out (`FindBarPlacement`).
    private func findPanelFrame(page: NSRect) -> NSRect {
        lastFindPage = page
        let inset = CraMetrics.findBarInset
        var page = page
        if let window, page.maxX > window.frame.maxX { page.size.width = max(0, window.frame.maxX - page.minX) }
        if askOnPage.state.enabled {
            let cover = shell.floatingToolbarCover
            let available = AskOnPageLayout.frame(preferred: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude),
                                                 page: page, inset: inset, toolbarOverPage: cover).size
            askOnPage.constrain(to: available)
            return AskOnPageLayout.frame(preferred: askOnPage.size, page: page, inset: inset, toolbarOverPage: cover)
        }
        return FindBarPlacement.frame(page: page, size: CraMetrics.findBarSize, inset: inset,
                                      toolbarOverPage: shell.floatingToolbarCover)
    }

    /// Attaches the visible tabs' Chrome windows over their pane areas, hides the others.
    func browserManagerPageWindowsChanged(focus requested: Bool) {
        askOnPage.service.refresh()
        LinkSummaryPreviewController.shared.validate(windowID: windowID)
        guard let window else { return }
        // A page that turns up after its tab was switched to (made on the press) leaves the keys
        // with a field of Cra's own that took them meanwhile: a double-click's rename (#424).
        let focus = requested && !ownFieldHasKeys
        syncInfoBars()
        frameReleaseAfterChange?.cancel()
        frameReleaseAfterChange = app.composition.clock.after(HiddenFrameRelease.afterPageChange) { [weak self] in
            guard let self else { return }
            self.frameReleaseAfterChange = nil
            self.releaseHiddenFrames(now: self.app.composition.clock.now)
        }
        // A focus still waiting for its page to embed is stale once pages change without one.
        if !focus { embedFocusTab = nil }
        ensureOverlayPanel()
        let visibleIDs = Set(browsers.visibleTabIDs)
        let focused = browsers.visibleRuntime?.hostWindow
        for (id, rt) in browsers.runtimes {
            guard let w = rt.hostWindow else {
                if visibleIDs.contains(id) { updatePageTopGrabber(id, from: nil) }
                continue
            }
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
            // Shown while drawing for releaseHiddenFrames: a child below this window until now,
            // so it is attached above like any page window, opaque and clickable again.
            if releasingFrames.remove(id) != nil {
                Self.applyFrameRelease(HiddenFrameRelease.doneSteps(shown: true), to: w)
            }
            if w.parent !== window {
                // Borderless: a titled window gets macOS's rounded corners on all four sides,
                // which shows under the toolbar and where the page meets DevTools.
                w.styleMask.remove([.titled, .resizable])
                w.styleMask.insert(.fullSizeContentView)
                ChromiumWindowCorners.setSquare(true, for: w)
                ChromiumChildHover.setDocked(true, for: w)
                ChromiumChildFullscreen.attach(w)
                if let page = w.contentView.flatMap(EmbeddedPages.webContentsView(in:)) { PageDropRouter.install(on: page) }
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
            updatePageTopGrabber(id, from: w)
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

    private func updatePageTopGrabber(_ id: UUID, from host: NSWindow?) {
        guard let window, let card = shell.card(for: id) else { return }
        let grabber = card.pageTopGrabber
        guard let page = EmbeddedPages.webContentsView(in: card.webArea)
            ?? host?.contentView.flatMap(EmbeddedPages.webContentsView(in:)) else {
            grabber.removeFromSuperview()
            return
        }
        grabber.isEnabled = { [weak self] in
            guard let self else { return false }
            return !self.isTornDown && self.store.settings.pageTopWindowDrag && !self.shell.contentFullscreen
        }
        // Arc's band reaches 60 pt from the card's top with its bar (#363): 28 pt under the toolbar.
        grabber.barHeight = { [weak card] in
            // A floating bar takes nothing from the page, so the band starts at the card's top.
            card?.barInset ?? 0
        }
        grabber.fillsWindow = { [weak self] in self?.shell.fillsWindow ?? false }
        grabber.titleDoubleClick = { [weak window] in (window as? CraWindow)?.performTitleDoubleClickAction() }
        grabber.attach(to: page, owner: window)
    }

    /// Page windows drawing once, hidden, so their last frame lets go of an evicted page (#195).
    private var releasingFrames: Set<UUID> = []

    /// A hidden tab's page window is ordered out with its compositor suspended, and its last frame
    /// kept the page's surface, and the page's tiles in the GPU process (~15 MB a tab), alive after
    /// Chromium evicted it: every tab ever shown kept them. Chrome detaches a background tab from its
    /// one window instead. Ordered in for a moment, transparent and below this window, the page
    /// window draws a frame without the page and Chromium frees it (HiddenFrameRelease). It goes in
    /// as a child below this window, transparent the whole time, so nothing of it shows, over a
    /// full-screen window or in Stage Manager either (#261).
    func releaseHiddenFrames(now: Date) {
        let visible = Set(browsers.visibleTabIDs)
        let hidden = browsers.runtimes.values.compactMap { rt -> HiddenFrameRelease.Tab? in
            guard let at = rt.hiddenAt, rt.hostWindow != nil, !visible.contains(rt.tabID) else { return nil }
            return .init(id: rt.tabID, hiddenAt: at, releasedFor: rt.hiddenFrameReleasedFor)
        }
        guard let window else { return }
        let pass = HiddenFrameRelease.pass(HiddenFrameRelease.due(hidden, visible: visible.count, now: now).filter { id in
            guard let w = browsers.runtime(for: id)?.hostWindow else { return false }
            return !w.isVisible && w.parent == nil && !releasingFrames.contains(id)
        })
        if pass.more {
            frameReleaseAfterChange?.cancel()
            frameReleaseAfterChange = app.composition.clock.after(0.25 + HiddenFrameRelease.passGap) { [weak self] in
                guard let self else { return }
                self.frameReleaseAfterChange = nil
                self.releaseHiddenFrames(now: self.app.composition.clock.now)
            }
        }
        for id in pass.now {
            guard let rt = browsers.runtime(for: id), let w = rt.hostWindow, !w.isVisible, w.parent == nil,
                  !releasingFrames.contains(id) else { continue }
            rt.hiddenFrameReleasedFor = rt.hiddenAt
            releasingFrames.insert(id)
            Self.applyFrameRelease(HiddenFrameRelease.drawSteps, to: w, below: window)
            // Two or three frames: the compositor unsuspends, paints and commits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak w] in
                guard let w else { return }
                // Taken by browserManagerPageWindowsChanged when the tab was shown meanwhile. With
                // this controller gone the window still goes: left in, it stayed for good (#261).
                if let self, self.releasingFrames.remove(id) == nil { return }
                Self.applyFrameRelease(HiddenFrameRelease.doneSteps(shown: false), to: w)
            }
        }
    }

    /// Does HiddenFrameRelease's steps to a page window; `window` is the one it goes below.
    private static func applyFrameRelease(_ steps: [HiddenFrameRelease.WindowStep], to w: NSWindow, below window: NSWindow? = nil) {
        for step in steps {
            switch step {
            case .transparent: w.alphaValue = 0
            case .opaque: w.alphaValue = 1
            case .clickThrough(let on): w.ignoresMouseEvents = on
            case .attachBelow: window?.addChildWindow(w, ordered: .below)
            case .detach: w.parent?.removeChildWindow(w)
            case .orderOut: w.orderOut(nil)
            }
        }
    }

    /// Moves the page's view from its Chrome window into its card (EmbeddedPages). With its
    /// DevTools open the page goes back: Chrome's docked frontend lays it out in its window.
    private func embedPage(_ id: UUID, from w: NSWindow) {
        guard EmbeddedPages.isEnabled else { return }
        guard let views = EmbeddedPages.pageViews(of: w) else { return }
        if let page = views.last { PageDropRouter.install(on: page) }
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
        let bounds = shell.paneCards.first { $0.webArea === target }?.pageBounds ?? target.bounds
        EmbeddedPages.place(views, in: bounds)
        if embedFocusTab == id { focusEmbeddedPage(id) }
    }

    /// `cra://debug?pageInsets=1`: where the focused page's input view sits against the compositor
    /// that draws the page, after its card lays out again, and the insets Chromium gave it. While
    /// the debugger bar shows, both say the bar's height at the top (#241).
    /// Each shown tab's card draws its page's bars (the Chromium engine's: PageInfoBar) and gives the page what is
    /// left below them.
    private func syncInfoBars() {
        for id in browsers.visibleTabIDs {
            guard let card = shell.card(for: id), let rt = browsers.runtime(for: id) else { continue }
            let before = card.infoBarStrip.height
            card.infoBarStrip.onAction = { [weak rt] bar, action in rt?.browser.infoBar(bar, action: action) }
            card.infoBarStrip.show(rt.infoBars)
            // A tab coming in gets the whole web area from BrowserManager: under bars it lays out again.
            if !rt.infoBars.isEmpty { card.needsLayout = true }
            guard card.infoBarStrip.height != before else { continue }
            card.needsLayout = true
            // The line EmbeddedPages writes when Chromium's own bar moves the page down on CEF (#241).
            CraLog.note("page view: Chromium insets top=\(Int(card.infoBarStrip.height)) left=0 bottom=0 right=0")
        }
    }

    func pageInsetsReadout() -> String {
        // The Chromium engine: the page's view in its card, under Cra's drawing of Chrome's bars.
        if let rt = browsers.visibleRuntime, rt.hostWindow == nil, let card = shell.card(for: rt.tabID) {
            pageInsetsReadouts += 1
            card.needsLayout = true
            card.layoutSubtreeIfNeeded()
            let c = card.webArea.bounds, p = rt.browser.containerView.frame
            let bars = Int(card.infoBarStrip.height)
            let inWindow = card.webArea.convert(c, to: nil)
            let origin = "\(Int(inWindow.minX)),\(Int((window?.frame.height ?? 0) - inWindow.maxY))"
            return "page view insets \(pageInsetsReadouts): top=\(Int(c.maxY - p.maxY)) left=\(Int(p.minX - c.minX)) bottom=\(Int(p.minY - c.minY)) right=\(Int(c.maxX - p.maxX)); Chromium's top=\(bars) left=0 bottom=0 right=0; page area at \(origin) \(Int(c.width))x\(Int(c.height))"
        }
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
        let focused = browsers.visibleTabID.flatMap { browsers.runtime(for: $0)?.pageViews } ?? []
        // The extension side panel's page keeps the keys it has.
        let panel = sidePanel.isShowing ? sidePanel.embeddedViews : []
        // The engine's DevTools docked in a card (EmbeddedDevTools) keep the keys too: clicked into, they have them.
        let devTools = shell.paneCards.compactMap { EmbeddedDevTools.holder(in: $0.webArea) }
        if !(focused + panel + devTools).contains(where: { responder.isDescendant(of: $0) }) { window.makeFirstResponder(nil) }
    }

    /// One of Cra's own text fields in this window has the keys (the field editor is an NSText; a
    /// page's view is not): a tab's rename in the sidebar, the address being edited in place.
    private var ownFieldHasKeys: Bool { window?.firstResponder is NSText }

    /// The tab whose embedded page should take keyboard focus once it is in its card.
    private var embedFocusTab: UUID?

    private func focusEmbeddedPage(_ id: UUID) {
        guard let window, let rt = browsers.runtime(for: id), let view = rt.pageViews.last, view.window === window else { return }
        embedFocusTab = nil
        // Embedded later than the switch: a field typed into since keeps the keys (#424).
        if ownFieldHasKeys { return }
        // Never from a panel that has the keys (the command bar filling a split pane, the find bar).
        if let key = NSApp.keyWindow, key !== window, !EmbeddedPages.isHost(key), key.parent === window { return }
        window.makeKey()
        if let render = EmbeddedPages.renderView(in: view) { window.makeFirstResponder(render) }
        if let host = rt.hostWindow { ChromiumPageFocus.focus(host) } else { rt.browser.setFocused(true) }
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
            guard let w = browsers.runtime(for: id)?.hostWindow else {
                updatePageTopGrabber(id, from: nil)
                continue
            }
            let body = frames[id] ?? focusRect
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
            // Chrome's docked frontend spans its pane's body, under the page.
            if devTools[id] != nil, browsers.devToolsDockedState[id] ?? true { positionDevToolsWindow(body, tab: id) }
            if w.frame != target { w.setFrame(target, display: live) }
            updatePageCorners(w, page: page, body: body)
            // A switch can show the page before its card exists; the card is laid out by now.
            embedPage(id, from: w)
            updatePageTopGrabber(id, from: w)
            if shell.devToolsFrontendDocked, w.isVisible {
                devToolsLog("page win \(w.windowNumber) '\(w.title)' tab \(id.uuidString.prefix(8)) visible=\(browsers.visibleTabIDs.contains(id)) body \(body) page \(page) style \(w.styleMask.rawValue) parent \(w.parent?.windowNumber ?? -1)")
            }
        }
        let pr: NSRect? = shell.devToolsFrontendDocked ? focusPage : nil
        if shell.frontendPageRect != pr { shell.frontendPageRect = pr }
        let focusOnScreen = window.convertToScreen(focusPage)
        if let panel = overlayPanel, panel.frame != overlayPanelFrame(page: focusOnScreen) { panel.setFrame(overlayPanelFrame(page: focusOnScreen), display: true) }
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
            overlayPanel?.animator().setFrame(overlayPanelFrame(page: window.convertToScreen(focusPage)), display: true)
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
        guard browsers.devToolsViews[tab] != nil,
              browsers.runtime(for: tab)?.hostWindow != nil || EmbeddedDevTools.applies(to: browsers.runtime(for: tab)?.browser),
              browsers.devToolsDockedState[tab] ?? true,
              let p = browsers.devToolsPlaceholders[tab] else { return body }
        return p.pageRect(in: body)
    }

    /// For `cra://debug?windowState`: the visible page window's clip round, the window's own corner round, and
    /// whether the page's corner stays inside the window's (#366: at a narrow margin a 6 pt page corner stood out
    /// past the window's). `inside` takes the card's inset from the window's top-right corner, where the sidebar
    /// never is on the left. An embedded page (EmbeddedPages) is clipped by its pane card, so that card's round counts.
    var pageCornerReadout: String {
        guard let window, let id = browsers.visibleTabID,
              let layer = browsers.runtime(for: id)?.hostWindow?.contentView?.layer
                ?? shell.paneCards.first(where: { $0.tabID == id })?.layer
        else { return "pageRound=- windowRound=- inside=-" }
        let windowRound = window.styleMask.contains(.fullScreen) ? 0 : LittleWindow.cornerRadius(of: window)
        let card = shell.contentContainer.frame
        let inset = min(shell.bounds.maxX - card.maxX, shell.bounds.maxY - card.maxY)
        let inside = layer.cornerRadius + inset >= windowRound - 0.5
        return String(format: "pageRound=%.0f windowRound=%.0f inside=%d", layer.cornerRadius, windowRound, inside ? 1 : 0)
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
        // window: where it meets the window's corners it takes their radius. With Rounded
        // corners (#582) every card corner is round, at the window's radius (ShellView.cardRadius).
        if shell.fillsWindow, !shell.roundsFilledCards {
            roundAtWindowCorners(layer, rect: page, flipped: cv.isFlipped)
            return
        }
        // The card's round as ShellView has it: Arc's 6 pt in its margin, more at a narrow one (#366), 0 in full screen.
        let radius = shell.paneCornerRadius
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        var corners: CACornerMask = []
        // A fullscreen card is square.
        if !shell.contentFullscreen, abs(page.minY - body.minY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(bottomLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(bottomRight) }
        }
        // Without the toolbar the page's top edge is the card's top edge too.
        if !shell.contentFullscreen, !shell.barsTakeRoom, abs(page.maxY - body.maxY) < 0.5 {
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
    /// Arc's "Share this tab instead": the call shares the tab and the tab shows, as when Arc's button is clicked.
    /// The page may live in another window (it was last shown there).
    func shareTabInstead(_ id: UUID) {
        let page = app.mainWindows.lazy.compactMap { $0.browsers.runtime(for: id)?.browser }.first
        guard page?.shareInstead() == true else { return }
        store.selectTab(id, window: windowID)
    }

    /// `cra://debug?tabSharing=<label>`: the tabs shared and switchable, the rows ringed in yellow, the rows showing
    /// "Share this tab instead", the cards ringed in yellow and the selected tab, each by URL. `hover` first hovers the
    /// row of the tab whose URL contains it, as the pointer would; `press` then clicks that row's button, and the
    /// readout waits for Chrome to switch.
    func tabSharingReadout(_ label: String, hover: String?, press: Bool, done: @escaping (String) -> Void) {
        func url(_ id: UUID) -> String {
            app.mainWindows.lazy.compactMap { $0.browsers.runtime(for: id)?.browser.currentURL }.first ?? id.uuidString
        }
        func list(_ ids: some Sequence<UUID>) -> String { ids.map(url).sorted().joined(separator: ",") }
        func rows() -> [TabRowView] {
            (window?.contentView.map { Self.views(TabRowView.self, in: $0) } ?? []).filter { !$0.isHiddenOrHasHiddenAncestor }
        }
        var pressed = false
        if let part = hover {
            guard let row = rows().first(where: { $0.model.map { url($0.id).contains(part) } ?? false }) else {
                done("tab sharing \(label): no row at \(part)"); return
            }
            row.list?.debugHover(row)
            if press { pressed = row.pressShareInsteadButton() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (pressed ? 1 : 0.2)) { [weak self] in
            guard let self else { return }
            self.syncTabSharing()
            self.window?.contentView?.layoutSubtreeIfNeeded()
            let shown = rows()
            let ringedRows = shown.filter(\.showsSharedRing).compactMap { $0.model?.id }
            let buttons = shown.filter(\.showsShareInsteadButton).compactMap { $0.model?.id }
            let ringedCards = self.shell.paneCards.filter(\.showsSharedRing).map(\.tabID)
            let selected = self.store.selectedTabID(window: self.windowID).map(url) ?? "-"
            done("tab sharing \(label): shared=\(list(self.sidebarUI.sharedTabIDs)) instead=\(list(self.sidebarUI.shareInsteadTabIDs))"
                 + " rows=\(list(ringedRows)) buttons=\(list(buttons)) cards=\(list(ringedCards))"
                 + (press ? " pressed=\(pressed ? 1 : 0)" : "") + " selected=\(selected)")
        }
    }

    private static func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }

    /// `cra://debug?recordingDot`: each shown tab row's recording dot and favicon, by the tab's URL, sorted.
    func recordingDotReadout() -> String {
        let rows = (window?.contentView.map { Self.views(TabRowView.self, in: $0) } ?? []).filter { !$0.isHiddenOrHasHiddenAncestor }
        return rows.compactMap { row -> String? in
            guard let id = row.model?.id else { return nil }
            let url = browsers.runtime(for: id)?.browser.currentURL ?? id.uuidString
            return "\(url) \(row.recordingDotReadout)"
        }.sorted().joined(separator: " | ")
    }

    /// Sharing spans windows: a call in one window can switch to a tab another window's sidebar lists.
    func browserManagerTabSharingChanged() {
        for w in app.mainWindows { w.syncTabSharing() }
    }

    /// The tabs calls share and the ones they can switch to, for the sidebar rows and the page cards
    /// (TabSharing). Each set is assigned only when it changed (syncSidebarUI).
    func syncTabSharing() {
        let pages = app.mainWindows.flatMap { $0.browsers.runtimes }
        let shared = Set(pages.filter { $0.value.browser.isBeingShared }.map { $0.key })
        let instead = Set(pages.filter { $0.value.browser.canShareInstead }.map { $0.key })
        if shared != sidebarUI.sharedTabIDs { sidebarUI.sharedTabIDs = shared }
        if instead != sidebarUI.shareInsteadTabIDs { sidebarUI.shareInsteadTabIDs = instead }
        if shared != shell.sharedTabIDs { shell.sharedTabIDs = shared }
    }

    func browserManagerDevToolsChanged() {
        BoostEditorController.shared.devToolsChanged()
        guard let window else { return }
        let visible = browsers.visibleDevToolsWindow
        let shown = browsers.visibleDevToolsWindows
        for (_, view) in browsers.devToolsViews {
            if let w = view.window, !shown.values.contains(where: { $0 === w }) {
                w.orderOut(nil)
                EmbeddedDevTools.park(w)
            }
        }
        // The engine's frontend docks over its pane's body too, in the card (EmbeddedDevTools).
        let selfDock = visible != nil && (browsers.visibleRuntime?.hostWindow != nil || EmbeddedDevTools.applies(to: browsers.visibleRuntime?.browser))
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
        syncEmbeddedDevTools()
        var attached = false
        for id in browsers.visibleTabIDs {
            guard let w = shown[id] else { continue }
            if EmbeddedDevTools.applies(to: browsers.runtime(for: id)?.browser) {
                if browsers.devToolsDockedState[id] == false { undockEmbeddedDevTools(w, tab: id) }
                continue
            }
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

    /// The tab's DevTools take the keys while it shows (EmbeddedDevTools.giveKeys).
    func browserManagerDevToolsTakeKeys(_ tabID: UUID) {
        guard let window, browsers.visibleTabIDs.contains(tabID), let dev = browsers.devToolsViews[tabID]?.window else { return }
        EmbeddedDevTools.giveKeys(to: dev, in: window)
    }

    /// The engine's docked frontends in their panes' cards, under the pages, which go where each left room; a card
    /// whose tab has none docked (closed, undocked, another tab now) lets go of the one it had.
    private func syncEmbeddedDevTools() {
        for card in shell.paneCards {
            let id = card.tabID
            let rt = browsers.runtime(for: id)
            let docked = browsers.visibleTabIDs.contains(id) && EmbeddedDevTools.applies(to: rt?.browser)
                && browsers.devToolsDockedState[id] ?? true
            let w = docked ? browsers.devToolsViews[id]?.window : nil
            if let held = EmbeddedDevTools.holder(in: card.webArea), held.home == nil || held.home !== w {
                held.removeFromSuperview()
            }
            if let w {
                EmbeddedDevTools.embed(w, in: card.webArea)
                card.devToolsPlaceholder = browsers.devToolsPlaceholders[id]
            } else {
                card.devToolsPlaceholder = nil
            }
            card.needsLayout = true
        }
    }

    /// "Undock into separate window" on the engine: the frontend leaves the card for its own window.
    private func undockEmbeddedDevTools(_ w: NSWindow, tab: UUID) {
        guard let window else { return }
        EmbeddedDevTools.restore(w)
        if !w.styleMask.contains(.titled) {
            DevToolsWindowChrome.undock(w, over: window, pageURL: browsers.runtime(for: tab)?.browser.currentURL)
            w.makeKeyAndOrderFront(nil)
        } else if !w.isVisible {
            w.orderFront(nil)
        }
    }

    /// The docked frontend moved its placeholder (also streamed while its splitter is dragged).
    func browserManagerDevToolsPageBoundsChanged() {
        syncEmbeddedDevTools()
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
            DevToolsWindowChrome.dock(w)
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
        if shell.fillsWindow, !shell.roundsFilledCards, let window {
            roundAtWindowCorners(layer, rect: window.convertFromScreen(w.frame), flipped: cv.isFlipped)
            return
        }
        layer.cornerRadius = shell.paneCornerRadius
        // Frontend-docked: the window spans the card body, so both bottom corners are
        // card corners, and the top ones too without the toolbar (else they showed past the
        // page's rounded top corners). Shell-docked (Alloy): it sits right of the page.
        let selfDock = browsers.runtime(for: tab)?.hostWindow != nil
        let bottom: CACornerMask = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = selfDock ? (shell.barsTakeRoom ? bottom : all) : [.layerMaxXMaxYCorner, .layerMaxXMinYCorner]
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
        DevToolsWindowChrome.undock(w, over: window, pageURL: browsers.runtime(for: tab)?.browser.currentURL)
        setDevToolsTitleBarInset(w, tab: tab)
        w.makeKeyAndOrderFront(nil)
    }

    /// The undocked window's title bar covers the top of the frontend: its layout moves down by
    /// the bar's height (0 when docked, `w` nil).
    private func setDevToolsTitleBarInset(_ w: NSWindow?, tab: UUID) {
        browsers.runtime(for: tab)?.browser.executeJavaScript(DevToolsWindowChrome.titleBarInsetScript(for: w), inDevTools: true)
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
        // Not under the page's keyboard lock: a press is the page's, and holding Esc leaves (Chrome does that).
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let id = contentFullscreenTab, let browser = browsers.runtime(for: id)?.browser {
            guard browser.holdsEscapeKey else {
                browser.exitFullscreen()
                return true
            }
            // Under the page's keyboard lock (Arc): a press is the page's and offers the next; that one leaves.
            if event.isARepeat { return false }
            switch keyboardLockEscape.press(at: event.timestamp, offerTime: ShinyToast.visibleFor) {
            case .exitFullscreen:
                CraLog.note("page notice: Esc again leaves full screen")
                browser.exitFullscreen()
                return true
            case .offerAgain:
                CraLog.note("page notice: \(KeyboardLockEscape.againKeys) \(KeyboardLockEscape.againText)")
                showToast("", keyCap: (KeyboardLockEscape.againKeys, KeyboardLockEscape.againText))
                return false
            }
        }
        // An extension's shortcut comes before the page, as in Chrome and Arc: ⌘ keys reach Cra only here (#744).
        if app.runExtensionCommandBeforePage(event) { return true }
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

    /// Arc's translation toasts (#310), for a page this window shows.
    func browserManagerTranslationToast(_ tabID: UUID, text: String) {
        guard store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID).contains(tabID) else { return }
        showToast(text)
    }

    /// An extension brought one of this window's tabs to the front (SwitchyOmega's Options with
    /// its settings tab already open): selected, as in Arc (GitHub #38). A page that asked
    /// (Chromium allows that after a click on its notification, or from its opener) also
    /// brings the window and Cra to the front, like Arc: Messenger's chat opens on a click.
    /// What comes forward is TabActivationRaise's: never this window from behind another
    /// browser window in use (#239).
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool) {
        store.selectTab(tabID, window: windowID)
        var key = NSApp.keyWindow
        while let parent = key?.parent { key = parent }
        let windowIsKey = key != nil && key === window
        let otherKey = key.map { k in app.mainWindows.contains { $0 !== self && $0.window === k } } ?? false
        let outcome = TabActivationRaise.outcome(byPage: byPage, appActive: NSApp.isActive, windowIsKey: windowIsKey,
                                                 anotherBrowserWindowIsKey: otherKey)
        CraLog.note("tab \(tabID.uuidString.prefix(8)) brought to the front by its \(byPage ? "page" : "extension"): "
                    + "\(outcome) (window key=\(windowIsKey), another window key=\(otherKey))")
        switch outcome {
        case .windowAndApp where !HitchMonitor.background:
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        case .window:
            showWindow(nil)
        default:
            break
        }
    }

    /// Arc's Peek (PeekTrigger): the link opens over the window and the tab stays put.
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool, newTab: Bool) -> Bool {
        guard !isIncognito, PeekTrigger.opens(url, from: pageURL, shiftClick: shiftClick, newTab: newTab,
                                               fromPinned: store.isPinned(tabID), settings: store.settings) else { return false }
        app.openPeek(url: url, over: self, fromTab: tabID)
        return true
    }

    /// Arc's ⌥⌘-click (LittleWindowTrigger, decided by BrowserManager): the link opens in a Little Window and the
    /// tab stays put. After Chromium's call returns, as a split pane opens: the window makes a page of its own.
    func browserManagerOpensLittleWindow(url: String, fromTab tabID: UUID) -> Bool {
        guard !isIncognito else { return false }
        let space = focusedSpaceID
        DispatchQueue.main.async { [weak self] in _ = self?.app.openLittleWindow(url: url, space: space) }
        return true
    }

    func browserManagerCaptureImage(at point: NSPoint, tabID: UUID) {
        guard tabID == browsers.visibleTabID else { return }
        capturePage(liftImageAt: point)
    }

    func browserManagerOpenLink(_ url: String, in kind: CraLinkWindow, space: UUID?, fromIncognito: Bool) {
        app.openLink(url, in: kind, space: space, fromIncognito: fromIncognito)
    }

    func browserManagerOpenedInBackground(_ tabID: UUID) { toastBackgroundTab(tabID) }

    /// Open Link in Split View (#257): the link opens as a pane beside the page it was clicked in,
    /// as ⌥Return does from the command bar; a split of four says so, as Add Split View does.
    func browserManagerOpenLinkInSplit(_ url: String, fromTab tabID: UUID) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        if url.isEmpty || url.lowercased().hasPrefix("cra:") || store.item(tabID) == nil { return }
        guard store.openLinkInSplit(url, from: tabID, window: windowID) != nil else {
            showToast("Cannot Add New Pane")
            return
        }
        refresh()
    }

    /// The area Arc's Peek is centred on (window coordinates): right of the sidebar to the
    /// window's edge, top to bottom; the whole window with the sidebar out of the way.
    private func peekAreaInWindow() -> NSRect {
        guard let window else { return .zero }
        let span = peekContentSpan()
        return PeekLayout.area(window: window.frame.size, contentMinX: span.minX, contentMaxX: span.maxX)
    }

    /// Where the page area starts and ends beside the sidebar (window coordinates): from its edge
    /// to the window's other one, the whole width with it hidden (`maxX` nil: the window's edge).
    private func peekContentSpan() -> (minX: CGFloat, maxX: CGFloat?) {
        // Asked from windowDidResize, before the shell has laid out at the new size.
        shell.layoutSubtreeIfNeeded()
        let content = shell.convert(shell.contentContainer.frame, to: nil)
        // While the sidebar slides, the edge is where the slide has it, on the way out too.
        let shown = store.window(windowID).sidebarVisible || shell.slidingSidebar
        if shell.sidebarSide == .right {
            let width = shell.bounds.width
            let beside = PageMargin.besideSidebar(cardEdge: Double(width - content.maxX), margin: shell.pageMargin, fillsWindow: shell.fillsWindow)
            return (0, shown && beside ? content.maxX : nil)
        }
        let beside = PageMargin.besideSidebar(cardEdge: Double(content.minX), margin: shell.pageMargin, fillsWindow: shell.fillsWindow)
        return (shown && beside ? content.minX : 0, nil)
    }

    /// Where a click closes a Peek (screen coordinates): the page area, not the sidebar, whose rows
    /// still open their tabs (#242).
    func peekDismissArea() -> NSRect {
        guard let window else { return .zero }
        let span = peekContentSpan()
        return PeekLayout.dismissArea(covering: window.frame, contentMinX: span.minX, contentMaxX: span.maxX)
    }

    /// cra://debug?peekCatcher: whether the shown Peek's click catcher leaves the sidebar's rows to
    /// the sidebar (#242).
    func peekCatcherReadout() -> String {
        guard let window, let dim = peeks.first(where: { !$0.isParked })?.dimFrame else { return "none" }
        let sidebar = window.convertToScreen(shell.sidebarHost.convert(shell.sidebarHost.bounds, to: nil))
        guard store.window(windowID).sidebarVisible else { return "sidebar=hidden floating=\(floatingSidebarOverPeek())" }
        return "sidebar=\(dim.intersects(sidebar.insetBy(dx: 0.5, dy: 0.5)) ? "covered" : "clear")"
    }

    /// Whether the hidden sidebar, slid out over the page, is in front of the shown Peek's windows
    /// (#295): "above", "below", or "none" while it isn't out. Read from the window server's order.
    private func floatingSidebarOverPeek() -> String {
        guard let sidebar = floatingSidebar?.attachedPanels.last, sidebar.isVisible else { return "none" }
        // The card's page is a Chromium window of its own, a child of the card's.
        let peekWindows = peeks.flatMap { $0.peekWindows + ($0.peekWindows.isEmpty ? [] : [$0.browser?.hostWindow].compactMap { $0 }) }
        // Front to back as the window server has them; the window's child order (back to front)
        // when it doesn't list one of them yet.
        var frontToBack = NSWindow.windowNumbers(options: [])?.map(\.intValue) ?? []
        if !([sidebar] + peekWindows).allSatisfy({ frontToBack.contains($0.windowNumber) }) {
            frontToBack = (window?.childWindows ?? []).reversed().map(\.windowNumber)
            for p in peeks { if let card = p.window, let host = p.browser?.hostWindow, let i = frontToBack.firstIndex(of: card.windowNumber) { frontToBack.insert(host.windowNumber, at: i) } }
        }
        guard let mine = frontToBack.firstIndex(of: sidebar.windowNumber) else { return "none" }
        let behind = peekWindows.allSatisfy { w in frontToBack.firstIndex(of: w.windowNumber).map { $0 > mine } ?? true }
        return behind ? "above" : "below"
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
    /// PeekLayout's script in Cra's isolated world (inside open shadow roots too), with a picture of
    /// it cut from Chromium's screenshot. Answers within `PeekSource.wait` whatever Chromium does.
    /// When the page names no link but the Peek came from a click on it (a closed shadow root,
    /// another site's frame, a page too busy to answer), the card grows from the click instead
    /// (GitHub #359); with neither, nil, and it grows from the whole area. No picture when the
    /// screenshot is late. `pointer` (screen coordinates) and `sinceMouseDown` stand in for the
    /// mouse's own for cra://debug?peekFrom.
    func peekSource(fromTab tabID: UUID?, pointer: NSPoint? = nil, sinceMouseDown: Double? = nil,
                    completion: @escaping (PeekSource?) -> Void) {
        guard let tabID, let window, let rt = browsers.runtimes[tabID], rt.pageWindow === window,
              let pageFrame = rt.pageScreenFrame, rt.browser.isCreated, !rt.browser.isClosed else {
            CraLog.note("peek: from the whole area (no page to find the link in)")
            completion(nil)
            return
        }
        let completion: (PeekSource?) -> Void = { source in
            CraLog.note(source.map { "peek: from \($0.fromLink ? "a link" : "the click") at \(Int($0.rect.minX)),\(Int($0.rect.minY)) \(Int($0.rect.width))×\(Int($0.rect.height))\($0.fromLink && $0.image == nil ? ", no picture" : "")" }
                ?? "peek: from the whole area (no link under the pointer or focused)")
            completion(source)
        }
        let m = pointer ?? NSEvent.mouseLocation
        let clickAge = sinceMouseDown ?? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let fractionPointer = pageFrame.contains(m)
            ? CGPoint(x: (m.x - pageFrame.minX) / pageFrame.width, y: (pageFrame.maxY - m.y) / pageFrame.height) : nil
        var fraction: CGRect??
        var picture: CGImage??
        var answered = false
        let finish: (Bool) -> Void = { [weak window] timedOut in
            guard !answered, let window else { return }
            if fraction == nil, !timedOut { return }
            // The picture is only for a link: without one, the click or the area needs none.
            if picture == nil, !timedOut, (fraction ?? nil) != nil { return }
            answered = true
            let page = window.convertFromScreen(pageFrame)
            let found = fraction ?? nil
            let link = found.flatMap { PeekLayout.source(fraction: $0, in: page) }
            switch PeekLayout.origin(link: link, pointer: window.convertPoint(fromScreen: m), sinceMouseDown: clickAge, page: page) {
            case .link(let rect)?:
                let image = (found.flatMap { f in (picture ?? nil).flatMap { PeekSource.crop($0, to: f) } })
                completion(PeekSource(tabID: tabID, rect: rect, image: image, fromLink: true))
            case .click(let rect)?:
                completion(PeekSource(tabID: tabID, rect: rect, image: nil, fromLink: false))
            case nil:
                completion(nil)
            }
        }
        let script = PeekLayout.sourceScript(pointer: fractionPointer)
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

    /// cra://debug?peekFrom: where a Peek from the selected tab would grow from with the pointer at
    /// `x`, `y` (fractions of the page, y down), `clicked` or resting there: "link W×H", "click W×H"
    /// or "area" (#359).
    func peekSourceReadout(x: Double, y: Double, clicked: Bool, completion: @escaping (String) -> Void) {
        guard let tab = selectedTab?.id, let f = browsers.runtimes[tab]?.pageScreenFrame else { completion("no page"); return }
        let pointer = NSPoint(x: f.minX + x * f.width, y: f.maxY - y * f.height)
        peekSource(fromTab: tab, pointer: pointer, sinceMouseDown: clicked ? 0 : .infinity) { source in
            completion(source.map { "\($0.fromLink ? "link" : "click") \(Int($0.rect.width.rounded()))×\(Int($0.rect.height.rounded()))" } ?? "area")
        }
    }

    /// Where the link a Peek came from is now (the page may have scrolled), in this window's coordinates: gone when
    /// the page has no such link or has it off the page, no answer when Chromium is late or the script fails (#682).
    func peekSourceAgain(_ source: PeekSource, completion: @escaping (PeekLayout.SourceAnswer) -> Void) {
        guard let window, let rt = browsers.runtimes[source.tabID], rt.pageWindow === window, let pageFrame = rt.pageScreenFrame,
              rt.browser.isCreated, !rt.browser.isClosed else { completion(.noAnswer); return }
        var answered = false
        // Where it grew from, as the page measures it: a link to the same address there stands in for one the page
        // re-rendered meanwhile (X's timeline).
        let near = PeekLayout.fraction(of: source.rect, in: window.convertFromScreen(pageFrame))
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": PeekLayout.sourceAgainScript(near: near), "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak window, weak rt] result, _ in
            let answer = PeekSource.answer(result)
            DispatchQueue.main.async {
                guard !answered else { return }
                answered = true
                guard let window, let frame = rt?.pageScreenFrame else { completion(.noAnswer); return }
                switch answer {
                case .some(.some(let f)):
                    completion(PeekLayout.source(fraction: f, in: window.convertFromScreen(frame)).map { .found($0) } ?? .gone)
                case .some(.none): completion(.gone)
                case .none: completion(.noAnswer)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekSource.wait) {
            guard !answered else { return }
            answered = true
            completion(.noAnswer)
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
        let look = PeekLayout.backdrop(veiled: peekVeil.isOn, edgeToEdge: shell.fillsWindow)
        let content = shell.contentContainer
        let center = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        PeekTransition.scaleBackdrop(content, around: center, to: look.scale, duration: duration, timing: timing)
        // Not a window drawing for releaseHiddenFrames: a child below this one, it stays transparent.
        let pages = browsers.runtimes.filter { !releasingFrames.contains($0.key) }.values.compactMap(\.hostWindow).filter { $0.parent === window }
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
    func canAddPane(to source: UUID) -> Bool { store.paneTabIDs(for: source).count < store.splitPaneLimit }

    func joinSplit(_ tabID: UUID, with source: UUID) {
        let split = store.splitContaining(source).map { sp in store.addToSplit(sp.id, tabID: tabID, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [source, tabID], at: source)
        store.selectTab(split.flatMap { store.paneID(for: tabID, in: $0) } ?? tabID, window: windowID)
    }

    private var peeks: [LittleWindowController] { app.littleWindows.filter { $0.peekParent === self } }

    /// The Peek on screen over this window: not waiting behind another tab, not on its way out.
    private var frontPeek: LittleWindowController? {
        peeks.first { !$0.isParked && !$0.closingPeek && $0.window?.isVisible == true }
    }

    /// The Peek the sidebar's address field stands for (PeekAddress, #648): the one in front, while the
    /// address is in the sidebar. nil: the field and its ← → ↻ are the tab's.
    private var sidebarPeek: LittleWindowController? {
        guard let page = PeekAddress.sidebarShows(peek: sidebarUI.peekPage, showToolbar: store.settings.showToolbar) else { return nil }
        return peeks.first { $0.peekID == page.id && !$0.closingPeek }
    }

    /// The Peek in front's page for the sidebar's address row, kept as its page moves on and as Peeks
    /// come, wait behind another tab and go (#648).
    func syncPeekAddress() {
        let page = frontPeek.map { p in
            PeekAddress.Page(id: p.peekID, url: p.currentURL == "about:blank" ? "" : p.currentURL, canGoBack: p.browser?.canGoBack ?? false,
                             canGoForward: p.browser?.canGoForward ?? false, isLoading: p.browser?.isLoading ?? false)
        }
        if sidebarUI.peekPage != page { sidebarUI.peekPage = page }
    }

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

    /// Back (⌘[, the toolbar, the Go menu) on tab `id`, the one in front by default: the page's
    /// own history, else a tab a link opened closes and the tab it came from shows again, as
    /// Arc's navigateBackToReferrer (GitHub #273).
    func goBack(_ id: UUID? = nil) {
        guard let id = id ?? browsers.visibleTabID, let b = browsers.runtime(for: id)?.browser else { return }
        switch store.backStep(id, canGoBack: b.canGoBack) {
        case .history:
            b.goBack()
        case .close(let referrer):
            store.closeToReferrer(id, referrer: referrer, window: windowID)
        case .none:
            break
        }
    }

    /// Whether the Back or Forward being pressed now was ⌘-clicked (#797): a click, not ⌘[.
    private var commandClicked: Bool {
        guard let e = NSApp.currentEvent else { return false }
        return BackForwardMenu.opensNewTab(commandHeld: e.modifierFlags.contains(.command),
                                           byMouse: e.type == .leftMouseUp || e.type == .leftMouseDown)
    }

    /// ⌘-click on Back or Forward (#797): the nearest page that way in tab `tab`'s history (the tab in
    /// front by default) opens in a new tab that comes to the front, where new tabs go, opened from
    /// `tab`; `tab` stays on its page, as in Arc. Logs "history new tab: <direction> <address>".
    func openHistoryInNewTab(_ direction: BackForwardMenu.Direction, from tab: UUID? = nil) {
        guard let id = tab ?? browsers.visibleTabID, let b = browsers.runtime(for: id)?.browser else { return }
        b.sendDevToolsMethod("Page.getNavigationHistory", params: "{}") { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, let result, let page = BackForwardMenu.newTabPage(history: result, direction: direction) else { return }
                self.store.createTab(url: page.url, title: page.title, in: self.store.spaceID(ofItem: id), select: true,
                                     window: self.windowID, referrer: id)
                CraLog.note("history new tab: \(direction == .back ? "back" : "forward") \(page.url)")
            }
        }
    }

    /// Right-click or hold Back or Forward (#416): the pages that way in tab `tab`'s history (a
    /// split pane's, or the tab in front), in Arc's menu under the button; a row goes straight to
    /// its page. Chromium's history comes over DevTools, so the main thread never waits for it.
    func showBackForwardMenu(tab: UUID?, direction: BackForwardMenu.Direction, anchor: NSView) {
        // The sidebar's ← → while its address field shows a Peek: the Peek's history (#648).
        let peek = tab == nil ? sidebarPeek?.browser : nil
        guard let id = tab ?? browsers.visibleTabID, let b = peek ?? browsers.runtime(for: id)?.browser else { return }
        let forPeek = peek != nil
        ArcTooltipController.shared.dismiss()
        b.sendDevToolsMethod("Page.getNavigationHistory", params: "{}") { [weak self, weak anchor] result, _ in
            MainActor.assumeIsolated {
                guard let self, let anchor, let parent = anchor.window, let result else { return }
                let rows = BackForwardMenu.rows(history: result, direction: direction)
                CraLog.note("back-forward menu: \(direction == .back ? "back" : "forward"), \(rows.count) rows")
                guard !rows.isEmpty else { return }
                let favicons = self.app.favicons
                let items = rows.map { row in
                    let key = FaviconKey.key(for: row.url)
                    return BackForwardMenuItem(title: row.title, icon: favicons.image(forKey: key), flip: favicons.glyphIsDark(forKey: key) == true)
                }
                let tones = ArcMenuTones(theme: self.store.focusedSpace(window: self.windowID).theme.shown)
                func ink(_ c: RGB) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
                let colors = SidebarCreationMenuColors(fill: ink(tones.fill), hover: ink(tones.hover), separator: ink(tones.separator),
                                                       shortcut: ink(tones.shortcut), disabled: ink(tones.disabled))
                let menu = BackForwardMenuView(items: items, colors: colors) { [weak self, weak b] index in
                    guard let self else { return }
                    self.backForwardMenu.close()
                    guard let index, let b = forPeek ? b : self.browsers.runtime(for: id)?.browser else { return }
                    if tab != nil, self.selectedTabID != id { self.store.selectTab(id, window: self.windowID) }
                    b.sendDevToolsMethod("Page.navigateToHistoryEntry", params: "{\"entryId\":\(rows[index].entryID)}") { _, error in
                        if let error { CraLog.note("back-forward menu: \(error)") }
                    }
                }
                let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                let screen = parent.screen?.visibleFrame ?? rect.insetBy(dx: -1000, dy: -1000)
                let place = BackForwardMenu.Layout.placement(button: rect, screen: screen, rows: items.count)
                menu.arrowX = place.tailX
                self.backForwardMenu.present(menu, frame: place.frame, from: anchor, systemShadow: false)
            }
        }
    }

    /// cra://debug?historyMenu=<label> (#416): the history menu's rows, width, the tail's offset
    /// from the button's centre and the gap from the button's bottom to the tail's tip, in points.
    func backForwardMenuReadout(_ label: String) -> String {
        guard let menu = backForwardMenu.content as? BackForwardMenuView, let frame = menu.window?.frame,
              let anchor = backForwardMenu.anchor, let parent = anchor.window else { return "history menu \(label): closed" }
        let button = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let m = BackForwardMenu.Layout.margin
        return "history menu \(label): rows=\(menu.rowCount) width=\(Int(frame.width - 2 * m)) tail=\(Int((frame.minX + menu.arrowX - button.midX).rounded()))"
            + " gap=\(Int((button.minY - frame.maxY + m).rounded())) selected=\(menu.selected ?? -1)"
    }

    /// The tab whose page `event` landed on: a Chromium page in its own host window, or the pane
    /// under the point for a page in this window (an embedded Chromium page, whose view lives in
    /// the pane card and not its host window, or an Easel or WebKit page). A swipe goes to the
    /// page under the pointer, which in Split View needn't be the focused pane. nil anywhere else
    /// (the sidebar, a panel).
    func pageTab(under event: NSEvent) -> UUID? {
        guard let target = event.window else { return nil }
        return browsers.visibleTabIDs.first { id in
            guard let browser = browsers.runtime(for: id)?.browser else { return false }
            if let host = browser.hostWindow, host === target { return true }
            let embedded = browser.hostWindow.flatMap { EmbeddedPages.isHost($0) ? EmbeddedPages.pageViews(of: $0)?.last : nil }
            let view = embedded ?? browser.containerView
            return view.window === target && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    /// A two-finger swipe back over tab `id`'s page, which has nothing behind it, so Chromium's
    /// swipe asks Cra (ChromiumHistorySwipe, GitHub #370): what Back does there, a link's tab
    /// closing to the tab it came from. nil when the swipe shouldn't start.
    func swipeBackClose(_ id: UUID) -> (() -> Void)? {
        guard case .close(let referrer) = store.backStep(id, canGoBack: false, swipe: true) else { return nil }
        return { [weak self] in
            guard let self else { return }
            store.closeToReferrer(id, referrer: referrer, window: windowID)
        }
    }

    /// Whether Back does anything on tab `id` showing `browser` (Arc: canNavigateBack).
    private func canNavigateBack(_ id: UUID?, _ browser: CraBrowser?) -> Bool {
        guard let id, let browser else { return false }
        return store.backStep(id, canGoBack: browser.canGoBack) != .none
    }

    /// Today tabs are archived. Pinned tabs and favorites stay; they unload
    /// and return to their pinned page (Arc's close-on-pinned behaviour). A Favorite is only deselected, unless
    /// `fromItsMenu` (its right-click menu's Close Tab) or its page is making sound, as in Arc (#740, #803).
    func closeTab(_ id: UUID, fromItsMenu: Bool = false) {
        guard let item = store.item(id), item.isTab else { return }
        if store.isPinned(id) {
            let panes = store.paneTabIDs(for: id)
            let wasSelected = selectedTabID.map(panes.contains) ?? false
            let audible = panes.contains { app.runtime(for: $0)?.browser.isAudible == true }
            let away = panes.filter { p in store.item(p)?.tab.map { !$0.savedURL.isEmpty && $0.url != $0.savedURL } ?? false }
            // A silent Favorite is only deselected: its page keeps running, and a click on it shows it as it was (#740).
            // Away from its pinned page, it goes back there in the background and stays loaded (#804).
            // One playing sound unloads like a pinned tab, so a video in it stops (#803).
            switch CloseSuccessor.pinnedClose(isFavorite: store.isFavorite(id), fromItsMenu: fromItsMenu,
                                              audible: audible, awayFromPinnedPage: !away.isEmpty) {
            case .deselectKeepingPage:
                store.favoritesClosedWithCmdW.formUnion(panes)
                if wasSelected { store.selectTab(store.closeSuccessor(ofDeselectedFavorite: id, window: windowID), window: windowID) }
                CraLog.note("close tab: favorite deselected, its page kept")
                return
            case .deselectGoingHome:
                store.favoritesClosedWithCmdW.formUnion(panes)
                if wasSelected { store.selectTab(store.closeSuccessor(ofDeselectedFavorite: id, window: windowID), window: windowID) }
                for p in away { resetPinnedTab(p) }
                CraLog.note("close tab: favorite deselected, back to its pinned page")
                return
            case .unloadToPinnedPage:
                break
            }
            if audible, store.isFavorite(id) { CraLog.note("close tab: favorite playing sound unloaded") }
            // A pinned split closes as one: every pane unloads and goes back to its page.
            for p in store.closePinnedTab(id, wasOpen: wasSelected) {
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

    /// The space's open tabs, the latest first, a split as one card (#554). A pinned tab that was
    /// closed (unloaded) isn't open: ⌃Tab doesn't list it, nor a pinned split none of whose panes is open,
    /// nor a Favorite closed with ⌘W whose page kept running (#784, as in Arc).
    private func openRecentCards(limit: Int, allSpaces: Bool = false) -> [RecentTabOrder.Card] {
        let recent = allSpaces ? store.recentCardsInAllSpaces(limit: .max, window: windowID)
            : store.recentCards(in: focusedSpaceID, limit: .max, window: windowID)
        return Array(recent.filter { card in
            card.panes.contains {
                RecentTabOrder.listsPane(selected: $0 == selectedTabID, pinned: store.isPinned($0), loaded: app.runtime(for: $0) != nil,
                                         closedWithCmdW: store.favoritesClosedWithCmdW.contains($0))
            }
        }.prefix(limit))
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

    /// Arc's ⌘-click on a Favorite (#801, Arc 1.174.2 measured 25 Nov 2026): its page moves to a new Today
    /// tab at the top, in the background and saved read, never visited; the Favorite stays open, back on its
    /// pinned page if it was away, on it or not. Arc moves the live page; here the new tab loads it, and a
    /// Favorite at home keeps its own.
    func separateFavorite(_ id: UUID) {
        guard let t = store.item(id)?.tab, store.isFavorite(id) else { return }
        let page = store.createTab(url: t.url, title: t.savedTitle, in: store.spaceID(ofItem: id), select: false, index: 0)
        store.markDuplicateRead(page.id)
        if t.url != t.savedURL { resetPinnedTab(id) }
        store.selectTab(id, window: windowID)
        CraLog.note("favorite separated: page to a new Today tab at the top, favorite \(t.url != t.savedURL ? "back on its pinned page" : "kept")")
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

    /// View ▸ Zoom In / Zoom Out (⌘+ ⌘−): Chrome's next step, and Arc's toast names it ("125%", #856).
    func zoom(in zoomIn: Bool) {
        guard let label = currentBrowser?.zoomStep(in: zoomIn) else { return }
        showToast(label)
    }

    /// View ▸ Zoom to Actual Size (⌘0), with Arc's "100%" toast (#856).
    func resetPageZoom() {
        guard let label = currentBrowser?.resetZoomShowing() else { return }
        showToast(label)
    }

    /// cra://debug?pageScale=<factor> pinches the front page to that scale (as a trackpad pinch does);
    /// pageScale=read:<label> logs "page scale <label>: <visualViewport.scale> zoom level: <n>".
    func debugPageScale(_ value: String) {
        guard let b = currentBrowser else { return CraLog.note("page scale: no page") }
        if let factor = Double(value) {
            b.sendDevToolsMethod("Emulation.setPageScaleFactor", params: #"{"pageScaleFactor":\#(factor)}"#) { _, error in
                CraLog.note("page scale set \(factor)\(error.map { ": \($0)" } ?? "")")
            }
            return
        }
        let label = value.hasPrefix("read:") ? String(value.dropFirst(5)) : value
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"window.visualViewport.scale","returnByValue":true}"#) { result, error in
            let object = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let scale = ((object?["result"] as? [String: Any])?["value"] as? NSNumber)?.doubleValue
            DispatchQueue.main.async {
                CraLog.note("page scale \(label): \(scale.map { String(format: "%.2f", $0) } ?? "? \(error ?? "")") zoom level: \(b.zoomLevel())")
            }
        }
    }

    var captureOverlay: CaptureOverlay?
    var captureRequest: (id: UUID, window: NSWindow)?

    /// Send To… an easel: the capture goes on it, under what is there, and its tab comes forward
    /// (a new one when it has none open).
    private func sendCapture(_ png: Data, toEasel id: UUID, source: Easel.Capture? = nil) {
        guard EaselFiles.add(picture: png, to: id, source: source) else { return }
        CraLog.note("capture sent to an easel, which now holds \(EaselFiles.current(id).items.count) items")
        let url = Easel(id: id).url
        if let tab = store.allTabs().first(where: { $0.tab?.url == url }) {
            // An easel open in a tab took the capture on its canvas (EaselFiles.add): unloading it
            // would save what it showed before over the file. One asleep opens from the file.
            if EaselFiles.canvas(for: id) == nil { browsers.unload(tab.id) }
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
                // A capture of the whole visible page, so it can go live like a dragged one.
                guard let self, let b = self.currentBrowser, let png,
                      let rt = self.browsers.visibleRuntime, let rect = self.pageScreenRect(rt) else { self?.captureFinished(.newEasel, png); return }
                let area = CGRect(origin: .zero, size: rect.size)
                self.captureSource(b, rect: area, page: rect.size) { [weak self] source in
                    if send, let last = EaselFiles.all().first { self?.sendCapture(png, toEasel: last.id, source: source); return }
                    self?.captureFinished(.newEasel, png, in: nil, source: source)
                }
            }
        }
    }

    /// Where a capture came from, for an easel (Arc's WebCard): the page's address and title, its
    /// CSS viewport and scroll, and the captured area in CSS pixels, read from the page.
    func captureSource(_ b: CraBrowser, rect: CGRect, page: CGSize, done: @escaping (Easel.Capture?) -> Void) {
        let url = b.currentURL, title = b.currentTitle
        guard Easel.webAddress(url) != nil else { done(nil); return }
        // Without the page's answer the capture keeps its address and title, and can't go live.
        let plain = Easel.Capture(url: url, title: title.isEmpty ? nil : title, image: "", captured: Date())
        var answered = false
        let finish: (Easel.Capture) -> Void = { capture in
            guard !answered else { return }
            answered = true
            done(capture)
        }
        // Chromium holds a page's answers back while its next address hasn't responded ("Still
        // waiting for … to respond"), so the capture waited for ever and no easel was made. The
        // picture is already taken: after the deadline it goes on without the page's scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + ContentCapture.sourceAnswerWait) {
            if !answered { CraLog.note("capture: the page didn't say where it is scrolled, sent without") }
            finish(plain)
        }
        let script = "[scrollX, scrollY, innerWidth, innerHeight]"
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        b.sendDevToolsMethod("Runtime.evaluate", params: params) { result, _ in
            let v = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { ($0["result"] as? [String: Any])?["value"] as? [Double] }
            DispatchQueue.main.async {
                guard let v, v.count == 4, page.width > 0 else { finish(plain); return }
                let k = v[2] / page.width  // CSS pixels per point (the page's zoom)
                finish(Easel.Capture(url: url, title: title.isEmpty ? nil : title, image: "", captured: Date(),
                                     viewport: .init(v[2], v[3]), scroll: .init(v[0], v[1]),
                                     area: .init(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)))
            }
        }
    }

    /// The capture menu's choice, once the overlay is down.
    func captureFinished(_ action: CaptureOverlay.Action?, _ png: Data?, in peek: LittleWindowController? = nil,
                         from: (browser: CraBrowser, rect: CGRect, page: CGSize)? = nil) {
        if action?.goesToAnEasel == true, let from, let png {
            captureSource(from.browser, rect: from.rect, page: from.page) { [weak self] source in
                self?.captureFinished(action, png, in: peek, source: source)
            }
            return
        }
        captureFinished(action, png, in: peek, source: nil)
    }

    private func captureFinished(_ action: CaptureOverlay.Action?, _ png: Data?, in peek: LittleWindowController?, source: Easel.Capture?) {
        captureOverlay = nil
        if let peek {
            if peek.canCapturePage, action != nil || NSApp.isActive { peek.focusPage() }
        } else if action != nil || NSApp.isActive, window?.isVisible == true {
            window?.makeKey()
            currentBrowser?.setFocused(true)
        }
        switch action {
        case .copy?:
            guard let png else { return }
            PageCommands.copyCapture(png)
            if let peek { peek.showToast("Screenshot Copied to Clipboard") } else { showToast("Screenshot Copied to Clipboard") }
        case .save?:
            if let png { saveCapture(png, over: peek?.window) }
        case .message?:
            if let png { sendCaptureViaMessages(png, in: peek) }
        case .newEasel?:
            guard let png, let easel = EaselFiles.create(withPicture: png, source: source) else { return }
            _ = store.createTab(url: easel.url, title: easel.title, select: true, window: windowID)
            revealForLittleWindowEasel(from: peek)
        case .sendToEasel(let id)?:
            guard let png else { return }
            sendCapture(png, toEasel: id, source: source)
            revealForLittleWindowEasel(from: peek)
        case .retake?:
            capturePage(in: peek)
        case .edit?, nil:
            // Edit stays in the capture (its editor); it never ends the mode.
            break
        }
    }

    /// Arc's "Send via iMessage…": Messages' compose sheet with the capture attached.
    private func sendCaptureViaMessages(_ png: Data, in peek: LittleWindowController? = nil) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Cra Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(PageCommands.captureFileName())
        guard (try? png.write(to: url)) != nil, let service = NSSharingService(named: .composeMessage),
              service.canPerform(withItems: [url]) else {
            showCaptureToast("Messages Isn't Available", in: peek)
            return
        }
        service.perform(withItems: [url])
    }

    // MARK: Sidebar

    func toggleSidebar() {
        if sidebarUI.libraryPage != nil {
            // The Library brought the sidebar out: leaving it hides the sidebar again.
            let showed = libraryShowedSidebar
            closeLibrary()
            if showed { return }
        }
        // New windows open with it as it is now, as in Arc (#644).
        store.chooseSidebar(visible: !sidebarVisible, window: windowID)
        if !sidebarVisible { floatingSidebar?.hide(animated: true) }
    }

    // MARK: Library

    /// Set when the Library brought a hidden sidebar out; leaving it hides the sidebar again.
    private var libraryShowedSidebar = false
    /// The drag of the sidebar's edge in progress (#287), and whether it has hidden the sidebar.
    private var sidebarResize: SidebarResize?
    private var hiddenByResize = false
    static let hiddenSidebarByDragKey = "hasHiddenSidebarWithGesture"

    /// Arc's Library button and ⇧⌘L: open the Library on the page last shown, or leave it. It slides in and out
    /// like the swipe into it, from a hidden sidebar too, and one that brought the sidebar out slides back out to
    /// it (LibrarySwipe.buttonMotion, #726).
    func toggleLibrary() {
        // One on its way in from a hidden sidebar lands first.
        guard hiddenLibrary == nil else { return }
        let opening = librarySettleSpring.map { $0.target < 1 } ?? (sidebarUI.libraryPage == nil)
        let sidebar: LibrarySwipe.ButtonSidebar = shell.contentFullscreen ? .none
            : shell.floatingSidebar || !shell.sidebarVisible ? .hidden : .docked
        let motion = LibrarySwipe.buttonMotion(opening: opening, sidebar: sidebar, swiping: librarySwipeFrom != nil)
        CraLog.note("library button: \(opening ? "opens" : "leaves") it \(motion)\(libraryShowedSidebar ? " to the hidden sidebar" : "")"
                    + (sidebar == .hidden ? ", the floating sidebar \(floatingSidebar?.isShown == true ? "out" : "away")" : ""))
        switch motion {
        case .slide(let target): slideLibrary(to: target)
        case .slideFromHidden: slideLibraryFromHidden()
        case .show: showLibrary(sidebarUI.lastLibraryPage)
        case .close: closeLibrary()
        }
    }

    /// The Library's back arrow and Esc: out the way its button takes it (#726). They went at once, and from a
    /// hidden sidebar the tab list showed over the Library for a few frames as the page widened in steps.
    func leaveLibrary() {
        guard librarySettleSpring.map({ $0.target >= 1 }) ?? (sidebarUI.libraryPage != nil) else { return }
        toggleLibrary()
    }

    /// A page's shortcut (⇧⌘J, View Media…): that page, or the Library closed when it shows that page
    /// already, as Arc's toggles do (LibraryShortcut, #649).
    func toggleLibrary(_ page: LibraryPage) {
        switch LibraryShortcut.step(requested: page, shown: sidebarUI.libraryPage) {
        case .show: showLibrary(page)
        case .close: toggleLibrary()
        }
    }

    /// The Library takes over the sidebar, which widens for its page rail (LibraryView).
    func showLibrary(_ page: LibraryPage) {
        guard hiddenLibrary == nil else { return }
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
        CraLog.note("library opens \(Int(width)) pt wide beside a \(Int(store.prefs.sidebarWidth)) pt tab sidebar")
        if sidebarVisible {
            shell.sidebarWidth = width
            shell.animateSidebar(visible: true, floating: false, fullscreen: shell.contentFullscreen, width: width)
        } else {
            floatingSidebar?.hide(animated: true)
            libraryShowedSidebar = true
            shell.sidebarWidth = width
            sidebarVisible = true
        }
        window?.makeKey()
    }

    /// The sidebar's width with the Library in it: Arc's 417 pt whatever the tab sidebar's width
    /// (narrower only in a window narrower than Arc allows), or on the Spaces page wide enough
    /// for every space's card (LibraryWidth, #302).
    private func libraryWidth(_ page: LibraryPage) -> CGFloat {
        let windowWidth = Double(window?.frame.width ?? 1280)
        guard page == .spaces else { return CGFloat(LibraryWidth.sidebar(window: windowWidth)) }
        let n = store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.count
        return CGFloat(LibraryWidth.sidebar(spacesCards: Double(SpacesManagerMetrics.width(spaces: n)), window: windowWidth))
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
            // ⇧⌘L and Esc move no pointer either (#635).
            floatingSidebar?.waitForPointerToMove()
        } else {
            shell.animateSidebar(visible: shell.sidebarVisible, floating: false, fullscreen: shell.contentFullscreen, width: width, duration: 0.1)
        }
        currentBrowser?.setFocused(true)
    }

    /// Arc's floating sidebar lives in its own panel above the page windows (see FloatingSidebarController).
    private(set) var floatingSidebar: FloatingSidebarController?

    /// Until when the floating sidebar stays out for an extension's popup it asked for: Chrome shows the
    /// popup a moment after the click (up to the 3 s ExtensionActions waits), and the pointer, over the
    /// Site Control Center that just closed, would send the sidebar away meanwhile (#531).
    private var floatingSidebarPopupHold: Date?

    private func holdFloatingSidebarForPopup() {
        guard floatingSidebar?.isShown == true else { return }
        floatingSidebarPopupHold = Date().addingTimeInterval(FloatingSidebarKeepOut.popupWait)
    }

    /// Settings ▸ Sidebar on the right (#464): the window is laid out again at once, the traffic
    /// lights with the sidebar. A hidden sidebar that is out goes home first, from the old edge.
    private func moveSidebar(to side: SidebarSide) {
        floatingSidebar?.hide(animated: false)
        shell.sidebarSide = side
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
        (window as? CraWindow)?.positionTrafficLights()
        CraLog.note("sidebar on the \(side.rawValue)")
    }

    private func installFloatingSidebar() {
        guard let window, floatingSidebar == nil else { return }
        let f = FloatingSidebarController(shell: shell, window: window, palette: { [weak self] in
            self?.focusedSpace.theme.palette ?? SpaceTheme.presets[0].palette
        })
        // Also over a page in full screen, where the sidebar is out of sight (#315).
        f.sidebarHidden = { [weak self] in
            self.map { FloatingSidebarGeometry.mayReveal(sidebarShown: $0.sidebarVisible, pageFullscreen: $0.shell.contentFullscreen) } ?? false
        }
        // Also while what it opened is up: its Site Control Center, and an extension's popup that hangs
        // from it (or is on its way), which lie beside it, past where the pointer sends it away (#531);
        // and while the window has no tab, which holds a hidden sidebar open (SidebarPresentation, #483).
        f.staysShown = { [weak self, weak f] in
            // While a space is being made in it (Arc's Create a Space page), it stays.
            if self?.sidebarUI.spaceCreation != nil { return true }
            // Its address being edited keeps it too: Arc's panel hanging from it (#691), or in place (#692).
            let addressOpen = (self?.commandBar.isOpen == true && self?.commandBar.compact == true)
                || (self?.shell.sidebarHost as? SidebarView)?.isEditingAddress == true
            let keep = FloatingSidebarKeepOut(folderPreviewOpen: FolderPreviewController.shared.isOpen,
                                              siteControlsOpen: self?.siteControlCenter.isShown == true, addressOpen: addressOpen,
                                              popupAnchor: ExtensionPopupWindow.shownAnchor, panelFrame: f?.panelWindow?.frame,
                                              popupAwaitedUntil: self?.floatingSidebarPopupHold)
            if keep.popupArrived { self?.floatingSidebarPopupHold = nil }
            // And while a swipe is bringing the Library in under it.
            return keep.staysOut(now: Date()) || self?.sidebarPresentation.mayRetract == false || self?.hiddenLibrary != nil
        }
        f.didAttachPanel = { [weak self] in
            // Keep the find bar above the floating sidebar.
            self?.raiseOverlayPanels()
        }
        f.install()
        floatingSidebar = f
    }

    /// A press outside the sidebar's address while it is open, which never moves the keys (#691, #692):
    /// on the floating sidebar's empty space (its panel takes the keys only when a click needs them) it
    /// closes the bar, Arc's address panel or the centred one, and the sidebar stays as the pointer
    /// says; anywhere in the sidebar's window but the field it puts the address edited in place back.
    private func sidebarAddressOutsideClick(_ event: NSEvent) {
        guard let clicked = event.window else { return }
        let floating = clicked === floatingSidebar?.panelWindow
        if SidebarAddressOutsideClick.closesBar(barOpen: commandBar.isOpen, inFloatingSidebar: floating) {
            if event.type == .leftMouseDown { commandBarClosingClick.panelClosed(byMouseDownAt: event.timestamp) }
            commandBarLostKeysTo = .barsWindow
            commandBar.close()
        }
        guard let sidebar = shell.sidebarHost as? SidebarView else { return }
        let onField = sidebar.addressFrameOnScreen?.contains(clicked.convertPoint(toScreen: event.locationInWindow)) ?? false
        if SidebarAddressOutsideClick.endsEdit(editing: sidebar.isEditingAddress, inSidebarsWindow: clicked === sidebar.window, onField: onField) {
            sidebar.endAddressEditing()
        }
    }

    /// Pages and DevTools are separate Chromium child windows, and Chromium drops a
    /// click on a window that isn't key. In Chrome they share one window, so moving
    /// between the page and DevTools never costs a click: make the target key first.
    /// Only while focus is already inside this window; a click into an inactive Cra
    /// still just activates it, like Chrome.
    private func installChildClickMonitor() {
        childClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.sidebarAddressOutsideClick(event)
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
            if event.phase == .began || event.phase == .mayBegin {
                // A swipe whose end never came (a view took the gesture's last events) is let go
                // now, so the sidebar isn't left between two pages.
                if self.swipeTracking { self.endSpaceSwipe() }
                if self.creationSwiping { self.endCreationSwipe() }
                self.swipeAxis = .vertical
            }
            // A mouse wheel only ever scrolls.
            if !event.hasPreciseScrollingDeltas { self.listScrolled(event) }
            // The momentum tail of a space swipe belongs to the swipe, not the tab list.
            if !event.momentumPhase.isEmpty {
                if self.swipeAxis == .horizontal { return nil }
                if self.isOverSidebar(event) { self.listScrolled(event) }
                return event
            }
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
                if overSidebar { self.hideListKnobs(at: event.timestamp) }
                self.swipeX = 0
                self.swipeY = 0
                return event
            case .changed:
                switch self.swipeAxis {
                case .vertical:
                    if self.isOverSidebar(event) { self.listScrolled(event) }
                    return event
                case .undecided:
                    self.swipeX += event.scrollingDeltaX
                    self.swipeY += event.scrollingDeltaY
                    guard max(abs(self.swipeX), abs(self.swipeY)) > 6 else { return event }
                    // One space still swipes, in a floating sidebar too.
                    guard abs(self.swipeX) > abs(self.swipeY) * 1.2, !self.isStandalone,
                          // At the Spaces page's end a swipe back along the cards scrolls them.
                          !(self.sidebarUI.libraryPage == .spaces && self.swipeX > 0) else {
                        self.swipeAxis = .vertical
                        self.listScrolled(event)
                        return event
                    }
                    // On Arc's Create a Space page a swipe back takes the page out under the fingers,
                    // and no swipe pages the spaces under it.
                    if self.sidebarUI.spaceCreation != nil {
                        self.swipeAxis = .horizontal
                        self.beginCreationSwipe()
                        self.trackCreationSwipe(by: self.swipeX, at: event.timestamp)
                        return nil
                    }
                    self.swipeAxis = .horizontal
                    HitchMonitor.mark("swipe-begin")
                    self.beginSpaceSwipe()
                    self.trackSpaceSwipe(by: self.swipeX, at: event.timestamp)
                    return nil
                case .horizontal:
                    if self.creationSwiping {
                        self.trackCreationSwipe(by: event.scrollingDeltaX, at: event.timestamp)
                    } else {
                        self.trackSpaceSwipe(by: event.scrollingDeltaX, at: event.timestamp)
                    }
                    return nil
                }
            case .ended, .cancelled:
                if self.swipeAxis != .vertical { self.showListKnobs(after: ListKnobGate.shownAfterScroll) }
                guard self.swipeAxis == .horizontal else { return event }
                if self.creationSwiping { self.endCreationSwipe() } else { self.endSpaceSwipe() }
                return nil
            default:
                return event
            }
        }
    }

    /// Two fingers touched over the sidebar: the knob hides, unless it already shows (#544).
    private func hideListKnobs(at time: TimeInterval) {
        listKnob.touched(at: time)
        guard listKnob.hidden else { return }
        swipeKnobReveal?.cancel()
        swipeKnobReveal = nil
        SidebarScroller.hiddenForSwipe = true
    }

    /// A list scrolled, under the fingers, by its momentum or by a wheel: its knob shows.
    private func listScrolled(_ event: NSEvent) {
        swipeKnobReveal?.cancel()
        swipeKnobReveal = nil
        listKnob.listScrolled(at: event.timestamp)
        SidebarScroller.hiddenForSwipe = false
    }

    /// After `delay` seconds: by then the knob AppKit flashed at the touch has faded out.
    private func showListKnobs(after delay: TimeInterval) {
        swipeKnobReveal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.listKnob.reveal()
            SidebarScroller.hiddenForSwipe = false
        }
        swipeKnobReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginSpaceSwipe() {
        swipeTracking = true
        swipeTravel = 0
        swipeSamples = []
        swipeHaptics = PageDetentHaptics()
        sidebarUI.spaceSettleVelocity = 0
        // A swipe during a Library settle picks it up where it shows.
        librarySwipeToward = librarySettleSpring?.target
        stopLibrarySettle()
        let shown = liveLibraryReveal
        librarySwipeFrom = nil
        swipeSpent = false
        if shell.floatingSidebar || hiddenLibrary != nil {
            // Hidden and out over the page: from the first space the Library comes in docked (Arc).
            if hiddenLibrary != nil || LibrarySwipe.startsFromHiddenSidebar(floatingShown: floatingSidebar?.isShown == true,
                                                                            onFirstSpace: store.spaceOrder.first == focusedSpaceID) {
                // Its view is made once the fingers head that way (trackLibrarySwipe), not for every swipe.
                if hiddenLibrary == nil {
                    sidebarUI.libraryRevealPage = sidebarUI.lastLibraryPage
                    sidebarUI.libraryRevealWidth = libraryWidth(sidebarUI.lastLibraryPage)
                    sidebarUI.libraryRevealBase = 0
                }
                librarySwipeFrom = shown ?? 0
            }
            swipeHaptics = PageDetentHaptics(page: -Int((librarySwipeFrom ?? 0).rounded()))
            return
        }
        guard shell.sidebarVisible || sidebarUI.libraryPage != nil else { return }
        if let page = sidebarUI.libraryPage {
            prepareLibraryReveal(page)
            librarySwipeFrom = shown ?? 1
        } else if shown != nil || store.spaceOrder.first == focusedSpaceID {
            // The Library button slides it in from any space.
            prepareLibraryReveal(sidebarUI.lastLibraryPage)
            librarySwipeFrom = shown ?? 0
        }
        // The Library is the page before the first space; a swipe picked up in a settle starts
        // from the page it was nearer.
        swipeHaptics = PageDetentHaptics(page: -Int((librarySwipeFrom ?? 0).rounded()))
    }

    private func performSwipeHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Swiping into the Library (LibrarySwipe)

    private func prepareLibraryReveal(_ page: LibraryPage) {
        sidebarUI.libraryRevealPage = page
        sidebarUI.libraryRevealWidth = libraryWidth(page)
        // A Library that brought out a hidden sidebar has no tab list beside it to slide back to.
        sidebarUI.libraryRevealBase = libraryShowedSidebar ? 0 : CGFloat(store.prefs.sidebarWidth)
    }

    // MARK: Into the Library from a hidden sidebar (LibrarySwipe, "From a hidden sidebar")

    /// The Library on its way in under a floating sidebar: a view of its own in the window until it
    /// lands, when the sidebar takes it over, docked.
    private var hiddenLibrary: (view: LibraryView, page: LibraryPage, width: CGFloat, reveal: CGFloat)?
    /// The reveal a swipe or a settle shows, whichever sidebar it started from.
    private var liveLibraryReveal: CGFloat? { hiddenLibrary?.reveal ?? sidebarUI.libraryReveal }
    /// A swipe out of the Library that ended on a hidden sidebar: the rest of it pages nothing.
    private var swipeSpent = false

    private func prepareHiddenLibraryReveal(_ page: LibraryPage) {
        guard hiddenLibrary == nil, let sidebar = shell.sidebarHost as? SidebarView else { return }
        let width = libraryWidth(page)
        let view = sidebar.makeDetachedLibrary(page)
        shell.addSubview(view, positioned: .below, relativeTo: shell.resizeHandle)
        hiddenLibrary = (view, page, width, 0)
        sidebarUI.libraryRevealPage = page
        sidebarUI.libraryRevealWidth = width
        sidebarUI.libraryRevealBase = 0
        if EmbeddedPages.isEnabled { shell.freezePages() }
        setLibraryReveal(0)
    }

    /// Landed from a hidden sidebar: the floating sidebar is out of sight by now, so the sidebar goes
    /// home and docks with the Library in it, where the swipe left it. Leaving it hides the sidebar again.
    private func landLibraryFromHidden(_ view: LibraryView, page: LibraryPage, width: CGFloat) {
        var instant = Transaction()
        instant.disablesAnimations = true
        floatingSidebar?.hide(animated: false)
        libraryShowedSidebar = true
        sidebarUI.lastLibraryPage = page
        sidebarUI.downloadsListOpen = false
        commandBar.close()
        shell.sidebarResizable = false
        (shell.sidebarHost as? SidebarView)?.adoptLibrary(view, page: page)
        withTransaction(instant) { sidebarUI.libraryPage = page }
        shell.sidebarWidth = width
        setSidebarVisibleInPlace(true)
        window?.makeKey()
        CraLog.note("library swipe from the hidden sidebar: lands docked \(Int(width)) pt wide")
    }

    /// The sidebar docked or hidden with no slide of its own: a Library swipe has already moved the
    /// Library and the page to where that leaves them.
    private func setSidebarVisibleInPlace(_ visible: Bool) {
        lastSidebarVisible = visible
        sidebarVisible = visible
        shell.sidebarVisible = visible
        shell.floatingSidebar = false
        (window as? CraWindow)?.trafficLightsHidden = !visible
        floatingSidebar?.sidebarVisibilityChanged()
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
    }

    /// A mouse's back button over the floating sidebar: the same way in, from rest.
    private func slideLibraryFromHidden() {
        guard hiddenLibrary == nil else { return }
        prepareHiddenLibraryReveal(sidebarUI.lastLibraryPage)
        guard hiddenLibrary != nil else { return showLibrary(sidebarUI.lastLibraryPage) }
        settleLibrary(from: 0, velocity: 0, to: 1)
    }

    /// Scenario hook: the Library held at reveal `r` on its way in from a hidden sidebar, and where
    /// that puts it, the page and the floating sidebar; `lift` lets go.
    func debugHiddenLibraryReveal(_ r: CGFloat, lift: Bool) {
        if lift {
            guard hiddenLibrary != nil else { return CraLog.note("hidden library reveal: none to let go") }
            swipeSamples = []
            endSpaceSwipe()
            return
        }
        if hiddenLibrary == nil {
            beginSpaceSwipe()
            if librarySwipeFrom != nil, shell.floatingSidebar { prepareHiddenLibraryReveal(sidebarUI.lastLibraryPage) }
        }
        guard let h = hiddenLibrary else { swipeTracking = false; return CraLog.note("hidden library reveal: not offered") }
        setLibraryReveal(r)
        shell.layoutSubtreeIfNeeded()
        let page = shell.frames(sidebarVisible: shell.sidebarVisible, floating: shell.floatingSidebar, fullscreen: shell.contentFullscreen,
                                width: shell.sidebarWidth).content.minX
        CraLog.note("hidden library reveal \(String(format: "%.2f", Double(r))): library x=\(Int(h.view.frame.minX.rounded())) w=\(Int(h.width))"
            + " page x=\(Int(page.rounded())) floating back=\(floatingSidebar?.retreatReadout ?? 0)")
    }

    /// Shows reveal `r`, and like Arc the sidebar widens with it, from its own width to the
    /// Library's, so the Library lands at its width with nothing left to resize.
    private func setLibraryReveal(_ r: CGFloat) {
        if var h = hiddenLibrary {
            h.reveal = r
            hiddenLibrary = h
            let x = LibrarySwipe.libraryX(reveal: r, base: 0, library: h.width)
            h.view.frame = shell.sidebarSide.place(NSRect(x: x, y: 0, width: h.width, height: shell.bounds.height), in: shell.bounds)
            shell.libraryRevealFromHidden = (r, h.width)
            floatingSidebar?.retreat(LibrarySwipe.floatingRetreat(reveal: r, library: h.width))
            return
        }
        // Embedded pages keep their size under their cards until the swipe lands.
        if sidebarUI.libraryReveal == nil, EmbeddedPages.isEnabled { shell.freezePages() }
        sidebarUI.libraryReveal = r
        shell.sidebarWidth = LibrarySwipe.sidebarWidth(reveal: r, base: sidebarUI.libraryRevealBase, library: sidebarUI.libraryRevealWidth)
    }

    /// Past the first space the fingers pull the Library in like the page before it; in the
    /// Library they push it back out. Returns false when the swipe is one between spaces.
    private func trackLibrarySwipe() -> Bool {
        guard let from = librarySwipeFrom else { return false }
        let width = sidebarUI.libraryRevealWidth
        guard let r = LibrarySwipe.reveal(from: from, travel: swipeTravel, width: width, toward: librarySwipeToward) else {
            // Back on the space and beyond: the swipe heads for the next space instead. One that
            // caught the Library sliding out lets it land first and pages with what's left.
            if from != 0 {
                swipeTravel = LibrarySwipe.travelPastSpace(from: from, travel: swipeTravel, width: width)
                librarySwipeFrom = 0
                librarySwipeToward = nil
                // Out to a hidden sidebar there is no next space on show to go on to.
                let toHidden = libraryShowedSidebar
                finishLibrarySwipe(at: 0)
                if toHidden {
                    librarySwipeFrom = nil
                    swipeSpent = true
                    return true
                }
            } else if hiddenLibrary != nil {
                finishLibrarySwipe(at: 0)
            } else if sidebarUI.libraryReveal != nil {
                setLibraryReveal(0)
                sidebarUI.libraryReveal = nil
                shell.thawPages()
            }
            return false
        }
        if sidebarUI.spaceSwipe != 0 { sidebarUI.spaceSwipe = 0 }
        // Back toward the Library after heading for the next space, in a floating sidebar.
        if shell.floatingSidebar, hiddenLibrary == nil {
            prepareHiddenLibraryReveal(sidebarUI.lastLibraryPage)
            guard hiddenLibrary != nil else { return false }
        }
        setLibraryReveal(r)
        if swipeHaptics.track(position: -r, pages: -1...0) { performSwipeHaptic() }
        return true
    }

    /// The release settles on the space swipe's spring, frame by frame on the display link.
    private func endLibrarySwipe(_ r: CGFloat) {
        librarySwipeFrom = nil
        let width = sidebarUI.libraryRevealWidth
        let velocity = LibrarySwipe.velocity(samples: swipeSamples, width: width)
        let target = LibrarySwipe.target(reveal: r, velocity: velocity)
        if swipeHaptics.land(on: -Int(target.rounded())) { performSwipeHaptic() }
        settleLibrary(from: r, velocity: velocity, to: target)
    }

    /// The Library button: the same spring from rest, or turned around from where a settle is.
    private func slideLibrary(to target: CGFloat) {
        if let s = librarySettleSpring {
            let t = CGFloat(s.clock.elapsed(now: CACurrentMediaTime()))
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
        libraryMaskTrailFrames = 0
        librarySettleFrames = 0
        let clock = SettleClock(started: CACurrentMediaTime())
        librarySettleSpring = (clock: clock, from: r, velocity: velocity, target: target)
        if librarySettleLink == nil {
            let link = shell.displayLink(target: self, selector: #selector(stepLibrarySettle))
            link.add(to: .main, forMode: .common)
            librarySettleLink = link
        }
        // A display link gives no frames while the display sleeps: a settle that never drew lands at once, or the
        // Library would stay on its way in and its button do nothing (#726).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let s = self.librarySettleSpring, s.clock == clock, s.clock.origin == nil else { return }
            CraLog.note("library slide drew no frame in 0.5 s: lands \(s.target >= 1 ? "in" : "out") at once")
            self.stopLibrarySettle()
            self.finishLibrarySwipe(at: s.target)
        }
    }

    @objc private func stepLibrarySettle(_ link: CADisplayLink) {
        guard var s = librarySettleSpring else { return stopLibrarySettle() }
        // Timed from its first frame, as the space pager's (SettleClock, #613).
        let t = CGFloat(s.clock.elapsed(atFrame: link.targetTimestamp, interval: link.targetTimestamp - link.timestamp))
        librarySettleSpring = s
        if LibrarySwipe.isSettled(from: s.from, velocity: s.velocity, to: s.target, at: t, width: sidebarUI.libraryRevealWidth) {
            stopLibrarySettle()
            // A scenario's proof that it moved, not appeared (#726).
            let hidden = hiddenLibrary != nil || libraryShowedSidebar
            CraLog.note("library slid \(s.target >= 1 ? "in" : "out")\(hidden ? (s.target >= 1 ? " from" : " to") + " the hidden sidebar" : "")"
                        + " on \(librarySettleFrames) frames over \(Int((t * 1000).rounded())) ms")
            finishLibrarySwipe(at: s.target)
        } else {
            // The last frame's narrowing: the space pages' mask must already be the column's, or the next space's
            // column shows past its edge (#679, #717).
            if (shell.sidebarHost as? SidebarView)?.pagesMaskTrails == true { libraryMaskTrailFrames += 1 }
            setLibraryReveal(LibrarySwipe.settle(from: s.from, velocity: s.velocity, to: s.target, at: t))
            librarySettleFrames += 1
        }
    }

    private func stopLibrarySettle() {
        librarySettleSpring = nil
        librarySettleLink?.invalidate()
        librarySettleLink = nil
    }

    /// Landed: the window is in the Library or on the space, at the width the swipe ends on.
    private func finishLibrarySwipe(at target: CGFloat) {
        if let h = hiddenLibrary {
            hiddenLibrary = nil
            shell.libraryRevealFromHidden = nil
            if target >= 1 {
                landLibraryFromHidden(h.view, page: h.page, width: h.width)
            } else {
                h.view.removeFromSuperview()
                floatingSidebar?.retreat(0)
                CraLog.note("library swipe from the hidden sidebar: back to the space")
            }
            shell.thawPages()
            return
        }
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
        if target < 1, libraryShowedSidebar {
            // It came out of a hidden sidebar, and that is where leaving it goes back to (Arc).
            libraryShowedSidebar = false
            setSidebarVisibleInPlace(false)
            // Two fingers move no pointer: one resting in the edge strip brought the sidebar straight
            // back out over the page (#635).
            floatingSidebar?.waitForPointerToMove()
            // The column has just narrowed from the Library's width; the next space's column lies past its edge (#679).
            let trails = (shell.sidebarHost as? SidebarView)?.pagesMaskTrails == true
            CraLog.note("library left by a swipe: the sidebar hides again, the space pages' mask \(trails ? "trails" : "follows") the column")
        } else if target < 1 {
            // Left in place (its button, ⇧⌘L, a swipe): the column narrows to the tab list's width with the next
            // space's column right past its edge, over the page (#717).
            shell.layoutSubtreeIfNeeded()
            let trails = (shell.sidebarHost as? SidebarView)?.pagesMaskTrails == true || libraryMaskTrailFrames > 0
            CraLog.note("library left in place: the space pages' mask \(trails ? "trails" : "follows") the column"
                        + (libraryMaskTrailFrames > 0 ? " on \(libraryMaskTrailFrames) frames" : ""))
        }
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

    /// A mouse's back or forward button released over the sidebar (Arc's SidebarView, issue #233).
    /// Returns false for any other button, or one released anywhere else.
    func mouseButtonSwitchesSpace(_ button: Int, _ event: NSEvent) -> Bool {
        guard let offset = MouseButtonSpaceSwitch.offset(buttonNumber: button), isOverSidebar(event) else { return false }
        stepSidebarPage(offset)
        return true
    }

    /// The sidebar's previous or next page, as the wheel turns it: the Library is the page before
    /// the first space, and the ends don't wrap (Arc). `menu`: Spaces ▸ Previous/Next Space, which reach the
    /// Library the same way but wrap where the wheel stops (WheelSpaceSwitch.menuTarget, #707).
    func stepSidebarPage(_ step: Int, menu: Bool = false) {
        let order = store.spaceOrder
        // Where the Library is headed, if it is sliding.
        let inLibrary = librarySettleSpring.map { $0.target >= 1 } ?? (sidebarUI.libraryPage != nil)
        let index = order.firstIndex(of: focusedSpaceID) ?? 0
        let libraryAllowed = shell.floatingSidebar ? floatingSidebar?.isShown == true : shell.sidebarVisible
        let page = menu
            ? WheelSpaceSwitch.menuTarget(step: step, index: index, count: order.count, inLibrary: inLibrary, libraryAllowed: libraryAllowed)
            : WheelSpaceSwitch.target(step: step, index: index, count: order.count, inLibrary: inLibrary, libraryAllowed: libraryAllowed)
        switch page {
        case .space(let i): store.focusSpace(order[i], window: windowID)
        case .openLibrary where shell.floatingSidebar: slideLibraryFromHidden()
        case .openLibrary, .closeLibrary: toggleLibrary()
        case nil: break
        }
    }

    /// Whether `event` is over this window's sidebar, docked or floating, in a window that has
    /// spaces to switch (not a Little Window).
    private func isOverSidebar(_ event: NSEvent) -> Bool {
        let host = shell.sidebarHost
        return (shell.sidebarVisible || shell.floatingSidebar) && event.window != nil && event.window === host.window
            && host.bounds.contains(host.convert(event.locationInWindow, from: nil)) && !isStandalone
    }

    /// Whether the pointer, not the key event's window, is over this window's sidebar. A key
    /// goes to the focused page, so ⌥← from a mouse button has to be hit-tested here (issue #233).
    func pointerOverSidebar() -> Bool {
        let host = shell.sidebarHost
        guard (shell.sidebarVisible || shell.floatingSidebar), !isStandalone, let window = host.window else { return false }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard host.bounds.contains(host.convert(point, from: nil)) else { return false }
        return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
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
        stepSidebarPage(step)
        return true
    }

    /// A space swipe of `steps` trackpad samples `dx` apart, 8 ms apart (cra://debug?swipe=).
    /// `stall` holds the main thread that many milliseconds right after the release, as a busy space switch does (#613).
    func debugSpaceSwipe(dx: CGFloat, steps: Int, stall: Int = 0) {
        beginSpaceSwipe()
        for i in 1...max(1, steps) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(i)) { [weak self] in
                self?.trackSpaceSwipe(by: dx, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(steps + 1)) { [weak self] in
            self?.endSpaceSwipe()
            if stall > 0 {
                self?.shell.layoutSubtreeIfNeeded()
                Thread.sleep(forTimeInterval: Double(min(stall, 2000)) / 1000)
            }
        }
    }

    private func trackSpaceSwipe(by dx: CGFloat, at time: TimeInterval) {
        let width = max(1, shell.sidebarWidth)
        swipeTravel += dx
        swipeSamples.append((time, dx))
        swipeSamples.removeAll { time - $0.time > 0.08 }
        if swipeSpent || trackLibrarySwipe() { return }
        let index = CGFloat(store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0)
        let first = -index, last = CGFloat(store.spaceOrder.count - 1) - index
        // Content follows the fingers (natural scrolling: fingers left = next space).
        var pages = max(-1, min(1, -swipeTravel / width))
        // Rubber band past either end, with the resistance curve AppKit scroll views use.
        func band(_ x: CGFloat) -> CGFloat { 1 - 1 / (x * 0.55 + 1) }
        if pages < first { pages = first - band(first - pages) * 0.5 }
        if pages > last { pages = last + band(pages - last) * 0.5 }
        // Past the last space the list gives as Arc's does, and that overscroll brings Arc's "+" out
        // (NewSpaceSwipe). Only for a swipe that began there: one that came from the space before
        // stops on the last space, as any swipe goes one page. The fingers' travel isn't held to a page.
        var overscroll: CGFloat = 0
        if last == 0, swipeTravel < 0, NewSpaceSwipe.isOffered(standalone: isStandalone) {
            overscroll = NewSpaceSwipe.overscroll(travel: -swipeTravel, page: width)
            pages = overscroll / width
        }
        setNewSpacePull(overscroll)
        sidebarUI.spaceSwipe = pages
        // Arc's performsPageDetentHaptics: a tick each time the nearest page changes.
        if swipeHaptics.track(position: pages, pages: Int(first)...Int(last)) { performSwipeHaptic() }
    }

    /// When the "+"'s ring became full, while it is.
    private var newSpaceFullSince: CFTimeInterval?

    /// The list is `overscroll` points past the last space: Arc's tick as the ring fills, and as it
    /// empties again.
    private func setNewSpacePull(_ overscroll: CGFloat) {
        let was = NewSpaceSwipe.isActivated(overscroll: sidebarUI.newSpacePull)
        let full = NewSpaceSwipe.isActivated(overscroll: overscroll)
        sidebarUI.newSpacePull = overscroll
        if full != was { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        if !full { newSpaceFullSince = nil } else if newSpaceFullSince == nil { newSpaceFullSince = CACurrentMediaTime() }
    }

    /// The fingers lift: the "+" goes back out, and if its ring had been full long enough Arc's
    /// Create a Space page comes in.
    private func liftNewSpacePull() {
        let overscroll = sidebarUI.newSpacePull
        guard overscroll > 0 else { return }
        let fullFor = newSpaceFullSince.map { CACurrentMediaTime() - $0 }
        newSpaceFullSince = nil
        sidebarUI.newSpacePull = 0
        let creates = NewSpaceSwipe.createsOnLift(fullFor: fullFor)
        let outcome = creates ? "New Space opens" : fullFor != nil ? "the ring was full too briefly" : "nothing"
        CraLog.note("new space pull: lifted \(String(format: "%.1f", Double(overscroll))) pt out, \(outcome)")
        // The "+" and the column spring back first: the sheet's own opening work would hold them
        // where the fingers left them.
        if creates { beginSpaceCreation() }
    }

    // MARK: Create a Space, in the sidebar (SpaceCreationDraft)

    /// The space the page was opened on: it wears the draft's theme while the page is up, the way a
    /// space wears the theme its editor is trying, so the sidebar, the window and the page show it.
    private var creationOrigin: UUID?
    private var creationDone: ((UUID) -> Void)?

    /// New Space…: Arc's Create a Space page takes the space's place in the sidebar. A window with
    /// no spaces of its own keeps the sheet.
    func beginSpaceCreation(created: ((UUID) -> Void)? = nil) {
        if sidebarUI.spaceCreation != nil {
            (shell.sidebarHost as? SidebarView)?.focusSpaceCreationName()
            return
        }
        guard !isStandalone, window != nil else { return showSpaceEditor(space: nil, created: created) }
        if sidebarUI.libraryPage != nil { closeLibrary() }
        commandBar.close()
        let origin = focusedSpaceID
        // Arc starts the page on the profile of the space it was opened from.
        let draft = SpaceCreationDraft(theme: SpaceColorPresets.newSpaceTheme(),
                                       profile: SpaceProfiles.forNewSpace(from: store.focusedSpace, profiles: store.profiles))
        creationOrigin = origin
        creationDone = created
        store.previewTheme(draft.theme, forSpace: origin)
        // The page area shows the new space's empty page, as Arc's does.
        store.windowsMakingSpace.insert(windowID)
        sidebarUI.spaceCreation = draft
        // With the sidebar hidden it comes out over the page and stays while the page is up.
        if !sidebarVisible, !shell.contentFullscreen { floatingSidebar?.show(why: "a new space's page") }
        CraLog.note("space creation opens")
    }

    // A swipe back on the page (SpaceCreationSwipe).
    private var creationSwiping = false

    private func beginCreationSwipe() {
        creationSwiping = true
        swipeTravel = 0
        swipeSamples = []
        closeCreationPanels()
        ArcTooltipController.shared.dismiss()
    }

    /// The page goes out under the fingers, `dx` points more to the right.
    private func trackCreationSwipe(by dx: CGFloat, at time: TimeInterval) {
        guard sidebarUI.spaceCreation != nil else { return }
        swipeTravel += dx
        swipeSamples.append((time, dx))
        swipeSamples.removeAll { time - $0.time > 0.08 }
        let pull = SpaceCreationSwipe.pull(travel: swipeTravel, width: max(1, shell.sidebarWidth))
        (shell.sidebarHost as? SidebarView)?.setCreationPull(pull)
    }

    /// The fingers lift: past half way or flicked out the page leaves, as Cancel; else it goes back in.
    private func endCreationSwipe() {
        guard creationSwiping else { return }
        creationSwiping = false
        guard sidebarUI.spaceCreation != nil, let sidebar = shell.sidebarHost as? SidebarView else { return }
        let span = (swipeSamples.last?.time ?? 0) - (swipeSamples.first?.time ?? 0)
        let moved = swipeSamples.reduce(0) { $0 + $1.dx }
        let velocity = span > 0.004 ? moved / CGFloat(span) / max(1, shell.sidebarWidth) : 0
        let pull = sidebar.creationPull
        let leaves = SpaceCreationSwipe.leaves(pull: pull, velocity: velocity)
        CraLog.note("space creation swipe: lifted \(String(format: "%.2f", Double(pull))) out, \(leaves ? "leaves" : "goes back")")
        if leaves { cancelSpaceCreation() } else { sidebar.setCreationPull(0, animated: true) }
    }

    /// Scenario hook: a swipe back of `travel` points held (`swipe:<pt>`), then let go (`lift`).
    private func debugCreationSwipe(_ travel: CGFloat?) {
        if let travel {
            if !creationSwiping { beginCreationSwipe() }
            // Slowly: no flick.
            trackCreationSwipe(by: travel - swipeTravel, at: ProcessInfo.processInfo.systemUptime)
            swipeSamples = []
        } else {
            endCreationSwipe()
        }
    }

    /// Choose a Theme: Arc's editor beside the sidebar, level with the row, on the draft. Every
    /// change shows at once; closing it keeps the theme.
    func showCreationThemeEditor(beside row: NSRect) {
        guard let window, let draft = sidebarUI.spaceCreation, let origin = creationOrigin else { return }
        closeCreationPanels()
        let store = self.store
        let editor = SpaceStyleEditor(theme: draft.theme) { [weak self] theme in
            guard let self, self.sidebarUI.spaceCreation != nil else { return }
            self.sidebarUI.spaceCreation?.theme = theme
            self.sidebarUI.spaceCreation?.themeChosen = true
            store.previewTheme(theme, forSpace: origin)
        }
        let size = NSSize(width: 382, height: 534)
        // Arc's panel stands against the sidebar's edge with the row about half way down it.
        let y = min(max(row.midY - size.height / 2, window.frame.minY), window.frame.maxY - size.height)
        let panel = StyleEditorPanel(contentRect: NSRect(x: row.maxX.rounded() + 2, y: y.rounded(), width: size.width, height: size.height)) {}
        let host = NSHostingView(rootView: editor.shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.top, 12).padding(.horizontal, 13.5).padding(.bottom, 19))
        host.sizingOptions = []
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The theme editor and the icon picker the page opened.
    func closeCreationPanels() {
        window?.childWindows?.first(where: { $0 is StyleEditorPanel })?.close()
        (shell.sidebarHost as? SidebarView)?.closeSpaceCreationPopovers()
    }

    /// Cancel, Escape, or another space picked: the space it was opened on comes back as it was.
    func cancelSpaceCreation() {
        guard sidebarUI.spaceCreation != nil else { return }
        closeCreationPanels()
        if let origin = creationOrigin { store.endThemePreview(forSpace: origin, keep: false) }
        creationOrigin = nil
        creationDone = nil
        store.windowsMakingSpace.remove(windowID)
        sidebarUI.spaceCreation = nil
        currentBrowser?.setFocused(true)
        CraLog.note("space creation cancelled")
    }

    /// Create Space: Arc's animation plays, then the space is made in this window, on the draft's
    /// theme and profile, and shown.
    func commitSpaceCreation() {
        guard let draft = sidebarUI.spaceCreation, draft.canCreate, creationOrigin != nil else { return }
        closeCreationPanels()
        guard let sidebar = shell.sidebarHost as? SidebarView else { return finishSpaceCreation() }
        sidebar.playSpaceCreation(icon: draft.icon) { [weak self] in self?.finishSpaceCreation() }
    }

    private func finishSpaceCreation() {
        guard let draft = sidebarUI.spaceCreation, let origin = creationOrigin else { return }
        let done = creationDone
        store.endThemePreview(forSpace: origin, keep: false)
        creationOrigin = nil
        creationDone = nil
        let id = store.createSpace(title: draft.createdTitle, emoji: draft.icon.emoji, symbol: draft.icon.symbol,
                                   iconImage: draft.icon.image, theme: draft.theme, focus: false).id
        if let profile = draft.profile { store.setProfile(profile, forSpace: id) }
        store.setSearchEngine(draft.searchEngine, forSpace: id)
        // In this window, whichever one is active.
        store.focusSpace(id, window: windowID)
        store.windowsMakingSpace.remove(windowID)
        sidebarUI.spaceCreation = nil
        CraLog.note("space creation made \"\(draft.createdTitle)\" on \(draft.profile == nil ? "Default" : "a profile"), theme \(draft.themeChosen ? "chosen" : "as opened"), search \(store.space(id)?.searchEngine ?? "default")")
        done?(id)
    }

    /// Scenario hook: the page's state, or one step on it (`type:<name>`, `icon:<emoji>`, `symbol:<name>`, `theme:<n>`,
    /// `profile:<n>`, `engine:<keyword>`, `create`, `cancel`, `tip:<profile|search>`, `swipe:<points>`, `lift`).
    func debugSpaceCreation(_ step: String) {
        let sidebar = shell.sidebarHost as? SidebarView
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "type": sidebar?.debugTypeSpaceName(parts.count > 1 ? parts[1] : "")
        case "icon": sidebarUI.spaceCreation?.icon = parts.count > 1 ? .emoji(parts[1]) : .none
        case "symbol": sidebarUI.spaceCreation?.icon = parts.count > 1 ? .symbol(parts[1]) : .none
        case "theme":
            if let origin = creationOrigin, sidebarUI.spaceCreation != nil {
                let theme = SpaceColorPresets.newSpaceTheme(index: Int(parts.count > 1 ? parts[1] : "") ?? 0)
                sidebarUI.spaceCreation?.theme = theme
                sidebarUI.spaceCreation?.themeChosen = true
                store.previewTheme(theme, forSpace: origin)
            }
        case "profile":
            let n = Int(parts.count > 1 ? parts[1] : "") ?? -1
            sidebarUI.spaceCreation?.profile = store.profiles.indices.contains(n) ? store.profiles[n].id : nil
        case "engine": sidebarUI.spaceCreation?.searchEngine = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        case "create": commitSpaceCreation()
        case "cancel": cancelSpaceCreation()
        case "tip": CraLog.note("space creation tip \(parts.count > 1 ? parts[1] : "profile"): \(sidebar?.debugSpaceCreationTip(parts.count > 1 ? parts[1] : "profile") ?? "none")")
        case "swipe": debugCreationSwipe(CGFloat(Double(parts.count > 1 ? parts[1] : "") ?? 0))
        case "lift": debugCreationSwipe(nil)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let dock = (self.shell.sidebarHost as? SidebarView)?.debugDockLine ?? "?"
            let page = self.sidebarUI.spaceCreation == nil ? "none" : (sidebar?.debugSpaceCreation ?? "none")
            let pages = self.store.visiblePaneTabIDs(in: self.focusedSpaceID, window: self.windowID).count
            CraLog.note("space creation \(step): \(page) dock=\(dock) space=\(self.focusedSpace.title) spaces=\(self.store.spaceOrder.count) pages=\(pages) pull=\(String(format: "%.2f", Double(sidebar?.creationPull ?? 0)))")
        }
    }

    /// Scenario hook: the "+" as the list `overscroll` points past the last space leaves it, and
    /// what it shows; `lift` lets go, at once when `overscroll` came with it.
    func debugNewSpacePull(_ overscroll: CGFloat?, lift: Bool) {
        if let overscroll {
            let onLast = store.spaceOrder.last == focusedSpaceID
            setNewSpacePull(onLast && NewSpaceSwipe.isOffered(standalone: isStandalone) ? overscroll : 0)
            // The space's column is that far out with it, as under the fingers.
            sidebarUI.spaceSwipe = sidebarUI.newSpacePull / max(1, shell.sidebarWidth)
            let line = (shell.sidebarHost as? SidebarView)?.debugNewSpacePlus ?? "none"
            let column = (shell.sidebarHost as? SidebarView)?.debugSpaceColumnShift ?? 0
            CraLog.note("new space plus: \(String(format: "%.1f", Double(sidebarUI.newSpacePull))) pt out, column=\(String(format: "%.1f", abs(Double(column)))) \(line)")
        }
        if lift {
            liftNewSpacePull()
            sidebarUI.spaceSwipe = 0
        }
    }

    private func endSpaceSwipe() {
        liftNewSpacePull()
        HitchMonitor.mark("swipe-lift")
        swipeTracking = false
        if let r = liveLibraryReveal, librarySwipeFrom != nil { return endLibrarySwipe(r) }
        if swipeSpent {
            swipeSpent = false
            librarySwipeFrom = nil
            return
        }
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
        // A flick lands on a page it never dragged past half of: the tick comes now (#260).
        if swipeHaptics.land(on: step) { performSwipeHaptic() }
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
    let translatePopover = TranslatePopover()

    /// Arc's translate popover (#310) under the button that was pressed (screen rect): the
    /// toolbar's, or the sidebar URL field's "Translation Available". The languages for its menu
    /// come with the first one opened on the page.
    func showTranslate(_ id: UUID, from anchor: NSRect?) {
        guard let window, let content = window.contentView, let rt = browsers.runtime(for: id), let state = rt.translation,
              let anchor = anchor ?? (shell.sidebarHost as? SidebarView)?.translateFrameOnScreen else { return }
        let rect = content.convert(window.convertFromScreen(anchor), from: nil)
        var actions = TranslateActions()
        actions.translate = { [weak self] target in self?.browsers.translatePage(id, to: target) }
        actions.showOriginal = { [weak self] in self?.browsers.revertTranslation(id) }
        actions.neverTranslateSite = { [weak self] in self?.browsers.neverTranslateSite(id) }
        actions.languageSettings = { [weak self] in self?.app.perform("languageSettings") }
        let show = { [weak self] in
            guard let self, let state = self.browsers.runtime(for: id)?.translation else { return }
            self.translatePopover.toggle(relativeTo: rect, of: content, state: state, actions: actions)
        }
        if state.languages.isEmpty { browsers.refreshTranslation(id, then: show) } else { show() }
    }
    /// The blocked pop-ups menu (#357) under the button that was pressed (screen rect): the
    /// toolbar's, or the sidebar URL field's "Pop-ups Blocked".
    func showBlockedPopups(_ id: UUID, from anchor: NSRect?) {
        guard let window, let content = window.contentView,
              let anchor = anchor ?? (shell.sidebarHost as? SidebarView)?.blockedPopupsFrameOnScreen else { return }
        let rect = content.convert(window.convertFromScreen(anchor), from: nil)
        blockedPopupsMenu(id).popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY - 4), in: content)
    }

    /// Chrome's blocked pop-ups bubble as a menu: the pop-ups (each opens as a tab below the page),
    /// Open All, and the site's Always Allow switch.
    func blockedPopupsMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let popups = browsers.blockedPopups(id)
        let heading = NSMenuItem(title: BlockedPopups.heading(count: popups.count), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for p in popups {
            let item = BlockMenuItem(title: BlockedPopups.menuTitle(url: p.url)) { [weak self] in self?.browsers.openBlockedPopups(id, popup: p.id) }
            item.toolTip = p.url
            menu.addItem(item)
        }
        if popups.count > 1 {
            menu.addItem(.separator())
            menu.addItem(BlockMenuItem(title: BlockedPopups.openAllTitle(count: popups.count)) { [weak self] in self?.browsers.openBlockedPopups(id) })
        }
        let pageURL = browsers.runtime(for: id)?.browser.currentURL ?? ""
        if let title = BlockedPopups.allowTitle(pageURL: pageURL) {
            menu.addItem(.separator())
            let allowed = browsers.popupsAllowed(id)
            let allow = BlockMenuItem(title: title) { [weak self] in self?.browsers.setPopupsAllowed(id, !allowed) }
            allow.state = allowed ? .on : .off
            menu.addItem(allow)
        }
        return menu
    }

    /// The space the Site Control Center was opened in.
    private var siteControlCenterSpaceID: UUID?

    /// Screen y of the focused card's toolbar bottom (its top edge when the toolbar is hidden),
    /// and the card's right edge.
    fileprivate func toolbarBottomOnScreen() -> (y: CGFloat, cardMaxX: CGFloat)? {
        guard let window else { return nil }
        // Whatever asks is about to hang something under the bar: a floating one comes out for it.
        shell.bringFloatingToolbarOut()
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
        let profile = profileDirectoryName, incognito = pageIsIncognito
        return ExtensionStore.shared.entries.filter { $0.isInstalled(inProfile: profile) }.map {
            ExtensionLaunch.Extension(id: $0.extensionID, popupPath: $0.popupPath, optionsPath: $0.optionsPath,
                                      enabled: $0.isEnabled(inProfile: profile, incognito: incognito))
        }
    }

    /// The Chromium profile folder the focused page loads in.
    var profileDirectoryName: String { selectedTabID.map(store.profileDirectoryName(item:)) ?? store.profileDirectoryName(space: focusedSpaceID) }

    /// Whether the focused page is incognito: then only the extensions its profile allows in
    /// incognito are listed and run (#620).
    var pageIsIncognito: Bool { selectedTabID.map(store.isIncognito(item:)) ?? store.isIncognito(space: focusedSpaceID) }

    /// The extensions turned on in the focused page's profile (in incognito, those allowed there).
    var extensionEntries: [ExtensionStore.Entry] {
        ExtensionStore.shared.entries(inProfile: profileDirectoryName, incognito: pageIsIncognito)
    }

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

    /// cra://debug?commandBarIcon (#755): the open bar's n-th row's favicon.
    func debugCommandBarIcon(_ i: Int) -> String { commandHost?.debugRowIcon(i) ?? "none" }
    /// cra://debug?commandBarShown (#805): which of the open bar's rows are in view.
    var debugCommandBarShown: String { commandHost?.debugShown ?? "none" }
    /// cra://debug?commandBarDelete (#779): the open bar's n-th row's ✕, in screen points; nil when it shows none.
    func debugCommandBarDeletePoint(_ i: Int) -> NSPoint? { commandPanel.isVisible ? commandHost?.debugDeletePoint(i) : nil }
    /// cra://debug?commandBarDeleteKey (#779): a key typed in the open bar's field, through the app as a key press goes
    /// (the menus' key equivalents first), only while the bar holds the keys.
    func debugCommandBarKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard commandPanel.isVisible, commandPanel.isKeyWindow else {
            CraLog.note("command bar key: the bar doesn't hold the keys"); return
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: commandPanel.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            NSApp.sendEvent(ev)
        }
        CraLog.note("command bar key: sent")
    }

    /// `cra://debug?switcher` (`=all`: ⌃⌥Tab's, #467).
    func debugTabSwitcher(allSpaces: Bool = false, held: NSEvent.ModifierFlags = []) {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tabSwitcher.isDark = dark
        tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
        tabSwitcher.palette = theme.palette
        let items = tabSwitcherItems(allSpaces: allSpaces)
        // The cards, for a scenario: a tab by its title, a split as its panes' titles (#554).
        let cards = items.map { $0.panes.isEmpty ? $0.title : "split(" + $0.panes.map(\.title).joined(separator: " | ") + ")" }
        CraLog.note("tab switcher: \(items.count) cards: \(cards.joined(separator: ", "))")
        tabSwitcher.debugOpen(items, held: held)
    }

    /// `cra://debug?switcher=state`: the open switcher's selected card (#696).
    func debugTabSwitcherState() { CraLog.note("tab switcher state: " + tabSwitcher.debugState) }

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
    /// The Open Extensions shortcut (⌘E). Held ⌘, it is Arc's extension picker (ExtensionPicker, #709): the Site
    /// Control Center with its first extension ringed, the next one on each press, and the ringed one's popup when
    /// ⌘ is let go. From the command bar (no ⌘ held) it opens or closes the Site Control Center as its button does.
    func openExtensions(commandHeld: Bool, isPickerKey: @escaping (NSEvent) -> Bool) {
        switch ExtensionPicker.press(commandHeld: commandHeld, picking: siteControlCenter.isPicking) {
        case .step: siteControlCenter.step()
        case .toggle: showSiteControlsFromTheirButton()
        case .openPicking:
            if !siteControlCenter.isShown { showSiteControlsFromTheirButton() }
            siteControlCenter.startPicking(isPickerKey: isPickerKey)
        }
    }

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
        let midX = SiteControlsPopupAnchor.buttonMidX(given: anchor ?? pressed, underPointer: Self.buttonFrameUnderPointer { $0 is SidebarGlyphButton },
                                                      sliders: (shell.sidebarHost as? SidebarView)?.siteControlsButtonFrameOnScreen,
                                                      pointerX: NSEvent.mouseLocation.x)
        // Arc's popover overlaps the bar by 4 pt (popover top 71 under a bar ending at 75).
        let onScreen = NSRect(x: midX - 16, y: y + 4, width: 32, height: 28)
        let rect = content.convert(window.convertFromScreen(onScreen), from: nil)
        let url = selectedTabID.flatMap { store.item($0)?.tab?.url } ?? ""
        var actions = SiteControlCenterActions()
        actions.share = { [weak self] anchor in self?.shareCurrentPage(from: anchor) }
        actions.copyURL = { [weak self] in self?.app.perform("copyURL") }
        actions.capture = { [weak self] in self?.capturePage() }
        actions.captureFullPage = { [weak self] in self?.captureFullPage() }
        // Opened from the sidebar's URL field (toolbar hidden): the popup hangs under that field from the
        // sliders, as a pin in the sidebar's grid hangs it from its own button. It hung at the page's top
        // right, away from a floating sidebar, which then slid away under it (#531).
        let fromSidebar = SiteControlsPopupAnchor.fromSidebar(
            showToolbar: store.settings.showToolbar, openedInPaneBar: pressed != nil && shell.panesShowBars,
            slidersFrame: (shell.sidebarHost as? SidebarView)?.siteControlsButtonFrameOnScreen, urlFieldBottom: y)
        actions.runExtension = { [weak self] id in
            guard let self else { return }
            guard let anchor = fromSidebar else { return self.runExtensionAction(id) }
            self.holdFloatingSidebarForPopup()
            self.runExtensionAction(id, buttonRightX: anchor.x, buttonBottomY: anchor.y)
        }
        actions.addExtension = { [weak self] in self?.openTab("https://chromewebstore.google.com/category/extensions") }
        actions.manageExtensions = { [weak self] in self?.openTab("chrome://extensions") }
        actions.clearCache = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(.cache) }
        actions.clearCookies = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(.cookies) }
        actions.clearSiteData = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(.siteData) }
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
        actions.pressSafariEngine = { [weak self] row in self?.pressSafariEngine(row, for: url) }
        // Arc's New Boost and the site's boosts (#478), where the page is a website and Boosts are on.
        if store.settings.boostsEnabled, BoostStore.canBoost(url) {
            actions.newBoost = { [weak self] in self?.openBoostEditor() }
            actions.editBoost = { [weak self] id in self?.openBoostEditor(id) }
            actions.toggleBoost = { id in
                guard var b = BoostStore.shared.boost(id) else { return }
                b.enabled.toggle()
                BoostStore.shared.update(b)
            }
            actions.manageBoosts = { [weak self] in self?.showLibrary(.boosts) }
        }
        siteControlCenterSpaceID = focusedSpaceID
        let show = { [weak self] (safariEngine: SafariEngineRow?) in
            guard let self, let window = self.window, window.isVisible else { return }
            self.siteControlCenter.show(relativeTo: rect, of: content, url: url, secure: secure, dark: SystemAppearance.shared.isDark,
                                        profile: self.profileDirectoryName, incognito: self.pageIsIncognito, tab: self.selectedTabID,
                                        protectedMedia: self.browsers.visibleTabID.flatMap { self.sidebarUI.navState(for: $0).protectedMedia },
                                        safariEngine: safariEngine, toggleChecked: true, store: self.store, actions: actions)
        }
        // The Safari's Engine row (ProtectedVideoPages.row): on for a WebKit page, or what moved it
        // there for one video; for a mixed site's Chromium page what Cra saw it ask and what was
        // chosen for the site; for any other Chromium page only once it asked for Widevine
        // (PageScript's `drm`), else no row. That one is asked in Cra's world; a page that doesn't
        // answer within 0.3 s opens without it.
        guard let b = currentBrowser, url.hasPrefix("http") else { return show(nil) }
        if b is WebKitBrowser || PageEngines.sites.mixedSite(for: b.currentURL) != nil { return show(safariEngineRow()) }
        var shown = false
        let once = { [weak self] (drm: Bool) in if !shown { shown = true; show(self?.safariEngineRow(askedForWidevine: drm)) } }
        b.evaluate(inIsolatedWorld: PageScript.world, params: #"{"expression":"window.__cra?.drm === true","returnByValue":true}"#) { result, _ in
            let drm = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { $0["result"] as? [String: Any] }?["value"] as? Bool == true
            DispatchQueue.main.async { once(drm) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { once(false) }
    }

    func debugChooseSafariEngine(_ on: Bool) {
        if let url = currentBrowser?.currentURL { chooseSafariEngine(on, for: url) }
    }

    /// The Site Control Center's Safari's Engine switch: the site plays in WebKit (or Chromium)
    /// from now on, and the focused page opens again there. Choosing it is knowing about it: no toast.
    private func chooseSafariEngine(_ on: Bool, for url: String) {
        guard let id = browsers.visibleTabID else { return PageEngines.choose(on ? .webKit : .chromium, for: url) }
        guard on else {
            PageEngines.choose(.chromium, for: url)
            return browsers.reopenInItsEngine(id)
        }
        // The page arrives signed in: its cookies go along (BrowserManager.moveSiteToSafariEngine).
        browsers.moveSiteToSafariEngine(id, url: url)
        if let service = PageEngines.sites.serviceName(for: url) { PageEngines.told(service) }
    }

    /// The help centre's page on why Spotify, Netflix and the others play in Safari's engine.
    static let protectedMediaHelp = SiteLinks.tagged("https://crabrowser.app/help/protected-media", from: .protectedMedia)

    func debugSiteControlsShown() -> Bool { siteControlCenter.isShown
    }

    /// Scenario hook (#531): "extension popup <step>: closed", or "shown, hangs from <sidebar|page>": whether
    /// the point it hangs from is over the sidebar (anchored or floating) or over the page.
    func debugExtensionPopup(_ step: String) {
        guard let anchor = ExtensionPopupWindow.shownAnchor else { return CraLog.note("extension popup \(step): closed") }
        let host = shell.sidebarHost
        let sidebar = host.window.map { $0.convertToScreen(host.convert(host.bounds, to: nil)) }
        let inSidebar = sidebar.map { anchor.x >= $0.minX && anchor.x <= $0.maxX + 1 } ?? false
        // Where the frame went (#634): its right edge from the anchor, its top from under the URL field.
        let frame = ExtensionPopupWindow.shownFrame ?? .zero
        CraLog.note("extension popup \(step): shown, hangs from \(inSidebar ? "sidebar" : "page")")
        CraLog.note("extension popup \(step) geometry: " + ExtensionPopupWindow.debugGeometry)
        CraLog.note("extension popup \(step) frame: dx=\(Int((frame.maxX - anchor.x).rounded())) dy=\(Int((frame.maxY - anchor.y).rounded())) "
                    + "minX=\(Int(frame.minX - (window?.screen?.frame.minX ?? 0))) fullscreen=\(window?.styleMask.contains(.fullScreen) == true ? 1 : 0) "
                    + "titleBar=\(Int(frame.midX)),\(Int((NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY + 10))")
    }

    /// Scenario hook (#531): "floating sidebar <step>: out" or "in".
    func debugFloatingSidebarState(_ step: String) {
        CraLog.note("floating sidebar \(step): \(floatingSidebar?.isShown == true ? "out" : "in")")
    }

    func debugSiteControlsRead(label: String = "1") { siteControlCenter.debugRead(label: label) }
    func debugSiteControlsPress(_ label: String, accessory: Bool) { siteControlCenter.debugPress(label, accessory: accessory) }

    /// Cra's privacy page, where the command bar's search-suggestions banner says "Learn more".
    static let privacyPage = SiteLinks.tagged("https://crabrowser.app/privacy", from: .commandBarNotice)

    /// Scenario hook (#314): the command bar's (i) ("badge") or a banner button ("settings", "dismiss",
    /// "learnMore") pressed as a click would, then the bar as it stands:
    /// "command bar notice badge: pressed true, badge false, banner true, rows 4, bar open, dismissed false".
    func debugCommandBarNotice(_ step: String) {
        let pressed = step == "badge" ? commandHost.debugPressBadge() : step == "state" ? true : commandHost.debugPressNotice(step)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            CraLog.note("command bar notice \(step): pressed \(pressed), badge \(self.commandHost.debugBadgeShown), "
                + "banner \(self.commandHost.debugNoticeShown), rows \(self.commandBar.result.items.count), "
                + "bar \(self.commandBar.isOpen ? "open" : "closed"), dismissed \(self.store.prefs.searchSuggestionsNoticeDismissed), "
                + "settings \(self.app.debugSettingsPane ?? "closed")")
        }
    }

    /// Scenario hook (#457): "enter" presses Tab on what the bar holds, "leave" Backspaces out of the
    /// scope, "state" only reads; then logs "command bar scope <step>: <scope name or none>, fill <#RRGGBB
    /// or default>, panel <#RRGGBB at alpha>" (the tint over the material, #502) once the bar has drawn.
    func debugCommandBarScope(_ step: String) {
        if step == "enter" { _ = commandBar.enterScope() } else if step == "leave" { commandBar.leaveScope() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            CraLog.note("command bar scope \(step): \(self.commandBar.scope?.name ?? "none"), fill \(self.commandHost.debugFill), "
                + "panel \(self.commandHost.debugPanel), placeholder \(self.commandBar.placeholder), "
                + "hint \(self.commandBar.result.scope?.hint ?? "-")")
        }
    }

    /// Scenario hooks (#226): the sidebar's URL field hovered, its buttons logged as
    /// "url field: copyURL extensions" ("url field: none" while the toolbar has the address).
    func debugURLFieldHover(_ on: Bool) {
        let items = (shell.sidebarHost as? SidebarView)?.debugURLFieldHover(on)
        CraLog.note("url field: " + (items.map { $0.map(Self.debugName).joined(separator: " ") } ?? "none"))
    }

    /// A press on the URL field's button by name ("siteControls", "copyURL"), then whether the
    /// Site Control Center is open once it had time to (it waits up to 0.3 s on the page).
    /// Scenario hooks (#344): "click" logs what a click on the sidebar URL field did ("url field
    /// click: editing <text>", "not editing" when it opened the command bar), "state" what it shows
    /// now; "type:<text>" or
    /// "escape:<text>" types into the field being edited, then presses Return or Escape.
    func debugURLFieldEdit(_ step: String) {
        let sidebar = shell.sidebarHost as? SidebarView
        if step == "click" {
            CraLog.note("url field click: " + (sidebar?.debugURLFieldClick() ?? "none") + ", command bar " + (commandBar.isOpen ? "open" : "closed")
                        + (commandBar.isOpen ? ", " + debugCommandPanelPlace : ""))
            return
        }
        if step == "state" {
            CraLog.note("url field state: " + (sidebar?.debugURLFieldState ?? "none") + ", command bar " + (commandBar.isOpen ? "open" : "closed")
                        + (commandBar.isOpen ? ", " + debugCommandPanelPlace : ""))
            return
        }
        let commit = step.hasPrefix("type:")
        let text = String(step.drop(while: { $0 != ":" }).dropFirst())
        CraLog.note("url field \(commit ? "return" : "escape"): " + (sidebar?.debugURLFieldType(text, commit: commit) == true ? "done" : "not editing"))
    }

    /// Where the open bar is (#663): "panel compact w=<pt> h=<pt> at field" when it hangs from the sidebar's
    /// address (its top left on the field's), "panel centred w=<pt>" otherwise.
    private var debugCommandPanelPlace: String {
        let f = commandPanel.frame
        if commandBarOverDeveloperBar {
            let bar = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.developerBarOnScreen?.bar
            let at = bar.map { abs($0.minX - f.minX) < 0.5 && abs($0.maxY - f.maxY) < 0.5 && abs($0.width - f.width) < 0.5 } == true
            return "panel developer w=\(Int(f.width.rounded())) h=\(Int(f.height.rounded())) " + (at ? "at bar" : "away from bar")
        }
        guard commandBar.compact else { return "panel centred w=\(Int(f.width))" }
        let field = (shell.sidebarHost as? SidebarView)?.addressFrameOnScreen
        let at = field.map { abs($0.minX - f.minX) < 0.5 && abs($0.maxY - f.maxY) < 0.5 } == true
        return "panel compact w=\(Int(f.width.rounded())) h=\(Int(f.height.rounded())) " + (at ? "at field" : "away from field")
    }

    /// Scenario hooks: the focused pane's toolbar address edited in place, as `debugURLFieldEdit`
    /// drives the sidebar's: "click", "state", "type:<text>" (then Return) or "escape:<text>".
    func debugToolbarAddressEdit(_ step: String) {
        let bar = shell.focusedCard?.toolbarHost as? PaneToolbarView
        let place = ", command bar " + (commandBar.isOpen ? "open" : "closed")
        switch step {
        case "click": CraLog.note("toolbar address click: " + (bar?.debugAddressClick() ?? "none") + place)
        case "state": CraLog.note("toolbar address state: " + (bar?.debugAddressState ?? "none") + place)
        default:
            let commit = step.hasPrefix("type:")
            let text = String(step.drop(while: { $0 != ":" }).dropFirst())
            CraLog.note("toolbar address \(commit ? "return" : "escape"): " + (bar?.debugAddressType(text, commit: commit) == true ? "done" : "not editing"))
        }
    }

    func debugURLFieldPress(_ name: String) {
        let item: ToolbarComposition.Item = name == "copyURL" ? .copyURL : .extensions
        let pressed = (shell.sidebarHost as? SidebarView)?.debugURLFieldPress(item) == true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            CraLog.note("url field press \(name): pressed \(pressed), site control center \(self?.siteControlCenter.isShown == true ? "shown" : "not shown")")
        }
    }

    /// Scenario hooks (#310). "line": the sidebar URL field's translate line ("translate line:
    /// Translation Available", or "none"). "open": a press on it (or on the toolbar's button), then
    /// "translate popover: <prompt> | <buttons>". "press:<title>": a press on a popover button.
    /// "menu": the Options menu's items.
    func debugTranslate(_ step: String) {
        let sidebar = shell.sidebarHost as? SidebarView
        switch step {
        case "line":
            CraLog.note("translate line: " + (sidebar?.debugTranslateLine ?? "none"))
        case "open":
            guard let id = browsers.visibleTabID else { return CraLog.note("translate popover: no tab") }
            let toolbar = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.buttonFrameOnScreen("translate")
            showTranslate(id, from: toolbar ?? sidebar?.translateFrameOnScreen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let v = self?.translatePopover.content, self?.translatePopover.isShown == true else {
                    return CraLog.note("translate popover: not shown")
                }
                CraLog.note("translate popover: \(v.prompt) | \(v.options.title), \(v.primary.title)")
            }
        case "menu":
            guard let v = translatePopover.content else { return CraLog.note("translate menu: no popover") }
            CraLog.note("translate menu: " + v.optionsMenu().items.map { $0.isSeparatorItem ? "|" : $0.title }.joined(separator: ", "))
        default:
            guard step.hasPrefix("press:"), let v = translatePopover.content else { return }
            let title = String(step.dropFirst(6))
            for b in [v.options, v.primary] where b.title == title { _ = b.accessibilityPerformPress() }
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

    /// File ▸ Share… (GitHub #279), on the open tab.
    func shareSelectedPage() { PageCommands.share(self) }

    /// The lock in the Site Control Center: the certificate of the page on screen.
    private func showCertificate() {
        guard let b = currentBrowser, let window else { return }
        let host = URL(string: b.currentURL)?.host ?? ""
        guard let certificates = b.sslStatus()?.certificates, !certificates.isEmpty else { return }
        CertificateWindow.show(certificates, host: host, over: window)
    }

    // MARK: Boosts

    /// Arc's New Boost: the open site's boost (made if it has none) in the editor beside the page;
    /// with an id, that boost (a Site Control Center row's chevron).
    func openBoostEditor(_ id: UUID? = nil) {
        guard let window, let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }),
              let boost = id.flatMap(BoostStore.shared.boost) ?? BoostStore.shared.boostForSite(of: url) else { showToast("Boosts Work on Websites"); return }
        BoostEditorController.shared.open(boost, over: window, page: .init(
            zap: { [weak self] on in self?.setZapping(on) },
            dim: { [weak self] on in self?.zapBrowser?.executeJavaScript(BoostZap.dimExpression(on)) },
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

    /// Arc's Zap (BoostZap): the page highlights what's under the pointer and asks before it zaps;
    /// the shelf under the page lists what's zapped. Cra polls the page for its answers, which go
    /// straight into the boost (the page hides them through the boost's stylesheet).
    /// Testing without the pointer (cra://debug?boostZap=1|0): Zap on or off, as its button does.
    func debugZap(_ on: Bool) {
        guard let model = BoostEditorController.shared.editing else { return CraLog.note("zap: no editor") }
        if model.zapping != on { model.toggleZap() }
    }

    private var zapTimer: Timer?
    private weak var zapBrowser: CraBrowser?
    private weak var zapCard: PaneCardView?

    private func setZapping(_ on: Bool) {
        zapTimer?.invalidate()
        zapTimer = nil
        zapBrowser?.executeJavaScript(BoostZap.stopExpression)
        zapBrowser = nil
        zapCard?.bottomBar = nil
        zapCard = nil
        guard on, let b = currentBrowser, let card = shell.focusedCard, let model = BoostEditorController.shared.editing else { return }
        zapBrowser = b
        zapCard = card
        b.executeJavaScript(BoostZap.script)
        let colors = ZapShelfColors.current(theme: focusedSpace.theme, toolbarHex: card.toolbarColor)
        card.bottomBar = ZapShelfHostingView(rootView: ZapShelfView(model: model, colors: colors))
        CraLog.note("zap on: shelf under the page")
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollZap() } }
        RunLoop.main.add(t, forMode: .common)
        zapTimer = t
    }

    private func pollZap() {
        guard let b = zapBrowser else { return }
        // Arc's Zap belongs to the page it started on.
        guard b === currentBrowser else { BoostEditorController.shared.stopZapping(); return }
        // The script goes in again after a navigation; then it answers what it zapped.
        let expression = BoostZap.script + ";" + BoostZap.takeExpression
        guard let data = try? JSONSerialization.data(withJSONObject: ["expression": expression, "returnByValue": true]),
              let params = String(data: data, encoding: .utf8) else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: params) { result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let selectors = BoostZap.parseTaken((o?["result"] as? [String: Any])?["value"] as? String ?? "")
                if !selectors.isEmpty { BoostEditorController.shared.addZapped(selectors) }
            }
        }
    }

    /// Testing the shelf without the pointer (cra://debug?zapHover=<cell>|-1, zapUnzap=<cell>,
    /// zapPress=this|related|cancel): the pointer on a cell, a cell's click, a popover button.
    func debugZapShelf(hover: Int?, unzap: Int?, press: String?) {
        guard let model = BoostEditorController.shared.editing else { return CraLog.note("zap shelf: no editor") }
        if let hover { model.hoveredZap = hover < 0 ? nil : hover }
        if let unzap, model.boost.zapped.indices.contains(unzap) { model.unzap(model.boost.zapped[unzap]) }
        if let press { zapBrowser?.executeJavaScript("window.__craZap&&window.__craZap.press('\(press)')") }
        let hint = BoostZap.hint(zapped: model.boost.zapped, hovered: model.hoveredZap)
        CraLog.note("zap shelf: cells=\(model.boost.zapped.count) hint=\(hint) bar=\(zapCard?.bottomBarHeight ?? 0) page=\(Int(zapCard?.webArea.frame.height ?? 0))")
    }

    private var pickTimer: Timer?
    private weak var pickBrowser: CraBrowser?
    private var pickAnswer: BoostPicker.Action?

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
        for t in pinnedTabsAway { resetPinnedTab(t.id) }
    }

    /// The focused space's pinned tabs away from their saved page, folders included, Favorites not:
    /// what Reset all tabs in this Space takes back.
    private var pinnedTabsAway: [SidebarItem] {
        store.tabs(under: store.focusedSpace(window: windowID).pinnedContainerID).filter { t in
            t.tab.map { $0.url != $0.savedURL } == true
        }
    }

    /// What the Tabs menu's rows can act on in this window's focused space (CraCore TabsMenu, #622).
    func tabsMenuFacts(littleWindowInFront: Bool) -> TabsMenu.Facts {
        let selection: TabsMenu.Facts.Selection = switch selectedTabID.flatMap({ store.rootContainer(of: $0) }) {
        case .favorites: .favorite
        case .pinned: .pinned
        case .today: .today
        case nil: .none
        }
        // Counted only as far as the rules look (one tab, another tab) and stopped at the first
        // clearable Today row: AppKit checks every row on each menu check, at any sidebar size.
        return TabsMenu.Facts(selection: selection, tabs: store.visibleTabCount(in: focusedSpaceID, upTo: 2),
                              clearableToday: store.todayHasClearable(playing: sidebarUI.audibleTabIDs),
                              resettablePinned: !pinnedTabsAway.isEmpty,
                              window: isBlank ? .blank : isIncognito ? .incognito : .normal,
                              littleWindowInFront: littleWindowInFront, makingSpace: sidebarUI.spaceCreation != nil)
    }

    /// Arc's Edit ▸ Copy URL as Quote, Save Page As and the page captures, on the open tab (PageCommands).
    func copyURLAsQuote() { PageCommands.copyURLAsQuote(self) }
    func savePageAs() { PageCommands.savePageAs(self) }

    func captureFullPage() {
        captureOverlay?.close()
        PageCommands.captureFullPage(self)
    }

    func capturePortrait() {
        captureOverlay?.close()
        PageCommands.capturePortrait(self)
    }

    /// The toast's Save: Arc's "Save Capture Image" panel, in Downloads.
    private func saveCapture(_ png: Data, over sourceWindow: NSWindow? = nil) {
        guard let window = sourceWindow ?? window else { return }
        PageCommands.saveCapture(png, over: window, host: self)
    }

    // MARK: Tab switcher

    /// ⌃Tab / ⌃⇧Tab: Arc's switcher over the space's recent tabs. ⌃⌥Tab (`allSpaces`, #467, not
    /// in Arc): the same cards over every space's, each naming its space.
    func cycleRecentTabs(_ delta: Int, event: NSEvent?, allSpaces: Bool = false) {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !tabSwitcher.isOpen {
            tabSwitcher.isDark = dark
            tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
            tabSwitcher.palette = theme.palette
        }
        tabSwitcher.cycle(delta, event: event) { tabSwitcherItems(allSpaces: allSpaces) }
        // The pages on screen are the freshest thumbnails there are: retake them for their card
        // (every pane of a split on screen).
        guard tabSwitcher.isOpen else { return }
        for current in browsers.visibleTabIDs {
            browsers.captureSnapshot(current) { [weak self] in
                guard let self else { return }
                self.tabSwitcher.updateSnapshot(current, self.browsers.runtime(for: current)?.snapshot)
            }
        }
    }

    private func tabSwitcherItems(allSpaces: Bool) -> [TabSwitcher.Item] {
        openRecentCards(limit: TabSwitcherMetrics.maxItems, allSpaces: allSpaces).compactMap { card in
            let id = card.opens
            guard let it = store.item(id), let tab = it.tab else { return nil }
            let space = allSpaces ? store.spaceID(ofItem: id, window: windowID).flatMap(store.space) : nil
            var item = TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot,
                                        space: space.map { TabSwitcher.SpaceLabel(title: $0.title, icon: SpaceMenuIcon.image(for: $0)) })
            if card.isSplit {
                let factors = SplitPaneLayout.normalizedFactors(ids: card.panes, stored: store.item(card.id)?.split?.widthFactors ?? [:])
                item.panes = card.panes.compactMap { pid in
                    guard let p = store.item(pid), let t = p.tab else { return nil }
                    return TabSwitcher.Pane(id: pid, title: p.displayTitle, iconKey: t.iconKey, snapshot: browsers.runtime(for: pid)?.snapshot,
                                            width: factors[pid] ?? 1 / CGFloat(card.panes.count))
                }
            }
            return item
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

    /// `fromSidebarAddress`: a click on the sidebar's address, which opens Arc's panel hanging from it
    /// (#663); ⌘L and the rest keep the centred bar.
    /// Arc's ⌥⌘G (gptMessage, #828): the ⌘T bar scoped to ChatGPT, or the plain bar with the switch off.
    func newChatGPTMessage() {
        openCommandBar(.newTab)
        guard commandBar.isOpen, ChatGPTCommandBar.newMessage(enabled: store.settings.chatGPTInCommandBar) == .scopedToChatGPT else { return }
        commandBar.openScoped(to: ChatGPTCommandBar.site)
    }

    func openCommandBar(_ mode: CommandBarMode, fromSidebarAddress: Bool = false) {
        guard let window else { return }
        // The bar takes over from the sidebar's address field edited in place (#344).
        (shell.sidebarHost as? SidebarView)?.endAddressEditing()
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
        commandBarAnchor = fromSidebarAddress ? (shell.sidebarHost as? SidebarView)?.addressFrameOnScreen : nil
        commandBar.compact = commandBarAnchor != nil
        // Arc's ⌘L on a page that shows the developer bar edits it in place, the suggestions across the card.
        let devBar = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.developerBarOnScreen
        commandBarOverDeveloperBar = DeveloperBarPanel.opens(editingURL: effectiveMode == .editURL && !fromSidebarAddress && prefill != nil,
                                                            barIsDeveloper: devBar != nil, barShown: devBar != nil)
        commandBar.developer = commandBarOverDeveloperBar ? devBar.map {
            CommandBarDeveloperInput(glyphCenterX: $0.glyphCenterX - $0.bar.minX, textX: $0.textX - $0.bar.minX, glyph: $0.glyph,
                                     glyphTint: $0.tint, topRadius: $0.cardRadius)
        } : nil
        commandBar.theme = focusedSpace.theme.shown
        commandBar.focusedSpaceID = focusedSpaceID
        commandBar.open(mode: effectiveMode, prefill: prefill)
        // Arc draws the New Tab row as the active one while the bar makes a new tab; the
        // sidebar scrolls to it (SpaceListView.revealActiveRow).
        sidebarUI.newTabPlaceholderActive = effectiveMode == .newTab && !fillingEmptyPane
        // Centred in the window, also when opened from the toolbar; from the sidebar's address, Arc's
        // panel over the top of the sidebar, as wide as the address (#663).
        commandBar.attached = false
        if commandBarOverDeveloperBar, let devBar {
            commandBar.panelWidth = devBar.bar.width
        } else if let anchor = commandBarAnchor {
            let address = (prefill ?? "") as NSString
            let textWidth = address.size(withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(SidebarAddressPanel.fontSize), weight: .medium)]).width
            commandBar.panelWidth = CGFloat(SidebarAddressPanel.width(textWidth: Double(textWidth), available: Double(window.frame.maxX - anchor.minX)))
        } else {
            commandBar.panelWidth = min(CraMetrics.commandBarWidth, window.frame.width - 80)
        }
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
            _ = commandBar.rowPlaces
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
        if commandBarOverDeveloperBar, let bar = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.developerBarOnScreen?.bar {
            // Its top on the developer bar's, the card's width; the rows drop across the page (#663 follow-up).
            let h = CGFloat(DeveloperBarPanel.height(rows: commandBar.rowPlaces))
            commandPanel.setFrame(NSRect(x: bar.minX, y: bar.maxY - h, width: bar.width, height: h), display: true)
            return
        }
        if let opened = commandBarAnchor {
            // Its top left on the address field's, where the field is now; the rows hang below (#663).
            let anchor = (shell.sidebarHost as? SidebarView)?.addressFrameOnScreen ?? opened
            let h = CGFloat(SidebarAddressPanel.height(rows: commandBar.rowPlaces))
            commandPanel.setFrame(NSRect(x: anchor.minX, y: anchor.maxY - h, width: commandBar.panelWidth, height: h), display: true)
            return
        }
        let h = CommandBarView.height(forRows: commandBar.rowPlaces)
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
        panel.level = .floating
        // Lost to another window (a click in window 2 while ⌘L was open in window 1), the keys stay
        // there: taking them back went on sending typing to this window's page (#429).
        let lostTo = commandBarLostKeysTo
        commandBarLostKeysTo = nil
        let closing: CommandBarClosing = lostTo.map { .lostKeys(to: $0) } ?? .byBar
        if closing.barsWindowTakesKeys { focusAfterCommandBar() }
    }

    /// Another app came to the front with the bar open: it stays with what was typed (#551, as in Arc),
    /// below the other app's windows rather than floating over them.
    private func commandBarWaitsForCra() {
        if NSApp.isActive { commandPanel.makeKeyAndOrderFront(nil); return }
        commandPanel.level = .normal
    }

    /// Cra is in front again: the bar that waited takes the keys back. A click that brought Cra back
    /// closes it, as any click outside the bar does; the clicked window takes the keys before the
    /// panel could lose them, so it never hears of that click otherwise.
    private func commandBarCraCameBack() {
        guard commandBar.isOpen, let panel = commandPanel else { return }
        panel.level = .floating
        if let e = NSApp.currentEvent, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(e.type), e.window !== panel {
            commandBarLostTheKeys()
            return
        }
        if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
    }

    /// The bar's panel lost the keys, or a click went past it: a click in Cra closes the bar, another
    /// app coming to the front doesn't (CommandBarClosing).
    private func commandBarLostTheKeys() {
        let event = NSApp.currentEvent
        let clickAt = event?.type == .leftMouseDown ? event?.timestamp : nil
        commandPanel.keysWent(owns: { [weak self] w in
            guard let self else { return false }
            return w === self.window || self.peeks.contains { $0.peekWindows.contains { $0 === w } }
        }, finish: { [weak self] holder in
            guard let self, self.commandBar.isOpen, !self.commandPanel.isKeyWindow else { return }
            guard CommandBarClosing.closesBar(lostKeysTo: holder) else { self.commandBarWaitsForCra(); return }
            self.commandBarClosingClick.panelClosed(byMouseDownAt: clickAt)
            self.commandBarLostKeysTo = holder
            self.commandBar.close()
        })
    }

    private func focusAfterCommandBar() {
        // ⌘T from a Peek and Escape: the keys go back to the Peek still over its tab (#379).
        if let peek = peeks.first(where: { !$0.isParked && $0.window?.isVisible == true }) {
            peek.window?.makeKeyAndOrderFront(nil)
            peek.focusPage()
            return
        }
        window?.makeKeyAndOrderFront(nil)
        currentBrowser?.setFocused(true)
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode) {
        let query = commandBar.query
        // address: what opens is an address entered, not a search; counted for the completion (#667).
        func open(_ url: String, address: Bool = false) {
            var url = url, entered = address
            // Another app's address opens that app, with no tab (#604).
            switch AppLinkPrompt.openTyped(url) {
            case .load: break
            case .openApp, .refuse: return
            case .search: url = commandBar.engine.searchURL(typed); entered = false
            }
            store.recordQuerySelection(query: query, url: url)
            let fillsEmptyPane = selectedTab?.isEmptyTab == true
            // A pinned tab keeps to its host: another host's address opens a Today tab (Arc).
            let leavesPinned = !fillsEmptyPane && selectedTabID.map(store.isPinned) == true
                && PinnedNavigation.typedURLOpensNewTab(url, from: selectedTab?.tab?.url ?? "")
            // Air Traffic Control routes a typed URL too (#421): the tab opens in the route's space and the window
            // goes there, as in Arc.
            let route = isStandalone ? nil : store.settings.space(forTypedURL: url).flatMap { id in
                store.orderedSpaces.contains(where: { $0.id == id }) ? id : nil
            }
            let destination = TypedDestination.of(loadsInSelectedTab: (mode == .editURL || fillsEmptyPane) && selectedTabID != nil && !leavesPinned,
                                                  route: route, focused: focusedSpaceID)
            // Counted in the profile it opens in, not the one it was typed in (#864).
            if entered { store.recordTyped(url: url, profile: store.profileID(space: destination.space(focused: focusedSpaceID))) }
            switch destination {
            case .selectedTab: loadInSelectedTab(url)
            case .routed(let space): store.createTab(url: url, in: space, window: windowID)
            case .newTab:
                let tab = store.createTab(url: url, window: windowID)
                if !isStandalone { browsers.beginRedirectRouting(for: tab.id, space: focusedSpaceID) }
            }
        }
        guard let s else {
            if typed.isEmpty { return }
            let address = SuggestionEngine.looksLikeURL(typed)
            open(address ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed), address: address)
            return
        }
        switch s.kind {
        case .switchToTab(let id):
            store.recordQuerySelection(query: query, url: s.url ?? "")
            // Filling Add Split View's new pane, an open tab comes into the split, as in Arc (#645).
            let empty = selectedTab?.isEmptyTab == true ? selectedTabID : nil
            let sameProfile = empty.map { store.profileDirectoryName(item: $0) == store.profileDirectoryName(item: id) } ?? false
            switch SplitPanePick.of(picked: id, emptyPane: empty, panes: empty.map { store.paneTabIDs(for: $0) } ?? [], sameProfile: sameProfile) {
            case .switchTo:
                store.selectTab(id, window: windowID)
            case .selectPane(let empty):
                store.selectTab(id, window: windowID)
                closeSplitPane(empty)
            case .join(let empty):
                fillEmptyPane(empty, with: id)
            }
        case .archived(let id):
            store.restoreArchived(id)
        case .navigate:
            let address = TypedURL.navigation(typed: typed, rowURL: s.url, rowIsForTyped: typed == commandBar.query)
            open(address ?? commandBar.engine.searchURL(typed), address: address != nil)
        case .search:
            open(s.url ?? commandBar.engine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "", address: true)
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            store.focusSpace(id, window: windowID)
        case .moveToSpace(let id):
            if let t = selectedTabID { store.moveTabAndFollow(t, toSpace: id, window: windowID) }
        case .revealFolder(let id):
            guard store.spaceID(ofItem: id) == focusedSpaceID else { return }
            store.revealInSidebar(id)
            store.setExpanded(id, true)
            if sidebarUI.libraryPage != nil { closeLibrary() }
            if !sidebarVisible { toggleSidebar() }
            sidebarUI.keyboardFocusID = id
            let ui = sidebarUI, space = focusedSpaceID
            DispatchQueue.main.async { SpaceListView.jumpToFolder(id, for: ui, space: space) }
        case .moveToFolder(let id):
            if let t = selectedTabID { store.moveItem(t, to: id, index: nil) }
        }
    }

    /// Shift-Return on a search in the bar (Instant Links, #407): the row, the plan and the results go to
    /// the space this window shows.
    private func runInstantLinks(_ phrase: String, engine: ChromiumSearchEngine) {
        InstantLinksService.shared.run(phrase: phrase, space: focusedSpaceID, engine: engine, store: store,
                                       host: .init(windowID: windowID, load: { [weak self] id in self?.browsers.ensureRuntime(for: id) }),
                                       asNewTab: sidebarUI.newTabPlaceholderActive)
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
        toastBackgroundTab(tab.id)
        return true
    }

    /// A tab opened behind the page, from the bar or from a page (#543): with the sidebar out the
    /// new row shows there; hidden, Arc says so in its toast.
    private func toastBackgroundTab(_ id: UUID) {
        let space = store.spaceID(ofItem: id)
        guard let text = BackgroundTabToast.text(sidebarVisible: sidebarVisible, tabSpace: space, shownSpace: focusedSpaceID,
                                                 tabSpaceTitle: space.flatMap { store.space($0)?.title }) else { return }
        backgroundTabToasts += 1
        CraLog.note("background tab toast \(backgroundTabToasts): \(text)")
        // Still up from the last one: it bumps and now holds this tab too; up with something else, or gone, it starts over.
        announcedBackgroundTabs = toast.isTappable ? announcedBackgroundTabs + [id] : [id]
        showToast(text) { [weak self] in
            // Arc's toast is a button (#543): it opens the tab it announced, in its space.
            guard let self, let tab = BackgroundTabToast.clickOpens(announced: self.announcedBackgroundTabs,
                                                                   isOpen: { self.store.item($0)?.isTab == true }) else {
                CraLog.note("background tab toast clicked: nothing to open")
                return
            }
            CraLog.note("background tab toast clicked: \(self.store.item(tab)?.tab?.url ?? "")")
            self.store.selectTab(tab, window: self.windowID)
        }
    }

    /// The background-tab toasts this window showed, for cra.log (scenario background-tab-toast).
    private var backgroundTabToasts = 0
    /// The tabs the toast up now announced, oldest first: a click opens the newest (BackgroundTabToast.clickOpens).
    private var announcedBackgroundTabs: [UUID] = []

    /// cra://debug?clickToast=1: a click on the toast up now, as the pointer's.
    func clickToastForTest() {
        if !toast.testClick() { CraLog.note("toast click: no toast to click") }
    }

    /// cra://debug?toastShown=<label>: whether a toast is up in this window.
    var toastIsShown: Bool { toast.isShown }
    var toastText: String { toast.text }

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
        guard store.paneTabIDs(for: current).count < store.splitPaneLimit else {
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
            url = TypedURL.navigation(typed: typed, rowURL: s?.url, rowIsForTyped: typed == commandBar.query) ?? commandBar.engine.searchURL(typed)
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
            self.slowResponseToastTab = nil
            self.protectedVideoPromptUp = false
            self.toast.show("\(service) plays with Safari's engine",
                            action: ShinyToast.Action(title: "Why?") { [weak self] in self?.showSiteControlsFromTheirButton() },
                            page: page, in: window, theme: self.focusedSpace.theme, onClose: told)
        }
    }

    /// Services whose toast was offered this session (they show once a session until answered).
    private var offeredProtectedMedia: Set<String> = []

    /// Arc's toast at the top right of the page (ShinyToast): Cra's confirmations.
    func showToast(_ text: String, keyCap: (keys: String, after: String)? = nil, action: ShinyToast.Action? = nil,
                   onTap: (() -> Void)? = nil) {
        guard let window else { return }
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        slowResponseToastTab = nil
        protectedVideoPromptUp = false
        toast.show(text, keyCap: keyCap, action: action, page: page, in: window, theme: focusedSpace.theme, onTap: onTap)
    }

    /// An MCP agent's pill at the bottom of the page (AgentPill): its face, what it does, Take Over (⌘.).
    private lazy var agentPill = AgentPill()

    /// ⌘. (Stop Loading) while an agent's pill is up here, or while an agent whose pill was closed
    /// with its × still acts here, stops the agent instead of the page.
    func takeOverFromAgent() -> Bool { agentPill.takeOverIfUp() || MCPServer.shared.takeOverClosedPill(in: windowID) }

    /// `tabWatched`: the agent acts in a tab the user is looking at (the whole pill), else only its face.
    func showAgentPill(_ text: String, tabWatched: Bool, lingers: TimeInterval, takeOver: @escaping () -> Void, close: @escaping () -> Void) {
        guard let window else { return }
        agentPill.show(text, tabWatched: tabWatched, lingers: lingers, page: { [weak self] in
            guard let self else { return nil }
            return self.shell.webContainer.convert(self.shell.webContainer.bounds, to: nil)
        }, in: window, takeOver: takeOver, close: close)
    }

    /// Tests (cra://debug?mcpPill=open|close|takeover): a click on the pill's face, on its ×, or ⌘.
    func pressAgentPill(_ part: String) {
        switch part {
        case "close": agentPill.pressClose()
        case "takeover": CraLog.note("mcp pill: ⌘. \(takeOverFromAgent() ? "took over" : "found no agent")")
        default: agentPill.open()
        }
    }

    // MARK: An agent's cursor

    /// The agent's cursor over each tab it acts in (AgentCursor), made on its first move.
    private var agentCursors: [UUID: AgentCursor] = [:]

    /// The pointer an MCP agent moves in tab `id`, for its cursor; nil for a tab not in this window.
    func agentPointer(for id: UUID) -> MCPPointerWatcher? {
        guard let runtime = browsers.runtime(for: id) else { return nil }
        for gone in agentCursors.keys where browsers.runtime(for: gone) == nil { agentCursors.removeValue(forKey: gone)?.hide() }
        let cursor = agentCursors[id] ?? AgentCursor(pageFrame: { [weak self] in self?.browsers.runtime(for: id)?.pageScreenFrame },
                                                     isWatched: { [weak self] in self?.agentTabIsWatched(id) ?? false })
        agentCursors[id] = cursor
        return AgentPointer(cursor: cursor, browser: runtime.browser, window: self)
    }

    /// The user can see tab `id`'s page: it is shown in this window, and the window is on screen
    /// and not covered. Only then does the agent's cursor show and its pointer slow down to be followed.
    func agentTabIsWatched(_ id: UUID) -> Bool {
        guard let window, window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) || Self.agentTabsWatchedUnseen,
              browsers.visibleTabIDs.contains(id), browsers.runtime(for: id)?.pageScreenFrame != nil else { return false }
        return true
    }

    /// Tests (cra://debug?mcpWatched=on): a shown tab counts as watched in a window behind other
    /// apps, so Tests/mcp_agent.py sees the watched cursor and scrolling without taking the screen.
    static var agentTabsWatchedUnseen = false

    /// The update banner's news while this window's sidebar (which carries the banner) is hidden:
    /// Cra's toast with the banner's action, staying until its ✕ so it isn't missed.
    func showUpdateToast(_ notice: UpdateNotice) {
        guard let window else { return }
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        protectedVideoPromptUp = false
        toast.show(notice.title, action: ShinyToast.Action(title: notice.button) { SoftwareUpdater.shared.act(on: notice) },
                   page: page, in: window, theme: focusedSpace.theme, onClose: {})
    }

    /// A Peek's page loads in the tab the Peek came from (⌘-click on Expand, GitHub #380): the tab
    /// comes to the front with the page, and a pinned one keeps its pinned address (updateTab).
    func loadPeekPage(_ url: String, inTab id: UUID) {
        guard store.item(id) != nil else { return }
        if selectedTabID != id { store.selectTab(id, window: windowID) }
        loadInSelectedTab(url)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Navigate the focused tab (an empty split pane gets its first page here).
    /// Return in an address edited in place (#344), for `id`: it loads there or, for another host
    /// from a pinned tab, in a new tab (SidebarAddressEdit.commit). `id` is selected first, so a
    /// split pane's bar loads in its own pane.
    private func commitAddress(_ typed: String, in id: UUID) {
        guard let item = store.item(id) else { return }
        switch SidebarAddressEdit.commit(typed: typed, currentURL: item.tab?.url ?? "", pinned: store.isPinned(id),
                                         searchURL: commandBar.engine.searchURL) {
        case .none: break
        case .load(let url):
            if selectedTabID != id { store.selectTab(id, window: windowID) }
            loadInSelectedTab(url)
        case .newTab(let url): store.createTab(url: url, window: windowID)
        }
    }

    func loadInSelectedTab(_ url: String) {
        guard let id = selectedTabID else { return }
        // Typed over an incognito tab, Chrome's Settings or Extensions page opens in a new tab of the
        // normal window (createTab sends it there), as Chrome's omnibox does; the tab keeps its page (#412).
        if store.isIncognito(item: id), !IncognitoPages.allows(url) {
            store.createTab(url: url, window: windowID)
            return
        }
        let wasEmpty = store.item(id)?.isEmptyTab == true
        store.updateTab(id, url: url)
        browsers.noteExplicitNavigation(id)
        if let rt = browsers.ensureRuntime(for: id), !wasEmpty { rt.browser.loadURL(url) }
        refresh()
        browsers.show(store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID), focused: id, focus: true)
    }

    // MARK: Find

    /// Privileged scenario seam: exercise the production query/native-command paths without
    /// global keyboard input. Result diagnostics contain identity/counts only, never query text.
    func debugFind(query: String?, step: String?, quote: Bool) {
        debugFindResults = true
        if let query {
            if quote { browsers.find(query, forward: true, purpose: .quote) }
            else {
                let restoring = overlay.findVisible && overlay.findQuery == query && browsers.findState.request?.purpose == .quote
                overlay.findQuery = query
                showFindBar()
                if restoring { find(query, forward: true) }
            }
        }
        switch step {
        case "show": showFindBar()
        case "close": hideFindBar()
        case "next": findNext(forward: true)
        case "previous": findNext(forward: false)
        default: break
        }
        logFindState()
    }

    private func logFindState() {
        let state = browsers.findState
        CraLog.note("find generation=\(state.request?.id.uuidString ?? "none") identifier=\(state.identifier.map(String.init) ?? "none") "
                    + "count=\(state.count.map(String.init) ?? "pending") ordinal=\(state.activeMatch) final=\(state.finalUpdate) "
                    + "purpose=\(state.request?.purpose == .quote ? "quote" : "ordinary")")
    }

    func showFindBar(focus: Bool = true) {
        let opening = !overlay.findVisible
        if opening { browsers.stopFinding(false) }
        syncAskOnPage()
        overlay.findVisible = true
        findTabID = selectedTabID
        findParked = false
        // Opening finds the text again on the page in front: a fresh search, so it starts at the first match.
        if opening, !overlay.findQuery.isEmpty { find(overlay.findQuery, forward: true) }
        if focus { overlay.findFocusToken += 1 }
        shell.findVisible = true
        shell.layoutContentChildren()
        if let window, let find = findPanel {
            if find.parent !== window { window.addChildWindow(find, ordered: .above) }
            refitFindPanel()
            if focus { find.makeKeyAndOrderFront(nil) } else { find.orderFront(nil) }
        }
    }

    func hideFindBar() {
        findParked = false
        overlay.findVisible = false
        overlay.findMatchCount = nil
        askOnPage.reset()
        shell.findVisible = false
        browsers.stopFinding(true)
        shell.layoutContentChildren()
        if let find = findPanel, let window {
            // Typing goes back to the page, unless focus already moved elsewhere.
            if find.isKeyWindow, let rt = browsers.visibleRuntime {
                // The page's Chrome window (CEF), else the page's view in this window (the Chromium engine).
                if let host = rt.hostWindow { host.makeKey() } else {
                    window.makeKey()
                    if let render = rt.pageViews.last.flatMap(EmbeddedPages.renderView(in:)) { window.makeFirstResponder(render) }
                }
            }
            window.removeChildWindow(find)
            find.orderOut(nil)
        }
        currentBrowser?.setFocused(true)
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Use Selection to Find: the page's selection becomes the
    /// search, on the find pasteboard too as macOS apps share it, and the bar finds it.
    func useSelectionForFind() {
        guard let b = currentBrowser, let owner = browsers.findPageContext() else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = ((o?["result"] as? [String: Any])?["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self, self.currentBrowser === b, self.browsers.findPageContext() == owner, !text.isEmpty else { return }
                let pb = NSPasteboard(name: .find)
                pb.clearContents()
                pb.setString(text, forType: .string)
                // Typing does not search in a conversation; this explicit Find command still must.
                let needsSearch = self.overlay.findVisible && (self.overlay.findQuery == text || !self.askOnPage.findsWhileTyping)
                self.overlay.findQuery = text
                self.showFindBar()
                if needsSearch { self.find(text, forward: true) }
            }
        }
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection (⌘J): the page scrolls its selection into view.
    func jumpToSelection() { PageCommands.jumpToSelection(currentBrowser) }

    func findNext(forward: Bool) {
        if !overlay.findVisible { showFindBar(); return }
        find(overlay.findQuery, forward: forward)
    }

    /// Always a follow-up find: CEF restarts the search when the text changes, and
    /// unlike a first request that selects a match (Chrome's find bar does this while
    /// typing), so the bar shows "1/3" rather than "0/3".
    private func find(_ q: String, forward: Bool) {
        browsers.find(q, forward: forward)
    }

    /// Ask on Page or the plain find bar, by the setting and the model; the card follows the page in
    /// front and the space's colour.
    func syncAskOnPage() {
        let enabled = store.settings.askOnPage && AskOnPageLocalModel.isAvailable && TidyTabsService.shared.currentModelAvailable
        let state = askOnPage.state
        if state.enabled != enabled {
            state.enabled = enabled
            if !enabled { askOnPage.reset() }
        }
        shell.findHost.isHidden = enabled
        askOnPage.view.isHidden = !enabled
        let theme = focusedSpace.theme.shown
        // Not theme.isDark: the card follows macOS, so it makes a question for each appearance (#408).
        askOnPage.setTone(themeHex: theme.accent ?? theme.colors.first ?? "#DDDDDD")
        if enabled { browsers.refreshAskOnPageDocument() }
        askOnPage.pageChanged(canAsk: browsers.askOnPageContext() != nil)
        refitFindPanel()
    }

    /// The find panel takes the card's size, its top trailing corner where it was.
    /// `followingToolbar`: the floating toolbar slides out or away, and the panel moves with it.
    private func refitFindPanel(followingToolbar: Bool = false) {
        guard let window, let find = findPanel, overlay.findVisible, let page = lastFindPage else { return }
        let frame = findPanelFrame(page: page)
        guard find.parent === window, find.frame != frame else { return }
        guard followingToolbar else { find.setFrame(frame, display: true); return }
        let out = shell.floatingToolbarCover > 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = out ? ToolbarAutoHide.revealDuration : ToolbarAutoHide.hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: out ? .easeOut : .easeIn)
            find.animator().setFrame(frame, display: true)
        }
    }

    /// For `cra://debug?findBar=<label>`: whether the find bar shows, and how far its panel is
    /// from the focused page's top and trailing edges.
    func debugFindBar(_ label: String) -> String {
        guard let find = findPanel, overlay.findVisible, let page = lastFindPage else { return "findBar \(label): visible=0" }
        // `focused`: the bar's field is its panel's first responder, so it has the keys whenever the panel is key
        // (a background copy never has a key window); `selected`: all of its text is selected, so typing replaces it.
        let editor = find.firstResponder as? NSTextView
        let focused = editor?.delegate is NSTextField
        let selected = editor.map { !$0.string.isEmpty && $0.selectedRange() == NSRange(location: 0, length: ($0.string as NSString).length) } ?? false
        return "findBar \(label): visible=1 top=\(Int(page.maxY - find.frame.maxY)) trailing=\(Int(page.maxX - find.frame.maxX)) "
            + "size=\(Int(find.frame.width))x\(Int(find.frame.height)) focused=\(focused ? 1 : 0) selected=\(selected ? 1 : 0) query=\(overlay.findQuery)"
    }

    /// For `cra://debug?key=…&target=find`: the find bar's panel, which has the keys while the bar is up.
    var debugFindPanel: NSWindow? { findPanel }

    // MARK: Sheets

    /// `created` runs with a new space's id once Save made it (Move to ▸ New Space…, #356).
    func showSpaceEditor(space: Space?, created: ((UUID) -> Void)? = nil) {
        guard let window else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 651, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        // Arc's New Space starts on the profile of the space it was opened from.
        let initialProfile = space == nil && !isStandalone ? SpaceProfiles.forNewSpace(from: store.focusedSpace, profiles: store.profiles) : nil
        let store = self.store
        let profilePath = space.flatMap { store.profilePath(space: $0.id) } ?? store.profilePath(profile: initialProfile)
        let defaultEngine = SearchEngines.shared.defaultEngine(profilePath: profilePath, legacy: store.settings.searchEngine)
        let engines = ChromiumSearchEngine.spaceChoices(among: SearchEngines.shared.keywords(profilePath: profilePath))
        let view = SpaceEditorView(existing: space, profiles: store.profiles, defaultProfileName: store.profileName(nil), initialProfile: initialProfile, searchEngines: engines,
                                   defaultEngineName: defaultEngine.name, onSave: { [weak panel] title, icon, theme, profile, newName, searchEngine in
            let id: UUID
            if let sid = space?.id, var s = store.space(sid) {
                s.rename(to: title); s.icon = icon; s.theme = theme
                store.updateSpace(s)
                id = s.id
            } else {
                id = store.createSpace(title: title, emoji: icon.emoji, symbol: icon.symbol, iconImage: icon.image, theme: theme).id
            }
            switch profile {
            case .existing(let p): store.setProfile(p, forSpace: id)
            case .new: store.setProfile(store.createProfile(name: newName).id, forSpace: id)
            }
            store.setSearchEngine(searchEngine, forSpace: id)
            if let panel { window.endSheet(panel) }
            if space == nil { created?(id) }
        }, onCancel: { [weak panel] in if let panel { window.endSheet(panel) } }, onPreview: { theme in
            // A new space has nothing to draw on yet; the sheet's own preview shows it.
            if let sid = space?.id { store.previewTheme(theme, forSpace: sid) }
        })
        panel.contentView = NSHostingView(rootView: view)
        spaceEditor = panel
        CraLog.note("space editor opens: \(space == nil ? "a new space" : "an existing space")")
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
        LinkSummaryPreviewController.shared.stop(windowID: windowID)
        cancelSpaceCreation()
        if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
        importWindow?.close()
        commandBar.close()
        if overlay.findVisible { hideFindBar() }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // Arc's Spaces page keeps the page its 56 pt while the window resizes; in a window
        // narrower than Arc allows, the other pages give way to the page too (LibraryWidth).
        if let page = sidebarUI.libraryPage, sidebarUI.libraryReveal == nil, libraryWidth(page) != shell.sidebarWidth {
            shell.sidebarWidth = libraryWidth(page)
            if page != .spaces { CraLog.note("library is \(Int(shell.sidebarWidth)) pt wide in a \(Int(window?.frame.width ?? 0)) pt window") }
        }
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
        if let host = browsers.visibleRuntime?.hostWindow { ChromiumPageFocus.focus(host) }
        refreshMaterialActive()
        // Cra came forward for a press on Picture in Picture's window only (#741): this window is still behind the app in
        // use, and an automatic Picture in Picture's video stays out.
        if !PictureInPictureChrome.shared.isInFrontForWindow { browsers.windowVisibilityChanged(covered: false) }
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
        if (notification.object as? NSWindow) === window {
            if let host = browsers.visibleRuntime?.hostWindow { ChromiumPageFocus.blur(host) }
            leaveIfCovered()
        }
        guard (notification.object as? NSWindow) === commandPanel, commandBar.isOpen else { return }
        // A page made behind the bar takes the keys while it opens: it takes them back. A click took them
        // (#807): that closes it, however soon after ⌘T.
        let click = NSApp.currentEvent.map { [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains($0.type) && $0.window !== commandPanel } ?? false
        let open = Date().timeIntervalSince(commandBarOpenedAt)
        CraLog.note(String(format: "command bar lost the keys %.2f s after opening%@", open, click ? " to a click" : ""))
        if CommandBarClosing.takesKeysBack(secondsOpen: open, byClick: click) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandPanel.makeKeyAndOrderFront(nil)
            }
            return
        }
        commandBarLostTheKeys()
    }

    // The sidebar header's toggle moves into the traffic lights' place while they are gone (Arc).
    func windowWillEnterFullScreen(_ notification: Notification) {
        sidebarUI.windowFullscreen = true; shell.windowFullscreen = true
        (window as? CraWindow)?.fullScreenChanged()
    }
    func windowWillExitFullScreen(_ notification: Notification) { sidebarUI.windowFullscreen = false; shell.windowFullscreen = false }
    func windowDidEnterFullScreen(_ notification: Notification) {
        (window as? CraWindow)?.fullScreenChanged()
        shell.needsLayout = true
        // Remembered for the next launch (#426), unless a page's video took the window there.
        if !pageFullscreenWindow.enteredForPage { store.updateWindow(windowID) { $0.fullScreen = true } }
        if let toast = pendingNoticeToast {
            pendingNoticeToast = nil
            showNoticeToast(toast)
        }
        runAfterFullScreen()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { runAfterFullScreen() }
    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? CraWindow)?.fullScreenChanged()
        // Put away into the menu bar, it leaves full screen only to order out: it comes back in it.
        if !isPutAway { store.updateWindow(windowID) { $0.fullScreen = false } }
        // Left with the green button or ⌃⌘F while a video was fullscreen: the page leaves too.
        if let id = contentFullscreenTab { browsers.runtime(for: id)?.browser.exitFullscreen() }
        contentFullscreenTab = nil
        if shell.contentFullscreen { shell.contentFullscreen = false }
        floatingSidebar?.sidebarVisibilityChanged()
        pageFullscreenWindow.windowLeftFullScreen()
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
    /// A locked screen covers every window and leaves nothing. macOS 27.2.1 called a window on a second
    /// display not visible when another app became active on the first, with nothing in front of it
    /// (#533): the windows in front decide (WindowCoverage).
    private func leaveIfCovered(settled: Bool = false) {
        guard let window, !window.isKeyWindow, !window.occlusionState.contains(.visible), !Self.screenIsLocked else { return }
        let coverage = Self.coverage(of: window)
        guard coverage.covered else {
            // Said in the log: the case the reporter's macOS made (#533), and what the scenarios watch for.
            CraLog.note("window not visible to macOS, nothing in front covers it: \(coverage.summary)")
            return
        }
        // Off screen: another desktop, the Dock, or the Mission Control or App Exposé grid, where the window is
        // still in sight (#698: a full-screen video went to Picture in Picture and came back to full screen each
        // time Mission Control opened). Decided after a moment, and once Mission Control has closed.
        if !coverage.onScreen, !settled {
            waitOffScreen()
            return
        }
        // What covered it, so a Picture in Picture nobody expected can be told apart (a test runner's window over Cra).
        CraLog.note("window out of sight: \(coverage.summary)")
        browsers.windowVisibilityChanged(covered: true)
    }

    /// Mission Control or App Exposé is up, by the Dock's windows over the displays (WindowCoverage).
    private static func missionControlShowing() -> Bool {
        WindowCoverage.missionControlShowing(CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
    }

    /// Asks the window server a few times a second while this window is off screen and not key
    /// (WindowCoverage.OffScreenWait), then decides as for any other change (leaveIfCovered). Back on screen
    /// or key, the wait ends: windowDidBecomeKey brings a video home as before.
    private func waitOffScreen() {
        guard offScreenTimer == nil else { return }
        offScreenWait = WindowCoverage.OffScreenWait()
        offScreenTimer = Timer.scheduledTimer(withTimeInterval: WindowCoverage.OffScreenWait.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.offScreenTick() }
        }
    }

    private func offScreenTick() {
        guard !isTornDown, let window, !window.isKeyWindow, !window.occlusionState.contains(.visible) else {
            if offScreenWait.sawMissionControl, let window { CraLog.note("Mission Control closed: window \(window.isKeyWindow ? "key" : "visible")") }
            return endOffScreenWait()
        }
        switch offScreenWait.tick(missionControl: Self.missionControlShowing()) {
        case .wait: break
        case .missionControl: CraLog.note("window in Mission Control: \(Self.coverage(of: window).summary), waits until it closes")
        case .outOfSight:
            let sawMissionControl = offScreenWait.sawMissionControl
            endOffScreenWait()
            if sawMissionControl { CraLog.note("Mission Control closed: window not visible") }
            leaveIfCovered(settled: true)
        }
    }

    private func endOffScreenWait() {
        offScreenTimer?.invalidate()
        offScreenTimer = nil
    }

    private var offScreenTimer: Timer?
    private var offScreenWait = WindowCoverage.OffScreenWait()

    /// `cra://debug?missionControl=open|close|state`: opens or closes Mission Control (Mission Control.app
    /// toggles it), and says once the Dock's windows show it or are gone, for the #698 scenario.
    func debugMissionControl(_ mode: String) {
        let want: Bool
        switch mode {
        case "open": want = true
        case "close": want = false
        default:
            CraLog.note("mission control: \(Self.missionControlShowing() ? "showing" : "not showing")")
            return
        }
        if Self.missionControlShowing() != want {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
        Self.sayMissionControl(when: want, after: mode, triesLeft: 50)
    }

    private static func sayMissionControl(when want: Bool, after mode: String, triesLeft: Int) {
        let showing = missionControlShowing()
        guard showing == want || triesLeft <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { sayMissionControl(when: want, after: mode, triesLeft: triesLeft - 1) }
            return
        }
        CraLog.note("mission control: \(showing ? "showing" : "not showing") after \(mode)")
    }

    /// What the window server has in front of `window`, its own parts (its child windows, Chrome's page
    /// host windows) told apart. Asked only after macOS said the window isn't visible, and by
    /// `cra://debug?windowCoverage=1`.
    static func coverage(of window: NSWindow) -> WindowCoverage.Reading {
        let number = CGWindowID(window.windowNumber)
        let own = number > 0 ? (CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]])?.first : nil
        let inFront = number > 0 ? CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, number) as? [[String: Any]] ?? [] : []
        return WindowCoverage.read(window: own, inFront: inFront, pid: ProcessInfo.processInfo.processIdentifier) { n in
            guard let w = NSApp.window(withWindowNumber: n) else { return false }
            return EmbeddedPages.isHost(w) || sequence(first: w, next: \.parent).contains { $0 === window }
        }
    }

    /// `cra://debug?windowCoverage=1`: what automatic Picture in Picture would read for this window if
    /// macOS called it not visible (#533).
    func windowCoverageReadout() -> String {
        guard let window else { return "window coverage: no window" }
        return "window coverage: \(Self.coverage(of: window).summary)"
    }

    /// `cra://debug?coverWindow=<mode>`: what takes this window out of sight, or doesn't, for the
    /// window-covered scenarios (#117, #533), with no other app to drive. A window that can be key takes
    /// key from this one: `other` lies opaque over all of it, `child` does too as its child window (a
    /// part of it: macOS calls the window not visible, the window server shows only its own part),
    /// `aside` is small and beside it. `minimise` puts it in the Dock. `off` takes the cover away and
    /// brings this window back as key.
    func debugCoverWindow(_ mode: String) {
        guard let window else { return }
        debugCover?.parent?.removeChildWindow(debugCover!)
        debugCover?.orderOut(nil)
        debugCover = nil
        switch mode {
        case "other", "child", "aside":
            var frame = window.frame
            if mode == "aside", let screen = window.screen?.visibleFrame {
                let size = CGSize(width: 80, height: 80)
                let corners = [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX - size.width, y: screen.minY),
                               CGPoint(x: screen.minX, y: screen.maxY - size.height), CGPoint(x: screen.maxX - size.width, y: screen.maxY - size.height)]
                frame = corners.map { CGRect(origin: $0, size: size) }.first { !$0.intersects(window.frame) }
                    ?? CGRect(origin: corners[0], size: size)
            }
            let cover = DebugCoverWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            cover.isReleasedWhenClosed = false
            cover.isOpaque = true
            cover.backgroundColor = .systemTeal
            cover.setFrame(frame, display: true)
            if mode == "child" { window.addChildWindow(cover, ordered: .above) }
            cover.makeKeyAndOrderFront(nil)
            debugCover = cover
        case "minimise":
            window.miniaturize(nil)
        default:
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        CraLog.note("cover window: \(mode), this window \(window.isKeyWindow ? "key" : "not key")")
    }
    private var debugCover: NSWindow?

    private final class DebugCoverWindow: NSWindow {
        override var canBecomeKey: Bool { true }
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
        // A page being made goes with its window: the space it was opened on gets its theme back.
        cancelSpaceCreation()
        askOnPage.reset()
        LinkSummaryPreviewController.shared.stop(windowID: windowID)
        tabSwitcher.cancel()
        // Teardown first hands any surviving page/download to its new window.
        app.mainWindowWillClose(self)
        TidyDownloadsService.shared.cancel(window: windowID)
    }

    override func showWindow(_ sender: Any?) {
        app.browserWindowWillShow(self)
        super.showWindow(sender)
        // A window that opens with no tab and its sidebar hidden (a relaunch) holds it open now that
        // it is on screen; the first refresh ran before it was.
        holdSidebarOpenIfEmpty()
    }

    /// GitHub #483: a window with no tab holds its hidden sidebar open (SidebarPresentation.heldOpen),
    /// whatever made it so: the sidebar button, the last tab closing, a space with nothing selected or a
    /// relaunch. It waits for the window to be on screen and for a space swipe to land; a tab ends it,
    /// and the pointer then sends the sidebar in as before.
    private func holdSidebarOpenIfEmpty() {
        guard let floatingSidebar, window?.isVisible == true, sidebarUI.spaceSwipe == 0,
              sidebarPresentation.mode == .heldOpen, !floatingSidebar.isShown else { return }
        floatingSidebar.showInPlace()
    }

    /// ⌘Q put Cra in the menu bar (#231): the window is out of sight and its pages are closed, as
    /// on a quit; the tabs stay. No page opens until `bringBack`.
    private(set) var isPutAway = false

    func putAway() {
        guard !isPutAway else { return }
        isPutAway = true
        TidyDownloadsService.shared.cancel(window: windowID)
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
        // Called as the window is about to show (browserWindowWillShow).
        DispatchQueue.main.async { [weak self] in self?.enterSavedFullScreen() }
    }

    /// A window that was in full screen when Cra quit (or went to the menu bar) goes back into it
    /// once shown (#426), on its own Space as before.
    /// `then` runs once the window is on its full-screen Space (a new window's command bar, #528),
    /// or right away when it doesn't go there.
    func enterSavedFullScreen(then: (() -> Void)? = nil) {
        guard let window, window.isVisible, store.window(windowID).fullScreen,
              !window.styleMask.contains(.fullScreen) else { then?(); return }
        afterFullScreen = then
        window.toggleFullScreen(nil)
    }

    private var afterFullScreen: (() -> Void)?

    private func runAfterFullScreen() {
        let then = afterFullScreen
        afterFullScreen = nil
        then?()
    }

    /// The window closed while others stay open: its pages close (the tabs stay in
    /// the sidebar) and it lets go of everything that would keep it alive.
    func tearDown() {
        isTornDown = true
        endOffScreenWait()
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
        for card in shell.paneCards { card.pageTopGrabber.removeFromSuperview() }
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
    /// While Cra comes forward for a press on Picture in Picture's window (#741), a browser window takes neither the
    /// keyboard nor main: the window's overlay has the keyboard, and the browser windows stay behind the app in use
    /// (PictureInPictureChrome.pressed).
    static var stayBehindWhileComingForward = false
    override var canBecomeKey: Bool { !Self.stayBehindWhileComingForward && super.canBecomeKey }
    override var canBecomeMain: Bool { !Self.stayBehindWhileComingForward && super.canBecomeMain }

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
        switch TitleBarDoubleClick(setting: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
        case .nothing: break
        case .minimize: miniaturize(nil)
        case .zoom: zoom(nil)
        }
    }

    /// The strip above the content card (the window's inset margin) stands in for the
    /// title bar there. It reaches 4 pt into the toolbar card, above its buttons, so a
    /// press just past the card's edge still counts. Movable-by-background only drags,
    /// and the toolbar takes a click as "edit URL", so the strip's presses are handled
    /// here: a double-click runs the title bar action, anything else drags the window.
    /// Edge to edge there is no margin, so only the 4 pt reaching into the toolbar (or the page) is left.
    /// The margin is the one Settings ▸ Pages ▸ Margin sets (Ideas #366, PageMargin.titleStrip).
    private var titleStripHeight: CGFloat {
        guard let shell = contentView as? ShellView else { return CGFloat(PageMargin.titleStrip(margin: PageMargin.arc, edgeToEdge: false)) }
        return CGFloat(PageMargin.titleStrip(margin: shell.pageMargin, edgeToEdge: shell.edgeToEdge))
    }

    /// Full screen is the system's to place (#308): no drag moves the window inside its Space,
    /// whether AppKit's own (title bar, background) or one of ours (`performDrag` from the title
    /// strip, the toolbar and the sidebar's top). Arc's full-screen window stays put the same way.
    /// The flags the sidebar sets while the pointer is over a draggable row stay as they were and
    /// apply again once the window leaves full screen.
    override var isMovable: Bool {
        get { super.isMovable && !styleMask.contains(.fullScreen) }
        set { super.isMovable = newValue }
    }

    override var isMovableByWindowBackground: Bool {
        get { super.isMovableByWindowBackground && !styleMask.contains(.fullScreen) }
        set { super.isMovableByWindowBackground = newValue }
    }

    override func performDrag(with event: NSEvent) {
        guard isMovable else { return }
        super.performDrag(with: event)
    }

    /// AppKit's screen-layout manager adjusts a window's frame on a move that takes it to another
    /// display (`_setFrameAfterMove:`, the server's report of a move, calls this): to the frame the
    /// window last had on that display, or, with none saved, to a proportional place on it. Meant
    /// for a display coming or going, it runs on a drag's moves and on its release as well, for a
    /// window an NSWindowController owns (a plain window is left alone), so the window jumped away
    /// from the pointer at each crossing, or at the release, and the offsets added up (three
    /// displays at 1x, 2x and 1x, 16 Nov 2026). Chromium's NativeWidgetMacNSWindow skips the same
    /// two callbacks while its move loop drags a tab across displays. Here the adjustment is skipped
    /// for every move the server reports, drags and their release; a display change, which comes
    /// another way, still gets AppKit's own adjustment.
    ///
    /// At a display crossing that adjustment is also what records the moved frame in AppKit. Skipped,
    /// AppKit kept the frame from before the crossing while the window was on the other display, and
    /// every menu opened away from the window: a `<select>`'s popup sat a display's width from its
    /// control (21 Nov 2026). So the frame the server reports is recorded here instead, where the
    /// window already is.
    @objc(_setFrameAfterMove:)
    func setFrameAfterMove(_ frameRect: NSRect) {
        guard let method = class_getInstanceMethod(NSWindow.self, Self.frameAfterMoveSelector) else { return }
        inFrameAfterMove = true
        skippedAdjustment = false
        typealias After = @convention(c) (NSWindow, Selector, NSRect) -> Void
        unsafeBitCast(method_getImplementation(method), to: After.self)(self, Self.frameAfterMoveSelector, frameRect)
        inFrameAfterMove = false
        if skippedAdjustment, frame != frameRect { setFrame(frameRect, display: false) }
    }

    @objc(_setFrame:fromAdjustmentToScreen:anchorIfNeeded:animate:)
    func setFrame(_ frameRect: NSRect, fromAdjustmentToScreen screen: NSScreen?, anchorIfNeeded anchor: UnsafePointer<CGPoint>?, animate: Bool) {
        if inFrameAfterMove {
            skippedAdjustment = true
            return
        }
        guard let method = class_getInstanceMethod(NSWindow.self, Self.frameAdjustmentSelector) else { return }
        typealias Adjust = @convention(c) (NSWindow, Selector, NSRect, NSScreen?, UnsafePointer<CGPoint>?, Bool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Adjust.self)(self, Self.frameAdjustmentSelector, frameRect, screen, anchor, animate)
    }

    private var inFrameAfterMove = false
    private var skippedAdjustment = false
    private static let frameAfterMoveSelector = NSSelectorFromString("_setFrameAfterMove:")
    private static let frameAdjustmentSelector = NSSelectorFromString("_setFrame:fromAdjustmentToScreen:anchorIfNeeded:animate:")

    /// `cra://debug?frameAfterMove=1`: the report the window server sends after a drag, for a move
    /// onto another display, and whether AppKit's frame is the reported frame afterwards. A menu,
    /// a `<select>`'s popup or a tooltip opens where AppKit thinks the window is.
    func frameAfterMoveReadout() -> String {
        guard let here = screen, let there = NSScreen.screens.first(where: { $0 != here }) else {
            return "frame after move: one display"
        }
        let moved = NSRect(origin: NSPoint(x: there.visibleFrame.minX + 40, y: there.visibleFrame.maxY - 40 - frame.height), size: frame.size)
        setFrameAfterMove(moved)
        let result = frame == moved ? "recorded" : "stale \(NSStringFromRect(frame)) for \(NSStringFromRect(moved))"
        return "frame after move: \(result)"
    }

    /// For the windowState readout: `own` when this class answers the adjustment and AppKit still
    /// has both callbacks, `appkit` when AppKit's run, `none` when AppKit no longer has them.
    static var frameAdjustment: String {
        let selectors = [frameAfterMoveSelector, frameAdjustmentSelector]
        guard selectors.allSatisfy(NSWindow.instancesRespond(to:)) else { return "none" }
        let own = selectors.allSatisfy { class_getMethodImplementation(CraWindow.self, $0) != class_getMethodImplementation(NSWindow.self, $0) }
        return own ? "own" : "appkit"
    }

    override func sendEvent(_ event: NSEvent) {
        // ⌘. while an agent's pill is up here: Take Over (AgentPill). Here, because a key for the
        // page goes from Chrome's application straight to this window: no local key monitor
        // sees it, and the page would make it Escape before the menu's Stop Loading.
        if event.type == .keyDown, AgentPill.isTakeOverKey(event),
           (windowController as? MainWindowController)?.takeOverFromAgent() == true { return }
        if event.type == .leftMouseDown, WindowDragRegion.allows(event, in: self),
           let content = contentView, event.locationInWindow.y >= content.bounds.height - titleStripHeight,
           isTitleStrip(content.hitTest(content.convert(event.locationInWindow, from: nil))) {
            if event.clickCount == 2 { performTitleDoubleClickAction() } else { performDrag(with: event) }
            return
        }
        super.sendEvent(event)
    }

    /// The sidebar, web content and native controls handle their own presses. Content
    /// fullscreen also leaves no title strip to drag.
    private func isTitleStrip(_ view: NSView?) -> Bool {
        var v = view
        while let current = v {
            if current is SidebarView || current is NSControl || current is NSTextView
                || NSStringFromClass(type(of: current)) == "WebContentsViewCocoa" { return false }
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

    /// Entering or leaving full screen changes whether the lights show (#308), so they are
    /// recomputed then rather than waiting for a layout pass to reach `layoutIfNeeded`.
    func fullScreenChanged() {
        updateTrafficLights(animated: false)
    }

    private func updateTrafficLights(animated: Bool) {
        let hide = trafficLightsHidden && !styleMask.contains(.fullScreen)
        guard hide != appliedTrafficLightsHidden else { return }
        appliedTrafficLightsHidden = hide
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        // Hidden buttons rest at alpha 1: AppKit refuses to miniaturize a window whose
        // minimize button has alpha 0 (⌘M and the floating sidebar's yellow button did nothing).
        guard animated else {
            for b in buttons { b.alphaValue = 1; b.isHidden = hide }
            parkTrafficLights(hide)
            return
        }
        if !hide {
            parkTrafficLights(false)
            for b in buttons where b.isHidden { b.alphaValue = 0; b.isHidden = false }
        }
        // Same timing as the sidebar's slide (ShellView.animateSidebar).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.085
            for b in buttons { b.animator().alphaValue = hide ? 0 : 1 }
        } completionHandler: { [weak self] in
            guard let self, self.appliedTrafficLightsHidden == hide else { return }
            for b in buttons { b.isHidden = hide; b.alphaValue = 1 }
            if hide { self.parkTrafficLights(true) }
        }
    }

    /// Hidden lights also wait outside the window, `parkedShift` left of their spot and spaced as they
    /// were. With the sidebar hidden the toolbar's toggle and ← sit where they were, and on macOS 27.2
    /// a click on ← there did nothing or zoomed the window (GitHub #449; on 26 the toolbar gets it).
    /// Out of the window, hidden buttons can't take a press on any macOS.
    private var trafficLightsParked = false
    private static let parkedShift: CGFloat = 1000

    private func parkTrafficLights(_ parked: Bool) {
        guard parked != trafficLightsParked else { return }
        trafficLightsParked = parked
        positionTrafficLights()
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

    /// Also from the shell's layout while the sidebar is on the right, where the lights go with it.
    func positionTrafficLights() {
        // Full screen is the system's to place, except lights still out of the window (#449).
        let fullScreen = styleMask.contains(.fullScreen)
        // The system's spacing between the buttons stays (20 pt on macOS 15, 23 on 26, #445).
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        // In the sidebar's top row, wherever the sidebar docks (#464). Parked lights wait left of the
        // window whatever the side (#449: 1000 pt left of a right-hand sidebar's would still be inside),
        // and full screen's come back to the system's left-hand spot.
        let offset = trafficLightsParked || fullScreen ? 0 : Double((contentView as? ShellView)?.trafficLightsOffset ?? 0)
        let xs = TrafficLightLayout.originsX(system: buttons.map { Double($0.frame.minX) }, leading: TrafficLightLayout.leading + offset)
        for (b, x) in zip(buttons, xs) {
            guard let sv = b.superview else { continue }
            if fullScreen, trafficLightsParked || b.frame.minX > -Self.parkedShift / 2 { continue }
            let x = CGFloat(x) - (trafficLightsParked ? Self.parkedShift : 0)
            let y = sv.bounds.height - CraMetrics.titleRowCenter - b.frame.height / 2
            let target = NSPoint(x: x, y: y)
            if abs(b.frame.origin.x - target.x) > 0.5 || abs(b.frame.origin.y - target.y) > 0.5 {
                b.setFrameOrigin(target)
            }
        }
    }
}
