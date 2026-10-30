import AppKit
import CraCEF
import SwiftUI

/// Arc's Little Arc, here a "Little Window": links from other apps (and ⌥⌘N)
/// open in a small, sidebar-less window with its own Chromium browser. The
/// page is not in the sidebar. Closing the window archives it to the Library
/// (Arc: archive source `littleArc`); "Open in <Space>" (⌘O) promotes it into a
/// space's Today list, moving the live browser into the main window.
///
/// Geometry and colours were measured from Arc 1.168's Little Arc on 24 Oct
/// 2026 (docs/arc-reverse-engineering.md, "Little Arc"): a 46pt navy strip with
/// muted traffic lights, one full-width search pill, and a split
/// "Open in <Space> ⌘O | ⌄" button; the page fills the rest, inside the window's rim.
@MainActor
@Observable
final class LittleWindowState {
    var url = ""
    var title = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var progress: Double = 0
    var themeColor = ""
    /// The space ⌘O opens into (the focused space when the window was made).
    var targetSpaceID: UUID
    var popupOpen = false
    /// Pointer hover, tracked by AppKit (SwiftUI's onHover sleeps while the
    /// Chrome page window, a child, is the key window).
    var hover: LittleHover = .none
    /// Width of the "Open in" button, reported by LittleToolbarView for hit-testing.
    var openButtonWidth: CGFloat = 160

    init(targetSpaceID: UUID) { self.targetSpaceID = targetSpaceID }
}

enum LittleHover { case none, pill, puzzle, link, open, chevron }

/// What the strip needs AppKit to do.
@MainActor
final class LittleWindowActions {
    var openCommandBar: () -> Void = {}
    var copyURL: () -> Void = {}
    var promote: (UUID?) -> Void = { _ in }
    var togglePopup: () -> Void = {}
    var closePopup: () -> Void = {}
}

/// Arc's Little Arc chrome, measured at 2x (window 1688×1010, profile "default").
enum LittleMetrics {
    static let barHeight: CGFloat = 46
    static let controlHeight: CGFloat = 30      // pill and button: y 8…38
    static let pillLeft: CGFloat = 83
    static let pillGap: CGFloat = 10            // pill → button
    static let rightMargin: CGFloat = 7
    static let chevronWidth: CGFloat = 29
    /// Arc's window corners; used when the system radius can't be read (see LittleWindow).
    static let cornerRadius: CGFloat = 10
    /// The light rim macOS draws along the window's edge. The page is a child window
    /// above the Little Window, so laid edge to edge it covered the rim on three sides.
    static let edgeInset: CGFloat = 1
    static let popupWidth: CGFloat = 240
    static let popupRowHeight: CGFloat = 54
    static let popupHeaderHeight: CGFloat = 46
    static let commandBarWidth: CGFloat = 500
    static let defaultSize = NSSize(width: 1400, height: 900)
    /// The old default, which every resize used to save (placement and the open
    /// animation included), so a stored copy of it was never the user's choice.
    static let legacyDefaultSize = NSSize(width: 1000, height: 700)
    static let minSize = NSSize(width: 480, height: 360)
    static let openDuration: TimeInterval = 0.12
}

/// Arc renders Little Arc with the default profile's dark palette whatever the
/// focused space's theme is (observed with the light "Victor" space focused).
enum LittlePalette {
    static let bar = Color(red: 12 / 255, green: 9 / 255, blue: 28 / 255)
    static let pill = Color(red: 37 / 255, green: 34 / 255, blue: 52 / 255)
    static let pillHover = Color(red: 45 / 255, green: 46 / 255, blue: 62 / 255)
    static let iconHover = Color(red: 65 / 255, green: 57 / 255, blue: 70 / 255)
    static let icon = Color(red: 110 / 255, green: 111 / 255, blue: 128 / 255)
    static let iconHot = Color(red: 170 / 255, green: 168 / 255, blue: 180 / 255)
    static let text = Color(red: 163 / 255, green: 161 / 255, blue: 169 / 255)
    static let label = Color(red: 130 / 255, green: 131 / 255, blue: 146 / 255)
    static let button = Color(red: 5 / 255, green: 6 / 255, blue: 37 / 255)
    static let buttonBorder = Color(red: 29 / 255, green: 30 / 255, blue: 55 / 255)
    static let buttonHover = Color(red: 22 / 255, green: 23 / 255, blue: 52 / 255)
    static let badge = Color(red: 23 / 255, green: 24 / 255, blue: 50 / 255)
    static let badgeText = Color(red: 139 / 255, green: 140 / 255, blue: 153 / 255)
    static let popupButton = Color(red: 92 / 255, green: 92 / 255, blue: 113 / 255)
    // Hover tips (measured): navy pill, lavender-white text, pale key caps with blue glyphs.
    static let tooltip = Color(red: 10 / 255, green: 13 / 255, blue: 75 / 255)
    static let tooltipText = Color(red: 222 / 255, green: 223 / 255, blue: 253 / 255)
    static let tooltipBorder = Color(red: 34 / 255, green: 37 / 255, blue: 93 / 255)
    static let tooltipCap = Color(red: 211 / 255, green: 212 / 255, blue: 253 / 255)
    static let tooltipCapGlyph = Color(red: 40 / 255, green: 46 / 255, blue: 252 / 255)
    static let barNS = NSColor(red: 12 / 255, green: 9 / 255, blue: 28 / 255, alpha: 1)
    static let buttonNS = NSColor(red: 5 / 255, green: 6 / 255, blue: 37 / 255, alpha: 1)

    /// The space name in "Open in Victor": the target theme's light foreground
    /// (Arc: semanticColorPalette.dark.foregroundPrimary; Victor → #FCEDBC).
    static func spaceName(_ theme: SpaceTheme) -> Color {
        Color(hex: theme.accent ?? theme.colors.first ?? "#FFFFFF").blendedToward(.white, 0.72)
    }
}

