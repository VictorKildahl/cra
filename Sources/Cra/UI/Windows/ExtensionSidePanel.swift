import AppKit
import CraCEF

/// An extension's side panel (Chrome's chrome.sidePanel) as a card on the right of the window's
/// panes: a header with the extension's icon, name and a close button, and the panel page under
/// it. Arc has no side panel, so extensions that open in one (MetaMask by default) did nothing
/// there; Chrome shows it beside the page, and so does Cra.
final class ExtensionSidePanelCard: NSView {
    static let headerHeight: CGFloat = 36

    /// Where the panel page's views go (EmbeddedPages), or where its window is laid over.
    let pageArea = NSView()
    private let header = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    let closeButton = ToolbarGlyphButton()
    private let hairline = NSView()
    private let shadowView = CardShadowView()
    var cornerRadius: CGFloat = CraMetrics.contentCornerRadius {
        didSet { layer?.cornerRadius = cornerRadius; syncShadow() }
    }
    var castsShadow = true { didSet { syncShadow() } }
    private var appearanceObservation: NSKeyValueObservation?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        pageArea.wantsLayer = true
        pageArea.autoresizesSubviews = false
        hairline.wantsLayer = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        header.addSubview(icon)
        header.addSubview(title)
        header.addSubview(closeButton)
        addSubview(pageArea)
        addSubview(header)
        addSubview(hairline)
        refreshColors()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshColors() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(name: String, icon image: NSImage?) {
        title.stringValue = name
        icon.image = image ?? SidebarSymbols.image("puzzlepiece.extension", size: 14)
        refreshColors()
    }

    /// The panel page follows the app's appearance, as pages do; the header matches it.
    private func refreshColors() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = CraBrowser.pageCanvasColor.cgColor
        header.wantsLayer = true
        header.layer?.backgroundColor = CraBrowser.pageCanvasColor.cgColor
        let ink = dark ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0, alpha: 0.8)
        title.textColor = ink
        hairline.layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: 0.08).cgColor
        closeButton.configure(symbol: "xmark", image: nil, help: "Close Side Panel", enabled: true, width: 26, iconSize: 11,
                              tint: ink.withAlphaComponent(0.7), hover: NSColor(white: dark ? 1 : 0, alpha: 0.08))
    }

    override func layout() {
        super.layout()
        let b = bounds, h = Self.headerHeight
        header.frame = NSRect(x: 0, y: b.height - h, width: b.width, height: h)
        icon.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
        closeButton.frame = NSRect(x: b.width - 8 - 26, y: (h - 26) / 2, width: 26, height: 26)
        let titleH = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(x: icon.frame.maxX + 8, y: (h - titleH) / 2, width: max(0, closeButton.frame.minX - icon.frame.maxX - 16), height: titleH)
        hairline.frame = NSRect(x: 0, y: b.height - h - 1, width: b.width, height: 1)
        pageArea.frame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - h - 1))
        EmbeddedPages.place(pageArea.subviews, in: pageArea.bounds)
    }

    // The same shadow as a page card (PaneCardView): a sibling behind it.
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
    override var isHidden: Bool { didSet { syncShadow() } }

    private func syncShadow() {
        let on = castsShadow && cornerRadius > 0 && !isHidden && superview != nil
        shadowView.isHidden = !on
        guard on else { return }
        shadowView.cornerRadius = cornerRadius
        let f = frame.insetBy(dx: -CardShadowView.pad, dy: -CardShadowView.pad)
        if shadowView.frame != f { shadowView.frame = f }
    }
}

/// One main window's extension side panel: shows, swaps and hides the panel page as extensions
/// ask (ExtensionSidePanelRequest decides), in its own Cra browser on the asking page's profile.
@MainActor
final class ExtensionSidePanelController: NSObject, @preconcurrency CraBrowserDelegate {
    private unowned let app: AppDelegate
    private unowned let shell: ShellView
    private weak var owner: MainWindowController?
    private var mainWindow: NSWindow? { owner?.window }
    private(set) var state: ExtensionSidePanelState?
    private var browser: CraBrowser?
    /// The panel page's own page target, so a request from the panel itself
    /// (chrome.sidePanel.close() in it) finds this window.
    private(set) var pageTarget: String?
    /// The page's area in window coordinates, nil while the shell shows no panel.
    private var bodyRect: NSRect?
    /// Page windows already made borderless and adopted (weakly keyed by identity; one per browser).
    private var attachedOnce: Set<ObjectIdentifier> = []

