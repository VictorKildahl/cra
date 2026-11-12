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
/// 2026 (docs/arc-reverse-engineering.md, "Little Arc"): a 46pt strip with
/// muted traffic lights, one full-width search pill, and a split
/// "Open in <Space> ⌘O | ⌄" button; the page fills the rest, inside the window's rim.
/// Arc 1.172.1 (10 Nov 2026) changed the strip's colour, the pill's address and the "Open in"
/// menu's sizes; those come from its captures (#329, #330, #331).
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
    /// The space ⌘O opens into: the focused space of the window in use last, as of when
    /// this window last took focus (Arc's Little Arc, see `refreshTarget`).
    var targetSpaceID: UUID
    /// The profile the page loads in (nil = Default). Arc's LittleBrowser.State.profile: set
    /// when the window opens and kept, whichever space "Open in" names later (#172).
    var profileID: UUID?
    var popupOpen = false
    /// Pointer hover, tracked by AppKit (SwiftUI's onHover sleeps while the
    /// Chrome page window, a child, is the key window).
    var hover: LittleHover = .none
    /// Width of the "Open in" button, reported by LittleToolbarView for hit-testing.
    var openButtonWidth: CGFloat = 160
    /// Width of the profile chip (0 = hidden), reported the same way.
    var profileChipWidth: CGFloat = 0
    /// The button has its ⌄ only while there is another space to pick (Arc 1.172.1, #331).
    var showsChevron = true
    /// The window waits for the page's first response: the address pill keeps its magnifier (#330).
    var awaitsFirstResponse = false

    init(targetSpaceID: UUID) { self.targetSpaceID = targetSpaceID }
}

enum LittleHover { case none, pill, profile, puzzle, link, open, chevron }

/// What the strip needs AppKit to do.
@MainActor
final class LittleWindowActions {
    var openCommandBar: () -> Void = {}
    var copyURL: () -> Void = {}
    var promote: (UUID?) -> Void = { _ in }
    var togglePopup: () -> Void = {}
    var closePopup: () -> Void = {}
    var showProfileMenu: (NSView) -> Void = { _ in }
}

/// Arc's Little Arc chrome, measured at 2x (window 1688×1010, profile "default").
enum LittleMetrics {
    static let barHeight: CGFloat = 46
    static let controlHeight: CGFloat = 30      // pill and button: y 8…38
    static let pillLeft: CGFloat = 83
    static let pillGap: CGFloat = 10            // pill → button
    static let rightMargin: CGFloat = 7
    static let chevronWidth: CGFloat = 29
    /// From the pill's right end to the profile chip's: past the link and puzzle buttons, 5 pt clear.
    static let profileChipTrailing: CGFloat = 64
    /// Arc's window corners; used when the system radius can't be read (see LittleWindow).
    static let cornerRadius: CGFloat = 10
    /// The light rim macOS draws along the window's edge. The page is a child window
    /// above the Little Window, so laid edge to edge it covered the rim on three sides.
    static let edgeInset: CGFloat = 1
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
    /// The strip, left to right: one gradient in every space (the same pixels after switching spaces).
    /// Arc 1.172.1, 10 Nov 2026, window captures at 2x, pixels read along the strip's top edge of a
    /// 1185 pt window: #242438 at the left end, #26243A, #292839 and #2C2439 between, #312339 at the
    /// right. The values wobble by a few units rather than rise, so two stops stay within them; 1.168's
    /// flat #0C091C is gone (#329).
    static let stripLeft = NSColor(srgbRed: 0x24 / 255, green: 0x24 / 255, blue: 0x38 / 255, alpha: 1)
    static let stripRight = NSColor(srgbRed: 0x31 / 255, green: 0x23 / 255, blue: 0x39 / 255, alpha: 1)
    /// The address pill is a lighter wash over the strip (about #38394A on the left, #43394B on the
    /// right, which is white at 9–10 %), so it follows the gradient. The hover is not measured.
    static let pill = Color.white.opacity(0.09)
    static let pillHover = Color.white.opacity(0.14)
    /// The open padlock for an http page (Arc's `hasInsecureContext`): orange on a pale orange wash.
    /// From the capture attached to #330: strokes about #E93700, and a tile that reads #4B3B45 over the
    /// pill's #3A3A4B, which is that orange at about 10 %.
    static let insecure = NSColor(srgbRed: 233 / 255, green: 55 / 255, blue: 0, alpha: 1)
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
    /// The "Open in" menu's magnifier, ∧ and "No results", and its placeholder (Arc 1.172.1, #331).
    static let moveMenuGlyph = Color(red: 80 / 255, green: 81 / 255, blue: 102 / 255)
    static let moveMenuPlaceholder = Color(red: 142 / 255, green: 143 / 255, blue: 157 / 255)
    // Hover tips (measured): navy pill, lavender-white text, pale key caps with blue glyphs.
    static let tooltip = Color(red: 10 / 255, green: 13 / 255, blue: 75 / 255)
    static let tooltipText = Color(red: 222 / 255, green: 223 / 255, blue: 253 / 255)
    static let tooltipBorder = Color(red: 34 / 255, green: 37 / 255, blue: 93 / 255)
    static let tooltipCap = Color(red: 211 / 255, green: 212 / 255, blue: 253 / 255)
    static let tooltipCapGlyph = Color(red: 40 / 255, green: 46 / 255, blue: 252 / 255)
    /// Arc's toast in a Little Arc ("Copied Current URL", 1.171, 3 Nov 2026, sRGB): deeper than the
    /// default dark theme's in a browser window, the same in every space.
    static let toast: ShinyToast.Colors = (NSColor(srgbRed: 41 / 255, green: 18 / 255, blue: 77 / 255, alpha: 1),
                                           NSColor(srgbRed: 33 / 255, green: 16 / 255, blue: 61 / 255, alpha: 1),
                                           NSColor(srgbRed: 33 / 255, green: 14 / 255, blue: 66 / 255, alpha: 1), .white)
    /// ⌥⌘N's card (Arc 1.172.1, 10 Nov 2026, 2x captures attached to #337): the bar #14141C to #17141B
    /// with a #4B4A50 hairline round it, the divider #2C2B32, the ✕ a #28262D tile with a #9C9A9E glyph.
    /// Below a bar that shrank to its rows the window shows dark navy at the top left (about #0D0B1B)
    /// running to plum at the bottom right (about #1C0A20), with grain that isn't drawn here.
    static let cardBar = NSColor(srgbRed: 0x15 / 255, green: 0x14 / 255, blue: 0x1C / 255, alpha: 1)
    static let cardBarBorder = NSColor(srgbRed: 0x4B / 255, green: 0x4A / 255, blue: 0x50 / 255, alpha: 1)
    static let cardDivider = NSColor(srgbRed: 0x2C / 255, green: 0x2B / 255, blue: 0x32 / 255, alpha: 1)
    static let cardClose = NSColor(srgbRed: 0x28 / 255, green: 0x26 / 255, blue: 0x2D / 255, alpha: 1)
    static let cardCloseGlyph = NSColor(srgbRed: 0x9C / 255, green: 0x9A / 255, blue: 0x9E / 255, alpha: 1)
    static let cardTopLeft = NSColor(srgbRed: 0x0D / 255, green: 0x0B / 255, blue: 0x1B / 255, alpha: 1)
    static let cardBottomRight = NSColor(srgbRed: 0x1C / 255, green: 0x0A / 255, blue: 0x20 / 255, alpha: 1)
    /// Behind the strip and around the page, where no gradient is drawn.
    static let barNS = stripLeft
    static let buttonNS = NSColor(red: 5 / 255, green: 6 / 255, blue: 37 / 255, alpha: 1)