@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate, @preconcurrency CraBrowserDelegate {
    unowned let app: AppDelegate
    let state: LittleWindowState
    let actions = LittleWindowActions()
    let commandBar: CommandBarController
    private(set) var browser: CraBrowser?
    /// The page (a video) is in element fullscreen.
    private var pageFullscreen = false
    private let shell: LittleShellView
    private var favicon: NSImage?
    private var promoted = false
    /// Hosts a page's window.open (a sign-in popup); its URL arrives after it shows.
    private let isPopupHost: Bool
    /// Arc's Peek: this Little Window sits over a browser window, which a dimming panel
    /// covers; a click on it, Escape or the close button ends the Peek.
    let isPeek: Bool
    private(set) weak var peekParent: MainWindowController?
    private var dim: PeekDimPanel?
    private var commandPanel: CommandBarPanel!
    private var commandHost: CommandBarView!
    private var commandBarOpenedAt = Date.distantPast
    private var commandObserving = false
    private var popup: LittlePopupPanel?
    private var tooltip: LittleTooltipPanel?
    private var tooltipTimer: Timer?

    var store: SidebarStore { app.store }
    var currentURL: String { browser?.currentURL ?? state.url }
    var hasPage: Bool { !currentURL.isEmpty && currentURL != "about:blank" }

    /// `url` nil makes a popup host: the browser adopts the next window.open
    /// CEF hands it (see `CraBrowserDelegate.browser:popupHostForURL:`).
    init(app: AppDelegate, url: String?, peekOver parent: MainWindowController? = nil) {
        self.app = app
        isPopupHost = url == nil
        isPeek = parent != nil
        peekParent = parent
        // Little Windows are normal browsing: they target the last normal window's space
        // (a Peek: the space of the window it covers).
        state = LittleWindowState(targetSpaceID: parent?.focusedSpaceID ?? app.store.focusedSpaceID(window: app.store.lastNormalWindowID))
        commandBar = CommandBarController(engine: app.engine, store: app.store)
        let size = app.store.prefs.littleWindowSize.map { NSSizeFromString($0) }
            .flatMap { $0 == LittleMetrics.legacyDefaultSize ? nil : $0 }
            .map { NSSize(width: max(LittleMetrics.minSize.width, $0.width), height: max(LittleMetrics.minSize.height, $0.height)) }
            ?? LittleMetrics.defaultSize
        let window = LittleWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: parent != nil ? [.titled, .closable, .fullSizeContentView]
                                      : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        shell = LittleShellView(frame: window.contentView!.bounds)
        super.init(window: window)
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = LittleMetrics.minSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = "Little Window"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = LittlePalette.barNS
        window.contentView = shell
        shell.setToolbar(LittleToolbarView(state: state, actions: actions, store: app.store))
        shell.onHover = { [weak self] h in
            guard let self, self.state.hover != h else { return }
            self.state.hover = h
            self.scheduleTooltip(for: h)
        }
        shell.openButtonWidth = { [weak self] in self?.state.openButtonWidth ?? 160 }
        if parent != nil {
            // A Peek is part of its window: no minimizing or zooming it on its own.
            window.isMovableByWindowBackground = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        } else {
            placeWindow()
        }

        actions.openCommandBar = { [weak self] in self?.openCommandBar() }
        actions.copyURL = { [weak self] in self?.copy(self?.currentURL ?? "") }
        actions.promote = { [weak self] sid in self?.promote(to: sid) }
        actions.togglePopup = { [weak self] in self?.togglePopup() }
        actions.closePopup = { [weak self] in self?.closePopup() }

        commandPanel = CommandBarPanel()
        commandHost = CommandBarView(controller: commandBar, favicons: app.favicons)
        commandPanel.contentView = commandHost
        commandPanel.delegate = self
        commandBar.onCommit = { [weak self] s, typed, mode, force in self?.handleCommit(s, typed: typed, mode: mode, forceNewTab: force) }
        commandBar.onClose = { [weak self] in self?.hideCommandPanel() }
        commandBar.spaceName = { [weak self] id in self?.store.space(id)?.title ?? "" }

        let b = CraBrowser(frame: shell.page.bounds, url: url.map { $0.isEmpty ? "about:blank" : $0 }, delegate: self)
        attach(b)
        state.url = (url == "about:blank" ? "" : url) ?? ""
    }

    required init?(coder: NSCoder) { fatalError() }

    private func attach(_ b: CraBrowser) {
        browser = b
        // Embedded (Alloy) hosting: the Chromium view lives inside the page area.
        // Chrome-style hosting delivers a window later (-browser:didCreateHostWindow:).
        let v = b.containerView
        v.frame = shell.page.bounds
        v.autoresizingMask = [.width, .height]
        shell.page.addSubview(v)
        shell.onPageFrame = { [weak self] rect in self?.positionHostWindow(rect) }
        if let w = b.hostWindow { attachHostWindow(w) }
    }

    /// Chrome-style hosting: the page is a frameless Chrome window; attach it
    /// as a child window over the page area and round its bottom corners.
    private func attachHostWindow(_ w: NSWindow) {
        guard let window, w.parent !== window else { return }
        // Borderless like MainWindowController's pages: a titled window gets macOS's
        // rounded corners on all four sides and a resize zone past the page's edges.
        w.styleMask.remove([.titled, .resizable])
        w.styleMask.insert(.fullSizeContentView)
        ChromiumWindowCorners.setSquare(true, for: w)
        ChromiumChildHover.setDocked(true, for: w)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovable = false
        w.hasShadow = false
        w.isOpaque = false
        w.backgroundColor = .clear
        ChromiumChildFullscreen.attach(w)
        if let cv = w.contentView {
            cv.isHidden = false   // a background tab's page (MainWindowController hides it)
            cv.wantsLayer = true
            cv.layer?.cornerCurve = .continuous
            // Chromium's content view is flipped, so its layer's MaxY edge is the bottom.
            cv.layer?.maskedCorners = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cv.layer?.masksToBounds = true
        }
        window.addChildWindow(w, ordered: .above)
        positionHostWindow(shell.convert(shell.page.frame, to: nil))
        w.orderFront(nil)
        // The command bar and the spaces popup stay above the page window.
        if commandPanel.parent === window { window.removeChildWindow(commandPanel); window.addChildWindow(commandPanel, ordered: .above) }
    }

    private func positionHostWindow(_ rectInWindow: NSRect) {
        guard let window, let w = browser?.hostWindow, w.parent === window, !rectInWindow.isEmpty else { return }
        let onScreen = window.convertToScreen(rectInWindow)
        if w.frame != onScreen { w.setFrame(onScreen, display: true) }
        // Chrome leaves its content view where the title bar ended (22 pt down), which
        // showed as a strip above the page and cut off its bottom.
        let full = NSRect(origin: .zero, size: onScreen.size)
        if let cv = w.contentView, cv.frame != full { cv.frame = full }
        // Chromium can restore its own style mask (fullscreen, display changes).
        if w.styleMask.contains(.titled) || w.styleMask.contains(.resizable) {
            w.styleMask.remove([.titled, .resizable])
            ChromiumWindowCorners.setSquare(true, for: w)
        }
        if let layer = w.contentView?.layer, layer.cornerRadius != shell.pageCornerRadius { layer.cornerRadius = shell.pageCornerRadius }
    }

    private func focusPage() {
        guard let b = browser else { return }
        if let w = b.hostWindow, w.parent === window { w.makeKey() }
        b.setFocused(true)
    }

    /// Where the window lands: centred on the screen under the pointer, cascaded
    /// off other little windows.
    private func placeWindow() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, vf.width - 40)
        frame.size.height = min(frame.height, vf.height - 40)
        let n = CGFloat(app.littleWindows.count)
        frame.origin = NSPoint(x: vf.midX - frame.width / 2 + n * 24, y: vf.midY - frame.height / 2 - n * 24)
        frame.origin.x = min(max(vf.minX, frame.origin.x), vf.maxX - frame.width)
        frame.origin.y = min(max(vf.minY, frame.origin.y), vf.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    /// Arc grows the window from a small rectangle under the pointer to its
    /// full frame in about 120 ms (content laid out at full size, no fade).
    func show() {
        guard let window else { return }
        let final = window.frame
        let mouse = NSEvent.mouseLocation
        var start = NSRect(x: mouse.x - 24, y: mouse.y - 15, width: 48, height: 30)
        start.origin.x = min(max(final.minX, start.minX), final.maxX - start.width)
        start.origin.y = min(max(final.minY, start.minY), final.maxY - start.height)
        // Content stays laid out at the full size (Arc clips it); a Chrome page
        // window would stick out of the growing frame, so it waits until the end.
        shell.frozenSize = final.size
        let host = browser?.hostWindow
        if let host, host.parent === window { host.alphaValue = 0 }   // orderOut would detach the child
        window.setFrame(start, display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // NSWindow frame animation (animationResizeTime is overridden to 120 ms).
        window.setFrame(final, display: true, animate: true)
        shell.frozenSize = nil
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
        if let host, host.parent === window { host.alphaValue = 1 }
        // A popup host has no URL until Chromium navigates it, but it is a page
        // all the same: the command bar would cover a sign-in popup.
        if hasPage || isPopupHost { focusPage() } else { openCommandBar() }
    }

    // MARK: Peek

    /// The dimming panel and the Peek, in their order above the parent's other children.
    var peekWindows: [NSWindow] { [dim, window].compactMap { $0 } }

    /// Grows out of the pointer like a Little Window, over the page area of its window.
    func showAsPeek() {
        guard let window, let parent = peekParent, let pw = parent.window else { return }
        let dim = PeekDimPanel(covering: pw) { [weak self] in self?.closeWindow() }
        self.dim = dim
        pw.addChildWindow(dim, ordered: .above)
        dim.orderFront(nil)
        dim.fadeIn()
        window.setFrame(parent.peekFrame(), display: false)
        pw.addChildWindow(window, ordered: .above)
        show()
    }

    func repositionPeek() {
        guard let window, let parent = peekParent, let pw = parent.window else { return }
        dim?.setFrame(pw.frame, display: true)
        window.setFrame(parent.peekFrame(), display: true)
    }

    private func endPeek() {
        guard isPeek, let dim else { return }
        self.dim = nil
        dim.parent?.removeChildWindow(dim)
        dim.orderOut(nil)
        if let window, let p = window.parent { p.removeChildWindow(window) }
        if !promoted, let pw = peekParent?.window, NSApp.isActive { pw.makeKeyAndOrderFront(nil) }
    }

    // MARK: Command bar (Arc: clicking the pill or ⌘L opens the command bar in the window)

    func openCommandBar() {
        guard let window else { return }
        tooltipTimer?.invalidate(); hideTooltip()
        closePopup()
        let prefill = hasPage ? currentURL : nil
        // Suggestions come from the normal profile even when an incognito window was in front.
        app.useNormalWindow()
        commandBar.highlight = store.focusedSpace.theme.palette.commandHighlight
        commandBar.focusedSpaceID = store.focusedSpaceID
        commandBar.open(mode: hasPage ? .editURL : .newTab, prefill: prefill)
        commandBar.attached = false
        commandBar.panelWidth = min(LittleMetrics.commandBarWidth, window.frame.width - 40)
        positionCommandPanel()
        if commandPanel.parent == nil { window.addChildWindow(commandPanel, ordered: .above) }
        commandBarOpenedAt = Date()
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

    /// Arc puts the bar's top a third of the way down the window.
    private func positionCommandPanel() {
        guard let window else { return }
        let h = CommandBarView.height(forRows: commandBar.result.items.count)
        let w = commandBar.panelWidth
        let wf = window.frame
        commandPanel.setFrame(NSRect(x: wf.midX - w / 2, y: wf.maxY - wf.height / 3 - h, width: w, height: h), display: true)
    }

    private func hideCommandPanel() {
        if commandPanel.parent != nil { window?.removeChildWindow(commandPanel) }
        let panel = commandPanel!
        let bar = commandBar
        // Not tied to self: the window may be closing (promotion), and the panel must still go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            if !bar.isOpen { panel.orderOut(nil) }
        }
        guard window?.isVisible == true else { return }
        window?.makeKeyAndOrderFront(nil)
        focusPage()
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode, forceNewTab: Bool) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            navigate(url)
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : store.settings.searchEngine.searchURL(typed))
            return
        }
        switch s.kind {
        case .switchToTab(let id):
            store.recordQuerySelection(query: query, url: s.url ?? "")
            app.useNormalWindow()
            store.selectTab(id)
            app.main.showWindow(nil)
        case .archived(let id):
            app.useNormalWindow()
            store.restoreArchived(id)
            app.main.showWindow(nil)
        case .navigate:
            open(typed == query ? (s.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed))
        case .search:
            open(s.url ?? store.settings.searchEngine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            store.focusSpace(id)
        case .moveToSpace(let id):
            promote(to: id)
        case .moveToFolder:
            break
        }
    }

    private func navigate(_ url: String) {
        state.url = url
        browser?.loadURL(url)
        focusPage()
    }

    // MARK: Tooltips (Arc: navy pill under the control after a short hover, key caps for shortcuts)

    private func scheduleTooltip(for h: LittleHover) {
        tooltipTimer?.invalidate()
        hideTooltip()
        let spec: (String, [String])? = switch h {
        case .puzzle: ("Extensions", [])
        case .link: ("Copy URL", ["⇧", "⌘", "C"])
        case .chevron: ("More Spaces", [])
        default: nil
        }
        guard let spec else { return }
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showTooltip(spec.0, caps: spec.1, for: h) }
        }
    }

    private func showTooltip(_ text: String, caps: [String], for h: LittleHover) {
        guard let window, state.hover == h, popup == nil, !commandBar.isOpen else { return }
        let panel = LittleTooltipPanel()
        let tip = LittleTooltipView(text: text, caps: caps)
        let size = tip.frame.size
        panel.contentView = tip
        let w = window.frame.width
        // Centred under the control; the chevron tip hugs the right edge like Arc's.
        let cx: CGFloat = switch h {
        case .puzzle: w - LittleMetrics.rightMargin - state.openButtonWidth - LittleMetrics.pillGap - 46
        case .link: w - LittleMetrics.rightMargin - state.openButtonWidth - LittleMetrics.pillGap - 15
        default: w - LittleMetrics.rightMargin - LittleMetrics.chevronWidth / 2
        }
        var x = window.frame.minX + cx - size.width / 2
        x = min(x, window.frame.maxX - size.width - 4)
        let y = window.frame.maxY - LittleMetrics.barHeight - size.height + 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        tooltip = panel
    }

    private func hideTooltip() {
        guard let t = tooltip else { return }
        tooltip = nil
        window?.removeChildWindow(t)
        t.orderOut(nil)
    }

    // MARK: Spaces popup (Arc: LittleBrowserMoveMenu)

    func togglePopup() {
        if popup != nil { closePopup() } else { openPopup() }
    }

    private func openPopup() {
        guard let window, popup == nil else { return }
        tooltipTimer?.invalidate(); hideTooltip()
        commandBar.close()
        let panel = LittlePopupPanel()
        panel.contentView = LittleSpacesPopup(state: state, store: store,
                                              onPick: { [weak self] sid in self?.closePopup(); self?.promote(to: sid) },
                                              onClose: { [weak self] in self?.closePopup() })
        panel.delegate = self
        let rows = min(store.spaceOrder.count, 6)
        let h = LittleMetrics.popupHeaderHeight + CGFloat(rows) * LittleMetrics.popupRowHeight
        let wf = window.frame
        panel.setFrame(NSRect(x: wf.maxX - 8 - LittleMetrics.popupWidth, y: wf.maxY - h, width: LittleMetrics.popupWidth, height: h), display: true)
        window.addChildWindow(panel, ordered: .above)
        popup = panel
        state.popupOpen = true
        panel.makeKeyAndOrderFront(nil)
    }

    func closePopup() {
        guard let panel = popup else { return }
        popup = nil
        state.popupOpen = false
        window?.removeChildWindow(panel)
        panel.orderOut(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Promote / close

    /// Move the page into a space (nil = the window's target space) as a Today
    /// tab. The live browser goes with it, so history, scroll position and
    /// logins stay.
    func promote(to spaceID: UUID?) {
        guard let b = browser, hasPage else { return }
        closePopup()
        commandBar.close()
        app.useNormalWindow()
        let sid = (spaceID ?? state.targetSpaceID).flatMap { store.space($0) != nil && !store.isIncognito(space: $0) ? $0 : nil }
            ?? store.focusedSpaceID
        let tab = store.createTab(url: b.currentURL, title: b.currentTitle, in: sid, select: true)
        if let favicon, let key = FaviconCache.key(for: b.currentURL) { app.favicons.store(favicon, forKey: key) }
        promoted = true
        browser = nil
        app.main.browsers.adopt(b, for: tab.id)
        window?.close()
        app.main.showWindow(nil)
        app.main.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Archive the page to the Library (Arc keeps closed Little Arcs there too).
    func archivePage() {
        // A Peek is a look at a link, not a page to keep.
        guard hasPage, !promoted, !isPeek else { return }
        store.archiveLittleWindowPage(url: currentURL, title: browser?.currentTitle ?? state.title)
        if let favicon, let key = FaviconCache.key(for: currentURL) { app.favicons.store(favicon, forKey: key) }
        promoted = true  // archived once; a later close must not archive again
    }

    /// Menu / key actions while this window is key. Returns false for actions
    /// that are not the little window's (the app handles those).
    func handle(action id: String) -> Bool {
        switch id {
        case "closeTab", "closeWindow": closeWindow()
        case "newTab", "editURL": openCommandBar()
        case "goBack": browser?.goBack()
        case "goForward": browser?.goForward()
        case "reload": browser?.reload()
        case "hardReload": browser?.reloadIgnoringCache()
        case "clearCache": browser?.clearSiteDataAndReload(cookies: false)
        case "clearCookies": browser?.clearSiteDataAndReload(cookies: true)
        case "stop": browser?.stopLoading()
        case "zoomIn": if let b = browser { b.setZoomLevel(b.zoomLevel() + 0.5) }
        case "zoomOut": if let b = browser { b.setZoomLevel(b.zoomLevel() - 0.5) }
        case "resetZoom": browser?.setZoomLevel(0)
        case "copyURL": copy(currentURL)
        case "copyURLMarkdown": copy("[\(browser?.currentTitle ?? state.title)](\(currentURL))")
        case "viewSource": browser?.viewSource()
        case "devTools", "jsConsole", "inspectElement": browser?.showDevTools()
        case "print": browser?.print()
        case "promoteLittleWindow": promote(to: nil)
        // No find bar or capture in little windows; keep them off the main window.
        case "find", "findNext", "findPrevious", "capturePage", "toggleSidebar", "pinTab", "favoriteTab", "renameTab",
             "duplicateTab", "resetTab", "muteTab", "clearToday", "nextTab", "previousTab", "recentTab", "recentTabBackward":
            break
        default: return false
        }
        return true
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// ⌘W / Close Window: the same path as the close button. (performClose is
    /// skipped: it refuses to act while the standard buttons are dimmed.)
    func closeWindow() {
        guard let window, window.isVisible, windowShouldClose(window) else { return }
        window.close()
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        tooltipTimer?.invalidate(); hideTooltip()
        closePopup()
        commandBar.close()
        archivePage()
        if let b = browser {
            b.containerView.isHidden = true
            if let w = b.hostWindow, w.parent === sender { sender.removeChildWindow(w); w.orderOut(nil) }
            b.close()  // -browserDidClose: drops the controller
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        endPeek()
        if browser == nil { app.removeLittleWindow(self) }
    }

    /// Left with the green button or ⌃⌘F while a video was fullscreen: the page leaves too.
    func windowDidExitFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window, pageFullscreen else { return }
        pageFullscreen = false
        browser?.exitFullscreen()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, (notification.object as? NSWindow) === window, !window.styleMask.contains(.fullScreen) else { return }
        if commandBar.isOpen { positionCommandPanel() }
        if popup != nil { closePopup() }
    }

    /// Only a drag by the user sets the remembered size, not placement clamping
    /// or the open animation.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window, (notification.object as? NSWindow) === window, !window.styleMask.contains(.fullScreen) else { return }
        store.prefs.littleWindowSize = NSStringFromSize(window.frame.size)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        browser?.probeBackgroundColor()
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        if commandBar.isOpen { positionCommandPanel() }
        if popup != nil { closePopup() }
    }

    func windowDidResignKey(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === popup {
            DispatchQueue.main.async { [weak self] in
                guard let self, let p = self.popup, !p.isKeyWindow else { return }
                self.closePopup()
            }
            return
        }
        guard w === commandPanel, commandBar.isOpen else { return }
        if Date().timeIntervalSince(commandBarOpenedAt) < 0.6 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandPanel.makeKeyAndOrderFront(nil)
            }
            return
        }
        commandBar.close()
    }

    // MARK: CraBrowserDelegate

    func browser(_ browser: CraBrowser, didChangeTitle title: String) {
        state.title = title
        window?.title = title.isEmpty ? "Little Window" : title
    }

    func browser(_ browser: CraBrowser, didChangeURL url: String) {
        if url.hasPrefix("data:text/html;base64,") { return }
        state.url = url == "about:blank" ? "" : url
    }

    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        state.isLoading = loading
        state.canGoBack = canGoBack
        state.canGoForward = canGoForward
        if !loading { state.progress = 0 }
    }

    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) { state.progress = progress }

    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {
        store.recordVisit(url: url, title: title)
    }

    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {
        favicon = image
        if let key = FaviconCache.key(for: browser.currentURL) { app.favicons.store(image, forKey: key) }
    }

    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) { state.themeColor = hex }
    /// The page window trails the shell during a fast resize; the gap shows the page's colour.
    func browser(_ browser: CraBrowser, didReportBackgroundColor hex: String) {
        shell.page.layer?.backgroundColor = NSColor(Color(hex: hex)).cgColor
    }
    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {}

    // Little windows never dock DevTools (CEF opens its own window for them).
    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {}
    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {}
    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {
        guard let window else { return }
        pageFullscreen = fullscreen
        if fullscreen != window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    /// Links that want a new tab open another little window (Arc does the same).
    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        if url.lowercased().hasPrefix("cra:") { return }
        app.openLittleWindow(url: url, activate: !background)
        if background { window?.makeKeyAndOrderFront(nil) }
    }

    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? {
        if url.lowercased().hasPrefix("cra:") { return nil }
        let w = app.makeLittleWindow(url: nil)
        w.state.url = url
        w.show()
        if background { window?.makeKeyAndOrderFront(nil) }
        return w.browser
    }

    func devToolsHostView(for browser: CraBrowser) -> NSView? { nil }
    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {}
    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) {
        attachHostWindow(window)
        if hasPage || isPopupHost, self.window?.isKeyWindow == true || window.isKeyWindow { focusPage() }
    }
    func browserDidCloseDevTools(_ browser: CraBrowser) {}
    func browser(_ browser: CraBrowser, handleKeyEvent event: NSEvent) -> Bool {
        // Escape leaves the page's element fullscreen, as in the main window.
        if pageFullscreen, event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            browser.exitFullscreen()
            return true
        }
        return app.handleReservedKey(event)
    }
    func browser(_ browser: CraBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        // Arc's "Exit the current context": Escape the page didn't use closes a Peek.
        if isPeek, event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            closeWindow()
            return true
        }
        return app.handleUnhandledKey(event)
    }
    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) { app.main.browserManager(download: download) }

    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void) {
        if kinds == 8 { completion(false); return }
        var what: [String] = []
        if kinds & 1 != 0 { what.append("camera") }
        if kinds & 2 != 0 { what.append("microphone") }
        if kinds & 4 != 0 { what.append("location") }
        let alert = NSAlert()
        alert.messageText = what.isEmpty ? "\(origin) is asking for a browser permission"
                                         : "\(origin) wants to use your \(what.joined(separator: " and "))"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        guard let window else { completion(false); return }
        alert.beginSheetModal(for: window) { resp in completion(resp == .alertFirstButtonReturn) }
    }

    func browserDidReceiveFocus(_ browser: CraBrowser) {}

    func browserDidClose(_ browser: CraBrowser) {
        browser.containerView.removeFromSuperview()
        guard self.browser === browser else { return }
        self.browser = nil
        if let window, window.isVisible {
            // The page closed itself (window.close()); the window goes with it.
            archivePage()
            window.close()
        }
        app.removeLittleWindow(self)
    }
}