    private static let widthKey = "extensionSidePanelWidth"
    static var savedWidth: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: widthKey) as? Double ?? ExtensionSidePanelWidth.initial) }
        set { UserDefaults.standard.set(Double(newValue), forKey: widthKey) }
    }

    init(app: AppDelegate, shell: ShellView, owner: MainWindowController) {
        self.app = app
        self.shell = shell
        self.owner = owner
        super.init()
        shell.sidePanel.closeButton.action = { [weak self] in self?.hide() }
        shell.onSidePanelFrame = { [weak self] rect in self?.place(rect) }
        shell.sidePanelHandle.onDrag = { [weak self] dx in self?.resize(by: dx) }
    }

    var isShowing: Bool { state != nil }

    /// Owns the browser `b` (the panel page).
    func owns(_ b: CraBrowser) -> Bool { browser === b }

    /// `profilePath`: the asking page's profile folder (nil = Default), where the panel loads.
    func handle(_ request: ExtensionSidePanelRequest, profilePath: String?) {
        switch request.change(from: state) {
        case .none: return
        case .hide: hide()
        case .show(let wanted): show(wanted, profilePath: profilePath)
        }
    }

    private func show(_ wanted: ExtensionSidePanelState, profilePath: String?) {
        let sameExtension = state.map { $0.extensionID == wanted.extensionID && $0.profile == wanted.profile } ?? false
        state = wanted
        CraLog.note("side panel shows \(wanted.extensionID) in \(wanted.profile)")
        let entry = ExtensionStore.shared.entries.first { $0.extensionID == wanted.extensionID }
        shell.sidePanel.show(name: entry?.name ?? "Extension", icon: entry?.icon)
        if sameExtension, let browser {
            // Another page of the same panel (chrome.sidePanel.setOptions with a new path).
            browser.loadURL(wanted.url)
        } else {
            closeBrowser()
            let b = CraBrowser(frame: NSRect(x: 0, y: 0, width: ExtensionSidePanelWidth.initial, height: 600), url: wanted.url,
                               delegate: self, incognito: false, profilePath: profilePath)
            browser = b
            if let host = b.hostWindow { attach(host) }
            Task { [weak self] in await self?.resolvePageTarget(of: b) }
        }
        shell.sidePanelWidth = Self.savedWidth
    }

    func hide() {
        guard let shown = state else { return }
        CraLog.note("side panel hides \(shown.extensionID)")
        state = nil
        closeBrowser()
        shell.sidePanelWidth = 0
    }

    private func closeBrowser() {
        pageTarget = nil
        attachedOnce.removeAll()
        guard let b = browser else { return }
        browser = nil
        if let host = b.hostWindow {
            if let views = EmbeddedPages.pageViews(of: host) { for v in views { v.removeFromSuperview() } }
            host.parent?.removeChildWindow(host)
            host.orderOut(nil)
        }
        b.close()
    }

    private func resolvePageTarget(of b: CraBrowser) async {
        let info: [String: Any]? = await withCheckedContinuation { cont in
            b.sendDevToolsMethod("Target.getTargetInfo", params: "{}") { result, _ in
                cont.resume(returning: result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
            }
        }
        guard browser === b else { return }
        pageTarget = (info?["targetInfo"] as? [String: Any])?["targetId"] as? String
    }

    private func resize(by dx: CGFloat) {
        let container = Double(shell.contentContainer.bounds.width)
        let w = ExtensionSidePanelWidth.clamp(Double(shell.sidePanelWidth - dx), container: container, gap: Double(SplitPaneLayout.Constants.gap),
                                              pages: shell.sidePanelPageMinimum)
        Self.savedWidth = CGFloat(w)
        shell.sidePanelWidth = CGFloat(w)
    }

    // MARK: Page placement

    /// Like a tab's page (MainWindowController.browserManagerPageWindowsChanged): Chrome's window
    /// stays, borderless and empty, over the panel; its page views move into the card.
    private func attach(_ host: NSWindow) {
        guard let mainWindow, attachedOnce.insert(ObjectIdentifier(host)).inserted else { return }
        host.styleMask.remove([.titled, .resizable])
        host.styleMask.insert(.fullSizeContentView)
        ChromiumWindowCorners.setSquare(true, for: host)
        ChromiumChildHover.setDocked(true, for: host)
        host.titlebarAppearsTransparent = true
        host.titleVisibility = .hidden
        host.isMovable = false
        host.hasShadow = false
        host.isOpaque = false
        host.backgroundColor = .clear
        if let cv = host.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = CraMetrics.contentCornerRadius
            cv.layer?.cornerCurve = .continuous
            cv.layer?.maskedCorners = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cv.layer?.masksToBounds = true
        }
        mainWindow.addChildWindow(host, ordered: .above)
        // Shown and raised under the overlay panels there, or ordered out while the panel has no room.
        place(bodyRect)
        if host.isVisible { owner?.sidePanelPageAttached() }
    }

    private func place(_ rect: NSRect?) {
        bodyRect = rect
        guard let mainWindow, let host = browser?.hostWindow, attachedOnce.contains(ObjectIdentifier(host)) else { return }
        guard let rect else {
            // The panel does not fit (a narrow window, a page in full screen): out of sight, as
            // a hidden tab's window is. Left on screen it stayed where the panel was, outside
            // a window that had just shrunk.
            host.contentView?.isHidden = true
            if let views = EmbeddedPages.pageViews(of: host) { for v in views { v.removeFromSuperview() } }
            if host.isVisible { host.orderOut(nil) }
            return
        }
        // Back from hidden: ordering out can take a child window off its parent.
        if host.parent !== mainWindow { mainWindow.addChildWindow(host, ordered: .above) }
        let target = mainWindow.convertToScreen(rect)
        if host.frame != target { host.setFrame(target, display: false) }
        if let cv = host.contentView, cv.frame.size != target.size { cv.frame = NSRect(origin: .zero, size: target.size) }
        host.contentView?.isHidden = false
        if !host.isVisible {
            host.orderFront(nil)
            owner?.sidePanelPageAttached()
        }
        guard EmbeddedPages.isEnabled, let views = EmbeddedPages.pageViews(of: host) else { return }
        EmbeddedPages.markHost(host)
        let area = shell.sidePanel.pageArea
        if views.contains(where: { $0.superview !== area }) { for v in views { area.addSubview(v) } }
        EmbeddedPages.place(views, in: area.bounds)
    }

    /// The panel page's views (embedded in the card), so the window keeps its focus there.
    var embeddedViews: [NSView] {
        guard let host = browser?.hostWindow else { return [] }
        return EmbeddedPages.pageViews(of: host) ?? []
    }

    // MARK: CraBrowserDelegate

    func browser(_ browser: CraBrowser, didChangeTitle title: String) {}
    func browser(_ browser: CraBrowser, didChangeURL url: String) {}
    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {}
    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) {}
    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {}
    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {}
    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {}
    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) {}
    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {}
    /// Links the panel opens go to tabs in this window, as Chrome opens them in its window.
    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {
        openTab(url, select: !background)
    }
    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? {
        openTab(url, select: !background)
        return nil
    }
    private func openTab(_ url: String, select: Bool) {
        guard let owner else { return }
        app.store.createTab(url: url, select: select, window: owner.windowID)
    }
    func devToolsHostView(for browser: CraBrowser) -> NSView? { nil }
    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {}
    func browserDidCloseDevTools(_ browser: CraBrowser) {}
    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) {
        guard self.browser === browser else { return }
        attach(window)
    }
    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {}
    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {}
    func browser(_ browser: CraBrowser, handleKeyEvent event: NSEvent) -> Bool { app.handleReservedKey(event) }
    func browser(_ browser: CraBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool { app.handleUnhandledKey(event) }
    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) { app.main.browserManager(download: download) }
    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    func browserDidReceiveFocus(_ browser: CraBrowser) {}
    /// window.close() in the panel page (MetaMask's "switch to popup view" does it): the panel goes.
    func browserDidClose(_ browser: CraBrowser) {
        guard self.browser === browser else { return }
        CraLog.note("side panel page closed itself")
        self.browser = nil
        state = nil
        pageTarget = nil
        attachedOnce.removeAll()
        if let host = browser.hostWindow {
            if let views = EmbeddedPages.pageViews(of: host) { for v in views { v.removeFromSuperview() } }
            host.parent?.removeChildWindow(host)
        }
        shell.sidePanelWidth = 0
    }
}

extension ExtensionSidePanelController {
    /// The window a request is for: the one whose panel page asked, else the one showing the
    /// asking tab, else the window in use (a Little Window's page). The panel loads in the
    /// asking page's profile.
    static func route(_ request: ExtensionSidePanelRequest, tab: UUID?, app: AppDelegate) {
        let windows = app.mainWindows
        let owner = windows.first { $0.sidePanel.pageTarget == request.targetID }
            ?? tab.flatMap { id in windows.first { $0.browsers.runtime(for: id) != nil } }
            ?? app.main
        owner?.sidePanel.handle(request, profilePath: profilePath(request.profile))
    }

    /// Chromium's profile folder name as CraBrowser takes it: nil for Default.
    static func profilePath(_ directoryName: String) -> String? {
        directoryName == "Default" || directoryName.isEmpty ? nil
            : AppPaths.chromiumCache.appendingPathComponent(directoryName, isDirectory: true).path
    }
}
