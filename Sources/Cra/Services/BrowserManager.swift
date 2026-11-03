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
    /// The page probe for this time on screen, until it has run (BrowserManager.scheduleProbe).
    var probeWork: DispatchWorkItem?
    /// When the page last went off screen (nil while shown); tab sleeping counts from here.
    var hiddenAt: Date?
    /// Invalidates a pending sleep probe even when navigation returns to the same URL.
    var navigationRevision: UInt = 0
    /// A page that refused to sleep isn't asked again before this (nil: ask on the next pass).
    var sleepProbeAfter: Date?
    /// Why the page last refused to sleep ("" when it didn't), so the log says it once.
    var sleepRefusal: String?
    /// Whether this page's DevTools are open, closing or asked for (DevToolsToggle).
    var devTools = DevToolsToggle()
    /// Loads of an extension's page Chromium blocked because the extension wasn't up yet
    /// (ExtensionPageRetry); back to 0 once a page loads.
    var extensionPageRetries = 0
    /// The next of those loads (LiveScheduler runs work only while its handle is kept).
    var extensionPageRetry: ScheduledWork?
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
    /// An extension asked for this tab to be in front (chrome.tabs.update with active: true),
    /// or with byPage the page did (window.focus(), clients.focus() from a notification click).
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool)
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
    /// Tabs whose page tab sleeping closed and that haven't been shown since.
    private(set) var sleptTabs: Set<UUID> = []
    /// Split view: the view a tab's Alloy-hosted Chromium view should live in.
    var paneHost: ((UUID) -> NSView?)?
    /// The browser window this manager shows pages in (tabs it opens are selected there).
    var windowID: UUID?
    /// A tab's live page held by another window's manager, handed over (see `release`).
    var takeRuntimeFromOtherWindow: ((UUID) -> TabRuntime?)?
    /// The window's sidebar player (Arc's "now playing"), fed with this manager's pages.
    var nowPlaying: NowPlaying?
    /// A tab's page closed (the tab closed or went to sleep), with what Chromium kept for it.
    var pageClosed: (UUID) -> Void = { _ in }
    private var byBrowser: [ObjectIdentifier: UUID] = [:]
    /// CEF's client holds its owner weakly; keep retired browsers alive until teardown finishes.
    private var closingBrowsers: [ObjectIdentifier: CraBrowser] = [:]

    /// Tab sleeping's clock: a test advances it instead of waiting out the idle threshold.
    let clock: Scheduler

    init(store: SidebarStore, favicons: FaviconCache, container: NSView, clock: Scheduler? = nil) {
        self.store = store
        self.favicons = favicons
        self.container = container
        self.clock = clock ?? LiveScheduler.shared
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
            if inRightProfile(rt) { log(tabID, "moves its page in from another window"); return rt }
            release(tabID)?.browser.close()
        }
        log(tabID, "opens a page for \(site(tab.url, tabID))")
        if sleptTabs.remove(tabID) != nil { Perf.begin(.tabWake, tabID.uuidString) }
        let browser = Perf.time(.pageCreate) {
            CraBrowser(frame: container.bounds, url: tab.url, delegate: self, incognito: store.isIncognito(item: tabID),
                       profilePath: store.profilePath(item: tabID))
        }
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
        log(tabID, "takes over a Little Window's page")
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
        rt.hiddenAt = clock.now
        if let t = store.item(tabID)?.tab {
            if t.muted { browser.setAudioMuted(true) }
            // A slept or restored page's toolbar keeps its colour while it loads (Arc).
            rt.themeColor = t.themeColor ?? ""
        }
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
        nowPlaying?.remove(tabID)
        nowPlaying?.pictureInPicture.remove(tabID)
        byBrowser[ObjectIdentifier(rt.browser)] = nil
        rt.snapshotWork?.cancel()
        rt.snapshotWork = nil
        rt.probeWork?.cancel()
        rt.probeWork = nil
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
        let started = Perf.now()
        let newSet = Set(tabIDs)
        for previous in visibleTabIDs where !newSet.contains(previous) {
            leaveTab(previous)
            runtimes[previous]?.hiddenAt = clock.now
        }
        let wasVisible = Set(visibleTabIDs)
        var shown: [UUID] = []
        // A tab without a page gets one here, timed as pageCreate: tabSwitch leaves it out (#136).
        var creating = 0.0
        for id in tabIDs {
            let made = runtimes[id] == nil ? Perf.now() : nil
            guard let rt = ensureRuntime(for: id) else { shown.append(id); continue }
            if let made { creating += Perf.ms(since: made) }
            if !wasVisible.contains(id) {
                returnToTab(rt)
                // A page can change its colours while hidden. One still loading reports them as it
                // paints; asked now, before its styles arrive, it would answer white.
                if !rt.browser.isLoading { rt.browser.probeBackgroundColor() }
            }
            rt.hiddenAt = nil
            rt.sleepProbeAfter = nil
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
        if let np = nowPlaying, np.onScreen != Set(shown) { np.onScreen = Set(shown) }
        visibleTabID = focused.flatMap { newSet.contains($0) ? $0 : nil } ?? shown.first
        if wasVisible != Set(shown) {
            HitchMonitor.mark("page-shown")
            if let rt = visibleRuntime {
                Perf.visibleSite(rt.browser.isIncognito ? nil : SiteNames.siteHost(of: rt.browser.currentURL))
                Perf.phase("firstPageShown")
            }
        }
        if focus, let f = visibleTabID, let rt = runtimes[f] { rt.browser.setFocused(true) }
        for id in shown where !wasVisible.contains(id) {
            if let rt = runtimes[id] {
                // A loading page gets its thumbnail once it has loaded: a capture now would be of
                // a half-painted page, in the busiest second of its load (#136).
                if !rt.browser.isLoading { scheduleSnapshot(id) }
                log(id, "shown: \(site(rt.browser.currentURL, id, rt.browser))\(rt.browser.isLoading ? ", loading" : "")\(rt.browser.isCreated ? "" : ", page not created yet")")
                // A loading page is probed once it has loaded (didChangeLoading), or says it never did.
                scheduleProbe(id, rt, after: rt.browser.isLoading ? 12 : 3)
            }
        }
        syncDevToolsVisibility()
        delegate?.browserManagerPageWindowsChanged(focus: focus)
        if wasVisible != Set(shown) { Perf.time(.tabSwitch, ms: Perf.ms(since: started) - creating) }
    }

    // MARK: Diagnostics

    /// Tab ids are cut to 8 characters, enough to follow one tab through the log.
    private func log(_ id: UUID, _ message: String) { CraLog.note("tab \(id.uuidString.prefix(8)) \(message)") }

    /// The page's own profile when there is one: an incognito tab can leave the store before a late line.
    private func site(_ url: String, _ id: UUID, _ browser: CraBrowser? = nil) -> String {
        browser?.isIncognito ?? store.isIncognito(item: id) ? "(incognito)" : CraLog.host(url)
    }

    /// A moment after a tab comes on screen and its page has loaded, the log gets what the page
    /// holds and where Cra put it: for the tab that "shows a white page until reloaded", the line
    /// that says why. Not sooner: the probe runs in the page, which is busiest while it loads (#136).
    private func scheduleProbe(_ id: UUID, _ rt: TabRuntime, after delay: TimeInterval) {
        rt.probeWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak rt] in
            guard let self, let rt, self.runtimes[id] === rt else { return }
            rt.probeWork = nil
            guard self.visibleTabIDs.contains(id) else { return }
            PageProbe.run(rt.browser) { [weak self] probe in
                guard let self, self.runtimes[id] === rt else { return }
                self.log(id, "page \(self.site(rt.browser.currentURL, id, rt.browser))\(rt.browser.isLoading ? " still loading" : ""): \(probe) \(PageProbe.viewState(rt))")
            }
        }
        rt.probeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        log(tabID, "closes its page")
        Perf.cancel(.pageLoad, tabID.uuidString)
        Perf.cancel(.tabWake, tabID.uuidString)
        pageClosed(tabID)
        rt.browser.containerView.isHidden = true
        closingBrowsers[ObjectIdentifier(rt.browser)] = rt.browser
        rt.browser.close()
        delegate?.browserManagerDidUpdate(tabID)
        delegate?.browserManagerPageWindowsChanged(focus: false)
    }

    // MARK: Tab sleeping

    /// Settings ▸ Tabs ▸ "Sleep tabs I haven't looked at in": a page off screen that long
    /// closes, like a closed pinned tab, and loads its URL again when shown. Pages that are
    /// loading, playing sound, recording, in Picture in Picture or DevTools, holding text the
    /// user typed or asking before they close (their own onbeforeunload) stay awake, and are
    /// asked again only after `refusalBackoff`. The log says once why a page stays awake.
    func sleepIdleTabs(hiddenLongerThan seconds: TimeInterval) {
        let now = clock.now
        let cutoff = now.addingTimeInterval(-seconds)
        for (id, rt) in runtimes {
            let b = rt.browser
            guard canSleep(rt, before: cutoff), rt.sleepProbeAfter.map({ $0 <= now }) ?? true else { continue }
            let url = b.currentURL
            let navigationRevision = rt.navigationRevision
            // Cra's isolated world sees typed text and media; the page's own onbeforeunload is only
            // visible from the page's world, so that's asked second.
            b.evaluate(inIsolatedWorld: PageScript.world, params: Self.sleepProbe) { [weak self, weak rt] result, _ in
                DispatchQueue.main.async {
                    guard let self, let rt, self.stillSleepable(id, rt, url, navigationRevision, cutoff) else { return }
                    let refusal = Self.sleepRefusal(result)
                    guard refusal.isEmpty else { return self.keepAwake(rt, url, refusal) }
                    rt.browser.sendDevToolsMethod("Runtime.evaluate", params: Self.beforeUnloadProbe) { [weak self, weak rt] result, _ in
                        DispatchQueue.main.async {
                            guard let self, let rt, self.stillSleepable(id, rt, url, navigationRevision, cutoff) else { return }
                            let refusal = Self.sleepRefusal(result)
                            guard refusal.isEmpty else { return self.keepAwake(rt, url, refusal) }
                            self.sleptTabs.insert(id)
                            Perf.count(.tabSlept)
                            if !rt.browser.isIncognito {
                                CraLog.note("tab sleep unloads \(CraLog.host(url)) (hidden \(Int(self.clock.now.timeIntervalSince(rt.hiddenAt ?? self.clock.now) / 60)) min)")
                            }
                            self.unload(id)
                        }
                    }
                }
            }
        }
    }

    private func stillSleepable(_ id: UUID, _ rt: TabRuntime, _ url: String, _ revision: UInt, _ cutoff: Date) -> Bool {
        runtimes[id] === rt && rt.navigationRevision == revision && rt.browser.currentURL == url && canSleep(rt, before: cutoff)
    }

    /// Asked again after the back-off; the log names the site once per reason (never an incognito one).
    private func keepAwake(_ rt: TabRuntime, _ url: String, _ refusal: String) {
        rt.sleepProbeAfter = clock.now.addingTimeInterval(Self.refusalBackoff)
        Perf.count(.sleepRefusal, refusal)
        if rt.sleepRefusal != refusal, !rt.browser.isIncognito { CraLog.note("tab sleep keeps \(CraLog.host(url)) awake: \(refusal)") }
        rt.sleepRefusal = refusal
    }

    static let refusalBackoff: TimeInterval = 10 * 60

    private func canSleep(_ rt: TabRuntime, before cutoff: Date) -> Bool {
        let b = rt.browser
        return rt.hiddenAt.map { $0 < cutoff } == true && !visibleTabIDs.contains(rt.tabID)
            && b.isCreated && !b.isClosed && !b.isLoading && !b.isInPictureInPicture
            && !b.isCapturingMedia && !b.isAudible && !b.hasDevTools
    }

    /// In Cra's isolated world: "" when the page has nothing to lose, else why it must stay:
    /// media playing, or text the user typed that is still there on the same URL (PageScript
    /// records trusted input; values a framework set, or text submitted by a navigation, don't
    /// count).
    private static let sleepProbe: String = {
        let js = """
        (() => {
          if ([...document.querySelectorAll('video,audio')].some(m => !m.paused && !m.ended && !m.muted && m.volume > 0)) return 'playing';
          const edited = e => e.isContentEditable ? e.textContent.trim() !== ''
            : e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked
            : e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected)
            : (e.value ?? '') !== '';
          for (const [e, href] of window.__cra?.typed ?? []) {
            if (!e.isConnected || href !== location.href) { window.__cra.typed.delete(e); continue; }
            if (edited(e)) return 'typed';
          }
          return '';
        })()
        """
        return evaluateParams(js, userGesture: false)
    }()

    /// In the page's world (leaves nothing behind): the page's own onbeforeunload. Listeners a
    /// framework adds with addEventListener don't count: nearly every app registers one, and the
    /// user never sees most of them fire.
    private static let beforeUnloadProbe = evaluateParams("typeof window.onbeforeunload === 'function' ? 'beforeunload' : ''", userGesture: false)

    /// The probe's answer; anything but a clean "" (an exception, no reply) refuses.
    private static func sleepRefusal(_ result: String?) -> String {
        guard let data = result?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "no reply" }
        guard json["exceptionDetails"] == nil else { return "probe failed" }
        guard let value = (json["result"] as? [String: Any])?["value"] as? String else { return "no reply" }
        return value
    }

    /// Drop runtimes whose tabs no longer exist (archived, deleted). A page can't change
    /// its Chromium profile: one whose tab moved to a space with another profile, or whose
    /// space switched profiles, closes and loads its URL again there when shown.
    func pruneMissingTabs() {
        for id in runtimes.keys where store.item(id)?.isTab != true { unload(id) }
        sleptTabs = sleptTabs.filter { store.item($0)?.isTab == true }
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

    // MARK: Delete browsing data

    /// Chrome's Settings page (its Delete browsing data dialog) runs in Chromium; the command
    /// bar's history is Cra's. Hear the dialog's "Delete data" and clear the same history here.
    /// One wait per page (a second load finds the first); the page answers once, then it waits
    /// again.
    private func watchClearBrowsingData(_ browser: CraBrowser) {
        let js = """
        (() => {
          if (typeof chrome === 'undefined' || typeof chrome.send !== 'function') return null;
          return window.__craClearBrowsingData ??= new Promise(resolve => {
            const send = chrome.send;
            chrome.send = function (name, args) {
              if (name === 'clearBrowsingData') {
                chrome.send = send;
                window.__craClearBrowsingData = null;
                resolve(JSON.stringify((args ?? []).slice(1)));
              }
              return send.apply(this, arguments);
            };
          });
        })()
        """
        let params: [String: Any] = ["expression": js, "returnByValue": true, "awaitPromise": true]
        let json = String(data: try! JSONSerialization.data(withJSONObject: params), encoding: .utf8)!
        browser.sendDevToolsMethod("Runtime.evaluate", params: json) { [weak self, weak browser] result, _ in
            DispatchQueue.main.async {
                guard let self, let browser, let message = Self.stringResult(result) else { return }
                if let range = BrowsingDataClear.historyRange(messageJSON: message, now: self.clock.now) { self.store.clearHistory(range) }
                if browser.currentURL.hasPrefix("chrome://settings") { self.watchClearBrowsingData(browser) }
            }
        }
    }

    // MARK: Picture in Picture

    /// Arc: "Enable Picture in Picture when you leave a video tab". The request
    /// goes out as the page is hidden, so the video keeps playing in the
    /// floating window; the page answers through didChangePictureInPicture.
    /// It goes through the protocol's user gesture like the player's button:
    /// the key press that lends the page activation raced the page going
    /// hidden, and PiP sometimes never opened.
    private func leaveTab(_ tabID: UUID) {
        guard store.settings.autoPictureInPicture, let rt = runtimes[tabID], !rt.browser.isInPictureInPicture else { return }
        rt.pendingAutoPictureInPicture = true
        requestPictureInPicture(tabID, automatic: true)
    }

    /// The window is out of sight: covered by another app, on another desktop or in the Dock.
    private(set) var windowCovered = false

    /// Arc's presentPipForOccludedWindow: a window out of sight and not key leaves its video tabs
    /// the way a tab switch does (a four-finger swipe to another desktop, another app on top), and
    /// the video comes back when the window is key again. Only pages playing sound are asked:
    /// the automatic request wants an unmuted video playing, and a page without one in its main
    /// frame gets the activation nudge, which an app switch shouldn't send to every page.
    func windowVisibilityChanged(covered: Bool) {
        guard covered != windowCovered else { return }
        windowCovered = covered
        for id in visibleTabIDs {
            guard let rt = runtimes[id] else { continue }
            if covered {
                if rt.browser.isAudible { leaveTab(id) }
            } else if rt.autoPictureInPicture || rt.pendingAutoPictureInPicture {
                returnToTab(rt)
            }
        }
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
        if let np = nowPlaying, np.pictureInPicture.contains(id) != active {
            if active { np.pictureInPicture.insert(id) } else { np.pictureInPicture.remove(id) }
        }
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
            if rt.autoPictureInPicture, id == visibleTabID, !windowCovered { browser.exitPictureInPicture() }
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

    func browser(_ browser: CraBrowser, didChangeAudible audible: Bool) {
        guard let id = tabID(of: browser) else { return }
        if let np = nowPlaying {
            if np.entries.contains(where: { $0.id == id }) {
                np.update(id) { $0.playing = audible }
            } else if audible {
                np.entries.append(.init(id: id, playing: true))
            }
            if audible { refreshMediaControls(id) }
        }
        delegate?.browserManagerDidUpdate(id)
    }

    // MARK: Now playing

    /// Play/pause, previous and next for the sidebar player. The page's own media session
    /// handlers go first (PageScript keeps them; YouTube, Spotify and SoundCloud skip tracks
    /// that way), else the page's media elements. Runs as a user gesture so play() is allowed.
    func performNowPlaying(_ id: UUID, _ action: NowPlaying.Action) {
        let op: String
        switch action {
        case .togglePlayback: op = "toggle"
        case .previous: op = "previoustrack"
        case .next: op = "nexttrack"
        case .dismiss: op = "pause"; nowPlaying?.remove(id)
        case .pictureInPicture:
            requestPictureInPicture(id, automatic: false)
            return
        case .setVolume(let v):
            nowPlaying?.update(id) { $0.volume = v }
            let js = "(v => { if (window.__cra) window.__cra.volume = v; document.querySelectorAll('video,audio').forEach(m => m.volume = v); })(\(max(0, min(1, v))))"
            runtimes[id]?.browser.evaluate(inIsolatedWorld: PageScript.world, params: Self.evaluateParams(js, userGesture: false)) { _, _ in }
            return
        case .toggleMute, .show: return
        }
        guard let rt = runtimes[id] else { nowPlaying?.remove(id); return }
        let js = """
        ((op) => {
          const cra = window.__cra, has = cra ? cra.query() : [];
          const media = [...document.querySelectorAll('video,audio')];
          const playing = media.some(m => !m.paused && !m.ended);
          if (op === 'toggle') op = playing ? 'pause' : 'play';
          if (has.includes(op)) cra.send(op);
          else if (op === 'pause') media.forEach(m => m.pause());
          else if (op === 'play') (media.find(m => m.currentTime > 0 && !m.ended) ?? media[0])?.play();
          return op === 'pause' ? 'paused' : op === 'play' ? 'playing' : playing ? 'playing' : 'paused';
        })(\(Self.jsonString(op)))
        """
        // No user gesture: the page has been playing, so it already has its activation, and the
        // page's own handlers shouldn't get a fresh one from Cra (PageScript).
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: Self.evaluateParams(js, userGesture: false)) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let state = Self.stringResult(result) else { return }
                self?.nowPlaying?.update(id) { $0.playing = state == "playing" }
            }
        }
    }

    /// The player's Picture in Picture button, and leaving a video tab. The tab is (about to be) off
    /// screen, so the key press that lends a page user activation for the context menu's Picture in
    /// Picture doesn't reliably reach it; the protocol's user gesture does. Only a player in an
    /// iframe falls back to the page path. Leaving a tab takes only an audible, playing video of
    /// some size, as the page path does (muted ones are hover previews or GIF-like loops).
    private func requestPictureInPicture(_ id: UUID, automatic: Bool) {
        guard let browser = runtimes[id]?.browser else { return }
        let js = """
        ((auto) => {
          if (document.pictureInPictureElement) return 'ok';
          const area = v => { const r = v.getBoundingClientRect(); return r.width * r.height; };
          const v = [...document.querySelectorAll('video')].filter(v => !v.disablePictureInPicture && v.readyState >= 1)
            .filter(v => !auto || (!v.paused && !v.ended && !v.muted && v.volume > 0 && v.videoWidth > 0 && area(v) >= 20000))
            .sort((a, b) => ((b.paused ? 0 : 1) - (a.paused ? 0 : 1)) || (area(b) - area(a)))[0];
          return v ? v.requestPictureInPicture().then(() => 'ok', e => e.name + ': ' + e.message) : 'none';
        })(\(automatic))
        """
        let params: [String: Any] = ["expression": js, "returnByValue": true, "awaitPromise": true, "userGesture": true]
        let json = String(data: try! JSONSerialization.data(withJSONObject: params), encoding: .utf8)!
        browser.sendDevToolsMethod("Runtime.evaluate", params: json) { [weak browser] result, _ in
            DispatchQueue.main.async {
                let answer = Self.stringResult(result)
                if answer == nil || answer == "none" { browser?.requestPictureInPicture(automatic: automatic) }
                else if let answer, answer != "ok" { NSLog("Cra: Picture in Picture request failed: %@", answer) }
            }
        }
    }

    /// Which track buttons the page answers (media session handlers).
    private func refreshMediaControls(_ id: UUID) {
        let js = """
        (() => { const has = window.__cra?.query() ?? [];
          return (has.includes('previoustrack') ? 'p' : '') + (has.includes('nexttrack') ? 'n' : '') + (document.querySelector('video') ? 'v' : ''); })()
        """
        runtimes[id]?.browser.evaluate(inIsolatedWorld: PageScript.world, params: Self.evaluateParams(js, userGesture: false)) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let has = Self.stringResult(result) else { return }
                self?.nowPlaying?.update(id) { $0.hasPrevious = has.contains("p"); $0.hasNext = has.contains("n"); $0.hasVideo = has.contains("v") }
            }
        }
    }

    private static func evaluateParams(_ js: String, userGesture: Bool) -> String {
        let params: [String: Any] = ["expression": js, "returnByValue": true, "userGesture": userGesture]
        return String(data: try! JSONSerialization.data(withJSONObject: params), encoding: .utf8)!
    }

    private static func jsonString(_ s: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)!.dropFirst().dropLast().description
    }

    private static func stringResult(_ result: String?) -> String? {
        guard let data = result?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["exceptionDetails"] == nil else { return nil }
        return (json["result"] as? [String: Any])?["value"] as? String
    }

    func browser(_ browser: CraBrowser, didChangeURL url: String) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.navigationRevision &+= 1
        // A quiet page that navigates leaves the player; a playlist moving on keeps its card.
        if !browser.isAudible { nowPlaying?.remove(id) }
        // Our own error page is a data: URL; keep the real address in the model.
        if url.hasPrefix("data:text/html;base64,") { return }
        // A restored page has no address yet when it is shown.
        if id == visibleTabID { Perf.visibleSite(browser.isIncognito ? nil : SiteNames.siteHost(of: url)) }
        store.updateTab(id, url: url)
        if !browser.isIncognito { LiveFolderManager.shared.pageChanged(tab: id, to: url) }
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let id = tabID(of: browser) else { return }
        if loading { runtimes[id]?.navigationRevision &+= 1 }
        if loading { Perf.begin(.pageLoad, id.uuidString) } else {
            Perf.end(.pageLoad, id.uuidString)
            Perf.end(.tabWake, id.uuidString)
        }
        if !loading { runtimes[id]?.progress = 0 }
        // Two seconds on, the page (a video player especially) has settled before it is captured.
        if !loading { scheduleSnapshot(id, after: 2) }
        if !loading, let rt = runtimes[id], rt.probeWork != nil { scheduleProbe(id, rt, after: 3) }
        if !loading, id == visibleTabID { Perf.phase("firstPageLoaded") }
        delegate?.browserManagerDidUpdate(id)
    }

    /// The window's loading bar pulses until the page commits, then sweeps (LoadingIndicator).
    func browser(_ browser: CraBrowser, didChangeCommittedLoad committed: Bool) {
        guard let id = tabID(of: browser) else { return }
        // Start-up phases: firstPageShown, then the page's navigation committed, then loaded.
        if committed, id == visibleTabID { Perf.phase("firstPageCommitted") }
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.progress = progress
        delegate?.browserManagerDidUpdate(id)
    }

    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {
        guard let id = tabID(of: browser) else { return }
        log(id, "loaded \(site(url, id, browser)) (HTTP \(statusCode))")
        if statusCode != 0 { runtimes[id]?.extensionPageRetries = 0 }
        guard !browser.isIncognito else { return }
        if url.hasPrefix("chrome://settings") { watchClearBrowsingData(browser) }
        store.recordVisit(url: url, title: title.isEmpty ? (store.item(id)?.tab?.savedTitle ?? "") : title)
    }

    /// A restored tab's extension page, asked for before --load-extension loaded the extension,
    /// loads again once it is up (ExtensionPageRetry).
    func browser(_ browser: CraBrowser, didFailLoadingURL url: String, errorCode: Int) {
        guard let id = tabID(of: browser), let rt = runtimes[id] else { return }
        let profile = store.profileDirectoryName(item: id)
        // Which extension the request went through, if any: a slow or failed first page is then a
        // network wait or a proxy that is down, told apart from a render (#136).
        log(id, "\(site(url, id, browser)) failed to load: net error \(errorCode), proxy \(ExtensionStore.shared.proxyLine(inProfile: profile))")
        guard !browser.isIncognito else { return }
        guard let wait = ExtensionPageRetry.delay(url: url, errorCode: errorCode, attempt: rt.extensionPageRetries, isOn: { ext in
            ExtensionStore.shared.entries(inProfile: profile).contains { $0.extensionID == ext }
        }) else { return }
        rt.extensionPageRetries += 1
        log(id, "loads \(site(url, id, browser)) again in \(wait) s: the extension wasn't loaded yet")
        rt.extensionPageRetry = clock.after(wait) { [weak self, weak browser] in
            // Still this tab's page, and nobody has gone elsewhere meanwhile.
            guard let self, let browser, self.runtimes[id]?.browser === browser, browser.currentURL == url else { return }
            browser.loadURL(url)
        }
    }

    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {
        guard let id = tabID(of: browser), let tab = store.item(id)?.tab else { return }
        let key = FaviconKey.key(for: tab.url) ?? tab.faviconKey
        guard let key else { return }
        favicons.store(image, forKey: key, persist: !browser.isIncognito)
        if tab.faviconKey != key { store.updateTab(id, url: tab.url) }
    }

    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) {
        guard let id = tabID(of: browser) else { return }
        runtimes[id]?.themeColor = hex
        store.setThemeColor(id, hex)
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
        runtimes[id]?.devTools.didOpen()
        delegate?.browserManagerDevToolsChanged()
    }

    func browserDidCloseDevTools(_ browser: CraBrowser) {
        guard let id = tabID(of: browser) else { return }
        devToolsViews[id] = nil
        devToolsPlaceholders[id] = nil
        devToolsDockedState[id] = nil
        delegate?.browserManagerDevToolsChanged()
        if let rt = runtimes[id] { perform(rt.devTools.didClose(), on: rt) }
    }

    /// ⌥⌘I, ⌥⌘J, ⌥⌘C and the developer bar's Console, Network and Inspect on the focused page
    /// (DevToolsToggle.Command).
    func runDevTools(_ command: DevToolsToggle.Command) {
        guard let rt = visibleRuntime else { return }
        let (effect, frontend) = rt.devTools.run(command)
        // A press made while DevTools close is done when they reopen (DevToolsToggle.didClose).
        rt.browser.devToolsAction = frontend
        perform(effect, on: rt)
    }

    private func perform(_ effect: DevToolsToggle.Effect, on rt: TabRuntime) {
        switch effect {
        case .show: rt.browser.showDevTools()
        case .close: rt.browser.closeDevTools()
        case .none: break
        }
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
        let alert = NSAlert()
        alert.messageText = PermissionPrompt.message(origin: origin, kinds: kinds)
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        guard let window = container.window else { completion(false); return }
        alert.beginSheetModal(for: window) { resp in completion(resp == .alertFirstButtonReturn) }
    }

    func browserDidReceiveFocus(_ browser: CraBrowser) {
        guard let id = tabID(of: browser) else { return }
        delegate?.browserManagerFocusedBrowser(id)
    }

    func browserRequestsActivation(_ browser: CraBrowser, byPage: Bool) {
        guard let id = tabID(of: browser) else { return }
        delegate?.browserManagerActivationRequested(id, byPage: byPage)
    }

    func browserDidClose(_ browser: CraBrowser) {
        closingBrowsers[ObjectIdentifier(browser)] = nil
        guard let id = tabID(of: browser) else { return }
        _ = release(id)
        delegate?.browserManagerDidUpdate(id)
        delegate?.browserManagerPageWindowsChanged(focus: false)
        // window.close() (a sign-in or payment popup finishing): the tab goes, like Chrome.
        if browser.closedByPage { log(id, "closed by its page"); delegate?.browserManagerPageClosedTab(id) }
    }
}
