import AppKit
import CraCEF

/// One live Chromium browser for a tab. Tabs that have not been opened since
/// launch have no runtime; archiving a tab destroys its runtime.
@MainActor
final class TabRuntime {
    let tabID: UUID
    let browser: CraBrowser
    var progress: Double = 0
    var themeColor: String = ""
    /// What the page paints behind its content ("#RRGGBB", "" until reported).
    var backgroundColor: String = ""
    /// Cra popped this tab's video out because the user left the tab (Arc's
    /// auto Picture in Picture); coming back brings the video home.
    var autoPictureInPicture = false
    var pendingAutoPictureInPicture = false
    /// The tab switcher's thumbnail, taken while the page was last on screen.
    var snapshot: NSImage?
    var snapshotWork: DispatchWorkItem?
    /// When the page last went off screen (nil while shown); tab sleeping counts from here.
    var hiddenAt: Date? = Date()
    /// Invalidates a pending sleep probe even when navigation returns to the same URL.
    var navigationRevision: UInt = 0
    /// Chrome-style hosting: the page's own window (nil until created, or for Alloy).
    var hostWindow: NSWindow? { browser.hostWindow }
    init(tabID: UUID, browser: CraBrowser) {
        self.tabID = tabID
        self.browser = browser
    }
}

@MainActor
protocol BrowserManagerDelegate: AnyObject {
    func browserManagerDidUpdate(_ tabID: UUID)
    func browserManager(statusMessage: String)
    /// Find in page results for the visible tab; -1 = no new value.
    func browserManager(findMatches count: Int, activeMatch: Int)
    func browserManager(download: CraDownloadInfo)
    func browserManager(fullscreen: Bool, tabID: UUID)
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView?
    /// A DevTools pane appeared or closed; the shell decides whether to show the dock.
    func browserManagerDevToolsChanged()
    /// Chrome's docked frontend moved its page placeholder (streamed while its splitter is dragged).
    func browserManagerDevToolsPageBoundsChanged()
    /// Chrome-style hosting: page windows appeared/changed; the shell re-attaches and orders them.
    func browserManagerPageWindowsChanged(focus: Bool)
    func browserManagerHandleKey(_ event: NSEvent) -> Bool
    func browserManagerHandleUnhandledKey(_ event: NSEvent) -> Bool
    func browserManagerFocusedBrowser(_ tabID: UUID)
    /// The page closed itself (window.close()).
    func browserManagerPageClosedTab(_ tabID: UUID)
    /// Arc's Peek: a link the user clicked (or Shift-clicked) in `tabID`, whose page is at
    /// `pageURL`. Return true when it opens in a Peek instead.
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool) -> Bool
}

/// Creates, shows, hides and tears down CEF browsers inside a container view.
@MainActor
final class BrowserManager: NSObject, @preconcurrency CraBrowserDelegate {
    let store: SidebarStore
    let favicons: FaviconCache
    let container: NSView
    weak var delegate: BrowserManagerDelegate?
    private(set) var runtimes: [UUID: TabRuntime] = [:]
    /// The focused pane's tab (the one toolbar actions and DevTools apply to).
    private(set) var visibleTabID: UUID?
    /// Every tab on screen, in pane order (one entry outside split view).
    private(set) var visibleTabIDs: [UUID] = []
    /// Split view: the view a tab's Alloy-hosted Chromium view should live in.
    var paneHost: ((UUID) -> NSView?)?
    /// The browser window this manager shows pages in (tabs it opens are selected there).
    var windowID: UUID?
    /// A tab's live page held by another window's manager, handed over (see `release`).
    var takeRuntimeFromOtherWindow: ((UUID) -> TabRuntime?)?
    private var byBrowser: [ObjectIdentifier: UUID] = [:]
    /// CEF's client holds its owner weakly; keep retired browsers alive until teardown finishes.
    private var closingBrowsers: [ObjectIdentifier: CraBrowser] = [:]

    init(store: SidebarStore, favicons: FaviconCache, container: NSView) {
        self.store = store
        self.favicons = favicons
        self.container = container
    }