    /// The space name in "Open in Victor": the target theme's light foreground
    /// (Arc: semanticColorPalette.dark.foregroundPrimary; Victor → #FCEDBC).
    static func spaceName(_ theme: SpaceTheme) -> Color {
        let theme = theme.shown
        return Color(hex: theme.accent ?? theme.colors.first ?? "#FFFFFF").blendedToward(.white, 0.72)
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
    /// The page's permission cards up (#371); each asks until it is answered or the window closes.
    private var permissionCards: [PermissionPopover] = []
    private var favicon: NSImage?
    private var promoted = false
    /// Hosts a page's window.open (a sign-in popup); its URL arrives after it shows.
    private let isPopupHost: Bool
    /// Arc's Peek: this Little Window sits over a browser window, which a dimming panel
    /// covers; a click on it, Escape or the close button ends the Peek.
    let isPeek: Bool
    private(set) weak var peekParent: MainWindowController?
    /// This Peek to its window's veil (MainWindowController.showPeekVeil).
    private let peekID = UUID()
    /// The tab the Peek came from: links that leave the Peek open as tabs placed from it, and
    /// the Peek waits on it while another tab is on screen (#242).
    let peekSourceTab: UUID?
    /// Another tab is on screen: the Peek is out of sight, its page alive, until its tab is back.
    private(set) var isParked = false
    private var dim: PeekDimPanel?
    /// The click catcher's frame (screen coordinates), for cra://debug?peekCatcher.
    var dimFrame: NSRect? { dim?.frame }
    private var controls: PeekControlsPanel?
    /// The Peek is on its way out (closePeekAnimated).
    private(set) var closingPeek = false
    /// The Peek is shrinking into place; a page window attaching now waits for the end.
    private var openingPeek = false
    /// The pictures moving while the Peek opens or closes.
    private var transition: PeekTransition?
    /// The link the Peek grew out of, which it closes back into (nil: the whole area).
    private var peekSource: PeekSource?
    private var commandPanel: CommandBarPanel!
    private var commandHost: CommandBarView!
    private var commandBarOpenedAt = Date.distantPast
    private var commandObserving = false
    private var popup: LittlePopupPanel?
    private var tooltip: LittleTooltipPanel?
    private var tooltipTimer: Timer?
    private let toast = ShinyToast()
    /// The page's wait for its first response (GitHub #256), whether the toast shows it, and the
    /// check when it falls due.
    private var slowResponse = SlowResponseNotice()
    private var slowResponseShown = false
    private var slowResponseCheck: ScheduledWork?
    /// The space "Open in" names (CraCore LittleWindowTarget): the one a cra://open or a route
    /// named, matching the page's profile, or the one picked in this window's command bar (#316),
    /// else the window used last's.
    private var target: LittleWindowTarget
    /// ⌥⌘N's card (GitHub #337, CraCore LittleCard): an empty Little Window is only its command bar,
    /// 490 × 329 pt at the top right of the screen, with no strip, traffic lights or page. A row that
    /// opens a page turns it into the full window (`expandCard`); anything else that closes the bar
    /// fades it out (`dismissCard`).
    private(set) var isCard = false
    private var cardFading = false
    /// The size the window takes when the card opens a page: the one the user left it at, or the default.
    private let openSize: NSSize
    /// The page's DevTools, docked in the page area as the browser window docks them in a pane
    /// (#348). ⌥⌘I opens and closes them (DevToolsToggle).
    private var devTools = DevToolsToggle()
    /// Chromium's window for the DevTools frontend, while they are open.
    private var devToolsView: NSView?
    /// The frontend is docked, Chrome's default; false once "Undock into separate window" is picked.
    private var devToolsDocked = true
    /// The room the docked frontend left for the page.
    private var devToolsPlaceholder: DevToolsPlaceholder?
    private var devToolsClickMonitor: Any?

    var store: SidebarStore { app.store }
    var currentURL: String { browser?.currentURL ?? state.url }
    var hasPage: Bool { !currentURL.isEmpty && currentURL != "about:blank" }

    /// `url` nil makes a popup host: the browser adopts the next window.open
    /// CEF hands it (see `CraBrowserDelegate.browser:popupHostForURL:`).
    /// `opener` is the page a link or popup came from; `fromTab` the tab a Peek came from.
    /// `space` is the space a cra://open asked for (#168).
    init(app: AppDelegate, url: String?, peekOver parent: MainWindowController? = nil, opener: CraBrowser? = nil, fromTab: UUID? = nil,
         space: UUID? = nil) {
        self.app = app
        isPopupHost = url == nil
        isPeek = parent != nil
        peekParent = parent
        peekSourceTab = parent == nil ? nil : fromTab
        // Little Windows are normal browsing: they target the last normal window's space
        // (a Peek: the space of the window it covers; a cra://open: the space it names).
        target = LittleWindowTarget(requested: parent == nil ? space : nil)
        state = LittleWindowState(targetSpaceID: parent?.focusedSpaceID
            ?? target.space(lastUsed: app.store.focusedSpaceID(window: app.store.lastNormalWindowID)))
        commandBar = CommandBarController(engine: app.engine, store: app.store)
        let size = app.store.prefs.littleWindowSize.map { NSSizeFromString($0) }
            .flatMap { $0 == LittleMetrics.legacyDefaultSize ? nil : $0 }
            .map { NSSize(width: max(LittleMetrics.minSize.width, $0.width), height: max(LittleMetrics.minSize.height, $0.height)) }
            ?? LittleMetrics.defaultSize
        openSize = size
        let window = LittleWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: parent != nil ? [.borderless]
                                      : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
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
        if parent != nil {
            // Arc's Peek is a card: no title bar or traffic lights, 8 pt corners, a shadow.
            shell.isPeek = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            let bar = PeekBarView(state: state)
            bar.onBack = { [weak self] in self?.browser?.goBack() }
            bar.onForward = { [weak self] in self?.browser?.goForward() }
            bar.onReload = { [weak self] in
                guard let b = self?.browser else { return }
                if b.isLoading { b.stopLoading() } else { b.reload() }
            }
            bar.onEditURL = { [weak self] in self?.openCommandBar() }
            bar.onCopy = { [weak self] in self?.copyURL() }
            shell.setPeekBar(bar)
        } else {
            shell.setToolbar(LittleToolbarView(state: state, actions: actions, store: app.store))
        }
        shell.onHover = { [weak self] h in
            guard let self, self.state.hover != h else { return }
            self.state.hover = h
            self.scheduleTooltip(for: h)
        }
        shell.openButtonWidth = { [weak self] in self?.state.openButtonWidth ?? 160 }
        shell.profileChipWidth = { [weak self] in self?.state.profileChipWidth ?? 0 }
        shell.showsChevron = { [weak self] in self?.state.showsChevron ?? true }
        if parent != nil {
            // A Peek is part of its window: no minimizing or zooming it on its own.
            window.isMovableByWindowBackground = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        } else {
            // Little Arc is a non-activating panel (AX subrole AXSystemDialog), so it opens over
            // the app in front even when that app is full screen (#186). An ordinary window can't
            // join another app's full-screen Space: macOS switched to the desktop to show it.
            // Auxiliary only: AppKit puts a full-screen-primary window shown while one of Cra's
            // windows is full screen into a full-screen Space of its own, a black screen with the
            // card in the middle and no traffic lights (#277). The page's own full screen adds
            // primary for as long as it lasts (browser(_:didChangeFullscreen:)).
            window.collectionBehavior = [.fullScreenAuxiliary]
            // ⌥⌘N (and anything else that opens one with nothing in it) shows Arc's card; a popup
            // host has no URL yet but is a page.
            if let url, url.isEmpty || url == "about:blank" { enterCard() } else { placeWindow() }
        }

        actions.openCommandBar = { [weak self] in self?.openCommandBar() }
        actions.copyURL = { [weak self] in self?.copyURL() }
        actions.promote = { [weak self] sid in self?.promote(to: sid) }
        actions.togglePopup = { [weak self] in self?.togglePopup() }
        actions.closePopup = { [weak self] in self?.closePopup() }
        actions.showProfileMenu = { [weak self] v in self?.showProfileMenu(from: v) }

        commandPanel = CommandBarPanel()
        commandHost = CommandBarView(controller: commandBar, favicons: app.favicons)
        commandPanel.contentView = commandHost
        commandPanel.delegate = self
        commandBar.onCommit = { [weak self] s, typed, mode in self?.handleCommit(s, typed: typed, mode: mode) }
        commandBar.onClose = { [weak self] in self?.hideCommandPanel() }
        commandBar.spaceName = { [weak self] id in self?.store.space(id)?.title ?? "" }
        commandBar.onNoticeSettings = { [weak self] in self?.app.showSettingsWindow(on: .profiles) }
        commandBar.onNoticeLearnMore = { [weak self] in self?.app.openInNormalWindow(MainWindowController.privacyPage) }

        // The page's sign-ins (#172). Arc's Little Arc takes the profile of the space it opens into
        // and keeps it; a Peek uses its tab's, so a shared favorite peeks in its list's profile. A
        // link from a Little Window stays in its page's profile, and a popup has to: Chromium
        // hosts a popup in its opener's profile. nil is the Default profile.
        if let opener {
            state.profileID = app.store.profileID(path: opener.profilePath)
        } else if let fromTab, app.store.item(fromTab) != nil {
            state.profileID = app.store.profileID(item: fromTab)
        } else {
            let sid = state.targetSpaceID
            state.profileID = app.store.isIncognito(space: sid) ? nil : app.store.profile(app.store.space(sid)?.profileID)?.id
        }
        // Chromium, or WebKit for a DRM service; a popup host takes its opener's engine.
        let b = PageEngines.makeBrowser(frame: shell.page.bounds, url: url.map { $0.isEmpty ? "about:blank" : $0 }, delegate: self,
                                        incognito: false, profilePath: app.store.profilePath(profile: state.profileID), opener: opener)
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
        w.contentView?.isHidden = false   // a background tab's page (MainWindowController hides it)
        // CEF hands the page window over at its own small frame: shown during a Peek's open it
        // flashed as a black block in the corner.
        // A Peek waiting on its tab shows it when it is back (unparkPeek).
        if openingPeek || isParked || isCard { w.contentView?.isHidden = true }
        w.ignoresMouseEvents = isParked || isCard
        window.addChildWindow(w, ordered: .above)
        ChromiumChildFocus.attach(w)
        layoutPageWindows()
        w.orderFront(nil)
        rejoinPage()
        // The command bar and the spaces popup stay above the page window.
        if commandPanel.parent === window { window.removeChildWindow(commandPanel); window.addChildWindow(commandPanel, ordered: .above) }
    }

    /// Chromium's windows hung on this one: the page's and, docked, its DevTools' under it. They
    /// hide, fade and let clicks through together.
    private var pageWindows: [NSWindow] {
        guard let window else { return [] }
        return [devToolsView?.window, browser?.hostWindow].compactMap { $0 }.filter { $0.parent === window }
    }

    private func layoutPageWindows() { positionHostWindow(shell.convert(shell.page.frame, to: nil)) }

    /// Lays Chromium's windows over the page area (`rectInWindow`): the page's own over all of it,
    /// or, with DevTools docked, their window over it and the page where their frontend left room.
    private func positionHostWindow(_ rectInWindow: NSRect) {
        guard let window, !rectInWindow.isEmpty else { return }
        let area = window.convertToScreen(rectInWindow)
        var page = area
        if let view = devToolsView, let dev = view.window, dev.parent === window {
            place(dev, at: area, corners: .bottom)
            if let cv = dev.contentView, view.frame != cv.bounds { view.frame = cv.bounds }
            if let hole = devToolsPlaceholder { page = hole.pageRect(in: area) }
        }
        guard let w = browser?.hostWindow, w.parent === window else { return }
        // The window's bottom corners are the page's only where it reaches them: beside DevTools
        // its edge is straight.
        place(w, at: page, corners: AreaCorners.shared(by: page, with: area).intersection(.bottom))
    }

    private func place(_ w: NSWindow, at onScreen: NSRect, corners: AreaCorners) {
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
        guard let cv = w.contentView else { return }
        cv.wantsLayer = true
        guard let layer = cv.layer else { return }
        if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
        if !layer.masksToBounds { layer.masksToBounds = true }
        if layer.cornerRadius != shell.pageCornerRadius { layer.cornerRadius = shell.pageCornerRadius }
        // Chromium's content view is flipped, so its layer's MaxY edge is the bottom.
        var mask: CACornerMask = []
        if corners.contains(.bottomLeft) { mask.insert(cv.isFlipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner) }
        if corners.contains(.bottomRight) { mask.insert(cv.isFlipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner) }
        if layer.maskedCorners != mask { layer.maskedCorners = mask }
    }

    func focusPage() {
        guard let b = browser else { return }
        if let w = b.hostWindow, w.parent === window { w.makeKey() }
        b.setFocused(true)
    }

    /// Shows the window without making it key (a link opened in the background).
    func orderFrontInBackground() {
        window?.orderFront(nil)
        rejoinPage()
    }

    /// The page window is an ordinary window, which can't join another app's full-screen
    /// Space: shown before this window, or by Chromium before it hands it over, it lands on the
    /// desktop, and making it key switched Spaces (#186). Ordered in again as this window's
    /// child, it joins this window's Space.
    private func rejoinPage() {
        guard let window, window.isVisible, window.isOnActiveSpace else { return }
        // DevTools first, so the page's window ends above them.
        let away = pageWindows.filter { !$0.isOnActiveSpace }
        guard !away.isEmpty else { return }
        for w in away {
            window.removeChildWindow(w)
            w.orderOut(nil)
            window.addChildWindow(w, ordered: .above)
            w.orderFront(nil)
        }
        // Only DevTools were away: the page's window goes back over them, without leaving the
        // screen (ordered out and back, Chromium scrolls the page to the top).
        if let host = browser?.hostWindow, host.parent === window, !away.contains(where: { $0 === host }) {
            window.removeChildWindow(host)
            window.addChildWindow(host, ordered: .above)
        }
        if commandPanel.parent === window { window.removeChildWindow(commandPanel); window.addChildWindow(commandPanel, ordered: .above) }
    }

    /// Where the window lands: centred on the screen under the pointer, cascaded
    /// off other little windows.
    private func placeWindow() {
        guard let window else { return }
        let vf = placementScreen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, vf.width - 40)
        frame.size.height = min(frame.height, vf.height - 40)
        let n = CGFloat(app.littleWindows.count)
        frame.origin = NSPoint(x: vf.midX - frame.width / 2 + n * 24, y: vf.midY - frame.height / 2 - n * 24)
        frame.origin.x = min(max(vf.minX, frame.origin.x), vf.maxX - frame.width)
        frame.origin.y = min(max(vf.minY, frame.origin.y), vf.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    /// The screen a new Little Window opens on: the one under the pointer.
    private var placementScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return TestScreen.screen ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: ⌥⌘N's card (#337)

    private func enterCard() {
        guard let window else { return }
        isCard = true
        shell.isCard = true
        shell.hidesBar = true
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(type)?.isHidden = true }
        // Arc's card isn't resized; its edges would offer it.
        window.styleMask.remove(.resizable)
        window.minSize = LittleCard.size
        window.setFrame(LittleCard.frame(in: placementScreen.visibleFrame), display: false)
    }

    /// A row opened a page: the same window takes its full size at once (Arc: in one frame, no
    /// animation), its top-right corner where the card's was, with the strip, the traffic lights and
    /// the page.
    private func expandCard() {
        guard isCard, let window else { return }
        isCard = false
        commandHost.card = nil
        commandPanel.appearance = nil
        shell.isCard = false
        shell.hidesBar = false
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(type)?.isHidden = false }
        window.styleMask.insert(.resizable)
        window.minSize = LittleMetrics.minSize
        let screen = window.screen ?? placementScreen
        window.setFrame(LittleCard.expanded(from: window.frame, to: openSize, in: screen.visibleFrame), display: true)
        for w in pageWindows {
            w.ignoresMouseEvents = false
            w.contentView?.isHidden = false
        }
        // A bar still open (the page navigated on its own) goes back to the browser window's look.
        if commandBar.isOpen { commandBar.close() }
    }