/// The navy strip on top, the page edge to edge below.
final class LittleShellView: NSView {
    private(set) var toolbarHost = NSView()
    let page = NSView()
    /// Reports the page area (window coordinates) so a Chrome-style page window can follow it.
    var onPageFrame: ((NSRect) -> Void)?
    var onHover: ((LittleHover) -> Void)?
    var openButtonWidth: () -> CGFloat = { 160 }
    /// While the window grows open, lay out for this (final) size anchored top-left.
    var frozenSize: NSSize? { didSet { needsLayout = true } }
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = LittlePalette.barNS.cgColor
        addSubview(toolbarHost)
        page.wantsLayer = true
        page.layer?.cornerCurve = .continuous
        page.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        page.layer?.masksToBounds = true
        page.layer?.backgroundColor = NSColor(white: 34 / 255, alpha: 1).cgColor
        page.autoresizesSubviews = true
        addSubview(page)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setToolbar(_ toolbar: LittleToolbarView) {
        toolbar.isOverControl = { [weak self] p in
            guard let self else { return false }
            // p is in the strip's own coordinates (flipped: y from the top).
            return self.hoverTarget(x: p.x, y: p.y) != .none
        }
        toolbarHost.removeFromSuperview()
        toolbarHost = toolbar
        addSubview(toolbar, positioned: .below, relativeTo: page)
        needsLayout = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        // activeAlways: the strip must react while the page window (a child) is key.
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        let inBar = p.y > bounds.height - LittleMetrics.barHeight
        onHover?(inBar ? hoverTarget(x: p.x, y: bounds.height - p.y) : .none)
    }