    func runtime(for tabID: UUID) -> TabRuntime? { runtimes[tabID] }
    var visibleRuntime: TabRuntime? { visibleTabID.flatMap { runtimes[$0] } }

    @discardableResult
    func ensureRuntime(for tabID: UUID) -> TabRuntime? {
        if let r = runtimes[tabID] { return r }
        // An empty split pane has no page yet (Arc shows the tinted card and the command bar).
        guard let item = store.item(tabID), let tab = item.tab, !item.isEmptyTab else { return nil }
        // The page moves between windows with its history and state, never loads twice.
        if let rt = takeRuntimeFromOtherWindow?(tabID) {
            rt.browser.delegate = self
            add(rt)
            if inRightProfile(rt) { return rt }
            release(tabID)?.browser.close()
        }
        let browser = CraBrowser(frame: container.bounds, url: tab.url, delegate: self, incognito: store.isIncognito(item: tabID),
                                 profilePath: store.profilePath(item: tabID))
        return register(browser: browser, tabID: tabID)
    }

    /// Take over a live browser from elsewhere (a Little Window being promoted
    /// to a tab): it keeps its history, scroll position and page state.
    @discardableResult
    func adopt(_ browser: CraBrowser, for tabID: UUID) -> TabRuntime {
        if let host = browser.hostWindow, let parent = host.parent { parent.removeChildWindow(host) }
        browser.containerView.removeFromSuperview()
        browser.delegate = self
        let rt = register(browser: browser, tabID: tabID)
        store.updateTab(tabID, url: browser.currentURL, title: browser.currentTitle)
        return rt
    }

    /// Popup host: a browser shell CEF will fill with window.open content.
    func makePopupHost(for tabID: UUID) -> CraBrowser {
        let browser = CraBrowser(frame: container.bounds, url: nil, delegate: self, incognito: store.isIncognito(item: tabID),
                                 profilePath: store.profilePath(item: tabID))
        register(browser: browser, tabID: tabID)
        return browser
    }

    @discardableResult
    private func register(browser: CraBrowser, tabID: UUID) -> TabRuntime {
        browser.userInfo = tabID.uuidString
        let rt = TabRuntime(tabID: tabID, browser: browser)
        if let t = store.item(tabID)?.tab, t.muted { browser.setAudioMuted(true) }
        add(rt)
        return rt
    }

    private func add(_ rt: TabRuntime) {
        let v = rt.browser.containerView
        v.frame = container.bounds
        v.autoresizingMask = [.width, .height]
        v.isHidden = true
        container.addSubview(v)
        runtimes[rt.tabID] = rt
        byBrowser[ObjectIdentifier(rt.browser)] = rt.tabID
        // CEF creates the page window inside CraBrowser's init, before the tab is known here,
        // so didCreateHostWindow could not place it: a background tab's window stayed shown.
        if rt.browser.hostWindow != nil { delegate?.browserManagerPageWindowsChanged(focus: false) }
    }

    /// Gives up a tab's live page so another window can show it. Its DevTools close:
    /// their window belongs to this one.
    func release(_ tabID: UUID) -> TabRuntime? {
        guard let rt = runtimes.removeValue(forKey: tabID) else { return nil }
        byBrowser[ObjectIdentifier(rt.browser)] = nil
        rt.snapshotWork?.cancel()
        rt.snapshotWork = nil
        if rt.browser.hasDevTools { rt.browser.closeDevTools() }
        devToolsViews[tabID] = nil
        devToolsPlaceholders[tabID] = nil
        devToolsDockedState[tabID] = nil
        if visibleTabID == tabID { visibleTabID = nil }
        visibleTabIDs.removeAll { $0 == tabID }
        if let host = rt.hostWindow {
            // Embedded page views live in the pane card, outside their host window.
            // Detach them now; their cached identity remains available for a handoff.
            if EmbeddedPages.isHost(host), let views = EmbeddedPages.pageViews(of: host) {
                for view in views where view.superview !== host.contentView { view.removeFromSuperview() }
            }
            host.parent?.removeChildWindow(host)
            host.orderOut(nil)
        }
        rt.browser.containerView.removeFromSuperview()
        delegate?.browserManagerDevToolsChanged()
        return rt
    }