    /// Esc, the ✕, focus elsewhere, or a row that opens no page (a tab in the browser window, a
    /// command): the card fades out in 190 ms and closes.
    private func dismissCard() {
        guard isCard, !cardFading, let window, window.isVisible else { return }
        cardFading = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = LittleCard.fadeDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.closeWindow()
        }
    }

    /// For cra://debug?littleShown: whether the window is the card, its size, and how far its
    /// top-right corner is from its screen's visible area's (#337).
    var debugCard: String {
        guard let window else { return "card=-" }
        let f = window.frame, vf = (window.screen ?? placementScreen).visibleFrame
        return String(format: "card=%d size=%.0fx%.0f corner=%.0f,%.0f strip=%d lights=%d", isCard ? 1 : 0, f.width, f.height,
                      vf.maxX - f.maxX, vf.maxY - f.maxY, shell.hidesBar ? 0 : 1,
                      window.standardWindowButton(.closeButton)?.isHidden == false ? 1 : 0)
    }

    /// For cra://debug?devToolsShown: the page's DevTools as they are on screen, read from Chromium's
    /// windows. `docked`: their window hangs on this one and covers the page area, with the page's
    /// own window inside it and smaller (the frontend's split). `pageFills`: the page has the whole
    /// area (#348).
    var debugDevTools: String {
        guard let window else { return "peek=\(isPeek ? 1 : 0) open=-" }
        let area = window.convertToScreen(shell.convert(shell.page.frame, to: nil))
        func same(_ a: NSRect, _ b: NSRect) -> Bool {
            abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
        }
        let page = browser?.hostWindow.flatMap { $0.parent === window ? $0.frame : nil } ?? .zero
        var out = "peek=\(isPeek ? 1 : 0) parked=\(isParked ? 1 : 0) open=\(browser?.hasDevTools == true ? 1 : 0)"
        if let dev = browser?.devToolsWindow {
            let split = area.insetBy(dx: -1, dy: -1).contains(page) && (page.width < area.width - 1 || page.height < area.height - 1)
            out += " docked=\(dev.parent === window && same(dev.frame, area) && split ? 1 : 0)"
                + " shown=\(dev.isVisible && dev.alphaValue > 0 && dev.contentView?.isHidden == false ? 1 : 0)"
                + String(format: " size=%.0fx%.0f", dev.frame.width, dev.frame.height)
        }
        return out + " pageFills=\(same(page, area) ? 1 : 0)" + String(format: " area=%.0fx%.0f", area.width, area.height)
    }

    /// cra://debug?littleCard=<step>: `go:<typed>` is Return on what was typed in the card's bar,
    /// `close` is Esc (#337).
    func debugCardStep(_ step: String) {
        if step == "close" { commandBar.close(); return }
        if step.hasPrefix("go:") { handleCommit(nil, typed: String(step.dropFirst(3)), mode: .newTab) }
    }

    /// Arc grows the window from a small rectangle under the pointer to its
    /// full frame in about 120 ms (content laid out at full size, no fade).
    func show() {
        guard let window else { return }
        if isCard {
            // Arc's card is on screen at its size from its first frame (98 % of it, settling within
            // 100 ms), the bar already in it.
            window.makeKeyAndOrderFront(nil)
            rejoinPage()
            NSApp.activate(ignoringOtherApps: true)
            openCommandBar()
            return
        }
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
        rejoinPage()
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

    /// The click catcher, the Peek and its buttons, in their order above the parent's other children.
    var peekWindows: [NSWindow] { isParked ? [] : [dim, window, controls].compactMap { $0 } }

    /// Arc's Peek: the card grows out of the link clicked in `tabID`'s page (without one, from the
    /// whole area right of the sidebar) to its own frame, its buttons riding its corner, while the
    /// page behind fades to 28 % (GitHub #204). The motion is PeekTransition's pictures on Core
    /// Animation; the real card and buttons wait at their places, invisible, and take over when it
    /// lands.
    func showAsPeek(fromTab tabID: UUID?) {
        guard let window, let parent = peekParent, let pw = parent.window else { return }
        let dim = PeekDimPanel(covering: parent.peekDismissArea(), of: pw) { [weak self] in self?.closeWindow() }
        self.dim = dim
        pw.addChildWindow(dim, ordered: .above)
        dim.orderFront(nil)
        // Arc's Peek of an easel (Library ▸ Easels, 8 Nov 2026): no toolbar, the canvas on #0B0B0B,
        // and only ✕ and ⤢ beside it.
        let easel = browser as? EaselBrowser
        if let easel {
            shell.hidesBar = true
            easel.usePeekLook()
        }
        var buttons: [PeekControlsPanel.Button] = [
            .init(symbol: "xmark", help: "Close (⌘W)") { [weak self] in self?.closeWindow() },
            .init(symbol: "arrow.up.left.and.arrow.down.right", help: "Expand (⌘O)") { [weak self] in
                self?.expandPeek(commandClick: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
            },
        ]
        if easel == nil {
            buttons.append(.init(symbol: "square.split.2x1", help: "Add To Split") { [weak self] in self?.promoteToSplit() })
        }
        let controls = PeekControlsPanel(buttons: buttons)
        self.controls = controls
        controls.place(parent.peekButtonFrames(), theme: parent.focusedSpace.theme)
        controls.alphaValue = 0
        window.alphaValue = 0
        window.setFrame(parent.peekFrame(), display: false)
        shell.layoutSubtreeIfNeeded()
        pw.addChildWindow(window, ordered: .above)
        pw.addChildWindow(controls, ordered: .above)
        parent.peekWindowsAttached()
        pw.makeMain()
        controls.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        openingPeek = true
        // Hidden, not transparent: Chromium sets its page window's alpha back to 1 as it shows it.
        for w in pageWindows { w.contentView?.isHidden = true }
        if hasPage || isPopupHost { focusPage() } else { openCommandBar() }
        // The card waits, invisible at its place, for the link it grows out of (at most
        // PeekSource.wait); a close meanwhile ends it unseen (closePeekAnimated).
        parent.peekSource(fromTab: tabID) { [weak self] source in
            guard let self, let window = self.window, let controls = self.controls, self.openingPeek, !self.closingPeek else { return }
            self.peekSource = source
            let t = PeekTransition(over: pw, card: pw.convertFromScreen(window.frame), cardImage: PeekTransition.picture(of: self.shell),
                                   column: pw.convertFromScreen(controls.frame), columnImage: controls.contentView.flatMap { PeekTransition.picture(of: $0) },
                                   source: source?.rect ?? pw.convertFromScreen(parent.peekArea()), sourceImage: source?.image)
            self.transition = t
            // Next turn, with the panel on its way to the screen.
            DispatchQueue.main.async { [weak self, weak t] in
                guard let self, let t, self.transition === t, !self.closingPeek else { return }
                // A Peek gone by then (Expand, Add To Split, a close) never veils the page, nor
                // one waiting on its tab.
                let peek = self.peekID
                DispatchQueue.main.asyncAfter(deadline: .now() + PeekTransition.lead) { [weak self, weak parent] in
                    guard self?.isParked != true else { return }
                    parent?.showPeekVeil(for: peek)
                }
                self.landPeek(t)
            }
        }
    }

    private func landPeek(_ t: PeekTransition) {
        t.open { [weak self, weak t] in
            guard let self, let window = self.window, !self.closingPeek else { return }
            self.openingPeek = false
            window.alphaValue = 1
            for w in self.pageWindows { w.contentView?.isHidden = false }
            self.controls?.alphaValue = 1
            // The real card is on screen a frame later; the picture goes after it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                t?.remove()
                if self.transition === t { self.transition = nil }
            }
        }
    }

    /// Another tab came on screen in the window (#242): Arc keeps a Peek per tab
    /// (`modalByWindowContent`), so it waits out of sight, its page as it was, until its tab is
    /// back (PeekPresence). The page behind comes back at once, as the tab switch is.
    func parkPeek() {
        guard isPeek, !isParked, !closingPeek, let window, let parent = peekParent else { return }
        isParked = true
        peekParent?.closeCapture(in: self)
        openingPeek = false
        transition?.remove()
        transition = nil
        tooltipTimer?.invalidate(); hideTooltip()
        closePopup()
        commandBar.close()
        for w in [dim, controls].compactMap({ $0 }) {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
        }
        // The card and its page window stay ordered in, invisible and letting clicks through to the
        // tab under them: ordered out and back, Chromium scrolled the page to the top, and the
        // reporter comes back for the next link where they left it. The page hidden, not
        // transparent: Chromium sets its window's alpha back.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        (window as? LittleWindow)?.isParked = true
        for w in pageWindows {
            w.contentView?.isHidden = true
            w.ignoresMouseEvents = true
        }
        parent.parkPeekVeil(for: peekID)
        // The keyboard goes back to the window (also in the background, where actions follow the key window).
        if let pw = parent.window { if NSApp.isActive { pw.makeKeyAndOrderFront(nil) } else { pw.makeKey() } }
        parent.currentBrowser?.setFocused(true)
    }

    /// Its tab is on screen again: the Peek is back where it was, over the page faded behind it.
    func unparkPeek() {
        guard isParked, let window, let parent = peekParent, let pw = parent.window else { return }
        isParked = false
        // Parked while it was still opening: it lands now, without the motion.
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        (window as? LittleWindow)?.isParked = false
        for w in pageWindows {
            w.contentView?.isHidden = false
            w.alphaValue = 1
            w.ignoresMouseEvents = false
        }
        controls?.alphaValue = 1
        // The click catcher under the card, the buttons over it, all above the window's other children.
        window.parent?.removeChildWindow(window)
        for w in [dim, window, controls].compactMap({ $0 }) {
            pw.addChildWindow(w, ordered: .above)
            w.orderFront(nil)
        }
        parent.peekWindowsAttached()
        repositionPeek()
        rejoinPage()
        if NSApp.isActive { window.makeKeyAndOrderFront(nil) }
        if hasPage || isPopupHost { focusPage() }
        parent.showPeekVeil(for: peekID, animated: false)
    }

    /// The tab the Peek waits on is gone (#242): the Peek goes with it, unseen and not offered
    /// back by ⇧⌘T, which reopens the tab.
    func dropPeek() {
        guard isPeek, let window, !closingPeek else { return }
        closingPeek = true
        peekParent?.closeCapture(in: self)
        transition?.remove()
        transition = nil
        guard windowShouldClose(window) else { return }
        window.close()
    }

    func repositionPeek() {
        guard let window, let parent = peekParent, let pw = parent.window, !closingPeek else { return }
        dim?.reposition(covering: parent.peekDismissArea(), of: pw)
        window.setFrame(parent.peekFrame(), display: true)
        controls?.place(parent.peekButtonFrames(), theme: parent.focusedSpace.theme)
    }

    /// Arc closes a Peek the way it opened, backwards: into the link it came from, where the page
    /// has it now (out to the whole area, fading, without one), as the page behind comes back. A
    /// picture of the card with its page (Chromium's own screenshot, waited for at most 80 ms)
    /// takes over from the real one. Expand and Add To Split don't animate.
    private func closePeekAnimated(then finish: @escaping () -> Void) {
        guard let window, let parent = peekParent, let pw = parent.window else { finish(); return }
        let neverShown = openingPeek && transition == nil
        closingPeek = true
        parent.closeCapture(in: self)
        transition?.remove()
        transition = nil
        // Closed while it was still finding its link: it goes without having been seen.
        if neverShown { finish(); return }
        var started = false
        // The card's screenshot and the link's place now, asked together.
        var shot: CGImage??
        // No link to look for again: the area, or the place the Peek was clicked open (#359).
        var linkNow: NSRect?? = peekSource.map { $0.fromLink ? nil : .some($0.rect) } ?? .some(nil)
        let start: (CGImage?) -> Void = { [weak self] page in
            guard let self, !started else { return }
            started = true
            let card = pw.convertFromScreen(window.frame)
            let pageRect = self.shell.page.frame
            // Into the link where the page has it now; where it was when Chromium is late; out to
            // the whole area, fading, when it's gone.
            let area = pw.convertFromScreen(parent.peekArea())
            let back: (rect: NSRect, image: CGImage?) = switch linkNow {
            case .none: (self.peekSource?.rect ?? area, self.peekSource?.image)
            case .some(.some(let r)): (r, self.peekSource?.image)
            case .some(.none): (area, nil)
            }
            let t = PeekTransition(over: pw, card: card,
                                   cardImage: PeekTransition.picture(of: self.shell, page: page, pageRect: pageRect),
                                   column: self.controls.map { pw.convertFromScreen($0.frame) } ?? .zero,
                                   columnImage: self.controls?.contentView.flatMap { PeekTransition.picture(of: $0) },
                                   source: back.rect, sourceImage: back.image)
            self.transition = t
            t.close {
                finish()
                t.remove()
            }
            // The picture is on screen (the same pixels) before the real card goes, so nothing blinks.
            DispatchQueue.main.asyncAfter(deadline: .now() + PeekTransition.lead) {
                window.alphaValue = 0
                for w in self.pageWindows { w.alphaValue = 0 }
                self.controls?.alphaValue = 0
                parent.hidePeekVeil(for: self.peekID)
            }
        }
        let ready: (Bool) -> Void = { timedOut in
            guard !started, timedOut || (shot != nil && linkNow != nil) else { return }
            start(shot ?? nil)
        }
        if let source = peekSource, source.fromLink {
            parent.peekSourceAgain(source) { r in
                if linkNow == nil { linkNow = .some(r) }
                ready(false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { ready(true) }
        guard let b = browser, hasPage else { shot = .some(nil); ready(false); return }
        b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"jpeg","quality":85,"optimizeForSpeed":true}"#) { result, _ in
            let image = PeekSource.image(fromScreenshot: result)
            DispatchQueue.main.async {
                if shot == nil { shot = .some(image) }
                ready(false)
            }
        }
    }

    private func endPeek() {
        guard isPeek, let dim else { return }
        self.dim = nil
        transition?.remove()
        transition = nil
        dim.parent?.removeChildWindow(dim)
        dim.orderOut(nil)
        if let controls {
            controls.parent?.removeChildWindow(controls)
            controls.orderOut(nil)
            self.controls = nil
        }
        if let window, let p = window.parent { p.removeChildWindow(window) }
        peekParent?.endPeekVeil(for: peekID)
        if !promoted, let pw = peekParent?.window, NSApp.isActive { pw.makeKeyAndOrderFront(nil) }
    }

    /// The Expand button: the page becomes a new tab, or with ⌘ held and Settings ▸ Links ▸ "⌘-click
    /// Expand opens in the tab" on, loads in the tab the Peek came from (PeekExpand, GitHub #380).
    func expandPeek(commandClick: Bool) {
        let source = peekSourceTab.flatMap { store.item($0) != nil ? $0 : nil }
        switch PeekExpand.target(commandClick: commandClick, hasSourceTab: source != nil, settings: store.settings) {
        case .newTab: promote(to: nil)
        case .sourceTab: if let source { loadInSourceTab(source) }
        }
    }

    /// The tab under the Peek navigates to the peeked page and the Peek goes, without its closing
    /// motion (Expand's own way out). The tab's history stays, so Back returns to where it was.
    private func loadInSourceTab(_ tabID: UUID) {
        guard hasPage, let parent = peekParent, let window else { return }
        let url = currentURL
        promoted = true  // the page lives on in the tab: not a closed Peek to reopen
        guard windowShouldClose(window) else { return }
        window.close()
        parent.loadPeekPage(url, inTab: tabID)
    }

    /// Add To Split: the peeked page becomes a tab and joins the tab under the Peek as a split
    /// pane, live as it is (Arc's openInSplit).
    func promoteToSplit() {
        guard let b = browser, hasPage, let parent = peekParent, let source = parent.selectedTabID else { return }
        guard parent.canAddPane(to: source) else {
            parent.showToast("Cannot Add New Pane")
            return
        }
        closePopup()
        commandBar.close()
        let sid = store.spaceID(ofItem: source) ?? parent.focusedSpaceID
        // Arc leaves a pinned tab where it is: the split is a new one at the top of Today, a copy
        // of the pinned tab's page beside the peeked one.
        var partner = source
        if store.isPinned(source), store.splitContaining(source) == nil, let page = store.item(source)?.tab {
            partner = store.createTab(url: page.url, title: page.savedTitle, in: sid, select: false, window: parent.windowID).id
        }
        let tab = store.createTab(url: b.currentURL, title: b.currentTitle, in: sid, select: false, window: parent.windowID)
        if let favicon, let key = FaviconKey.key(for: b.currentURL) { app.favicons.store(favicon, forKey: key) }
        promoted = true
        endDevTools(of: b)
        browser = nil
        parent.browsers.adopt(b, for: tab.id)
        window?.close()
        parent.joinSplit(tab.id, with: partner)
    }

    // MARK: Command bar (Arc: clicking the pill or ⌘L opens the command bar in the window)

    func openCommandBar() {
        guard let window else { return }
        tooltipTimer?.invalidate(); hideTooltip()
        closePopup()
        let prefill = hasPage ? currentURL : nil
        // Suggestions come from the normal profile even when an incognito window was in front.
        app.useNormalWindow()
        commandBar.theme = store.focusedSpace.theme.shown
        commandBar.focusedSpaceID = store.focusedSpaceID
        commandBar.spaceShown = isPeek ? nil : state.targetSpaceID
        commandBar.open(mode: hasPage ? .editURL : .newTab, prefill: prefill)
        commandBar.attached = false
        commandBar.panelWidth = isCard ? window.frame.width - 2 * LittleMetrics.edgeInset
            : min(LittleMetrics.commandBarWidth, window.frame.width - 40)
        // Little Arc's palette is dark whatever macOS uses, the card's bar with it.
        commandPanel.appearance = isCard ? NSAppearance(named: .darkAqua) : nil
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

    /// Arc puts the bar's top a third of the way down the window; in the card it is the window, inside
    /// its rim, down to its rows.
    private func positionCommandPanel() {
        guard let window else { return }
        let h = CommandBarView.height(forRows: commandBar.rowPlaces)
        let w = commandBar.panelWidth
        let wf = window.frame
        if isCard {
            let inset = LittleMetrics.edgeInset
            let bar = LittleCard.barFrame(height: h, in: wf, inset: inset)
            let radius = max(0, (window as? LittleWindow)?.systemCornerRadius ?? LittleMetrics.cornerRadius) - inset
            let card = CommandBarCard(top: radius, bottom: bar.fills ? radius : LittleCard.barBottomRadius,
                                      closeTrailing: LittleCard.closeTrailing - inset, dividerInset: LittleCard.dividerInset - inset)
            if commandHost.card != card { commandHost.card = card }
            commandPanel.setFrame(bar.frame, display: true)
            return
        }
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
        if isCard {
            // The bar closes before its row runs: a row that opens a page expands the card by then.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCard, !self.commandBar.isOpen else { return }
                self.dismissCard()
            }
            return
        }
        window?.makeKeyAndOrderFront(nil)
        focusPage()
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            navigate(url)
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed))
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
            open(s.url ?? commandBar.engine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            // Switching spaces in a Little Window switches its own "Open in", not the browser
            // window's space (#316); the next Little Window follows the window used last again.
            // A Peek's follows the window it covers, and an incognito space switches the window
            // as before.
            if isPeek || store.isIncognito(space: id) {
                store.focusSpace(id)
            } else {
                target.pick(id)
            }
            refreshTarget()
            // The card is its bar: it stays open, now opening into the space picked.
            if isCard { openCommandBar() }
        case .moveToSpace(let id):
            promote(to: id)
        case .moveToFolder:
            break
        }
    }

    /// `cra://debug?littleCommit=<typed>`: the bar's "Switch to" row for `typed`, committed as ↩
    /// on it does; logs the rows found (#316).
    /// For `cra://debug?littleShown`: the address pill's padlock and text (#330).
    var debugReadout: String { (shell.toolbarHost as? LittleToolbarView)?.debugReadout ?? "" }

    func debugCommit(_ typed: String) {
        let shown = isPeek ? nil : state.targetSpaceID
        let rows = commandBar.engine.suggestions(for: typed, mode: .newTab, currentTabID: nil, spaceShown: shown).items
        let row = rows.first { if case .switchSpace = $0.kind { true } else { false } }
        CraLog.note("little commit \(typed): \(row?.title ?? "no Switch to row")")
        if let row { handleCommit(row, typed: typed, mode: .newTab) }
    }

    /// cra://debug?littleMenu=<step>: drives the "Open in" menu (#331) and logs what it shows.
    /// open (as the ⌄ or ⇧⌘O), down<n> (↓ n times), type:<text> (the filter), close.
    func debugMenu(_ step: String) {
        switch step {
        case "open": if popup == nil { openPopup() }
        case "close": closePopup()
        case let s where s.hasPrefix("down"): (popup?.contentView as? LittleSpacesPopup)?.debugMove(down: Int(s.dropFirst(4)) ?? 1)
        case let s where s.hasPrefix("type:"): (popup?.contentView as? LittleSpacesPopup)?.debugType(String(s.dropFirst(5)))
        default: break
        }
        var line = "chevron=\(state.showsChevron ? 1 : 0)"
        if let panel = popup, let window, let menu = panel.contentView as? LittleSpacesPopup {
            let f = panel.frame, w = window.frame
            line += String(format: " menu=%.0fx%.0f top=%.0f right=%.0f ", f.width, f.height, w.maxY - f.maxY, w.maxX - f.maxX) + menu.debugState
        } else {
            line += " menu=closed"
        }
        CraLog.note("little menu \(step): \(line)")
    }

    private func navigate(_ url: String) {
        expandCard()
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
        guard let window, popup == nil, state.showsChevron else { return }
        tooltipTimer?.invalidate(); hideTooltip()
        commandBar.close()
        let panel = LittlePopupPanel()
        panel.contentView = LittleSpacesPopup(state: state, store: store,
                                              onPick: { [weak self] sid in self?.closePopup(); self?.promote(to: sid) },
                                              onClose: { [weak self] in self?.closePopup() })
        panel.delegate = self
        panel.setFrame(LittleMoveMenu.frame(rows: store.orderedSpaces.count, in: window.frame), display: true)
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

    /// Arc's Little Arc names the space of the browser window used last and updates when it
    /// takes focus again (Arc 1.171: switched in the main window, "Open in" followed; #92),
    /// until a space is picked in this window (#316).
    func refreshTarget() {
        target.forget { store.space($0) != nil }
        let id = peekParent?.focusedSpaceID ?? target.space(lastUsed: store.focusedSpaceID(window: store.lastNormalWindowID))
        if state.targetSpaceID != id { state.targetSpaceID = id }
    }

    /// The space the "Open in" button names, and Tabs ▸ "Open in <space>" with it (TabsMenu).
    var openInSpace: Space { store.space(state.targetSpaceID) ?? store.focusedSpace }

    /// Move the page into a space (nil = the window's target space) as a Today
    /// tab, in the window already showing that space if there is one (Arc). The
    /// live browser goes with it, so history, scroll position and logins stay.
    func promote(to spaceID: UUID?) {
        guard let b = browser, hasPage else { return }
        (b as? EaselBrowser)?.usePageLook()
        closePopup()
        commandBar.close()
        app.useNormalWindow()
        if spaceID == nil { refreshTarget() }
        let wanted = spaceID ?? state.targetSpaceID
        let sid = store.space(wanted) != nil && !store.isIncognito(space: wanted) ? wanted : store.focusedSpaceID
        // Held: closing this window can make another browser window key, which changes app.main.
        let target = app.useNormalWindow(forSpace: sid)
        let tab = store.createTab(url: b.currentURL, title: b.currentTitle, in: sid, select: true, window: target.windowID)
        if let favicon, let key = FaviconKey.key(for: b.currentURL) { app.favicons.store(favicon, forKey: key) }
        promoted = true
        endDevTools(of: b)
        browser = nil
        target.browsers.adopt(b, for: tab.id)
        window?.close()
        target.showWindow(nil)
        target.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Profile

    /// Arc's Little Arc shows the page's profile in its address pill once there is more than one
    /// (LittleBrowser.State.shouldShowProfileIndicators).
    var showsProfile: Bool { !store.profiles.isEmpty }

    var profileName: String { store.profile(state.profileID)?.name ?? "Default" }

    /// The indicator's menu (LittleBrowserToolbarAction.showChangeProfileMenu): every profile,
    /// the page's ticked (ChangeProfileMenuOption.isCurrent).
    func showProfileMenu(from view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let options: [(UUID?, String)] = [(nil, "Default")] + store.profiles.map { ($0.id, $0.name) }
        for (id, name) in options {
            MenuItems.add(menu, name, on: id == state.profileID) { [weak self] in self?.changeProfile(to: id) }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
    }

    static let bypassProfileDialogKey = "shouldBypassConfirmLittleWindowProfileDialog"

    /// Arc asks first (ProfileDialogUtils.MoveKind.changeProfileInLittleWindow), with a
    /// "Don't ask again" that sets shouldBypassConfirmLittleBrowserProfileDialog.
    func changeProfile(to id: UUID?) {
        guard id != state.profileID, let window else { return }
        if UserDefaults.standard.bool(forKey: Self.bypassProfileDialogKey) { reload(inProfile: id); return }
        let alert = AppDialog(title: "Open this page in \(store.profile(id)?.name ?? "Default")?",
                              message: "Each Profile has different browser data, so this webpage might look a little different.",
                              actions: [DialogAction("Change Profile"), .cancel], suppressionTitle: "Don’t ask again")
        alert.present(over: window) { [weak self, weak alert] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            if alert?.isSuppressed == true { UserDefaults.standard.set(true, forKey: Self.bypassProfileDialogKey) }
            self.reload(inProfile: id)
        }
    }

    /// A page can't move between profiles: a new browser in the other one loads its address.
    private func reload(inProfile id: UUID?) {
        guard browser != nil else { return }
        state.profileID = id
        replacePage(at: hasPage ? currentURL : "about:blank")
    }

    /// A new page at `url` in place of this window's, in the engine the address gets (a profile
    /// change, or a navigation the other engine has to show).
    private func replacePage(at url: String) {
        guard let old = browser else { return }
        endDevTools(of: old)
        old.delegate = nil
        if let w = old.hostWindow, w.parent === window { window?.removeChildWindow(w); w.orderOut(nil) }
        old.containerView.removeFromSuperview()
        let b = PageEngines.makeBrowser(frame: shell.page.bounds, url: url, delegate: self, incognito: false,
                                        profilePath: store.profilePath(profile: state.profileID))
        attach(b)
        old.close()
        if window?.isKeyWindow == true { focusPage() }
    }

    /// A navigation the other engine has to show (ProtectedMediaSites): this window's page opens
    /// again there, a turn later (not from inside Chromium's navigation callback).
    func browser(_ browser: CraBrowser, handsOffNavigationToURL url: String, method: String) -> Bool {
        guard browser === self.browser, PageEngines.handoffTarget(from: browser, to: url, method: method) != nil else { return false }
        DispatchQueue.main.async { [weak self, weak browser] in
            guard let self, let browser, browser === self.browser else { return }
            self.state.url = url
            self.replacePage(at: url)
        }
        return true
    }

    /// Archive the page to the Library (Arc keeps closed Little Arcs there too).
    func archivePage() {
        // A Peek is a look at a link, not a page to keep.
        guard hasPage, !promoted, !isPeek else { return }
        store.archiveLittleWindowPage(url: currentURL, title: browser?.currentTitle ?? state.title)
        if let favicon, let key = FaviconKey.key(for: currentURL) { app.favicons.store(favicon, forKey: key) }
        promoted = true  // archived once; a later close must not archive again
    }

    /// Menu / key actions while this window is key. Returns false for actions
    /// that are not the little window's (the app handles those).
    func handle(action id: String) -> Bool {
        if handleCapture(action: id) { return true }
        switch id {
        // ⌘W on the card fades it out, as Esc does (#337).
        case "closeTab", "closeWindow": if isCard, !cardFading, window?.isVisible == true { dismissCard() } else { closeWindow() }
        case "newTab", "editURL":
            // ⌘T in a Peek is the browser window's New Tab bar, with its tabs; ⌘L edits the Peek (#379).
            let opening = CommandBarOpening.of(id == "newTab" ? .newTab : .editURL, in: isPeek ? .peek : .littleWindow, hasPage: hasPage)
            if opening.owner == .browserWindow, let parent = peekParent { parent.openCommandBar(opening.mode) } else { openCommandBar() }
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
        case "copyURL": copyURL()
        case "copyURLMarkdown":
            copy("[\(browser?.currentTitle ?? state.title)](\(currentURL))")
            showToast("Copied URL as Markdown")
        case "viewSource": browser?.viewSource()
        case "devTools": runDevTools(.toggle)
        case "jsConsole": runDevTools(.console)
        case "networkPanel": runDevTools(.network)
        case "inspectElement": runDevTools(.inspect)
        case "print": browser?.print()
        // The rest of the page's commands run on this page, not on the browser window's tab (#333).
        case "share": PageCommands.share(self)
        case "copyURLQuote": PageCommands.copyURLAsQuote(self)
        case "savePageAs": PageCommands.savePageAs(self)
        case "captureFullPage": PageCommands.captureFullPage(self)
        case "capturePortrait": PageCommands.capturePortrait(self)
        case "jumpToSelection": PageCommands.jumpToSelection(browser)
        case "pictureInPicture": browser?.requestPictureInPicture(automatic: false)
        case "cast": if browser?.runChromeCommand("IDC_ROUTE_MEDIA") != true { showToast("Nothing to Cast") }
        case "taskManager": if browser?.runChromeCommand("IDC_TASK_MANAGER") != true { showToast("Open a Page First") }
        case "toggleDeveloperMode": if hasPage { store.settings.toggleDeveloperMode(url: currentURL) }
        case "stayOnTop": toggleStayOnTop()
        case "promoteLittleWindow": promote(to: nil)
        // Arc's Show Little Arc "Open In" Menu (⇧⌘O): the ⌄ button's list of spaces.
        case "littleWindowOpenInMenu": if hasPage, !isPeek { togglePopup() }
        // Move Tab to Space N (⌃⌘N, #86) sends the page there, as the spaces popup does (#92).
        case let id where id.hasPrefix("moveTabToSpace"):
            if let n = Int(id.dropFirst(14)), n >= 1, n <= store.spaceOrder.count { promote(to: store.spaceOrder[n - 1]) }
        // No find bar, sidebar or split in little windows; keep them off the main window.
        case "find", "findNext", "findPrevious", "useSelectionForFind", "toggleSidebar", "pinTab", "favoriteTab", "renameTab",
             "duplicateTab", "resetTab", "muteTab", "clearToday", "nextTab", "previousTab", "recentTab", "recentTabBackward",
             "revealTab", "collapsePinned", "collapseAllFolders", "expandAllFolders", "resetSpaceTabs",
             "addSplitView", "closeSplitPane", "separateFromSplit", "expandSplitPane", "flipSplitOrientation", "nextSplitPane", "previousSplitPane":
            break
        case let id where id.hasPrefix("splitPane"): break
        default: return false
        }
        return true
    }

    /// Window ▸ Stay On Top floats this window over other apps' windows. A Peek rides on its
    /// browser window, so that one floats with it.
    var staysOnTop: Bool { isPeek ? peekParent?.staysOnTop ?? false : window?.level == .floating }
    func toggleStayOnTop() {
        if isPeek { peekParent?.toggleStayOnTop(); return }
        window?.level = staysOnTop ? .normal : .floating
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// ⇧⌘C and the link button: Arc's toast over the window's top-right corner, as in a browser window.
    private func copyURL() {
        copy(currentURL)
        showToast("Copied Current URL", action: .share(currentURL))
    }

    /// The toast sits 8 pt under the window's top, over the toolbar (Arc's Little Arc).
    func showToast(_ text: String, action: ShinyToast.Action? = nil) {
        guard let window, let content = window.contentView else { return }
        slowResponseShown = false
        toast.show(text, action: action, page: content.convert(content.bounds, to: nil), in: window, colors: LittlePalette.toast)
    }

    /// ⌘W / Close Window: the same path as the close button. (performClose is
    /// skipped: it refuses to act while the standard buttons are dimmed.)
    func closeWindow() {
        guard let window, window.isVisible || isParked else { return }
        if isPeek, !closingPeek {
            if hasPage, !promoted, let parent = peekParent {
                parent.closedPeek = (currentURL, peekSourceTab, store.clock.now)
            }
            // Out of sight (its window closing, ⌘Q to the menu bar): nothing to animate.
            if isParked {
                closingPeek = true
            } else {
                closePeekAnimated { [weak self] in self?.closeWindow() }
                return
            }
        }
        guard windowShouldClose(window) else { return }
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
            // Its DevTools close with the page, an undocked window of theirs too.
            for w in pageWindows { sender.removeChildWindow(w); w.orderOut(nil) }
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
        guard let window, (notification.object as? NSWindow) === window else { return }
        if !isPeek { window.collectionBehavior.remove(.fullScreenPrimary) }
        guard pageFullscreen else { return }
        pageFullscreen = false
        browser?.exitFullscreen()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, (notification.object as? NSWindow) === window, !window.styleMask.contains(.fullScreen) else { return }
        if commandBar.isOpen { positionCommandPanel() }
        if popup != nil { closePopup() }
        // A toast that stays (the slow-response notice) keeps to the top right.
        if let content = window.contentView { toast.follow(page: content.convert(content.bounds, to: nil), in: window) }
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
        if isCard {
            // A click on the card below a shrunk bar keeps it; another window or app closes it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                if NSApp.isActive, NSApp.keyWindow === self.window { self.commandPanel.makeKeyAndOrderFront(nil); return }
                if NSApp.keyWindow === self.commandPanel { return }
                // A test copy runs behind other apps (CRA_TEST_BACKGROUND): it never has the focus to lose.
                if HitchMonitor.background || Date().timeIntervalSince(self.commandBarOpenedAt) < 0.6 {
                    self.commandPanel.makeKeyAndOrderFront(nil)
                    return
                }
                self.commandBar.close()
            }
            return
        }
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
        // The card's blank page went somewhere by itself: show it.
        if isCard, hasPage { expandCard() }
    }

    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        state.isLoading = loading
        state.canGoBack = canGoBack
        state.canGoForward = canGoForward
        if !loading { state.progress = 0 }
        syncSlowResponse(browser)
    }

    func browser(_ browser: CraBrowser, didChangeCommittedLoad committed: Bool) { syncSlowResponse(browser) }

    /// As in a browser window (MainWindowController.syncSlowResponse): ten seconds without the
    /// page's first response puts it in the toast, with Stop Loading. `reporting`: the page whose
    /// event this is; its first one comes while it is still being made, before `browser` is set.
    private func syncSlowResponse(_ reporting: CraBrowser? = nil) {
        let browser = reporting ?? self.browser
        let clock = app.composition.clock
        let now = clock.now
        if let browser {
            slowResponse.update(LoadingIndicator.Phase(isLoading: browser.isLoading, committed: browser.hasCommittedLoad),
                                navigation: browser.navigationStarts, now: now)
        } else {
            slowResponse.update(.hidden, navigation: 0, now: now)
        }
        let waiting = slowResponse.waitingSince != nil
        if state.awaitsFirstResponse != waiting { state.awaitsFirstResponse = waiting }
        slowResponseCheck?.cancel()
        slowResponseCheck = nil
        if let due = slowResponse.showsAt, due > now {
            slowResponseCheck = clock.after(due.timeIntervalSince(now)) { [weak self] in self?.syncSlowResponse() }
        }
        if slowResponse.isShown(at: now) {
            guard !slowResponseShown, let window, let content = window.contentView, let browser else { return }
            slowResponseShown = true
            let host = browser.isIncognito ? "(incognito)" : CraLog.host(browser.navigatingURL ?? currentURL)
            toast.show(SlowResponseNotice.message(for: browser.navigatingURL ?? currentURL),
                       action: ShinyToast.Action(title: "Stop Loading") { [weak browser] in
                           CraLog.note("Little Window: page \(host) stopped from the notice")
                           browser?.stopLoading()
                       },
                       page: content.convert(content.bounds, to: nil), in: window, colors: LittlePalette.toast,
                       onClose: { [weak self] in
                           self?.slowResponse.close()
                           self?.slowResponseShown = false
                       })
            CraLog.note("Little Window: page \(host) still waiting for a response: notice shown (navigation \(browser.navigationStarts))")
        } else if slowResponseShown {
            slowResponseShown = false
            CraLog.note("Little Window: page no longer waiting: notice gone")
            toast.dismiss()
        }
    }

    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) { state.progress = progress }

    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {
        store.recordVisit(url: url, title: title)
    }

    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {
        favicon = image
        if let key = FaviconKey.key(for: browser.currentURL) { app.favicons.store(image, forKey: key) }
    }

    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) { state.themeColor = hex }
    /// The page window trails the shell during a fast resize; the gap shows the page's colour
    /// (Arc's canvas while a new page has none yet).
    func browser(_ browser: CraBrowser, didReportBackgroundColor hex: String) {
        shell.page.layer?.backgroundColor = (hex.isEmpty ? CraBrowser.pageCanvasColor : NSColor(Color(hex: hex))).cgColor
    }
    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {}

    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {
        guard let window else { return }
        pageFullscreen = fullscreen
        // Only a full-screen-primary window gets a full-screen Space of its own (#277: not while it opens).
        if fullscreen, !isPeek { window.collectionBehavior.insert(.fullScreenPrimary) }
        if fullscreen != window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    /// A Shift-clicked link opens in this window: Arc's Little Arc has no Peek of its own, so its
    /// Shift-click is a plain click (1.171, 3 Nov 2026).
    /// In a Peek, a target=_blank link leaves it for a tab (PeekTrigger.leavesPeek, #202).
    func browser(_ browser: CraBrowser, opensPeekForURL url: String, shiftClick: Bool, newTab: Bool) -> Bool {
        if url.lowercased().hasPrefix("cra:") { return false }
        if isPeek, PeekTrigger.leavesPeek(url, shiftClick: shiftClick, newTab: newTab) {
            openTabFromPeek(url, inBackground: false)
            return true
        }
        guard shiftClick else { return false }
        browser.loadURL(url)
        return true
    }

    /// Links that want a new tab open another little window (Arc does the same); a Peek's open
    /// as tabs in its window's space.
    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        if url.lowercased().hasPrefix("cra:") { return }
        if isPeek { openTabFromPeek(url, inBackground: background); return }
        app.openLittleWindow(url: url, activate: !background, opener: browser)
        if background { window?.makeKeyAndOrderFront(nil) }
    }

    func browser(_ browser: CraBrowser, requestsWindowWithURL url: String, kind: CraLinkWindow) {
        app.openLink(url, in: kind, space: state.targetSpaceID, fromIncognito: browser.isIncognito)
    }

    /// Arc 1.171 (#202): a link from a Peek that asks for a new tab is a Today tab in the space,
    /// placed as a link from the tab under the Peek would be, and selected. The Peek waits on its
    /// own tab, as it does for any other tab (parkPeek, #242), for the next link. A background
    /// one (⌘-click) leaves the Peek on screen.
    private func openTabFromPeek(_ url: String, inBackground background: Bool) {
        guard let parent = peekParent else { return }
        parent.browsers.openLinkTab(url, from: peekSourceTab, inBackground: background)
    }

    /// A popup that needs its opener (a sign-in window) stays a Little Window, over a Peek too:
    /// closing the Peek for a tab would close the page waiting on it.
    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? {
        if url.lowercased().hasPrefix("cra:") { return nil }
        if isPeek, background {
            openTabFromPeek(url, inBackground: true)
            return nil
        }
        let w = app.makeLittleWindow(url: nil, opener: browser)
        w.state.url = url
        w.show()
        if background { window?.makeKeyAndOrderFront(nil) }
        return w.browser
    }

    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) {
        attachHostWindow(window)
        if hasPage || isPopupHost, self.window?.isKeyWindow == true || window.isKeyWindow { focusPage() }
    }

    // MARK: DevTools

    /// ⌥⌘I, ⌥⌘J, ⌥⌘C and their menu items on this window's page, as BrowserManager.runDevTools
    /// has them for a tab: ⌥⌘I closes DevTools that are open.
    private func runDevTools(_ command: DevToolsToggle.Command) {
        guard let b = browser else { return }
        // WebKit's inspector (a DRM service's page) reports nothing back: it is only ever asked to show.
        guard b.hostWindow != nil else {
            b.showDevTools()
            return
        }
        let (effect, frontend) = devTools.run(command)
        // A press made while DevTools close is done when they reopen (DevToolsToggle.didClose),
        // one made while they open once the frontend is up.
        b.devToolsAction = frontend
        perform(effect)
    }

    private func perform(_ effect: DevToolsToggle.Effect) {
        switch effect {
        case .show: browser?.showDevTools()
        case .close: browser?.closeDevTools()
        case .frontend: browser?.applyDevToolsAction()
        case .none: break
        }
    }

    /// Only an Alloy page asks; it gets CEF's own DevTools window.
    func devToolsHostView(for browser: CraBrowser) -> NSView? { nil }

    /// Chromium made the DevTools window: 10 pt square in the top left corner of the primary
    /// display, where it stayed for a Little Window and a Peek (#348). It docks over the page
    /// area, as in the browser window.
    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {
        guard browser === self.browser else { return }
        devToolsView = view
        devToolsDocked = true
        devToolsPlaceholder = nil
        devTools.didOpen()
        syncDevToolsWindow()
    }

    func browserDidCloseDevTools(_ browser: CraBrowser) {
        guard browser === self.browser else { return }
        clearDevTools()
        layoutPageWindows()
        perform(devTools.didClose())
    }

    /// The docked frontend placed the page (also streamed while its splitter is dragged).
    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {
        // Undocked frontends still report bounds (device mode); only setIsDocked changes the dock state.
        guard browser === self.browser, devToolsDocked, let dev = devToolsView?.window else { return }
        let size = dev.contentView?.bounds.size ?? NSSize(width: bounds.maxX, height: bounds.maxY)
        devToolsPlaceholder = DevToolsPlaceholder(bounds: bounds, frontendSize: size)
        layoutPageWindows()
    }

    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {
        guard browser === self.browser else { return }
        if !docked { devToolsPlaceholder = nil }
        guard devToolsDocked != docked else { return }
        devToolsDocked = docked
        syncDevToolsWindow()
    }

    func browser(_ browser: CraBrowser, devToolsShowsPanel panel: String) {
        if browser === self.browser { devTools.didShowPanel(panel) }
    }

    /// Hangs the DevTools window on this one over the page area, under the page's own window, or,
    /// once the frontend's "Undock into separate window" is picked, lets it go as a window of its own.
    private func syncDevToolsWindow() {
        guard let window, let dev = devToolsView?.window else { layoutPageWindows(); return }
        if !devToolsDocked {
            guard dev.parent === window else { return }
            window.removeChildWindow(dev)
            dev.contentView?.isHidden = false
            dev.alphaValue = 1
            dev.ignoresMouseEvents = false
            DevToolsWindowChrome.undock(dev, over: window, pageURL: currentURL)
            browser?.executeJavaScript(DevToolsWindowChrome.titleBarInsetScript(for: dev), inDevTools: true)
            layoutPageWindows()
            dev.makeKeyAndOrderFront(nil)
            return
        }
        if dev.parent !== window {
            DevToolsWindowChrome.dock(dev)
            // As the page's window: out of sight while a Peek opens or waits on its tab.
            if openingPeek || isParked || isCard { dev.contentView?.isHidden = true }
            dev.ignoresMouseEvents = isParked || isCard
            window.addChildWindow(dev, ordered: .above)
            browser?.executeJavaScript(DevToolsWindowChrome.titleBarInsetScript(for: nil), inDevTools: true)
            dev.orderFront(nil)
            // Child windows ignore orderWindow:relativeTo:; re-adding a child puts it above its
            // siblings. The page's window goes over DevTools, the command bar over both.
            if let host = browser?.hostWindow, host.parent === window {
                window.removeChildWindow(host)
                window.addChildWindow(host, ordered: .above)
                host.orderFront(nil)
            }
            if commandPanel.parent === window { window.removeChildWindow(commandPanel); window.addChildWindow(commandPanel, ordered: .above) }
            installDevToolsClickMonitor()
        }
        layoutPageWindows()
        rejoinPage()
    }

    /// The page leaves for a tab, or another takes its place: its DevTools close, as a tab's do
    /// when its page moves to another window (BrowserManager.release).
    private func endDevTools(of b: CraBrowser) {
        if let dev = devToolsView?.window, dev.parent === window {
            window?.removeChildWindow(dev)
            dev.orderOut(nil)
        }
        if b.hasDevTools { b.closeDevTools() }
        clearDevTools()
        devTools = DevToolsToggle()
        layoutPageWindows()
    }

    private func clearDevTools() {
        devToolsView = nil
        devToolsPlaceholder = nil
        devToolsDocked = true
        if let monitor = devToolsClickMonitor { NSEvent.removeMonitor(monitor) }
        devToolsClickMonitor = nil
    }

    /// The page and its DevTools are separate Chromium windows, and Chromium drops a click on a
    /// window that isn't key. In Chrome they share one window, so going from one to the other
    /// never costs a click: the one clicked becomes key first, while focus is already in this
    /// window (as MainWindowController.installChildClickMonitor does for a pane).
    private func installDevToolsClickMonitor() {
        guard devToolsClickMonitor == nil else { return }
        devToolsClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let window = self.window, let target = event.window,
                  self.pageWindows.contains(where: { $0 === target }),
                  !target.isKeyWindow, target.canBecomeKey, NSApp.isActive,
                  let key = NSApp.keyWindow, key === window || key.parent === window else { return event }
            target.makeKey()
            return event
        }
    }
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
        // The main window's card, in the page's top left corner as in a Little Arc (#371). A quiet
        // notification deny here would save a block for the site that its tabs then hit too (#137).
        let card = PermissionPopover(title: PermissionPrompt.message(origin: origin, kinds: kinds),
                                     actions: [DialogAction("Allow"), DialogAction("Not Now", role: .cancel)])
        guard window != nil else { completion(false); return }
        let page = shell.page
        permissionCards.append(card)
        card.present(relativeTo: page.bounds, of: page) { [weak self, weak card] resp in
            self?.permissionCards.removeAll { $0 === card }
            completion(resp == .alertFirstButtonReturn)
        }
    }

    func browserDidReceiveFocus(_ browser: CraBrowser) {}

    func browserDidClose(_ browser: CraBrowser) {
        browser.containerView.removeFromSuperview()
        guard self.browser === browser else { return }
        self.browser = nil
        clearDevTools()
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
    /// The profile chip's width in the pill, 0 while it is hidden.
    var profileChipWidth: () -> CGFloat = { 0 }
    var showsChevron: () -> Bool = { true }
    /// While the window grows open, lay out for this (final) size anchored top-left.
    var frozenSize: NSSize? { didSet { needsLayout = true } }
    /// Arc's Peek card: its own 32 pt bar, the page edge to edge, 8 pt corners all round.
    var isPeek = false {
        didSet {
            layer?.cornerRadius = isPeek ? PeekLayout.cornerRadius : 0
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = isPeek
            needsLayout = true
        }
    }
    private var barHeight: CGFloat { hidesBar ? 0 : (isPeek ? PeekLayout.barHeight : LittleMetrics.barHeight) }
    /// A page with no toolbar over it (an easel in Peek).
    var hidesBar = false { didSet { toolbarHost.isHidden = hidesBar; needsLayout = true } }
    /// ⌥⌘N's card (#337): no page, Little Arc's own background where the bar doesn't reach.
    var isCard = false {
        didSet {
            cardBackground.isHidden = !isCard
            page.isHidden = isCard
            needsLayout = true
        }
    }
    private let cardBackground = CAGradientLayer()
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = LittlePalette.barNS.cgColor
        // Top left to bottom right (the layer's y runs up).
        cardBackground.colors = [LittlePalette.cardTopLeft.cgColor, LittlePalette.cardBottomRight.cgColor]
        cardBackground.startPoint = CGPoint(x: 0, y: 1)
        cardBackground.endPoint = CGPoint(x: 1, y: 0)
        cardBackground.isHidden = true
        layer?.addSublayer(cardBackground)
        addSubview(toolbarHost)
        page.wantsLayer = true
        page.layer?.cornerCurve = .continuous
        page.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        page.layer?.masksToBounds = true
        page.layer?.backgroundColor = CraBrowser.pageCanvasColor.cgColor
        page.autoresizesSubviews = true
        addSubview(page)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPeekBar(_ bar: PeekBarView) {
        toolbarHost.removeFromSuperview()
        toolbarHost = bar
        addSubview(bar, positioned: .below, relativeTo: page)
        needsLayout = true
    }

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
        guard !isPeek else { return }
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
            let chipW = profileChipWidth()
            let chipRight = pillRight - LittleMetrics.profileChipTrailing
            if chipW > 0, x >= chipRight - chipW, x < chipRight { return .profile }
            return .pill
        }
        if x >= buttonLeft, x < w - LittleMetrics.rightMargin {
            return showsChevron() && x >= w - LittleMetrics.rightMargin - LittleMetrics.chevronWidth ? .chevron : .open
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
        if isCard {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardBackground.frame = bounds
            CATransaction.commit()
        }
        let barH = barHeight
        toolbarHost.frame = NSRect(x: 0, y: b.maxY - barH, width: b.width, height: barH)
        let inset = fullscreen || isPeek ? 0 : LittleMetrics.edgeInset
        page.frame = NSRect(x: inset, y: b.minY + inset, width: max(0, b.width - 2 * inset), height: max(0, b.height - barH - inset))
        page.layer?.cornerRadius = pageCornerRadius
        for sub in page.subviews where sub.frame != page.bounds { sub.frame = page.bounds }
        onPageFrame?(convert(page.frame, to: nil))
    }

    /// The page's bottom corners follow the window's, just inside its rim.
    var pageCornerRadius: CGFloat {
        if isPeek { return PeekLayout.cornerRadius }
        guard let window = window as? LittleWindow, !window.styleMask.contains(.fullScreen) else { return 0 }
        return max(0, window.systemCornerRadius - LittleMetrics.edgeInset)
    }
}