    /// Mirrors LittleToolbarView's layout (pill from x 83, 10pt gap, button, 7pt margin).
    private func hoverTarget(x: CGFloat, y: CGFloat) -> LittleHover {
        guard y >= 8, y <= 8 + LittleMetrics.controlHeight else { return .none }
        let w = bounds.width
        let buttonLeft = w - LittleMetrics.rightMargin - openButtonWidth()
        let pillRight = buttonLeft - LittleMetrics.pillGap
        if x >= LittleMetrics.pillLeft, x < pillRight {
            if abs(x - (pillRight - 46)) <= 13 { return .puzzle }
            if abs(x - (pillRight - 15)) <= 13 { return .link }
            return .pill
        }
        if x >= buttonLeft, x < w - LittleMetrics.rightMargin {
            return x >= w - LittleMetrics.rightMargin - LittleMetrics.chevronWidth ? .chevron : .open
        }
        return .none
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(.none)
    }

    override func layout() {
        super.layout()
        let size = frozenSize ?? bounds.size
        let b = NSRect(x: 0, y: bounds.height - size.height, width: size.width, height: size.height)
        let fullscreen = window?.styleMask.contains(.fullScreen) ?? false
        let barH = LittleMetrics.barHeight
        toolbarHost.frame = NSRect(x: 0, y: b.maxY - barH, width: b.width, height: barH)
        let inset = fullscreen ? 0 : LittleMetrics.edgeInset
        page.frame = NSRect(x: inset, y: b.minY + inset, width: max(0, b.width - 2 * inset), height: max(0, b.height - barH - inset))
        page.layer?.cornerRadius = pageCornerRadius
        for sub in page.subviews where sub.frame != page.bounds { sub.frame = page.bounds }
        onPageFrame?(convert(page.frame, to: nil))
    }