    func show(_ tabID: UUID?, focus: Bool) {
        show(tabID.map { [$0] } ?? [], focused: tabID, focus: focus)
    }

    /// Show several tabs at once (split view); `focused` gets keyboard focus.
    func show(_ tabIDs: [UUID], focused: UUID?, focus: Bool) {
        let newSet = Set(tabIDs)
        for previous in visibleTabIDs where !newSet.contains(previous) {
            leaveTab(previous)
            runtimes[previous]?.hiddenAt = Date()
        }
        let wasVisible = Set(visibleTabIDs)
        var shown: [UUID] = []
        for id in tabIDs {
            guard let rt = ensureRuntime(for: id) else { shown.append(id); continue }
            if !wasVisible.contains(id) { returnToTab(rt) }
            rt.hiddenAt = nil
            let v = rt.browser.containerView
            // Alloy hosting only: the Chromium view moves into its pane. Chrome-style
            // pages live in their own windows; re-parenting their view makes Chrome
            // spawn stock windows.
            if rt.browser.hostWindow == nil, let host = paneHost?(id), v.superview !== host {
                v.removeFromSuperview()
                host.addSubview(v)
            }
            v.frame = v.superview?.bounds ?? container.bounds
            v.isHidden = false
            shown.append(id)
        }
        for (id, other) in runtimes where !newSet.contains(id) {
            other.browser.containerView.isHidden = true
            if other.browser.hostWindow == nil, other.browser.containerView.superview !== container {
                other.browser.containerView.removeFromSuperview()
                container.addSubview(other.browser.containerView)
            }
        }
        visibleTabIDs = shown
        visibleTabID = focused.flatMap { newSet.contains($0) ? $0 : nil } ?? shown.first
        if wasVisible != Set(shown) { HitchMonitor.mark("page-shown") }
        if focus, let f = visibleTabID, let rt = runtimes[f] { rt.browser.setFocused(true) }
        for id in shown where !wasVisible.contains(id) { scheduleSnapshot(id) }
        syncDevToolsVisibility()
        delegate?.browserManagerPageWindowsChanged(focus: focus)
    }

    // MARK: Tab switcher thumbnails