/// Traffic lights at Arc's spots (x 17/39/61, centred on the strip), grey until the pointer is
/// over them.
/// A panel like Little Arc's, so it can open on another app's full-screen Space (#186), that
/// otherwise acts as the window it was: main when titled, Escape left to the page and the app.
final class LittleWindow: NSPanel {
    /// The traffic lights are grey until the pointer is over them (Arc 1.172.1, 10 Nov 2026: three grey
    /// discs at rest, red ×, yellow − and green over the group, even with the window in front). Reporting
    /// them inactive draws the grey; AppKit colours the group while the pointer is on it (#329). The
    /// browser window keeps its lights coloured (see CraWindow).
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton type: UInt) -> Bool { false }
    /// Arc's open animation: ~120 ms from a small rectangle to the full frame.
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { LittleMetrics.openDuration }
    /// A Peek is borderless (Arc's card has no title bar) but still takes the keyboard, unless it
    /// waits on its tab out of sight (#242).
    var isParked = false
    override var canBecomeKey: Bool { !isParked }
    /// A panel never becomes main; a titled window did, and the browser window's active look
    /// and the page's hover state follow the main window.
    override var canBecomeMain: Bool { styleMask.contains(.titled) }
    /// NSPanel closes itself on Escape; a window passes it on.
    override func cancelOperation(_ sender: Any?) {
        nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
    }
    /// A non-activating panel takes clicks without bringing Cra forward; a window brings it.
    override func sendEvent(_ event: NSEvent) {
        if styleMask.contains(.nonactivatingPanel), !NSApp.isActive,
           [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            NSApp.activate(ignoringOtherApps: true)
        }
        // The page is a Chromium child window. With it key, a press on the bar reached the button
        // but its release never came, so Back, Forward, Refresh, the address and "Open in" did
        // nothing (GitHub #195). The browser window makes the window under a click key first for
        // its own children (MainWindowController.installChildClickMonitor); this window does too.
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), !isKeyWindow, canBecomeKey,
           NSApp.isActive, NSApp.keyWindow?.parent === self {
            makeKey()
        }
        super.sendEvent(event)
    }

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
        super.init(contentRect: NSRect(x: 0, y: 0, width: LittleMoveMenu.width, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        // Arc's menu is whole in the first frame after the click (#331): no system fade.
        animationBehavior = .none
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
    private let gradient = CAGradientLayer()
    private let pill = NSView()
    /// The magnifier, or the open padlock for a page that isn't served over https (#330).
    private let search = NSImageView()
    private var isInsecure = false
    /// For `cra://debug?littleShown`: the padlock and the pill's text.
    var debugReadout: String { "padlock=\(isInsecure ? 1 : 0) address=\(urlLabel.stringValue)" }
    private let urlLabel = NSTextField.sidebarLabel(size: 13)
    private let puzzle = LittleIconView(symbol: "puzzlepiece.extension", size: 15)
    private let link = LittleIconView(symbol: "link", size: 14)
    private let profileChip = LittleProfileChip()
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
        gradient.colors = [LittlePalette.stripLeft.cgColor, LittlePalette.stripRight.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.insertSublayer(gradient, at: 0)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.layer?.cornerCurve = .continuous
        addSubview(pill)
        search.wantsLayer = true
        search.layer?.cornerRadius = 5
        search.layer?.cornerCurve = .continuous
        search.imageScaling = .scaleNone
        showSecurity(insecure: false)
        pill.addSubview(search)
        urlLabel.textColor = NSColor(LittlePalette.text)
        urlLabel.alignment = .center
        pill.addSubview(urlLabel)
        pill.addSubview(puzzle)
        pill.addSubview(link)
        pill.addSubview(profileChip)
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
        let (url, hover, popupOpen, space, spaces, profile, waiting) = withObservationTracking {
            (state.url, state.hover, state.popupOpen, store.space(state.targetSpaceID) ?? store.focusedSpace, store.spaceOrder.count,
             // Arc's shouldShowProfileIndicators: only once there is a profile besides Default.
             store.profiles.isEmpty ? nil : store.profile(state.profileID)?.name ?? "Default", state.awaitsFirstResponse)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        let chevronShown = LittleMoveMenu.showsChevron(spaces: spaces)
        if state.showsChevron != chevronShown { state.showsChevron = chevronShown }
        divider.isHidden = !chevronShown
        chevronPart.isHidden = !chevronShown
        // Arc shows the host alone; a page without one (an internal page, a file) keeps its address.
        urlLabel.stringValue = url.isEmpty ? "" : LittleAddress.host(of: url) ?? SuggestionEngine.humanURL(url)
        // Arc keeps the magnifier while a first response is awaited.
        showSecurity(insecure: !waiting && LittleAddress.isInsecure(url))
        pill.toolTip = url
        pill.layer?.backgroundColor = NSColor(hover == .pill ? LittlePalette.pillHover : LittlePalette.pill).cgColor
        puzzle.hovered = hover == .puzzle
        link.hovered = hover == .link
        profileChip.isHidden = profile == nil
        profileChip.name = profile ?? ""
        profileChip.hovered = hover == .profile
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

    /// The pill starts with a magnifier; a page that isn't served over https gets Arc's open padlock
    /// instead, orange on a pale orange tile (#330).
    private func showSecurity(insecure: Bool) {
        isInsecure = insecure
        search.layer?.backgroundColor = insecure ? LittlePalette.insecure.withAlphaComponent(0.10).cgColor : nil
        search.image = SidebarSymbols.image(insecure ? "lock.open" : "magnifyingglass", size: 13, weight: .medium)
        search.contentTintColor = insecure ? LittlePalette.insecure : NSColor(LittlePalette.icon)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let w = bounds.width, ch = LittleMetrics.controlHeight, y: CGFloat = 8
        // Open button: 10 + "Open in <space>" + 6 + ⌘O (5 + text + 5) + 8 | 1 | 29 (no ⌄ with one space).
        let tw = ceil(openLabel.attributedStringValue.size().width)
        let bw = ceil(badgeLabel.attributedStringValue.size().width) + 10
        let partW = 10 + tw + 6 + bw + 8
        let openW = partW + (state.showsChevron ? 1 + LittleMetrics.chevronWidth : 0)
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
        // The padlock's tile sits 4 pt in from the pill's left and top, 22 pt square.
        search.frame = isInsecure ? NSRect(x: 4, y: 4, width: 22, height: ch - 8) : NSRect(x: 0, y: 0, width: 34, height: ch)
        // The URL is centred over the whole pill, 80 pt clear of each end.
        link.frame = NSRect(x: pillW - 2 - 26, y: 2, width: 26, height: 26)
        puzzle.frame = NSRect(x: pillW - 2 - 26 - 5 - 26, y: 2, width: 26, height: 26)
        let chipW = profileChip.isHidden ? 0 : profileChip.fittingWidth
        profileChip.frame = NSRect(x: pillW - LittleMetrics.profileChipTrailing - chipW, y: (ch - LittleProfileChip.height) / 2,
                                   width: chipW, height: LittleProfileChip.height)
        if state.profileChipWidth != chipW { state.profileChipWidth = chipW }
        // The URL stays centred, clear of the chip on both sides.
        let clear = max(80, chipW > 0 ? LittleMetrics.profileChipTrailing + chipW + 8 : 80)
        urlLabel.frame = NSRect(x: clear - SidebarText.inset, y: (ch - 16) / 2, width: max(0, pillW - 2 * clear) + 2 * SidebarText.inset, height: 16)
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
            if !chevronPart.isHidden, chevronPart.frame.contains(openButton.convert(p, from: self)) { actions.togglePopup() }
            else if !state.url.isEmpty { actions.promote(nil) }
        } else if pill.frame.contains(p) {
            let q = pill.convert(p, from: self)
            if link.frame.contains(q) { actions.copyURL() }
            else if !profileChip.isHidden, profileChip.frame.contains(q) { actions.showProfileMenu(profileChip) }
            else if !puzzle.frame.contains(q) { actions.openCommandBar() }
        }
    }
}

/// Arc's ProfileIndicatorView in the Little Arc's address field (URLField.Accessory.profileIndicator):
/// the profile smiley ("archie"), the profile's name and a chevron, as it opens the profile menu, on
/// ProfileIndicatorBackgroundColor (dark: white at 31/255). Sized like the profile pill in Arc's tips.
final class LittleProfileChip: NSView {
    static let height: CGFloat = 22
    private let face = ProfileAvatarView(frame: NSRect(x: 6, y: 4, width: 14, height: 14))
    private let label = NSTextField.sidebarLabel(size: 11, weight: .medium)
    private let chevron = NSImageView()
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    var name = "" { didSet { if name != oldValue { label.stringValue = name; needsLayout = true } } }
    var hovered = false {
        didSet {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(hovered ? 46 / 255 : 31 / 255).cgColor
            let ink = NSColor(hovered ? LittlePalette.iconHot : LittlePalette.text)
            label.textColor = ink
            face.ink = ink
            chevron.contentTintColor = ink
        }
    }

    var fittingWidth: CGFloat {
        let textW = ceil((name as NSString).size(withAttributes: [.font: Self.font]).width)
        return 6 + 14 + 3 + textW + 4 + 8 + 6
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        label.font = Self.font
        label.lineBreakMode = .byClipping
        chevron.image = SidebarSymbols.image("chevron.down", size: 8, weight: .bold)
        chevron.imageScaling = .scaleNone
        addSubview(face)
        addSubview(label)
        addSubview(chevron)
        hovered = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let textW = ceil((name as NSString).size(withAttributes: [.font: Self.font]).width)
        let th = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: 6 + 14 + 3 - SidebarText.inset, y: (Self.height - th) / 2, width: textW + 2 * SidebarText.inset, height: th)
        chevron.frame = NSRect(x: 6 + 14 + 3 + textW + 4, y: 0, width: 8, height: Self.height)
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

/// Arc's LittleBrowserMoveMenu (`LittleMoveMenu`): "Search Spaces…" with a chevron-up button, then
/// one 46 pt row per space (a 26 pt tile with the emoji on the space colour) in a list that
/// scrolls past 350 pt, or "No results". The space "Open in" names leads, highlighted.
@MainActor
final class LittleSpacesPopup: NSView, NSTextFieldDelegate {
    private let state: LittleWindowState
    private let store: SidebarStore
    private let onPick: (UUID) -> Void
    private let onClose: () -> Void
    private let field = NSTextField()
    private let close = NSView()
    private let divider = NSView()
    private let scroll = NSScrollView()
    private let listView = FlippedView()
    private let empty = NSTextField.sidebarLabel(size: 13)
    private var rows: [NSView] = []
    private var list: [Space] = []
    private var selected = 0 { didSet { refreshSelection(); revealSelected() } }
    private var revealOnLayout = true

    init(state: LittleWindowState, store: SidebarStore, onPick: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.onPick = onPick
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LittlePalette.buttonNS.cgColor
        layer?.cornerRadius = LittleMoveMenu.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = LittleMoveMenu.border
        layer?.borderColor = NSColor(LittlePalette.buttonBorder).cgColor
        let h = LittleMoveMenu.headerHeight
        let glass = NSImageView(frame: NSRect(x: 16, y: 0, width: 14, height: h))
        glass.image = SidebarSymbols.image("magnifyingglass", size: 13, weight: .medium)
        glass.contentTintColor = NSColor(LittlePalette.moveMenuGlyph)
        glass.imageScaling = .scaleNone
        addSubview(glass)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = NSColor.white.withAlphaComponent(0.9)
        field.placeholderAttributedString = NSAttributedString(string: "Search Spaces...", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(LittlePalette.moveMenuPlaceholder)])
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        // Arc 1.172.1: a plain ∧ after an 18 pt rule (1.168 had a filled 28 pt button).
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(LittlePalette.buttonBorder).cgColor
        addSubview(divider)
        let up = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        up.image = SidebarSymbols.image("chevron.up", size: 11, weight: .semibold)
        up.contentTintColor = NSColor(LittlePalette.moveMenuGlyph)
        up.imageScaling = .scaleNone
        close.addSubview(up)
        addSubview(close)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = listView
        addSubview(scroll)
        empty.stringValue = "No results"
        empty.alignment = .center
        empty.textColor = NSColor(LittlePalette.moveMenuGlyph)
        addSubview(empty)
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
        let spaces = LittleMoveMenu.order(store.orderedSpaces.map(\.id), target: state.targetSpaceID).compactMap(store.space)
        list = q.isEmpty ? spaces : spaces.filter { $0.title.lowercased().contains(q) }
        rows.forEach { $0.removeFromSuperview() }
        let rh = LittleMoveMenu.rowHeight, ts = LittleMoveMenu.tileSize
        rows = list.map { s in
            let row = FlippedView()
            row.wantsLayer = true
            let tile = NSView(frame: NSRect(x: LittleMoveMenu.tileX, y: (rh - ts) / 2, width: ts, height: ts))
            tile.wantsLayer = true
            tile.layer?.cornerRadius = LittleMoveMenu.tileRadius
            tile.layer?.cornerCurve = .continuous
            tile.layer?.backgroundColor = NSColor(hex: s.theme.shown.accent ?? s.theme.shown.colors.first ?? "#888888").cgColor
            // Arc 1.172.1: a 12 pt emoji, centred (a 🍎 12.5 pt wide in the 26 pt tile).
            let emoji = NSTextField.sidebarLabel(size: 12)
            emoji.stringValue = s.emoji
            emoji.alignment = .center
            emoji.frame = NSRect(x: -SidebarText.inset, y: (ts - 15) / 2 + 1, width: ts + 2 * SidebarText.inset, height: 15)
            tile.addSubview(emoji)
            if let name = s.symbol {
                let glyph = NSImageView(frame: NSRect(x: 0, y: 0, width: ts, height: ts))
                glyph.image = SidebarSymbols.image(name, size: 11, weight: .medium)
                glyph.imageScaling = .scaleNone
                glyph.contentTintColor = .white
                tile.addSubview(glyph)
            }
            row.addSubview(tile)
            let title = NSTextField.sidebarLabel(size: LittleMoveMenu.titleSize, weight: .semibold)
            title.stringValue = s.title
            title.textColor = NSColor.white.withAlphaComponent(0.82)
            let tx = LittleMoveMenu.textX
            title.frame = NSRect(x: tx - SidebarText.inset, y: (rh - 16) / 2,
                                 width: LittleMoveMenu.width - tx - 14 + 2 * SidebarText.inset, height: 16)
            row.addSubview(title)
            listView.addSubview(row)
            return row
        }
        empty.isHidden = !list.isEmpty
        // The menu grows and shrinks with the list, its top edge where it was.
        if let window {
            let f = window.frame, h = LittleMoveMenu.frame(rows: list.count, in: .zero).height
            if f.height != h { window.setFrame(NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h), display: true) }
        }
        needsLayout = true
        refreshSelection()
    }

    private func refreshSelection() {
        for (i, r) in rows.enumerated() {
            r.layer?.backgroundColor = i == selected ? NSColor(LittlePalette.buttonHover).cgColor : nil
        }
    }

    /// Scrolls the list so the selected row is whole (arrow keys past the visible rows).
    private func revealSelected() {
        guard rows.indices.contains(selected) else { return }
        let clip = scroll.contentView
        let y = LittleMoveMenu.scrollOffset(showing: selected, from: clip.bounds.minY, rows: rows.count)
        guard y != clip.bounds.minY else { return }
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    override func layout() {
        super.layout()
        let h = LittleMoveMenu.headerHeight, w = bounds.width
        // Measured from the menu's right edge: the ∧ centred 22 pt in, the rule 38 pt in.
        close.frame = NSRect(x: w - 22 - 8, y: (h - 16) / 2, width: 16, height: 16)
        divider.frame = NSRect(x: w - 38, y: (h - 18) / 2, width: 1, height: 18)
        let fx = LittleMoveMenu.textX
        let fh = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: fx - SidebarText.inset, y: (h - fh) / 2, width: divider.frame.minX - 8 - fx + 2 * SidebarText.inset, height: fh)
        let rh = LittleMoveMenu.rowHeight
        scroll.frame = NSRect(x: 0, y: h, width: w, height: max(0, bounds.height - h))
        listView.frame = NSRect(x: 0, y: 0, width: w, height: CGFloat(rows.count) * rh)
        for (i, r) in rows.enumerated() {
            r.frame = NSRect(x: 0, y: CGFloat(i) * rh, width: w, height: rh)
        }
        empty.frame = NSRect(x: -SidebarText.inset, y: h + (LittleMoveMenu.noResultsHeight - 16) / 2, width: w + 2 * SidebarText.inset, height: 16)
        if revealOnLayout { revealOnLayout = false; revealSelected() }
    }

    // MARK: Debug (cra://debug?littleMenu=…)

    /// rows, the first row, the highlighted one, how far the list is scrolled and whether the
    /// highlighted row is whole in view.
    var debugState: String {
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView.bounds
        let shown = rows.indices.contains(selected) && clip.contains(rows[selected].frame)
        let name = { (i: Int) in self.list.indices.contains(i) ? self.list[i].title : "-" }
        return String(format: "rows=%d first=%@ selected=%@ scroll=%.0f inView=%d empty=%d", list.count, name(0), name(selected),
                      clip.minY, shown ? 1 : 0, empty.isHidden ? 0 : 1)
    }

    func debugMove(down n: Int) {
        for _ in 0..<n where !list.isEmpty { selected = (selected + 1) % list.count }
    }

    func debugType(_ text: String) {
        field.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    // MARK: Keys and pointer

    func controlTextDidChange(_ obj: Notification) {
        rebuild()
        layoutSubtreeIfNeeded()
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

    /// The row under the pointer, if it is over the visible list.
    private func row(at event: NSEvent) -> Int? {
        guard scroll.frame.contains(convert(event.locationInWindow, from: nil)) else { return nil }
        let p = listView.convert(event.locationInWindow, from: nil)
        return rows.firstIndex { $0.frame.contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        if let i = row(at: event), i != selected { selected = i }
    }

    /// Clicks on the list land here (the rows only draw); its scroller keeps its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, hit !== scroll, hit.isDescendant(of: scroll), !(hit is NSScroller) { return self }
        return hit
    }

    override func scrollWheel(with event: NSEvent) {
        if scroll.frame.contains(convert(event.locationInWindow, from: nil)) { scroll.scrollWheel(with: event) }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if close.frame.contains(convert(event.locationInWindow, from: nil)) { onClose(); return }
        if let i = row(at: event), list.indices.contains(i) { onPick(list[i].id) }
    }
}