    /// The page's bottom corners follow the window's, just inside its rim.
    var pageCornerRadius: CGFloat {
        guard let window = window as? LittleWindow, !window.styleMask.contains(.fullScreen) else { return 0 }
        return max(0, window.systemCornerRadius - LittleMetrics.edgeInset)
    }
}

/// Traffic lights at Arc's spots (x 17/39/61, centred on the strip), always in
/// colour like the main window.
final class LittleWindow: NSWindow {
    /// Window buttons stay coloured while inactive (see CraWindow).
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton type: UInt) -> Bool { true }
    /// Arc's open animation: ~120 ms from a small rectangle to the full frame.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { LittleMetrics.openDuration }

    /// macOS's corner radius for this window (16 pt on macOS 26, larger than Arc's
    /// 10), read from the frame view's private `_cornerRadius`.
    var systemCornerRadius: CGFloat { Self.cornerRadius(of: self) }

    static func cornerRadius(of window: NSWindow) -> CGFloat {
        typealias RadiusIMP = @convention(c) (AnyObject, Selector) -> CGFloat
        let sel = NSSelectorFromString("_cornerRadius")
        guard let frameView = window.contentView?.superview, let method = class_getInstanceMethod(type(of: frameView), sel) else { return LittleMetrics.cornerRadius }
        let radius = unsafeBitCast(method_getImplementation(method), to: RadiusIMP.self)(frameView, sel)
        return radius > 0 ? radius : LittleMetrics.cornerRadius
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard !styleMask.contains(.fullScreen) else { return }
        for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = standardWindowButton(type), let sv = b.superview else { continue }
            let target = NSPoint(x: 17 + CGFloat(i) * 22 - b.frame.width / 2, y: sv.bounds.height - LittleMetrics.barHeight / 2 - b.frame.height / 2)
            if abs(b.frame.origin.x - target.x) > 0.5 || abs(b.frame.origin.y - target.y) > 0.5 { b.setFrameOrigin(target) }
        }
    }
}