    /// Chromium renders nothing for a hidden page, so thumbnails are taken while a tab is
    /// on screen: a moment after it appears or finishes loading, and when the switcher opens.
    private func scheduleSnapshot(_ id: UUID, after delay: TimeInterval = 1) {
        guard let rt = runtimes[id] else { return }
        rt.snapshotWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.captureSnapshot(id) }
        rt.snapshotWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The visible viewport, cropped to the switcher's thumbnail shape from the top.
    /// No `clip`: a clipped screenshot makes Chromium emulate the clip's size and scale on
    /// the live page, which drew the page shrunk into its corner for a few frames, a
    /// second after every tab switch and page load. Without one it copies the frame
    /// already on screen, and the crop and downscale happen here instead.
    func captureSnapshot(_ id: UUID, completion: (() -> Void)? = nil) {
        guard let rt = runtimes[id], visibleTabIDs.contains(id) else { completion?(); return }
        rt.browser.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"jpeg","quality":80,"optimizeForSpeed":true}"#) { [weak self, weak rt] shot, _ in
            DispatchQueue.global(qos: .utility).async {
                let image = shot.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { $0["data"] as? String }.flatMap { Data(base64Encoded: $0) }.flatMap(Self.thumbnail(fromViewport:))
                DispatchQueue.main.async {
                    if let image, let rt, self?.runtimes[id] === rt { rt.snapshot = image }
                    completion?()
                }
            }
        }
    }

    /// The top of the viewport at the thumbnail's aspect ratio, centred horizontally,
    /// at most twice the thumbnail's width in pixels.
    nonisolated private static func thumbnail(fromViewport data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil), full.width > 0, full.height > 0 else { return nil }
        let thumb = TabSwitcherMetrics.thumbnail
        let aspect = thumb.width / thumb.height
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let cw = min(w, h * aspect), ch = cw / aspect
        guard let crop = full.cropping(to: CGRect(x: ((w - cw) / 2).rounded(), y: 0, width: cw.rounded(), height: ch.rounded())) else { return nil }
        let outW = Int(min(cw, thumb.width * 2).rounded()), outH = Int((CGFloat(outW) / aspect).rounded())
        guard outW > 0, outH > 0,
              let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: outW, height: outH)) }
    }

    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) {
        delegate?.browserManagerPageWindowsChanged(focus: tabID(of: browser) == visibleTabID)
    }

    func unload(_ tabID: UUID) {
        // CEF closes asynchronously. Retire ownership first so reopening the tab
        // creates a new browser, and late callbacks cannot mutate its replacement.
        guard let rt = release(tabID) else { return }
        rt.browser.containerView.isHidden = true
        closingBrowsers[ObjectIdentifier(rt.browser)] = rt.browser
        rt.browser.close()
        delegate?.browserManagerDidUpdate(tabID)
        delegate?.browserManagerPageWindowsChanged(focus: false)
    }

    // MARK: Tab sleeping

    /// Settings ▸ Tabs ▸ "Sleep tabs I haven't looked at in": a page off screen that long
    /// closes, like a closed pinned tab, and loads its URL again when shown. Pages that are
    /// loading, playing sound, recording, in Picture in Picture or DevTools, holding typed
    /// text or asking before they close (beforeunload) stay awake.
    func sleepIdleTabs(hiddenLongerThan seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        for (id, rt) in runtimes {
            let b = rt.browser
            guard canSleep(rt, before: cutoff) else { continue }
            let url = b.currentURL
            let navigationRevision = rt.navigationRevision
            b.sendDevToolsMethod("Runtime.evaluate", params: Self.sleepProbe) { [weak self, weak rt] result, _ in
                DispatchQueue.main.async {
                    guard let self, let rt, let current = self.runtimes[id], current === rt,
                          current.navigationRevision == navigationRevision, current.browser.currentURL == url,
                          self.canSleep(current, before: cutoff),
                          Self.probeSaysIdle(result) else { return }
                    self.unload(id)
                }
            }
        }
    }

    private func canSleep(_ rt: TabRuntime, before cutoff: Date) -> Bool {
        let b = rt.browser
        return rt.hiddenAt.map { $0 < cutoff } == true && !visibleTabIDs.contains(rt.tabID)
            && b.isCreated && !b.isClosed && !b.isLoading && !b.isInPictureInPicture
            && !b.isCapturingMedia && !b.hasDevTools
    }

    /// true when the page has nothing to lose: no audible media, no edited fields, no
    /// beforeunload handler (closing would ask "Leave site?" on a page nobody is looking at).
    private static let sleepProbe: String = {
        let js = """
        (() => {
          const playing = [...document.querySelectorAll('video,audio')].some(m => !m.paused && !m.ended && !m.muted && m.volume > 0);
          const typed = [...document.querySelectorAll('input,textarea,select')].some(e =>
            e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked
            : e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected)
            : !['hidden','submit','button','reset','image','file','search'].includes(e.type) && e.value !== e.defaultValue);
          const editing = document.activeElement?.isContentEditable === true;
          const guarded = !!window.onbeforeunload || (getEventListeners(window).beforeunload || []).length > 0;
          return !(playing || typed || editing || guarded);
        })()
        """
        let params: [String: Any] = ["expression": js, "returnByValue": true, "includeCommandLineAPI": true]
        return String(data: try! JSONSerialization.data(withJSONObject: params), encoding: .utf8)!
    }()

    private static func probeSaysIdle(_ result: String?) -> Bool {
        guard let data = result?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exceptionDetails"] == nil,
              let value = (json["result"] as? [String: Any])?["value"] as? Bool else { return false }
        return value
    }

    /// Drop runtimes whose tabs no longer exist (archived, deleted). A page can't change
    /// its Chromium profile: one whose tab moved to a space with another profile, or whose
    /// space switched profiles, closes and loads its URL again there when shown.
    func pruneMissingTabs() {
        for id in runtimes.keys where store.item(id)?.isTab != true { unload(id) }
        for (id, rt) in runtimes where store.item(id)?.isTab == true && !inRightProfile(rt) {
            release(id)?.browser.close()
        }
    }

    private func inRightProfile(_ rt: TabRuntime) -> Bool {
        rt.browser.isIncognito || rt.browser.profilePath == store.profilePath(item: rt.tabID)
    }

    func closeAll() { for id in Array(runtimes.keys) { unload(id) } }

    func layoutVisible() {
        for id in visibleTabIDs {
            guard let v = runtimes[id]?.browser.containerView else { continue }
            v.frame = v.superview?.bounds ?? container.bounds
        }
    }

    private func tabID(of browser: CraBrowser) -> UUID? {
        guard let id = byBrowser[ObjectIdentifier(browser)], runtimes[id]?.browser === browser else { return nil }
        return id
    }

    // MARK: Picture in Picture

    /// Arc: "Enable Picture in Picture when you leave a video tab". The request
    /// goes out before the page is hidden, so the video keeps playing in the
    /// floating window; the page answers through didChangePictureInPicture.
    private func leaveTab(_ tabID: UUID) {
        guard store.settings.autoPictureInPicture, let rt = runtimes[tabID], !rt.browser.isInPictureInPicture else { return }
        rt.pendingAutoPictureInPicture = true
        rt.browser.requestPictureInPicture(automatic: true)
    }

    func browser(_ browser: CraBrowser, didChangePictureInPicturePlayback playing: Bool) {
        PictureInPictureChrome.shared.isPlaying = playing
    }

    /// Picture in Picture's "back to tab": select the tab, bring its window up
    /// and put the video back in the page (also when the tab was already selected).
    private func bringToFront(_ tabID: UUID) {
        store.selectTab(tabID, window: windowID)
        container.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        runtimes[tabID]?.browser.exitPictureInPicture()
    }

    /// Back on the tab: the video comes home. Arc closes its Picture in Picture
    /// window whenever the tab it came from is in front again, however it was
    /// opened (observed on 1.168: the window went away the moment its source
    /// window became key).
    private func returnToTab(_ rt: TabRuntime) {
        rt.pendingAutoPictureInPicture = false
        if rt.browser.isInPictureInPicture { rt.browser.exitPictureInPicture() }
    }

    func browser(_ browser: CraBrowser, didChangePictureInPicture active: Bool) {
        guard let id = tabID(of: browser), let rt = runtimes[id] else { return }
        if active {
            // The floating window's hover controls act on this tab.
            PictureInPictureChrome.shared.actions = PictureInPictureActions(
                backToTab: { [weak self] in self?.bringToFront(id) },
                togglePlayback: { [weak browser] in browser?.togglePictureInPicturePlayback() },
                skip: { [weak browser] s in browser?.skipPictureInPicture(by: s) },
                close: { [weak browser] in browser?.exitPictureInPicture() })
            PictureInPictureChrome.shared.isPlaying = browser.isPictureInPicturePlaying
            PictureInPictureChrome.shared.videoEntered()
        } else {
            PictureInPictureChrome.shared.videoLeft()
        }
        if active {
            rt.autoPictureInPicture = rt.pendingAutoPictureInPicture
            rt.pendingAutoPictureInPicture = false
            // The request from leaving the tab landed after the user came back.
            if rt.autoPictureInPicture, id == visibleTabID { browser.exitPictureInPicture() }
        } else {
            rt.autoPictureInPicture = false
        }
        delegate?.browserManagerDidUpdate(id)
    }

    // MARK: CraBrowserDelegate

    func browser(_ browser: CraBrowser, didChangeTitle title: String) {
        guard let id = tabID(of: browser) else { return }
        store.updateTab(id, title: title)
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeMediaCapture capturing: Bool) {
        guard let id = tabID(of: browser) else { return }
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeURL url: String) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.navigationRevision &+= 1
        // Our own error page is a data: URL; keep the real address in the model.
        if url.hasPrefix("data:text/html;base64,") { return }
        store.updateTab(id, url: url)
        if !browser.isIncognito { LiveFolderManager.shared.pageChanged(tab: id, to: url) }
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let id = tabID(of: browser) else { return }
        if loading { runtimes[id]?.navigationRevision &+= 1 }
        if !loading { runtimes[id]?.progress = 0 }
        if !loading { scheduleSnapshot(id) }
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.progress = progress
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {
        guard let id = tabID(of: browser), !browser.isIncognito else { return }
        store.recordVisit(url: url, title: title.isEmpty ? (store.item(id)?.tab?.savedTitle ?? "") : title)
    }

    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {
        guard let id = tabID(of: browser), let tab = store.item(id)?.tab else { return }
        let key = FaviconCache.key(for: tab.url) ?? tab.faviconKey
        guard let key else { return }
        favicons.store(image, forKey: key, persist: !browser.isIncognito)
        if tab.faviconKey != key { store.updateTab(id, url: tab.url) }
    }

    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.themeColor = hex
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didReportBackgroundColor hex: String) {
        guard let id = tabID(of: browser), let rt = runtimes[id], rt.backgroundColor != hex else { return }
        rt.backgroundColor = hex
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {
        delegate?.browserManager(statusMessage: message)
    }

    func browser(_ browser: CraBrowser, didFindMatches count: Int, activeMatch: Int) {
        guard let id = tabID(of: browser), id == visibleTabID else { return }
        delegate?.browserManager(findMatches: count, activeMatch: activeMatch)
    }

    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {
        guard let id = tabID(of: browser) else { return }
        delegate?.browserManager(fullscreen: fullscreen, tabID: id)
    }

    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {
        // cra:// is Cra's scripting scheme (DevTools Protocol, key presses); a page must not drive it.
        if url.lowercased().hasPrefix("cra:") { return }
        let sourceSpace = tabID(of: browser).flatMap { store.spaceID(ofItem: $0) }
        let parentIndex = tabID(of: browser).flatMap { id -> Int? in
            guard let it = store.item(id), let p = it.parentID, store.rootContainer(of: id) != nil,
                  case .today = store.rootContainer(of: id)! else { return nil }
            return (store.item(p)?.children.firstIndex(of: id) ?? -1) + 1
        }
        // Links from a today tab open right below it (Arc); otherwise at the top.
        let tab = store.createTab(url: url, in: sourceSpace, select: !background,
                                  parent: parentIndex != nil ? store.item(tabID(of: browser)!)?.parentID : nil,
                                  index: parentIndex, window: windowID)
        if background {
            store.markUnread(tab.id, true)
            ensureRuntime(for: tab.id)  // load it so the title and favicon fill in
        }
    }

    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? {
        if url.lowercased().hasPrefix("cra:") { return nil }
        let sourceSpace = tabID(of: browser).flatMap { store.spaceID(ofItem: $0) }
        let tab = store.createTab(url: url, in: sourceSpace, select: !background, window: windowID)
        if background { store.markUnread(tab.id, true) }
        let host = makePopupHost(for: tab.id)
        if !background { show(tab.id, focus: true) }
        return host
    }

    func browser(_ browser: CraBrowser, opensPeekForURL url: String, shiftClick: Bool) -> Bool {
        guard let id = tabID(of: browser), !browser.isIncognito else { return false }
        return delegate?.browserManagerOpensPeek(url: url, fromTab: id, pageURL: browser.currentURL, shiftClick: shiftClick) ?? false
    }

    func devToolsHostView(for browser: CraBrowser) -> NSView? {
        guard let id = tabID(of: browser) else { return nil }
        return delegate?.browserManagerDevToolsHost(for: id)
    }

    private(set) var devToolsViews: [UUID: NSView] = [:]
    var visibleTabHasDevTools: Bool { visibleTabID.flatMap { devToolsViews[$0] } != nil }

    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {
        guard let id = tabID(of: browser) else { return }
        devToolsViews[id] = view
        delegate?.browserManagerDevToolsChanged()
    }

    func browserDidCloseDevTools(_ browser: CraBrowser) {
        guard let id = tabID(of: browser) else { return }
        devToolsViews[id] = nil
        devToolsPlaceholders[id] = nil
        devToolsDockedState[id] = nil
        delegate?.browserManagerDevToolsChanged()
    }

    /// Chrome's docked frontend reported where the page goes: `bounds` are points with a
    /// top-left origin inside a DevTools window whose content measured `frontendSize`.
    struct DevToolsPlaceholder: Equatable {
        var bounds: NSRect
        var frontendSize: NSSize
    }
    private(set) var devToolsPlaceholders: [UUID: DevToolsPlaceholder] = [:]
    /// False once the user undocked Chrome's frontend into its own window.
    private(set) var devToolsDockedState: [UUID: Bool] = [:]

    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {
        guard let id = tabID(of: browser) else { return }
        // Undocked frontends still report bounds (device mode); only setIsDocked changes the dock state.
        guard devToolsDockedState[id] != false else { return }
        let size = devToolsViews[id]?.window?.contentView?.bounds.size ?? NSSize(width: bounds.maxX, height: bounds.maxY)
        devToolsPlaceholders[id] = DevToolsPlaceholder(bounds: bounds, frontendSize: size)
        delegate?.browserManagerDevToolsPageBoundsChanged()
    }

    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {
        guard let id = tabID(of: browser) else { return }
        if !docked { devToolsPlaceholders[id] = nil }
        guard devToolsDockedState[id] != docked else { return }
        devToolsDockedState[id] = docked
        delegate?.browserManagerDevToolsChanged()
    }

    /// CEF's window for the visible tab's DevTools, if any.
    var visibleDevToolsWindow: NSWindow? { visibleTabID.flatMap { devToolsViews[$0]?.window } }

    /// DevTools windows on screen, by tab: every pane's Chrome-style frontend (it docks
    /// inside its own pane), and an Alloy frontend only for the focused tab (the shell
    /// has one dock).
    var visibleDevToolsWindows: [UUID: NSWindow] {
        var out: [UUID: NSWindow] = [:]
        for id in visibleTabIDs {
            guard let w = devToolsViews[id]?.window else { continue }
            if id == visibleTabID || runtimes[id]?.hostWindow != nil { out[id] = w }
        }
        return out
    }

    private func syncDevToolsVisibility() {
        delegate?.browserManagerDevToolsChanged()
    }

    func browser(_ browser: CraBrowser, handleKeyEvent event: NSEvent) -> Bool {
        delegate?.browserManagerHandleKey(event) ?? false
    }

    func browser(_ browser: CraBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        delegate?.browserManagerHandleUnhandledKey(event) ?? false
    }

    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) {
        delegate?.browserManager(download: download)
    }

    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void) {
        // Notification prompts are denied quietly (no modal), like Arc's default.
        if kinds == 8 { completion(false); return }
        var what: [String] = []
        if kinds & 1 != 0 { what.append("camera") }
        if kinds & 2 != 0 { what.append("microphone") }
        if kinds & 4 != 0 { what.append("location") }
        if kinds & 8 != 0 { what.append("notifications") }
        let alert = NSAlert()
        alert.messageText = what.isEmpty ? "\(origin) is asking for a browser permission"
                                         : "\(origin) wants to use your \(what.joined(separator: " and "))"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        guard let window = container.window else { completion(false); return }
        alert.beginSheetModal(for: window) { resp in completion(resp == .alertFirstButtonReturn) }
    }

    func browserDidReceiveFocus(_ browser: CraBrowser) {
        guard let id = tabID(of: browser) else { return }
        delegate?.browserManagerFocusedBrowser(id)
    }

    func browserDidClose(_ browser: CraBrowser) {
        closingBrowsers[ObjectIdentifier(browser)] = nil
        guard let id = tabID(of: browser) else { return }
        _ = release(id)
        delegate?.browserManagerDidUpdate(id)
        delegate?.browserManagerPageWindowsChanged(focus: false)
        // window.close() (a sign-in or payment popup finishing): the tab goes, like Chrome.
        if browser.closedByPage { delegate?.browserManagerPageClosedTab(id) }
    }
}