/// The shade over a browser window while a Peek shows on it; a click on it ends the Peek.
final class PeekDimPanel: NSPanel {
    private final class Shade: NSView {
        var onClick: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func rightMouseDown(with event: NSEvent) { onClick() }
    }

    init(covering parent: NSWindow, onClick: @escaping () -> Void) {
        super.init(contentRect: parent.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let shade = Shade(frame: NSRect(origin: .zero, size: parent.frame.size))
        shade.onClick = onClick
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        shade.layer?.cornerRadius = LittleWindow.cornerRadius(of: parent)
        shade.layer?.cornerCurve = .continuous
        shade.autoresizingMask = [.width, .height]
        contentView = shade
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = LittleMetrics.openDuration
            animator().alphaValue = 1
        }
    }
}

/// Borderless, non-activating tooltip panel (never takes key status).
final class LittleTooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 28),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }
}

/// Arc's hover tip: 28pt navy pill, 14pt semibold text, 20pt key caps.
final class LittleTooltipView: NSView {
    init(text: String, caps: [String]) {
        super.init(frame: .zero)
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let textW = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let capsW = caps.isEmpty ? 0 : 2 + CGFloat(caps.count) * 20 + CGFloat(caps.count - 1) * 4
        let pillW = 10 + textW + (caps.isEmpty ? 0 : 6 + capsW) + (caps.isEmpty ? 10 : 6)
        // .padding(2) around the 28 pt pill.
        setFrameSize(NSSize(width: pillW + 4, height: 32))
        let pill = NSView(frame: NSRect(x: 2, y: 2, width: pillW, height: 28))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(LittlePalette.tooltip).cgColor
        pill.layer?.cornerRadius = 10
        pill.layer?.cornerCurve = .continuous
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor(LittlePalette.tooltipBorder).cgColor
        addSubview(pill)
        let label = NSTextField.sidebarLabel(size: 14, weight: .semibold)
        label.stringValue = text
        label.textColor = NSColor(LittlePalette.tooltipText)
        label.frame = NSRect(x: 10 - SidebarText.inset, y: (28 - 17) / 2, width: textW + 2 * SidebarText.inset, height: 17)
        pill.addSubview(label)
        var x = 10 + textW + 6 + 2
        for c in caps {
            let cap = NSView(frame: NSRect(x: x, y: 4, width: 20, height: 20))
            cap.wantsLayer = true
            cap.layer?.backgroundColor = NSColor(LittlePalette.tooltipCap).cgColor
            cap.layer?.cornerRadius = 5
            cap.layer?.cornerCurve = .continuous
            let glyph = NSTextField.sidebarLabel(size: 12, weight: .semibold)
            glyph.stringValue = c
            glyph.textColor = NSColor(LittlePalette.tooltipCapGlyph)
            glyph.alignment = .center
            glyph.frame = NSRect(x: -SidebarText.inset, y: (20 - 15) / 2, width: 20 + 2 * SidebarText.inset, height: 15)
            cap.addSubview(glyph)
            pill.addSubview(cap)
            x += 24
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Borderless child panel for the spaces menu; takes the keyboard for filtering.
final class LittlePopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: LittleMetrics.popupWidth, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }
}

// MARK: - Strip

/// The strip's controls, drawn by AppKit: the address pill (search glyph, centred URL, the
/// extensions and copy-link icons) and the "Open in <Space> ⌘O | ⌄" button. Hover comes from
/// the shell's tracking (`state.hover`); clicks land here. They work on the first click even
/// when the page window holds key status, and only the empty parts of the strip drag the
/// window (a press on the pill or the button must not start a window-move session).
@MainActor
final class LittleToolbarView: NSView {
    private let state: LittleWindowState
    private let actions: LittleWindowActions
    private let store: SidebarStore
    private let pill = NSView()
    private let search = NSImageView()
    private let urlLabel = NSTextField.sidebarLabel(size: 13)
    private let puzzle = LittleIconView(symbol: "puzzlepiece.extension", size: 15)
    private let link = LittleIconView(symbol: "link", size: 14)
    private let openButton = NSView()
    private let openPart = NSView()
    private let openLabel = NSTextField.sidebarLabel(size: 13, weight: .medium)
    private let badge = NSView()
    private let badgeLabel = NSTextField.sidebarLabel(size: 11, weight: .medium)
    private let divider = NSView()
    private let chevronPart = NSView()
    private let chevron = NSImageView()
    /// Asked by the shell: does a press here hit a control (else it moves the window)?
    var isOverControl: ((NSPoint) -> Bool)?

    init(state: LittleWindowState, actions: LittleWindowActions, store: SidebarStore) {
        self.state = state
        self.actions = actions
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LittlePalette.barNS.cgColor
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.layer?.cornerCurve = .continuous
        addSubview(pill)
        search.image = SidebarSymbols.image("magnifyingglass", size: 13, weight: .medium)
        search.contentTintColor = NSColor(LittlePalette.icon)
        search.imageScaling = .scaleNone
        pill.addSubview(search)
        urlLabel.textColor = NSColor(LittlePalette.text)
        urlLabel.alignment = .center
        pill.addSubview(urlLabel)
        pill.addSubview(puzzle)
        pill.addSubview(link)
        openButton.wantsLayer = true
        openButton.layer?.backgroundColor = LittlePalette.buttonNS.cgColor
        openButton.layer?.cornerRadius = 7
        openButton.layer?.cornerCurve = .continuous
        openButton.layer?.masksToBounds = true
        openButton.layer?.borderWidth = 1
        openButton.layer?.borderColor = NSColor(LittlePalette.buttonBorder).cgColor
        addSubview(openButton)
        openPart.wantsLayer = true
        openButton.addSubview(openPart)
        openPart.addSubview(openLabel)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = NSColor(LittlePalette.badge).cgColor
        badgeLabel.stringValue = "⌘O"
        badgeLabel.textColor = NSColor(LittlePalette.badgeText)
        badge.addSubview(badgeLabel)
        openPart.addSubview(badge)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(LittlePalette.buttonBorder).cgColor
        openButton.addSubview(divider)
        chevronPart.wantsLayer = true
        chevron.imageScaling = .scaleNone
        chevron.contentTintColor = NSColor(LittlePalette.label)
        chevronPart.addSubview(chevron)
        openButton.addSubview(chevronPart)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        let (url, hover, popupOpen, space) = withObservationTracking {
            (state.url, state.hover, state.popupOpen, store.space(state.targetSpaceID) ?? store.focusedSpace)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        urlLabel.stringValue = url.isEmpty ? "" : SuggestionEngine.humanURL(url)
        pill.toolTip = url
        pill.layer?.backgroundColor = NSColor(hover == .pill ? LittlePalette.pillHover : LittlePalette.pill).cgColor
        puzzle.hovered = hover == .puzzle
        link.hovered = hover == .link
        let text = NSMutableAttributedString(string: "Open in ", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                                             .foregroundColor: NSColor(LittlePalette.label)])
        text.append(NSAttributedString(string: space.title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold),
                                                                         .foregroundColor: NSColor(LittlePalette.spaceName(space.theme))]))
        openLabel.attributedStringValue = text
        openButton.toolTip = "Open this page in \(space.title) as a tab (⌘O)"
        openPart.layer?.backgroundColor = hover == .open ? NSColor(LittlePalette.buttonHover).cgColor : nil
        chevronPart.layer?.backgroundColor = hover == .chevron ? NSColor(LittlePalette.buttonHover).cgColor : nil
        chevron.image = SidebarSymbols.image(popupOpen ? "chevron.up" : "chevron.down", size: 10, weight: .bold)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, ch = LittleMetrics.controlHeight, y: CGFloat = 8
        // Open button: 10 + "Open in <space>" + 6 + ⌘O (5 + text + 5) + 8 | 1 | 29.
        let tw = ceil(openLabel.attributedStringValue.size().width)
        let bw = ceil(badgeLabel.attributedStringValue.size().width) + 10
        let partW = 10 + tw + 6 + bw + 8
        let openW = partW + 1 + LittleMetrics.chevronWidth
        if state.openButtonWidth != openW { state.openButtonWidth = openW }
        openButton.frame = NSRect(x: w - LittleMetrics.rightMargin - openW, y: y, width: openW, height: ch)
        openPart.frame = NSRect(x: 0, y: 0, width: partW, height: ch)
        openLabel.frame = NSRect(x: 10 - SidebarText.inset, y: (ch - 16) / 2, width: tw + 2 * SidebarText.inset, height: 16)
        badge.frame = NSRect(x: 10 + tw + 6, y: (ch - 16) / 2, width: bw, height: 16)
        badgeLabel.frame = NSRect(x: 5 - SidebarText.inset, y: (16 - 14) / 2, width: bw - 10 + 2 * SidebarText.inset, height: 14)
        divider.frame = NSRect(x: partW, y: 0, width: 1, height: ch)
        chevronPart.frame = NSRect(x: partW + 1, y: 0, width: LittleMetrics.chevronWidth, height: ch)
        chevron.frame = chevronPart.bounds
        // The pill fills the rest from x 83.
        let pillW = max(0, openButton.frame.minX - LittleMetrics.pillGap - LittleMetrics.pillLeft)
        pill.frame = NSRect(x: LittleMetrics.pillLeft, y: y, width: pillW, height: ch)
        search.frame = NSRect(x: 0, y: 0, width: 34, height: ch)
        // The URL is centred over the whole pill, 80 pt clear of each end.
        urlLabel.frame = NSRect(x: 80 - SidebarText.inset, y: (ch - 16) / 2, width: max(0, pillW - 160) + 2 * SidebarText.inset, height: 16)
        link.frame = NSRect(x: pillW - 2 - 26, y: 2, width: 26, height: 26)
        puzzle.frame = NSRect(x: pillW - 2 - 26 - 5 - 26, y: 2, width: 26, height: 26)
    }

    // MARK: Clicks

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool {
        guard let window, let isOverControl else { return true }
        return !isOverControl(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// Presses on the empty strip move the window before they get here (mouseDownCanMoveWindow).
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if openButton.frame.contains(p) {
            if chevronPart.frame.contains(openButton.convert(p, from: self)) { actions.togglePopup() }
            else if !state.url.isEmpty { actions.promote(nil) }
        } else if pill.frame.contains(p) {
            let q = pill.convert(p, from: self)
            if link.frame.contains(q) { actions.copyURL() }
            else if !puzzle.frame.contains(q) { actions.openCommandBar() }
        }
    }
}

/// Icon in the pill: 26pt hover square, brighter glyph.
private final class LittleIconView: NSView {
    private let glyph = NSImageView()
    var hovered = false {
        didSet {
            glyph.contentTintColor = NSColor(hovered ? LittlePalette.iconHot : LittlePalette.icon)
            layer?.backgroundColor = hovered ? NSColor(LittlePalette.iconHover).cgColor : nil
        }
    }

    init(symbol: String, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        glyph.image = SidebarSymbols.image(symbol, size: size)
        glyph.imageScaling = .scaleNone
        glyph.contentTintColor = NSColor(LittlePalette.icon)
        glyph.frame = bounds
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Arc's LittleBrowserMoveMenu: "Search Spaces…" with a chevron-up button, then
/// one 54pt row per space (40pt tile with the emoji on the space colour).
@MainActor
final class LittleSpacesPopup: NSView, NSTextFieldDelegate {
    private let state: LittleWindowState
    private let store: SidebarStore
    private let onPick: (UUID) -> Void
    private let onClose: () -> Void
    private let field = NSTextField()
    private let close = NSView()
    private var rows: [NSView] = []
    private var list: [Space] = []
    private var selected = 0 { didSet { refreshSelection() } }

    init(state: LittleWindowState, store: SidebarStore, onPick: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.onPick = onPick
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LittlePalette.buttonNS.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(LittlePalette.buttonBorder).cgColor
        let h = LittleMetrics.popupHeaderHeight
        let glass = NSImageView(frame: NSRect(x: 14, y: 0, width: 16, height: h))
        glass.image = SidebarSymbols.image("magnifyingglass", size: 13, weight: .medium)
        glass.contentTintColor = NSColor(LittlePalette.icon)
        glass.imageScaling = .scaleNone
        addSubview(glass)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = NSColor.white.withAlphaComponent(0.9)
        field.placeholderString = "Search Spaces…"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        close.wantsLayer = true
        close.layer?.cornerRadius = 6
        close.layer?.cornerCurve = .continuous
        close.layer?.backgroundColor = NSColor(LittlePalette.popupButton).cgColor
        let up = NSImageView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        up.image = SidebarSymbols.image("chevron.up", size: 11, weight: .bold)
        up.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        up.imageScaling = .scaleNone
        close.addSubview(up)
        addSubview(close)
        // Set in init, so didSet doesn't run: highlight by hand.
        selected = max(0, store.orderedSpaces.firstIndex { $0.id == state.targetSpaceID } ?? 0)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(field)
    }

    private func rebuild() {
        let q = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        list = q.isEmpty ? store.orderedSpaces : store.orderedSpaces.filter { $0.title.lowercased().contains(q) }
        rows.forEach { $0.removeFromSuperview() }
        rows = list.prefix(6).map { s in
            let row = FlippedView()
            row.wantsLayer = true
            let tile = NSView(frame: NSRect(x: 14, y: (LittleMetrics.popupRowHeight - 40) / 2, width: 40, height: 40))
            tile.wantsLayer = true
            tile.layer?.cornerRadius = 9
            tile.layer?.cornerCurve = .continuous
            tile.layer?.backgroundColor = NSColor(hex: s.theme.accent ?? s.theme.colors.first ?? "#888888").cgColor
            let emoji = NSTextField.sidebarLabel(size: 20)
            emoji.stringValue = s.emoji
            emoji.alignment = .center
            emoji.frame = NSRect(x: -SidebarText.inset, y: (40 - 25) / 2, width: 40 + 2 * SidebarText.inset, height: 25)
            tile.addSubview(emoji)
            row.addSubview(tile)
            let title = NSTextField.sidebarLabel(size: 15, weight: .semibold)
            title.stringValue = s.title
            title.textColor = NSColor.white.withAlphaComponent(0.88)
            title.frame = NSRect(x: 14 + 40 + 12 - SidebarText.inset, y: (LittleMetrics.popupRowHeight - 18) / 2,
                                 width: LittleMetrics.popupWidth - 66 - 14 + 2 * SidebarText.inset, height: 18)
            row.addSubview(title)
            addSubview(row)
            return row
        }
        needsLayout = true
        refreshSelection()
    }

    private func refreshSelection() {
        for (i, r) in rows.enumerated() {
            r.layer?.backgroundColor = i == selected ? NSColor(LittlePalette.buttonHover).cgColor : nil
        }
    }

    override func layout() {
        super.layout()
        let h = LittleMetrics.popupHeaderHeight, w = bounds.width
        close.frame = NSRect(x: w - 9 - 28, y: (h - 28) / 2, width: 28, height: 28)
        let fx: CGFloat = 14 + 16 + 10
        let fh = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: fx - SidebarText.inset, y: (h - fh) / 2, width: close.frame.minX - 10 - fx + 2 * SidebarText.inset, height: fh)
        for (i, r) in rows.enumerated() {
            r.frame = NSRect(x: 0, y: h + CGFloat(i) * LittleMetrics.popupRowHeight, width: w, height: LittleMetrics.popupRowHeight)
        }
    }

    // MARK: Keys and pointer

    func controlTextDidChange(_ obj: Notification) {
        rebuild()
        selected = 0
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if list.indices.contains(selected) { onPick(list[selected].id) }
        case #selector(NSResponder.cancelOperation(_:)):
            onClose()
        case #selector(NSResponder.moveDown(_:)):
            if !list.isEmpty { selected = (selected + 1) % list.count }
        case #selector(NSResponder.moveUp(_:)):
            if !list.isEmpty { selected = (selected - 1 + list.count) % list.count }
        default:
            return false
        }
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = rows.firstIndex(where: { $0.frame.contains(p) }), i != selected { selected = i }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if close.frame.contains(p) { onClose(); return }
        if let i = rows.firstIndex(where: { $0.frame.contains(p) }), list.indices.contains(i) { onPick(list[i].id) }
    }
}
