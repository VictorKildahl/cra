import AppKit
import CraCEF
import JavaScriptCore

@main
enum BrowserManagerLifecycleTests {
    private static let idleReply = #"{"result":{"type":"string","value":""}}"#
    private static let isolatedProbe = "cra:Runtime.evaluate"
    private static var checks = 0

    /// An Option-clicked link, which Chromium makes a download, opens in Split View instead
    /// (#298); other downloads, and a closed page's, go ahead as downloads.
    // promise: #298
    @MainActor
    private static func optionClickSplitCase(_ manager: BrowserManager, _ observer: Observer, live: CraBrowser, closed: CraBrowser, tab: UUID) async {
        let option = UInt(NSEvent.ModifierFlags.option.rawValue)
        let before = observer.splitLinks.count
        expect(manager.browser(live, opensSplitForDownloadURL: "https://example.test/option", clickModifiers: option, clickAge: 0.05),
               "an Option-clicked link's download becomes a split pane")
        expect(!manager.browser(live, opensSplitForDownloadURL: "https://example.test/plain.zip", clickModifiers: 0, clickAge: 0.05)
               && !manager.browser(live, opensSplitForDownloadURL: "https://example.test/later.zip", clickModifiers: option, clickAge: -1)
               && !manager.browser(closed, opensSplitForDownloadURL: "https://example.test/stale-option", clickModifiers: option, clickAge: 0.05),
               "a plain click's download, one with no click, and a closed page's stay downloads")
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(observer.splitLinks.dropFirst(before).map(\.url) == ["https://example.test/option"] && observer.splitLinks.last?.tab == tab,
               "the Option-clicked link opens beside the live page's tab, once Chromium's call has returned")
    }

    /// A two-finger swipe back over a page asks for the tab its view belongs to (#370): the page's
    /// own Alloy container, its Chrome window, or the views moved out of that window into a card.
    // promise: #370
    @MainActor
    private static func pageViewTabCase(_ manager: BrowserManager, _ runtime: TabRuntime, tab: UUID) {
        let inContainer = NSView()
        runtime.browser.containerView.addSubview(inContainer)
        let host = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        let page = NSView(), inPage = NSView()
        page.addSubview(inPage)
        runtime.browser.hostWindow = host
        EmbeddedPages.viewsByHost[ObjectIdentifier(host)] = [page]
        defer {
            inContainer.removeFromSuperview()
            runtime.browser.hostWindow = nil
            EmbeddedPages.viewsByHost[ObjectIdentifier(host)] = nil
        }
        expect(manager.visibleTabID(ofPageView: inContainer) == tab && manager.visibleTabID(ofPageView: inPage) == tab,
               "a page view in the tab's container, or in its page moved into a card, is the tab's")
        expect(manager.visibleTabID(ofPageView: NSView()) == nil, "a view of no page on screen is no tab's")
    }

    /// Arc's ⌥⌘-click opens a link in a Little Window (#373): only when the switch is on and the page's own
    /// last click had ⌥⌘, not a click made with other keys while ⌥⌘ are down by the time Chromium asks.
    // promise: #373
    @MainActor
    private static func optionCommandLittleWindowCase(_ manager: BrowserManager, _ store: SidebarStore, _ observer: Observer,
                                                      live: CraBrowser, closed: CraBrowser, tab: UUID) {
        let optionCommand = UInt(NSEvent.ModifierFlags([.option, .command]).rawValue)
        let command = UInt(NSEvent.ModifierFlags.command.rawValue)
        let link = "https://example.test/little"
        let before = observer.littleWindowLinks.count
        store.settings.littleWindowOnOptionCommandClick = false
        expect(!manager.browser(live, opensLittleWindowForURL: link, clickModifiers: optionCommand, clickAge: 0.05),
               "with the switch off a ⌥⌘-click stays Chromium's split view click (#298)")
        store.settings.littleWindowOnOptionCommandClick = true
        expect(!manager.browser(live, opensLittleWindowForURL: link, clickModifiers: command, clickAge: 0.05)
               && !manager.browser(live, opensLittleWindowForURL: link, clickModifiers: 0, clickAge: 0.05)
               && !manager.browser(live, opensLittleWindowForURL: link, clickModifiers: optionCommand, clickAge: -1)
               && !manager.browser(closed, opensLittleWindowForURL: link, clickModifiers: optionCommand, clickAge: 0.05),
               "a ⌘-click, a plain click, no click in this page and a closed page's open no Little Window")
        expect(manager.browser(live, opensLittleWindowForURL: link, clickModifiers: optionCommand, clickAge: 0.05),
               "a ⌥⌘-click with the switch on opens one")
        expect(observer.littleWindowLinks.dropFirst(before).map(\.url) == [link] && observer.littleWindowLinks.last?.tab == tab,
               "from the live page's tab, once")
        store.settings.littleWindowOnOptionCommandClick = false
    }

    @MainActor
    static func main() async {
        await sparePagesCase()
        await tabFaviconsCase()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let id = store.createTab(url: "https://example.test/pinned").id
        manager.show(id, focus: false)
        let old = manager.runtime(for: id)!
        let snapshotWork = old.snapshotWork!
        old.browser.onClose = {
            expect(manager.runtime(for: id) == nil, "active ownership is retired before CEF close starts")
        }
        manager.unload(id)
        expect(old.browser.closeRequested && snapshotWork.isCancelled, "unloading requests close and cancels queued snapshot work")
        expect(manager.visibleTabID == nil && old.browser.containerView.superview == nil, "retired page is removed from the visible shell immediately")
        manager.show(id, focus: false)
        let replacement = manager.runtime(for: id)!
        expect(replacement !== old && !replacement.browser.closeRequested, "reopening before CEF close completes creates a live replacement")
        old.browser.navigate(to: "https://example.test/stale")
        expect(store.item(id)?.tab?.url == "https://example.test/pinned", "late navigation from the retired browser cannot change the replacement URL")
        old.browser.closedByPage = true
        old.browser.finishClose()
        expect(manager.runtime(for: id) === replacement && manager.visibleTabID == id && manager.visibleTabIDs == [id],
               "late close cannot remove or deselect the replacement")
        expect(observer.closedTabs.isEmpty, "late page-close cannot archive the replacement tab")
        manager.browserRequestsActivation(old.browser, byPage: false)
        manager.browserRequestsActivation(replacement.browser, byPage: false)
        expect(observer.activatedTabs == [id], "an extension's tabs.update activation reaches only the live page's tab")
        manager.browserRequestsActivation(replacement.browser, byPage: true)
        expect(observer.activatedTabs == [id, id] && observer.activatedByPage == [false, true],
               "a page's own focus request (a notification click) arrives marked as the page's")

        // The page's context menu: Open Link in New Window / Little Window / Incognito Window and
        // Capture Image… go to the window, with the tab's space; a closed page's requests don't.
        manager.browser(replacement.browser, requestsWindowWithURL: "https://example.test/link", kind: .little)
        manager.browser(old.browser, requestsWindowWithURL: "https://example.test/stale", kind: .new)
        expect(observer.openedLinks.map(\.url) == ["https://example.test/link"] && observer.openedLinks.first?.kind == .little
               && observer.openedLinks.first?.space == store.spaceID(ofItem: id) && observer.openedLinks.first?.incognito == false,
               "Open Link in Little Window reaches the window with the tab's space")
        manager.browser(replacement.browser, requestsCaptureOfImageAt: NSPoint(x: 12, y: 34))
        manager.browser(old.browser, requestsCaptureOfImageAt: NSPoint(x: 1, y: 1))
        expect(observer.capturedImages.count == 1 && observer.capturedImages.first?.tab == id
               && observer.capturedImages.first?.point == NSPoint(x: 12, y: 34),
               "Capture Image… reaches the window for the live page's tab only")
        manager.browser(replacement.browser, requestsSplitPaneWithURL: "https://example.test/entry")
        manager.browser(old.browser, requestsSplitPaneWithURL: "https://example.test/stale-entry")
        expect(observer.splitLinks.map(\.url) == ["https://example.test/entry"] && observer.splitLinks.first?.tab == id,
               "Open Link in Split View reaches the window with the live page's tab, a closed page's doesn't")
        await optionClickSplitCase(manager, observer, live: replacement.browser, closed: old.browser, tab: id)
        pageViewTabCase(manager, replacement, tab: id)
        optionCommandLittleWindowCase(manager, store, observer, live: replacement.browser, closed: old.browser, tab: id)

        let retainedID = store.createTab(url: "https://example.test/retained").id
        weak var retainedBrowser = manager.ensureRuntime(for: retainedID)?.browser
        manager.unload(retainedID)
        expect(retainedBrowser != nil, "CEF's weak owner remains alive while asynchronous close is pending")
        retainedBrowser?.finishClose()
        expect(retainedBrowser == nil, "completed teardown releases the retired browser")
        retainedBrowser = nil

        let synchronousID = store.createTab(url: "https://example.test/pending-creation").id
        let synchronous = manager.ensureRuntime(for: synchronousID)!.browser
        synchronous.onClose = { [weak synchronous] in synchronous?.finishClose() }
        manager.unload(synchronousID)
        expect(manager.runtime(for: synchronousID) == nil, "a never-created browser can close synchronously without leaving ownership behind")

        replacement.browser.closedByPage = true
        replacement.browser.finishClose()
        expect(manager.runtime(for: id) == nil && manager.visibleTabID == nil && observer.closedTabs == [id],
               "the active page's own close still removes its runtime and reports the tab close")

        embeddedPageHandoffCase()
        await snapshotCase()
        loadingTabCase()
        themeDataCase()
        await sleepCase("an unchanged idle page sleeps", shouldSleep: true) { _, _ in }
        await sleepCase("loading started while the probe was pending stays awake") { _, rt in rt.browser.setLoading(true) }
        await sleepCase("a completed same-URL reload invalidates the old probe") { _, rt in
            rt.browser.setLoading(true); rt.browser.setLoading(false)
        }
        await sleepCase("navigation invalidates the old document's idle reply") { _, rt in
            rt.browser.navigate(to: "https://example.test/new-document")
        }
        await sleepCase("media capture started while the probe was pending stays awake") { _, rt in rt.browser.isCapturingMedia = true }
        await sleepCase("DevTools opened while the probe was pending stays awake") { _, rt in rt.browser.hasDevTools = true }
        await sleepCase("Picture in Picture started while the probe was pending stays awake") { _, rt in rt.browser.isInPictureInPicture = true }
        await sleepCase("a tab shown before the idle reply stays awake") { manager, rt in manager.show(rt.tabID, focus: false) }
        await sleepCase("a tab shown then hidden again has a fresh idle interval") { manager, rt in
            manager.show(rt.tabID, focus: false); manager.show(nil, focus: false)
        }
        await sleepCase("an old probe cannot unload a replacement runtime") { manager, rt in
            manager.unload(rt.tabID)
            manager.ensureRuntime(for: rt.tabID)?.hiddenAt = Date.distantPast
        }
        await sleepCase("an exception reply cannot authorize sleeping", reply: #"{"exceptionDetails":{},"result":{"value":""}}"#) { _, _ in }
        await sleepCase("a page holding typed text stays awake", reply: #"{"result":{"type":"string","value":"typed"}}"#) { _, _ in }
        await refusalBackoffCase()
        recentTabsCase()
        freezingVoteCase()
        await sleepClockCase()
        await pressureSweepCase()
        await discardCase()
        await discardedPageLoadCase()
        await discardedPageColoursCase()
        await sleepCountsCase()
        shortTimerCase()
        recentlyAudibleCase()
        await audiblePageStaysAwakeCase()
        await suspendedMediaSleepsCase()
        await sweepThatClosesNothingCase()
        devToolsCase()
        extensionTabActivationCase()
        await translationCase()
        await beforeUnloadCase()
        nowPlayingCase()
        await nowPlayingAfterSleepCase()
        await nowPlayingResumeWithinHoldCase()
        musicNotesPauseWithinHoldCase()
        await nowPlayingPictureInPictureCase()
        nowPlayingSkipsPictureInPictureCase()
        await leaveVideoTabPictureInPictureCase()
        await pictureInPicturePerSiteCase()
        await splitCopySleepsPinnedTabCase()
        await coveredWindowPictureInPictureCase()
        await callPictureInPictureCase()
        await playerMediaSessionCase()
        pageColoursCase()
        extensionPageRetryCase()
        await sleepCase("malformed or missing replies cannot authorize sleeping", reply: nil) { _, _ in }
        await pageProbeCase()
        await pageEngineCase()
        pageHistoryCase()
        await permissionWaitsForItsTabCase()
        permissionPopoverStepsAsideCase()
        print("Browser manager lifecycle: \(checks) checks passed")
    }

    @MainActor
    private static func tabFaviconsCase() async {
        let store = SidebarStore()
        let cache = FaviconCache()
        let manager = BrowserManager(store: store, favicons: cache, container: NSView())
        defer { manager.closeAll() }
        let first = store.createTab(url: "https://gitlab.com/projects/pr1").id
        let second = store.createTab(url: "https://gitlab.com/projects/pr2").id
        let firstBrowser = manager.ensureRuntime(for: first)!.browser
        let secondBrowser = manager.ensureRuntime(for: second)!.browser
        let orange = NSImage(contentsOfFile: "Tests/Fixtures/Pages/icon-orange.png")!
        let blue = NSImage(contentsOfFile: "Tests/Fixtures/Pages/icon-blue.png")!
        let iconURL = "https://gitlab.com/favicon.ico"
        manager.browser(firstBrowser, didLoadFavicon: orange, forURL: iconURL)
        manager.browser(secondBrowser, didLoadFavicon: blue, forURL: iconURL)
        let firstKey = store.item(first)!.tab!.faviconKey!
        let secondKey = store.item(second)!.tab!.faviconKey!
        expect(firstKey != secondKey, "tabs with the same favicon URL have independent cache entries")
        expect(cache.image(forKey: firstKey) === orange && cache.image(forKey: secondKey) === blue,
               "loading the second project preserves the first project's icon")
        let orangeColor = cache.dominantColor(forKey: firstKey)
        let blueColor = cache.dominantColor(forKey: secondKey)
        expect(orangeColor != nil && blueColor != nil && orangeColor != blueColor, "the fixture icons have different colors")
        manager.browser(firstBrowser, didLoadFavicon: blue, forURL: "data:image/png;base64,blue")
        expect(store.item(first)?.tab?.faviconKey == firstKey, "a dynamic favicon reuses the tab's cache entry")
        expect(cache.dominantColor(forKey: firstKey) == blueColor, "an updated favicon refreshes its cached color")
        manager.browser(secondBrowser, didLoadFavicon: orange, forURL: iconURL)
        expect(cache.image(forKey: firstKey) === blue && cache.image(forKey: secondKey) === orange,
               "updating a pipeline icon leaves the other project's icon unchanged")

        let privateTab = store.createTab(url: "https://gitlab.com/projects/private").id
        store.incognitoItems.insert(privateTab)
        let privateBrowser = manager.ensureRuntime(for: privateTab)!.browser
        manager.browser(privateBrowser, didLoadFavicon: blue, forURL: iconURL)
        let privateKey = store.item(privateTab)!.tab!.faviconKey!
        expect(privateKey != firstKey && privateKey != secondKey, "an incognito tab has its own favicon")
        let disk = FaviconCache()
        for _ in 0..<100 {
            disk.reset()
            if disk.dominantColor(forKey: firstKey) == blueColor && disk.dominantColor(forKey: secondKey) == orangeColor { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        expect(disk.dominantColor(forKey: firstKey) == blueColor && disk.dominantColor(forKey: secondKey) == orangeColor,
               "a fresh cache restores each project's last icon, including a dynamic favicon")
        expect([firstKey, secondKey].allSatisfy { FileManager.default.fileExists(atPath: AppPaths.favicons.appendingPathComponent(FaviconCache.fileName($0)).path) },
               "each project has its own persisted favicon instead of relying on the host fallback")
        expect(!FileManager.default.fileExists(atPath: AppPaths.favicons.appendingPathComponent(FaviconCache.fileName(privateKey)).path),
               "an incognito favicon is never written to disk")
        manager.unload(first)
        manager.browser(firstBrowser, didLoadFavicon: orange, forURL: iconURL)
        expect(cache.image(forKey: firstKey) === blue, "a retired browser cannot replace a tab's favicon")
    }

    // promise: #80
    /// The line cra.log gets about a page on screen (#80): how many frames the page was asked
    /// for, and which display's refresh rate its window follows.
    @MainActor
    private static func pageProbeCase() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let runtime = manager.ensureRuntime(for: store.createTab(url: "https://example.test/probe").id)!
        var line: String?
        PageProbe.run(runtime.browser) { line = $0 }
        expect(runtime.browser.lastParams.contains(#""awaitPromise":true"#) && runtime.browser.lastParams.contains("frameRate"),
               "the probe waits for the page to count its frames")
        let page = #"{"blank":false,"ready":"complete","visibility":"visible","painted":false,"frameRate":0}"#
        let reply = try! JSONSerialization.data(withJSONObject: ["result": ["type": "string", "value": page]])
        runtime.browser.reply(to: "Runtime.evaluate", with: String(decoding: reply, as: UTF8.self))
        await drainMainQueue()
        expect(line?.hasSuffix("visibility=visible viewport=? scrollHeight=? elements=? children=? painted=0 frameRate=0 video=?") == true,
               "a visible page that was never asked to draw reads frameRate=0")

        // Off every screen, as in a headless run: the window follows no display.
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(runtime.browser.containerView)
        expect(PageProbe.viewState(runtime).hasSuffix(" display=none"), "the view state names the display the page's window is on")
        manager.closeAll()
    }

    /// DRM services open in WebKit (ProtectedMediaSites); a popup keeps its opener's engine; a
    /// navigation the other engine has to show reopens the tab's page there, in its place on screen.
    @MainActor
    private static func pageEngineCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let player = store.createTab(url: "https://open.spotify.com/").id
        let site = store.createTab(url: "https://example.test/a").id
        let other = store.createTab(url: "https://example.test/b").id
        manager.show([site, other], focused: other, focus: false)
        expect(manager.ensureRuntime(for: player)?.browser is WebKitBrowser, "a DRM service's tab opens in WebKit")
        let chromium = manager.runtime(for: site)!.browser
        expect(!(chromium is WebKitBrowser), "any other site opens in Chromium")

        // window.open keeps its opener's engine: WebKit can only fill a web view it made.
        let fromWebKit = manager.browser(manager.runtime(for: player)!.browser, popupHostForURL: "https://example.test/signin", inBackground: true)
        expect(fromWebKit is WebKitBrowser, "a WebKit page's popup host is a WebKit page, whatever its address")
        let fromChromium = manager.browser(chromium, popupHostForURL: "https://open.spotify.com/", inBackground: true)
        expect(fromChromium.map { !($0 is WebKitBrowser) } == true, "a Chromium page's popup host is Chromium's, whatever its address")

        // A POST, or a site Chromium shows: the navigation goes on in Chromium.
        expect(!manager.browser(chromium, handsOffNavigationToURL: "https://www.netflix.com/login", method: "POST"),
               "a POST to a service stays: its body can't move")
        expect(!manager.browser(chromium, handsOffNavigationToURL: "https://example.test/c", method: "GET"), "a Chromium site stays in Chromium")
        await drainMainQueue()
        expect(manager.runtime(for: site)?.browser === chromium, "nothing moved")

        // A link in the left pane to Netflix: the pane's page reopens in WebKit, same split, same focus.
        expect(manager.browser(chromium, handsOffNavigationToURL: "https://www.netflix.com/browse", method: "GET"),
               "Chromium's navigation to a service stops before its request goes out")
        expect(manager.runtime(for: site)?.browser === chromium, "the page moves a turn later, not inside Chromium's callback")
        await drainMainQueue()
        let moved = manager.runtime(for: site)?.browser
        expect(moved is WebKitBrowser && moved?.currentURL == "https://www.netflix.com/browse", "the pane's page opens in WebKit at the address")
        expect(chromium.closeRequested && store.item(site)?.tab?.url == "https://www.netflix.com/browse", "the Chromium page closes; the tab has the new address")
        expect(manager.visibleTabIDs == [site, other] && manager.visibleTabID == other, "the split keeps its panes, order and focus")
        chromium.finishClose()

        // Cra's own navigation in a WebKit page (the URL bar) to another site goes back to Chromium.
        expect(manager.browser(moved!, handsOffNavigationToURL: "https://example.test/typed", method: "GET"),
               "a typed address WebKit doesn't show moves to Chromium")
        expect(!manager.browser(moved!, handsOffNavigationToURL: "https://www.netflix.com/title/1", method: "GET"),
               "a typed address of a service stays in WebKit")
        await drainMainQueue()
        expect(!(manager.runtime(for: site)?.browser is WebKitBrowser) && manager.visibleTabIDs == [site, other], "back in Chromium, in its pane")

        // A tab out of sight gets its page in the other engine at once, so its title and favicon fill in.
        let hidden = manager.ensureRuntime(for: store.createTab(url: "https://t.example.test/x").id)!
        expect(manager.browser(hidden.browser, handsOffNavigationToURL: "https://www.disneyplus.com/", method: "GET"), "a background redirect moves too")
        await drainMainQueue()
        expect(manager.runtime(for: hidden.tabID)?.browser is WebKitBrowser && !manager.visibleTabIDs.contains(hidden.tabID),
               "a hidden tab is reopened in WebKit and stays hidden")

        // WebKit's own fullscreen window covers Cra's: the video is on screen, so no Picture in Picture.
        store.settings.autoPictureInPicture = true
        let player2 = store.createTab(url: "https://www.netflix.com/watch/1").id
        manager.show(player2, focus: false)
        let fullscreen = manager.runtime(for: player2)!.browser as! WebKitBrowser
        fullscreen.isAudible = true
        fullscreen.isContentFullscreen = true
        manager.windowVisibilityChanged(covered: true)
        expect(!fullscreen.replies.contains { $0.method == "Runtime.evaluate" }, "a WebKit page in its own fullscreen isn't sent to Picture in Picture")
        manager.windowVisibilityChanged(covered: false)
        fullscreen.isContentFullscreen = false
        manager.windowVisibilityChanged(covered: true)
        expect(fullscreen.replies.contains { $0.method == "Runtime.evaluate" }, "out of fullscreen, a covered window's playing WebKit page is asked as before")
        manager.windowVisibilityChanged(covered: false)
        store.settings.autoPictureInPicture = false

        // The Site Control Center's Safari's Engine switch: a site off the list moves to WebKit, in its
        // place on screen, and back; the choice holds for the next page of that site.
        let chosen = store.createTab(url: "https://stream.example.test/film").id
        manager.show([chosen, other], focused: chosen, focus: false)
        let before = manager.runtime(for: chosen)!.browser
        manager.reopenInItsEngine(chosen)
        expect(manager.runtime(for: chosen)?.browser === before, "without a choice the page stays where it is")
        PageEngines.choose(.webKit, for: "https://stream.example.test/film")
        manager.reopenInItsEngine(chosen)
        await drainMainQueue()
        expect(manager.runtime(for: chosen)?.browser is WebKitBrowser && manager.visibleTabIDs == [chosen, other] && manager.visibleTabID == chosen,
               "chosen for Safari's engine, the page opens in WebKit in its pane")
        expect(PageEngines.sites.engine(for: "https://stream.example.test/other") == .webKit, "the choice holds for the site")
        PageEngines.choose(.chromium, for: "https://stream.example.test/film")
        manager.reopenInItsEngine(chosen)
        await drainMainQueue()
        expect(!(manager.runtime(for: chosen)?.browser is WebKitBrowser), "chosen back, the page opens in Chromium")
        expect(PageEngines.choices.added.isEmpty && PageEngines.choices.removed.isEmpty, "chosen back, nothing is left on the lists")

        // A late request from a page that already moved changes nothing.
        expect(!manager.browser(chromium, handsOffNavigationToURL: "https://www.netflix.com/", method: "GET"), "a retired page can't move its tab again")
        manager.closeAll()
    }

    // promise: #2 #4
    /// A tab open in another window moves its page over without reloading it (#2), and back to the
    /// first window when that one is used again (#4): the same runtime, its views reattached.
    @MainActor
    private static func embeddedPageHandoffCase() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let host = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20),
                            styleMask: .borderless, backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        defer { EmbeddedPages.viewsByHost[ObjectIdentifier(host)] = nil; host.close() }
        let sourcePane = NSView(), destinationPane = NSView()
        let compositor = NSView(), input = NSView()
        sourcePane.addSubview(compositor)
        host.contentView!.addSubview(input)
        EmbeddedPages.viewsByHost[ObjectIdentifier(host)] = [compositor, input]
        let store = SidebarStore()
        let id = store.createTab(url: "https://example.test/handoff").id
        let source = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let runtime = source.ensureRuntime(for: id)!
        runtime.browser.hostWindow = host
        let released = source.release(id)!
        expect(compositor.superview == nil, "release detaches moved-out compositor/input views before CEF closes")
        expect(input.superview === host.contentView, "release preserves views already in their native host")
        expect(EmbeddedPages.isHost(host) && EmbeddedPages.pageViews(of: host)?.first === compositor,
               "release preserves embedded host and cached view identity")
        let destination = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        observer.onPageWindowsChanged = {
            // Model the existing shell callback: reattach cached views to the new pane.
            guard destination.runtime(for: id) === runtime else { return }
            for view in EmbeddedPages.pageViews(of: host) ?? [] { destinationPane.addSubview(view) }
        }
        destination.delegate = observer
        destination.takeRuntimeFromOtherWindow = { _ in released }
        expect(destination.ensureRuntime(for: id) === runtime && compositor.superview === destinationPane
               && input.superview === destinationPane, "a handoff reuses the same runtime and reattaches its cached views")
        destination.unload(id)
        expect(compositor.superview == nil && input.superview == nil, "unload immediately removes both moved-out drawing and hit-test views")
        runtime.browser.finishClose()
    }

    @MainActor
    private static func snapshotCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://example.test/thumbnail").id
        manager.show(id, focus: false)
        let old = manager.runtime(for: id)!
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let pixels = bitmap.representation(using: .png, properties: [:])!.base64EncodedString()
        await withCheckedContinuation { continuation in
            manager.captureSnapshot(id) { continuation.resume() }
            old.browser.reply(to: "Page.captureScreenshot", with: "{\"data\":\"\(pixels)\"}")
        }
        expect(old.snapshot != nil, "a live page still receives its rendered thumbnail")
        await withCheckedContinuation { continuation in
            manager.captureSnapshot(id) { continuation.resume() }
            manager.unload(id)
            manager.show(id, focus: false)
            old.browser.reply(to: "Page.captureScreenshot", with: "{\"data\":\"\(pixels)\"}")
        }
        expect(manager.runtime(for: id)?.snapshot == nil, "a late thumbnail cannot overwrite the replacement page's snapshot")
        manager.closeAll()
    }

    // promise: #136
    /// A tab shown while its page loads is neither captured nor probed until the load is over
    /// (#136): both ask the renderer for work in the busiest second of the page.
    @MainActor
    private static func loadingTabCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://example.test/loading").id
        let rt = manager.ensureRuntime(for: id)!
        rt.browser.isLoading = true
        manager.show(id, focus: false)
        let probe = rt.probeWork
        expect(rt.snapshotWork == nil && probe != nil, "a page shown while loading gets no thumbnail yet, and a pending probe")
        rt.browser.setLoading(false)
        expect(rt.snapshotWork != nil, "its thumbnail is taken once it has loaded")
        expect(probe?.isCancelled == true && rt.probeWork != nil && rt.probeWork !== probe, "its probe moves to after the load")
        manager.unload(id)
        expect(rt.probeWork == nil && rt.snapshotWork == nil, "unloading drops the pending probe")
        manager.closeAll()
    }

    /// Arc's "Allow websites to get your theme data" (on by default): each page that commits gets the
    /// space's palette as `--arc-palette-*` variables from Cra's world; off, pages get none.
    @MainActor
    private static func themeDataCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://example.test/themed").id
        let rt = manager.ensureRuntime(for: id)!
        let themed = { rt.browser.replies.filter { $0.method == isolatedProbe }.count }
        let before = themed()
        manager.browser(rt.browser, didChangeCommittedLoad: true)
        expect(themed() == before + 1 && rt.browser.lastIsolatedParams.contains("--arc-palette-title: #")
               && rt.browser.lastIsolatedParams.contains("adoptedStyleSheets"), "a committed page gets the theme's variables")
        manager.browser(rt.browser, didChangeCommittedLoad: false)
        expect(themed() == before + 1, "a load that hasn't committed gets nothing yet")
        store.settings.shareThemeWithWebsites = false
        manager.browser(rt.browser, didChangeCommittedLoad: true)
        expect(themed() == before + 1, "with the setting off, pages get none")
        // Arc's "Block Cookie Banners", off by default: on, a committed page gets the banner rules.
        store.settings.blockCookieBanners = true
        manager.browser(rt.browser, didChangeCommittedLoad: true)
        expect(themed() == before + 2 && rt.browser.lastIsolatedParams.contains("__craCookieBanners")
               && rt.browser.lastIsolatedParams.contains("#onetrust-banner-sdk"), "blocking cookie banners hides them on every committed page")
        // Arc's Boosts: a committed page on a boosted site gets the boost's stylesheet and script.
        BrowserManager.boostFor = { url in url.contains("example.test") ? (css: "h1 { color: red }", js: "window.boosted = 1") : nil }
        store.settings.blockCookieBanners = false
        rt.browser.navigate(to: "https://example.test/themed")
        manager.browser(rt.browser, didChangeCommittedLoad: true)
        expect(rt.browser.replies.contains { $0.method == isolatedProbe } && rt.browser.lastIsolatedParams.contains("__craBoost")
               && rt.browser.lastIsolatedParams.contains("h1 { color: red }") && rt.browser.scripts.last == "window.boosted = 1",
               "a boosted site's page gets the boost's CSS and runs its script")
        BrowserManager.boostFor = nil
        manager.closeAll()
    }

    @MainActor
    private static func sleepCase(_ message: String, shouldSleep: Bool = false, reply: String? = idleReply,
                                  mutate: (BrowserManager, TabRuntime) -> Void) async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0  // one page alone; the 10 most recent are kept (recentTabsCase)
        let id = store.createTab(url: "https://example.test/sleep").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(runtime.browser.replies.contains { $0.method == isolatedProbe }, "eligible page receives an asynchronous sleep probe")
        mutate(manager, runtime)
        runtime.browser.reply(to: isolatedProbe, with: reply)
        await drainMainQueue()
        // The page's own onbeforeunload is asked second, in the page's world.
        if runtime.browser.replies.contains(where: { $0.method == "Runtime.evaluate" }) {
            runtime.browser.reply(to: "Runtime.evaluate", with: idleReply)
            await drainMainQueue()
        }
        await finishSleep(runtime.browser)
        expect(asleep(manager, id) == shouldSleep, message)
        manager.closeAll()
    }

    private static let discardedReply = #"{"discarded":true,"processEnded":true}"#

    /// Answers the steps after the page's own probes: Chromium's freezing reasons, then the discard.
    @MainActor
    private static func finishSleep(_ browser: CraBrowser, reasons: String = #"{"reasons":[]}"#,
                                    discard: String? = discardedReply, discardError: String? = nil) async {
        if browser.replies.contains(where: { $0.method == "Cra.getFreezingState" }) {
            browser.reply(to: "Cra.getFreezingState", with: reasons)
            await drainMainQueue()
        }
        if browser.replies.contains(where: { $0.method == "Cra.discard" }) {
            if let discardError { browser.fail("Cra.discard", with: discardError) } else { browser.reply(to: "Cra.discard", with: discard) }
            await drainMainQueue()
        }
    }

    /// Discarded in place, or closed by a CEF that can't discard.
    @MainActor
    private static func asleep(_ manager: BrowserManager, _ id: UUID) -> Bool {
        manager.runtime(for: id).map(\.discarded) ?? true
    }

    // promise: #136
    /// Like Arc, the 10 tabs used last keep their pages however long they have been hidden (#136).
    @MainActor
    private static func recentTabsCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let ids = (0..<13).map { store.createTab(url: "https://example.test/recent\($0)").id }
        let runtimes = ids.map { manager.ensureRuntime(for: $0)! }
        manager.show(ids[12], focus: false)
        for (n, rt) in runtimes.dropLast().enumerated() { rt.hiddenAt = Date(timeIntervalSince1970: Double(n)) }
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        let probed = runtimes.map { $0.browser.replies.contains { $0.method == isolatedProbe } }
        expect(probed == [true, true, true] + Array(repeating: false, count: 10),
               "the visible tab and the 9 hidden most recently stay awake; only older pages are asked")
        manager.closeAll()
    }

    // promise: #136
    /// Like Arc, a page out of sight past the threshold is voted to freeze unless it is one of
    /// the 10 tabs used last; showing it drops the vote (#136).
    @MainActor
    private static func freezingVoteCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let ids = (0..<12).map { store.createTab(url: "https://example.test/freeze\($0)").id }
        let runtimes = ids.map { manager.ensureRuntime(for: $0)! }
        manager.show(ids[11], focus: false)
        for (n, rt) in runtimes.dropLast().enumerated() { rt.hiddenAt = Date(timeIntervalSince1970: Double(n)) }
        let votes = { runtimes.map { rt in rt.browser.replies.filter { $0.method == "Cra.setFreezingVote" }.count } }
        manager.freezeIdleTabs(hiddenLongerThan: 60)
        expect(votes() == [1, 1] + Array(repeating: 0, count: 10) && runtimes[0].freezeVoted && !runtimes[2].freezeVoted,
               "only pages beyond the 10 tabs used last are voted to freeze")
        expect(runtimes[0].browser.lastParams.contains("true") || runtimes[1].browser.lastParams.contains("true"), "the vote says true")
        manager.freezeIdleTabs(hiddenLongerThan: 60)
        expect(votes() == [1, 1] + Array(repeating: 0, count: 10), "a vote already cast is not sent again")
        manager.show(ids[0], focus: false)
        expect(!runtimes[0].freezeVoted && votes()[0] == 2 && runtimes[0].browser.lastParams.contains("false"),
               "showing a frozen tab drops its vote")
        manager.closeAll()
    }

    // promise: #32
    /// A page that refused isn't probed again every minute, only after the back-off or once shown again.
    @MainActor
    private static func refusalBackoffCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0  // one page alone; the 10 most recent are kept (recentTabsCase)
        let id = store.createTab(url: "https://example.test/typed").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        runtime.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
        await drainMainQueue()
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(!runtime.browser.replies.contains { $0.method == isolatedProbe }, "a refused page is not probed again before the back-off")
        runtime.sleepProbeAfter = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(runtime.browser.replies.contains { $0.method == isolatedProbe }, "a refused page is probed again after the back-off")
        manager.closeAll()
    }

    /// Pages made ahead (SparePages): a tab that needs a page takes its profile's spare, made
    /// SparePage.refillDelay after the last page was made, instead of waiting for CEF's window.
    @MainActor
    private static func sparePagesCase() async {
        SparePages.shared.dropAll()
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let first = store.createTab(url: "https://example.test/one").id
        let one = manager.ensureRuntime(for: first)!
        expect(one.browser.takenURL == nil && !one.browser.isSpare, "with no spare yet, the page is made on the spot")
        expect(SparePages.shared.take(profilePath: nil) == nil, "the next spare isn't made on the same click")
        clock.advance(by: SparePage.refillDelay)
        let second = store.createTab(url: "https://example.test/two").id
        let two = manager.ensureRuntime(for: second)!
        expect(two.browser.takenURL == "https://example.test/two", "the next tab takes the spare made after the first and loads its address")
        expect(two.browser.delegate === manager && manager.runtime(for: second)?.browser === two.browser,
               "the taken spare is the tab's page, reporting to its window")
        expect(SparePages.shared.take(profilePath: nil) == nil, "a taken spare is no longer kept")
        clock.advance(by: SparePage.refillDelay)
        let spare = SparePages.shared.take(profilePath: nil)
        expect(spare?.isSpare == true, "another spare is made after it was taken")
        spare?.close()
        manager.closeAll()
        SparePages.shared.dropAll()
    }

    // promise: #32
    /// Tab sleeping on the manager's clock: an hour's threshold and the 10-minute back-off run
    /// in no time, and nothing is asked a second early.
    @MainActor
    private static func sleepClockCase() async {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        manager.protectedRecentTabs = 0  // one page alone; the 10 most recent are kept (recentTabsCase)
        let id = store.createTab(url: "https://example.test/clock").id
        let runtime = manager.ensureRuntime(for: id)!
        func probed() -> Bool { runtime.browser.replies.contains { $0.method == isolatedProbe } }
        clock.advance(by: 3599)
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 3600))
        expect(!probed(), "a page hidden a second short of the threshold is not asked")
        clock.advance(by: 2)
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 3600))
        expect(probed(), "a page hidden past the threshold is asked")
        runtime.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
        await drainMainQueue()
        clock.advance(by: BrowserManager.refusalBackoff - 1)
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 3600))
        expect(!probed(), "a refused page is not asked again inside the back-off")
        clock.advance(by: 1)
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 3600))
        expect(probed(), "a refused page is asked again once the back-off ends")
        manager.closeAll()
    }

    // promise: #153
    /// Under memory pressure (#153) the 3 pages hidden longest are asked, the 10 tabs used last
    /// included; a page refusing inside its back-off doesn't take one of the 3, and a page left
    /// less than 5 minutes ago isn't asked.
    @MainActor
    private static func pressureSweepCase() async {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let ids = (0..<6).map { store.createTab(url: "https://example.test/pressure\($0)").id }
        let runtimes = ids.map { manager.ensureRuntime(for: $0)! }
        for (n, rt) in runtimes.enumerated() { rt.hiddenAt = clock.now.addingTimeInterval(-3600 + Double(n) * 60) }
        runtimes[5].hiddenAt = clock.now.addingTimeInterval(-4 * 60)
        runtimes[0].sleepProbeAfter = clock.now.addingTimeInterval(60)
        func probed() -> [Bool] { runtimes.map { rt in rt.browser.replies.contains { $0.method == isolatedProbe } } }
        manager.sleepIdleTabs(.memoryPressure(.warning))
        expect(probed() == [false, true, true, true, false, false],
               "the 3 pages hidden longest are asked, past a refusing page, none of the 10 used last kept")
        for rt in runtimes[1...3] {
            rt.browser.reply(to: isolatedProbe, with: idleReply)
            await drainMainQueue()
            rt.browser.reply(to: "Runtime.evaluate", with: idleReply)
            await drainMainQueue()
            await finishSleep(rt.browser)
        }
        expect(ids.map { asleep(manager, $0) } == [false, true, true, true, false, false], "the 3 pages are discarded")
        manager.sleepIdleTabs(.memoryPressure(.warning))
        expect(probed()[4] && !probed()[5], "the next sweep takes the next page, not one left 4 minutes ago")
        manager.closeAll()
    }

    // promise: #153
    /// Sleeping discards the page in place (#153): the runtime stays with Chromium's history and
    /// scroll position, showing the tab loads it now, and it holds none of the 10 recent places.
    /// A call with camera and microphone off, or a device, keeps the page awake; a CEF without
    /// Cra.discard closes the page as before.
    @MainActor
    private static func discardCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        func sleepOne(_ reasons: String = #"{"reasons":[]}"#, discard: String? = discardedReply, error: String? = nil) async -> (UUID, TabRuntime) {
            let id = store.createTab(url: "https://example.test/discard").id
            let rt = manager.ensureRuntime(for: id)!
            rt.hiddenAt = Date.distantPast
            manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
            rt.browser.reply(to: isolatedProbe, with: idleReply)
            await drainMainQueue()
            rt.browser.reply(to: "Runtime.evaluate", with: idleReply)
            await drainMainQueue()
            await finishSleep(rt.browser, reasons: reasons, discard: discard, discardError: error)
            return (id, rt)
        }

        let (id, rt) = await sleepOne()
        expect(manager.runtime(for: id) === rt && rt.discarded && manager.sleptTabs.contains(id) && !rt.browser.closeRequested,
               "a discarded page keeps its runtime and browser")
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(!rt.browser.replies.contains { $0.method == isolatedProbe }, "a discarded page isn't asked again")
        manager.show(id, focus: false)
        expect(!rt.discarded && !manager.sleptTabs.contains(id) && rt.browser.replies.contains { $0.method == "Cra.load" },
               "showing a discarded tab loads its page at once")

        let (call, callRT) = await sleepOne(#"{"reasons":["has an active WebRTC connection"],"connectedReasons":[]}"#)
        expect(!callRT.discarded && manager.runtime(for: call) === callRT && callRT.sleepRefusal == "call",
               "a page in a call with camera and microphone off stays awake")
        let (popup, popupRT) = await sleepOne(#"{"reasons":[],"connectedReasons":["connected to HID device"]}"#)
        expect(!popupRT.discarded && manager.runtime(for: popup) === popupRT && popupRT.sleepRefusal == "device",
               "a page whose connected page uses a device stays awake")
        let (old, _) = await sleepOne(error: "'Cra.discard' wasn't found")
        expect(manager.runtime(for: old) == nil && manager.sleptTabs.contains(old), "a CEF without Cra.discard closes the page as before")
        let (busy, busyRT) = await sleepOne(discard: #"{"discarded":false}"#)
        expect(!busyRT.discarded && manager.runtime(for: busy) === busyRT && busyRT.sleepRefusal == "navigating",
               "a page Chromium wouldn't discard is asked again later")
        manager.closeAll()
    }

    // promise: #214
    /// CEF reports a load end for the page a discard just ended (#214). That page isn't there: the
    /// log says nothing, history gets no visit and no Web Store install starts. Loaded again on
    /// waking, it counts.
    @MainActor
    private static func discardedPageLoadCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let url = "https://example.test/discarded-load"
        let id = store.createTab(url: url).id
        let rt = manager.ensureRuntime(for: id)!
        rt.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        rt.browser.reply(to: isolatedProbe, with: idleReply)
        await drainMainQueue()
        rt.browser.reply(to: "Runtime.evaluate", with: idleReply)
        await drainMainQueue()
        await finishSleep(rt.browser)
        let installs = ExtensionStore.shared.webStoreProfiles.count
        expect(rt.discarded, "the page is discarded")
        manager.browser(rt.browser, didFinishLoadingURL: url, title: "Discarded", statusCode: 200)
        expect(store.visits.isEmpty && ExtensionStore.shared.webStoreProfiles.count == installs,
               "a discarded page's load end is no visit and starts no Web Store install")
        manager.show(id, focus: false)
        manager.browser(rt.browser, didFinishLoadingURL: url, title: "Woken", statusCode: 200)
        expect(store.visits == [url] && ExtensionStore.shared.webStoreProfiles.count == installs + 1,
               "the page loaded again on waking is a visit")
        manager.closeAll()
    }

    // promise: #237
    /// The blank document a discard leaves answers the load end's colour probes with white (#237:
    /// every discarded YouTube or GitHub tab saved #FFFFFF, a 2 MB sidebar.json write each, and
    /// woke with a white toolbar). The tab keeps the colours its page reported; woken, the page
    /// reports again.
    @MainActor
    private static func discardedPageColoursCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let id = store.createTab(url: "https://example.test/dark-site").id
        let rt = manager.ensureRuntime(for: id)!
        manager.browser(rt.browser, didReportThemeColor: "#212121")
        manager.browser(rt.browser, didReportBackgroundColor: "#0F0F0F")
        rt.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        rt.browser.reply(to: isolatedProbe, with: idleReply)
        await drainMainQueue()
        rt.browser.reply(to: "Runtime.evaluate", with: idleReply)
        await drainMainQueue()
        await finishSleep(rt.browser)
        expect(rt.discarded, "the page is discarded")
        manager.browser(rt.browser, didReportThemeColor: "#FFFFFF")
        manager.browser(rt.browser, didReportBackgroundColor: "#FFFFFF")
        expect(store.item(id)?.tab?.themeColor == "#212121" && rt.themeColor == "#212121" && rt.backgroundColor == "#0F0F0F",
               "a discarded page's blank document doesn't replace the tab's colours")
        manager.show(id, focus: false)
        manager.browser(rt.browser, didReportThemeColor: "#303030")
        expect(store.item(id)?.tab?.themeColor == "#303030", "the page loaded again on waking reports its colour")
        manager.closeAll()
    }

    // promise: #214
    /// What the recorder says about tab sleeping (#214): a candidate passed over counts once per
    /// reason (the first that holds, TabSleepPolicy.hold), and a page refusing again after the
    /// back-off counts as a retry of the same page, not as another page.
    @MainActor
    private static func sleepCountsCase() async {
        var facts: [(PerfCounter, String)] = []
        Perf.attach { fact in if case .count(let c, let key, _, _) = fact { facts.append((c, key)) } }
        defer { Perf.attach(nil) }
        facts = []  // what earlier cases left in the recorder's start-up buffer
        func counted(_ c: PerfCounter) -> [String] { facts.filter { $0.0 == c }.map(\.1) }
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0

        let loadingID = store.createTab(url: "https://example.test/loading").id
        let loading = manager.ensureRuntime(for: loadingID)!
        loading.hiddenAt = Date.distantPast
        loading.browser.setLoading(true)
        for _ in 0..<3 { manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60)) }
        expect(counted(.sleepSkip) == ["loading"] && !loading.browser.replies.contains { $0.method == isolatedProbe },
               "a loading page passed over three times counts once, as loading")
        loading.browser.setLoading(false)
        loading.browser.hasDevTools = true
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(counted(.sleepSkip) == ["loading", "devTools"], "a new reason counts again")
        loading.browser.hasDevTools = false
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        expect(loading.browser.replies.contains { $0.method == isolatedProbe }, "with nothing holding it the page is asked")
        loading.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
        await drainMainQueue()
        for _ in 0..<2 {
            loading.sleepProbeAfter = Date.distantPast
            manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
            loading.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
            await drainMainQueue()
        }
        expect(counted(.sleepRefusal) == ["typed"] && counted(.sleepRetry) == ["typed", "typed"],
               "one page refusing three times is one refusal and two retries")
        manager.closeAll()
    }

    // promise: #153
    /// "Force tabs out of memory after:" below Arc's 4 hours closes the 10 tabs used last too;
    /// 4 hours and more keep them (#153).
    @MainActor
    private static func shortTimerCase() {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let id = store.createTab(url: "https://example.test/short").id
        let runtime = manager.ensureRuntime(for: id)!
        clock.advance(by: 9 * 3600)
        manager.sleepIdleTabs(.timer(.fourHours))
        manager.sleepIdleTabs(.timer(.eightHours))
        expect(!runtime.browser.replies.contains { $0.method == isolatedProbe }, "at 4 hours or more the tab used last stays")
        manager.sleepIdleTabs(.timer(.twoHours))
        expect(runtime.browser.replies.contains { $0.method == isolatedProbe }, "below 4 hours it is asked")
        manager.closeAll()
    }

    // promise: #153
    /// A page that played sound counts as in use: tab sleeping waits as long after it went quiet
    /// as after it went out of sight (#153).
    @MainActor
    private static func recentlyAudibleCase() {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        manager.protectedRecentTabs = 0
        let id = store.createTab(url: "https://example.test/audible").id
        let runtime = manager.ensureRuntime(for: id)!
        clock.advance(by: 3600)
        manager.browser(runtime.browser, didChangeAudible: true)
        clock.advance(by: 120)
        manager.browser(runtime.browser, didChangeAudible: false)
        clock.advance(by: 14 * 60)
        manager.sleepIdleTabs(.timer(.fifteenMinutes))
        expect(!runtime.browser.replies.contains { $0.method == isolatedProbe }, "a page quiet for 14 minutes isn't asked at 15")
        clock.advance(by: 2 * 60)
        manager.sleepIdleTabs(.timer(.fifteenMinutes))
        expect(runtime.browser.replies.contains { $0.method == isolatedProbe }, "quiet for 16 minutes it is")
        manager.closeAll()
    }

    // promise: #28
    /// A tab playing sound, Web Audio included (Chromium's own audible state, #28), is never put
    /// to sleep, however long it has been out of sight, and one that starts playing while it is
    /// being asked stays awake too.
    @MainActor
    private static func audiblePageStaysAwakeCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let id = store.createTab(url: "https://example.test/playing").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        runtime.browser.isAudible = true
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        manager.sleepIdleTabs(.memoryPressure(.warning))
        expect(!runtime.browser.replies.contains { $0.method == isolatedProbe } && !asleep(manager, id),
               "a page playing sound is never asked to sleep, on the timer or under memory pressure")
        manager.closeAll()
        await sleepCase("a page that starts playing while it is asked stays awake") { _, rt in rt.browser.isAudible = true }
    }

    // promise: #275
    /// Chromium suspends a video in a hidden tab without pausing it: `paused` stays false, nothing
    /// is heard, and Chromium says the tab is silent. Its page sleeps like any quiet one (#275: 35
    /// YouTube tabs refused as "playing" all night while none made a sound). The probe that runs
    /// here is the real one, on a page with such a video.
    @MainActor
    private static func suspendedMediaSleepsCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let id = store.createTab(url: "https://example.test/watch").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        runtime.browser.isAudible = false
        manager.sleepIdleTabs(.memoryPressure(.warning))
        let answer = runProbe(runtime.browser.lastIsolatedParams, media: "[{paused: false, ended: false, muted: false, volume: 1}]")
        runtime.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"\#(answer)"}}"#)
        await drainMainQueue()
        if runtime.browser.replies.contains(where: { $0.method == "Runtime.evaluate" }) {
            runtime.browser.reply(to: "Runtime.evaluate", with: idleReply)
            await drainMainQueue()
        }
        await finishSleep(runtime.browser)
        expect(asleep(manager, id) && runtime.sleepRefusal == nil, "a page whose suspended video makes no sound sleeps under memory pressure")
        manager.closeAll()
    }

    /// The isolated probe's expression, run in JavaScriptCore on a page with these media elements
    /// and nothing typed.
    private static func runProbe(_ params: String, media: String) -> String {
        let json = try! JSONSerialization.jsonObject(with: Data(params.utf8)) as! [String: Any]
        let context = JSContext()!
        context.evaluateScript("var window = {}; var location = {href: 'https://example.test/watch'}; "
            + "var document = {querySelectorAll: () => \(media)};")
        return context.evaluateScript(json["expression"] as? String)?.toString() ?? "no reply"
    }

    // promise: #275
    /// A pressure sweep whose pages all refuse says so once they have answered (#275: after a
    /// wake, twelve sweeps asked 3 pages each and the log had only their headers).
    @MainActor
    private static func sweepThatClosesNothingCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        var logged: [String] = []
        manager.sleepPassLogged = { logged += $0.lines }
        let runtimes = (0..<3).map { n in manager.ensureRuntime(for: store.createTab(url: "https://example.test/editor\(n)").id)! }
        for rt in runtimes { rt.hiddenAt = Date.distantPast }
        manager.sleepIdleTabs(.memoryPressure(.warning))
        for rt in runtimes {
            rt.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
            await drainMainQueue()
        }
        await drainMainQueue()
        expect(logged == ["tab sleep for memory pressure closes nothing: 3 pages refused (typed 3)"],
               "a sweep whose 3 pages refused says why it closed nothing")
        manager.closeAll()
    }

    /// #38: an extension's chrome.tabs.update({active: true}) (SwitchyOmega's Options on its open
    /// settings tab) selects that Cra tab, and only while its page is the tab's live one.
    // promise: #38
    @MainActor
    private static func extensionTabActivationCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let options = store.createTab(url: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html").id
        let other = store.createTab(url: "https://example.test/other").id
        manager.show(options, focus: false)
        let page = manager.runtime(for: options)!.browser
        manager.show(other, focus: false)
        manager.browserRequestsActivation(page, byPage: false)
        expect(observer.activatedTabs == [options] && observer.activatedByPage == [false],
               "the extension's activation asks for its options tab, not the one in front")
        manager.unload(options)
        manager.browserRequestsActivation(page, byPage: false)
        expect(observer.activatedTabs == [options], "a page already closing selects nothing")
        manager.closeAll()
    }

    /// #310: Chromium's translate state reaches the page's runtime (Arc's button and popover read
    /// it there), Arc's toasts go to the window, and Show Original says where the page went back to.
    /// Cra.getTranslateState's languages survive the pushed states, which don't carry them.
    // promise: #310
    @MainActor
    private static func translationCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let id = store.createTab(url: "https://lenta.test/").id
        manager.show(id, focus: false)
        let rt = manager.runtime(for: id)!
        manager.browser(rt.browser, didChangeTranslateState: #"{"url":"https://lenta.test/","source":"ru","current":"ru","target":"en","available":true,"step":"offer"}"#)
        expect(rt.translation?.offersTranslation == true && observer.translationToasts.isEmpty,
               "Chromium's offer gives the page its translate button, with no toast")
        manager.refreshTranslation(id)
        rt.browser.reply(to: "Cra.getTranslateState", with: #"{"url":"https://lenta.test/","source":"ru","current":"ru","target":"en","available":true,"languages":["de","en","ru"]}"#)
        await drainMainQueue()
        manager.translatePage(id, to: "de")
        expect(rt.browser.lastParams == #"{"target":"de"}"#, "Choose Another Language translates to the one picked")
        rt.browser.reply(to: "Cra.translatePage", with: #"{"url":"https://lenta.test/","source":"ru","current":"ru","target":"en","available":true,"pending":true}"#)
        await drainMainQueue()
        manager.browser(rt.browser, didChangeTranslateState: #"{"url":"https://lenta.test/","source":"ru","current":"de","target":"en","available":true,"translated":true,"step":"translated"}"#)
        expect(observer.translationToasts == ["Translated to German"], "a finished translation gets Arc's toast")
        expect(rt.translation?.languages == ["de", "en", "ru"], "the languages outlive the pushed state")
        manager.revertTranslation(id)
        rt.browser.reply(to: "Cra.revertTranslation", with: #"{"url":"https://lenta.test/","source":"ru","current":"ru","target":"en","available":true}"#)
        await drainMainQueue()
        expect(observer.translationToasts.last == "Translated back to Russian" && rt.translation?.translated == false,
               "Show Original goes back to the page's language, with Arc's toast")
        manager.browser(rt.browser, didChangeTranslateState: "{}")
        expect(rt.translation?.offersTranslation == true, "a page with no translate client's empty state changes nothing")
        manager.closeAll()
    }

    /// ⌥⌘I pressed again while CEF is still closing DevTools opens them once they are gone,
    /// instead of closing them a second time. Console and Network switch panels on open DevTools.
    // promise: #138
    @MainActor
    private static func devToolsCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://example.test/devtools").id
        manager.show(id, focus: false)
        let browser = manager.runtime(for: id)!.browser
        manager.runDevTools(.toggle)
        manager.browser(browser, didCreateDevToolsView: NSView())
        manager.runDevTools(.toggle)
        manager.runDevTools(.console)
        expect(browser.devToolsRequests == ["show", "close"], "a press while DevTools close asks CEF for nothing yet")
        manager.browserDidCloseDevTools(browser)
        expect(browser.devToolsRequests == ["show", "close", "show"] && browser.devToolsAction == "console",
               "once CEF reports them closed, the press opens them again, on the Console (#88)")
        manager.browser(browser, didCreateDevToolsView: NSView())
        manager.runDevTools(.inspect)
        expect(browser.devToolsRequests.last == "show" && manager.runtime(for: id)!.devTools.state == .open
               && browser.devToolsAction == "inspect", "Inspect Element on open DevTools keeps them open and arms the picker")
        manager.browser(browser, devToolsShowsPanel: "console")
        manager.runDevTools(.network)
        expect(browser.devToolsRequests.last == "apply network" && manager.runtime(for: id)!.devTools.state == .open,
               "Network on the Console switches the open frontend to Network (#138)")
        manager.browser(browser, devToolsShowsPanel: "network")
        manager.runDevTools(.network)
        expect(browser.devToolsRequests.last == "close" && browser.devToolsAction == nil, "Network on the Network panel closes them")
        manager.closeAll()
    }

    // promise: #32
    /// The page's own onbeforeunload, asked in its world after the isolated probe, keeps it awake.
    @MainActor
    private static func beforeUnloadCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0  // one page alone; the 10 most recent are kept (recentTabsCase)
        let id = store.createTab(url: "https://example.test/editor").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        runtime.browser.reply(to: isolatedProbe, with: idleReply)
        await drainMainQueue()
        runtime.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"beforeunload"}}"#)
        await drainMainQueue()
        expect(manager.runtime(for: id) != nil, "a page with its own onbeforeunload stays awake")
        manager.closeAll()
    }

    // promise: #303
    /// Pausing hides music notes before the speaker's recently-audible hold expires.
    @MainActor
    private static func musicNotesPauseWithinHoldCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://music.youtube.com/watch?v=test").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.browser.isAudible = true
        runtime.soundPlaying = true

        manager.browser(runtime.browser, didChangeSoundPlaying: false)
        expect(!runtime.soundPlaying && runtime.browser.isAudible,
               "music notes stop on pause while the speaker is still recently audible")
        manager.browser(runtime.browser, didChangeSoundPlaying: true)
        expect(runtime.soundPlaying, "music notes resume within the audible hold without a player card")

        manager.unload(id)
        let replacement = manager.ensureRuntime(for: id)!
        manager.browser(runtime.browser, didChangeSoundPlaying: true)
        expect(!replacement.soundPlaying, "a retired page's sound cannot start the replacement's notes")
        manager.closeAll()
    }

    // promise: #33
    /// The sidebar player lists pages that played sound, keeps paused ones, hides the one on
    /// screen, and drops a page that navigates while quiet or closes.
    @MainActor
    private static func nowPlayingCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://example.test/a").id, b = store.createTab(url: "https://example.test/b").id
        let ra = manager.ensureRuntime(for: a)!, rb = manager.ensureRuntime(for: b)!
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeAudible: true)
        expect(np.entries.map(\.id) == [a] && np.entries[0].playing, "a page that starts playing gets a card")
        manager.show(a, focus: false)
        expect(np.shown.isEmpty, "the card of the page on screen is hidden")
        manager.show(b, focus: false)
        expect(np.shown.map(\.id) == [a], "leaving the page shows its card")
        ra.browser.isAudible = false
        manager.browser(ra.browser, didChangeAudible: false)
        expect(np.entries.first?.playing == false, "a paused page keeps its card, marked paused")
        rb.browser.isAudible = true
        manager.browser(rb.browser, didChangeAudible: true)
        expect(np.entries.map(\.id) == [a, b], "cards stack oldest first")
        ra.browser.navigate(to: "https://example.test/elsewhere")
        expect(np.entries.map(\.id) == [b], "a quiet page that navigates leaves the player")
        rb.browser.navigate(to: "https://example.test/next-track")
        expect(np.entries.map(\.id) == [b], "a playing page that navigates (a playlist) keeps its card")
        manager.unload(b)
        expect(np.entries.isEmpty, "closing the page removes its card")
        manager.closeAll()
    }

    // promise: #275
    /// A card follows its page through a sleep (#275): a discarded page leaves the player, as a
    /// closed one does, and on waking the Mac a card reads the tab's sound again, so one Chromium
    /// stopped hearing in the night doesn't stay on "playing".
    @MainActor
    private static func nowPlayingAfterSleepCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://example.test/a").id, b = store.createTab(url: "https://example.test/b").id
        let ra = manager.ensureRuntime(for: a)!, rb = manager.ensureRuntime(for: b)!
        for rt in [ra, rb] {
            rt.browser.isAudible = true
            manager.browser(rt.browser, didChangeAudible: true)
        }
        ra.browser.isAudible = false
        manager.browser(ra.browser, didChangeAudible: false)
        ra.audibleAt = Date.distantPast
        ra.hiddenAt = Date.distantPast
        ra.browser.replies.removeAll()  // the card's media-controls questions
        manager.sleepIdleTabs(TabSleepPolicy(hiddenFor: 60))
        ra.browser.reply(to: isolatedProbe, with: idleReply)
        await drainMainQueue()
        ra.browser.reply(to: "Runtime.evaluate", with: idleReply)
        await drainMainQueue()
        await finishSleep(ra.browser)
        expect(ra.discarded && np.entries.map(\.id) == [b], "a discarded page leaves the player")
        rb.browser.isAudible = false
        manager.systemDidWake()
        expect(np.entries.map(\.id) == [b] && np.entries[0].playing == false,
               "after a wake, a card whose tab no longer sounds reads paused")
        manager.closeAll()
    }

    /// Paused from the sidebar's card, then played again on the page within the 2 s the engine
    /// holds a quiet tab audible: the tab never went quiet, so only its sound starting tells the
    /// card. Before, the card stayed on paused while the page played (Chromium and WebKit, 7 Nov 2026).
    @MainActor
    private static func nowPlayingResumeWithinHoldCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://music.example.test/").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!, rb = manager.ensureRuntime(for: b)!
        manager.show(b, focus: false)
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        manager.browser(ra.browser, didChangeAudible: true)
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"actions":["play","pause"],"pictureInPicture":false}"#)
        await drainMainQueue()
        ra.browser.replies.removeAll()
        manager.performNowPlaying(a, .togglePlayback)
        ra.browser.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"string","value":"playing"}}"#)
        await drainMainQueue()
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"handled":true,"pictureInPicture":false}"#)
        await drainMainQueue()
        expect(np.entries.first?.playing == false, "paused from the card, the card shows paused")
        manager.browser(ra.browser, didChangeSoundPlaying: false)
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        expect(np.entries.first?.playing == true, "the page playing again within the hold shows on the card")
        manager.browser(rb.browser, didChangeSoundPlaying: true)
        expect(np.entries.map(\.id) == [a], "sound alone doesn't make a card: the held audible state does")
        manager.closeAll()
    }

    // promise: #33
    /// The sidebar player (#33) has no card for a tab whose video is in Picture in Picture; the
    /// card comes back when the video leaves it.
    @MainActor
    private static func nowPlayingSkipsPictureInPictureCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://example.test/video").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        manager.show(b, focus: false)
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeAudible: true)
        expect(np.shown.map(\.id) == [a], "a tab playing out of sight has a card")
        ra.browser.isInPictureInPicture = true
        manager.browser(ra.browser, didChangePictureInPicture: true)
        expect(np.shown.isEmpty && np.entries.map(\.id) == [a], "its video in Picture in Picture: no card")
        ra.browser.isInPictureInPicture = false
        manager.browser(ra.browser, didChangePictureInPicture: false)
        expect(np.shown.map(\.id) == [a], "back from Picture in Picture, the card is back")
        manager.closeAll()
    }

    /// The player's Picture in Picture button asks the off-screen page through the protocol, as a
    /// user gesture; only a page with no video of its own (a player in an iframe) gets the
    /// context menu's request. The gesture goes only to a page that has a video: a first look runs
    /// without one, since a gesture also lets the page open pop-ups for a few seconds (#357).
    @MainActor
    private static func nowPlayingPictureInPictureCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.nowPlaying = NowPlaying()
        let a = store.createTab(url: "https://example.test/video").id
        let ra = manager.ensureRuntime(for: a)!
        for (answer, fallback, label) in [("ok", 0, "a page that entered Picture in Picture"),
                                          ("NotAllowedError: denied", 0, "a page that refused"),
                                          ("none", 1, "a page with no video of its own")] {
            let before = ra.browser.pictureInPictureRequests
            manager.performNowPlaying(a, .pictureInPicture)
            expect(ra.browser.lastParams.contains(#""userGesture":false"#), "the first look at the page runs with no user gesture")
            if answer == "none" {
                ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"none"}}"#)
                await drainMainQueue()
                expect(ra.browser.lastParams.contains(#""userGesture":false"#), "a page with no video gets no user gesture")
            } else {
                ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"video"}}"#)
                await drainMainQueue()
                expect(ra.browser.lastParams.contains(#""userGesture":true"#), "the player's request runs as a user gesture")
                ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"\#(answer)"}}"#)
                await drainMainQueue()
            }
            expect(ra.browser.pictureInPictureRequests - before == fallback,
                   "\(label) \(fallback == 1 ? "falls back to" : "does not also get") the page request")
        }
        manager.closeAll()
    }

    /// Leaving a video tab (Arc's automatic Picture in Picture) asks the page through the protocol as
    /// a user gesture, for an audible playing video only. The key press the page path lends the page
    /// raced the tab going hidden, so PiP sometimes never opened (X report, 2 Nov 2026). Only a page
    /// with such a video gets the gesture: leaving any tab handed one out, and with it the right to
    /// open pop-ups for a few seconds (#357).
    // promise: #357
    @MainActor
    private static func leaveVideoTabPictureInPictureCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let a = store.createTab(url: "https://example.test/video").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        store.settings.autoPictureInPicture = true
        manager.show(a, focus: false)
        for (answer, fallback, label) in [("ok", 0, "a page that entered Picture in Picture"),
                                          ("none", 1, "a page with no video of its own"),
                                          (nil, 1, "a page whose answer was lost")] as [(String?, Int, String)] {
            let before = ra.browser.automaticPictureInPictureRequests
            manager.show(b, focus: false)
            expect(!ra.browser.replies.contains { $0.method == "Cra.autoPictureInPicture" }, "a page that isn't capturing goes straight to the video request")
            expect(ra.browser.lastParams.contains(#""userGesture":false"#), "leaving a tab looks for a video with no user gesture")
            expect(ra.browser.lastParams.contains("})(true, false)"), "leaving a video tab takes only an audible, playing video")
            if answer == "ok" {
                ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"video"}}"#)
                await drainMainQueue()
                expect(ra.browser.lastParams.contains(#""userGesture":true"#), "a page with such a video is asked as a user gesture")
                expect(ra.browser.lastParams.contains("})(true, true)"), "and asked for Picture in Picture")
            }
            let reply = answer.map { #"{"result":{"type":"string","value":"\#($0)"}}"# }
            ra.browser.reply(to: "Runtime.evaluate", with: reply)
            await drainMainQueue()
            if answer != "ok" {
                expect(ra.browser.lastParams.contains(#""userGesture":false"#), "\(label) gets no user gesture")
            }
            expect(ra.browser.automaticPictureInPictureRequests - before == fallback,
                   "\(label) \(fallback == 1 ? "falls back to" : "does not also get") the page request")
            manager.show(a, focus: false)
        }
        store.settings.autoPictureInPicture = false
        manager.show(b, focus: false)
        expect(!ra.browser.replies.contains { $0.method.hasSuffix("Runtime.evaluate") }, "with the setting off, leaving the tab asks nothing")
        manager.closeAll()
    }

    /// The Site Control Center's Automatic Picture-In-Picture switch is per site (GitHub #326): a tab
    /// on a site turned off goes out of sight without Picture in Picture, and a tab on another site
    /// still opens it.
    // promise: #326
    @MainActor
    private static func pictureInPicturePerSiteCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let music = store.createTab(url: "https://music.example.test/song").id, video = store.createTab(url: "https://video.example.test/film").id
        let other = store.createTab(url: "https://example.test/other").id
        let rm = manager.ensureRuntime(for: music)!, rv = manager.ensureRuntime(for: video)!
        store.settings.autoPictureInPicture = true
        store.settings.autoPictureInPictureOff = ["music.example.test"]
        manager.show(music, focus: false)
        manager.show(other, focus: false)
        expect(!rm.browser.replies.contains { $0.method == "Runtime.evaluate" }, "a site turned off isn't asked for Picture in Picture")
        manager.show(video, focus: false)
        manager.show(other, focus: false)
        expect(rv.browser.replies.contains { $0.method == "Runtime.evaluate" }, "another site still is")
        manager.closeAll()
    }

    /// ⌥Return in the command bar (or Add Split View) on a pinned video tab: the split shows a Today
    /// copy of the page, and the pinned tab goes to sleep instead of opening its video in Picture in
    /// Picture, so one video plays (Arc; X report, 4 Nov 2026). A plain tab switch still opens it.
    @MainActor
    private static func splitCopySleepsPinnedTabCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        store.settings.autoPictureInPicture = true
        let pinned = store.createTab(url: "https://example.test/video").id
        let rp = manager.ensureRuntime(for: pinned)!
        manager.show(pinned, focus: false)
        var split = TestItem(id: UUID(), tab: nil, isSplit: true)
        var copy = store.createTab(url: "https://example.test/video")
        copy.tab?.activeTabBeforeCreationID = pinned
        copy.parentID = split.id
        store.items[copy.id] = copy
        let empty = store.createTab(url: "").id
        store.items[empty]?.parentID = split.id
        split.children = [copy.id, empty]
        store.items[split.id] = split
        manager.show([copy.id, empty], focused: empty, focus: false)
        expect(!rp.browser.replies.contains { $0.method == "Runtime.evaluate" }, "the pinned tab's video doesn't open in Picture in Picture")
        expect(rp.browser.replies.contains { $0.method == "Cra.discard" }, "the pinned tab the split copied goes to sleep")
        rp.browser.reply(to: "Cra.discard", with: discardedReply)
        await drainMainQueue()
        expect(manager.sleptTabs.contains(pinned), "the pinned tab is asleep, its page loads again when selected")

        // A video tab left for another tab (not its copy) still opens Picture in Picture.
        let video = store.createTab(url: "https://example.test/video2").id
        let rv = manager.ensureRuntime(for: video)!
        manager.show(video, focus: false)
        manager.show(copy.id, focus: false)
        expect(rv.browser.replies.contains { $0.method.hasSuffix("Runtime.evaluate") }, "leaving another video tab still asks for Picture in Picture")
        expect(!rv.browser.replies.contains { $0.method == "Cra.discard" }, "and doesn't put it to sleep")
        manager.closeAll()
    }

    /// A call (Google Meet with "Automatic picture-in-picture" on) registers its own
    /// `enterpictureinpicture` media session handler, which opens a Document Picture in Picture
    /// window of the call. Leaving its tab while it uses the camera or microphone, or its window
    /// going out of sight, drives Chrome's automatic Picture in Picture (`Cra.autoPictureInPicture`),
    /// as Chrome's tab strip and Arc do; coming back has Chrome close the window (GitHub #198).
    /// A page Chrome doesn't ask gets the video request.
    // promise: #198
    @MainActor
    private static func callPictureInPictureCase() async {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let a = store.createTab(url: "https://meet.example.test/abc").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        store.settings.autoPictureInPicture = true
        ra.browser.isCapturingMedia = true
        manager.show(a, focus: false)
        let asked = #"{"asked":true,"pictureInPicture":false}"#, notAsked = #"{"asked":false,"pictureInPicture":false}"#
        let hidden = #"{"tab":"hidden"}"#, shown = #"{"tab":"shown"}"#
        let evaluations = { ra.browser.replies.filter { $0.method == "Runtime.evaluate" }.count }
        let calls = { ra.browser.replies.filter { $0.method == "Cra.autoPictureInPicture" }.count }
        let settle = { while ra.browser.replies.contains(where: { $0.method == "Cra.autoPictureInPicture" }) {
            ra.browser.reply(to: "Cra.autoPictureInPicture", with: "{}") } }

        manager.show(b, focus: false)
        expect(calls() == 1 && ra.browser.lastParams == hidden, "leaving a call's tab drives Chrome's automatic Picture in Picture")
        ra.browser.reply(to: "Cra.autoPictureInPicture", with: asked)
        await drainMainQueue()
        expect(evaluations() == 0 && ra.browser.automaticPictureInPictureRequests == 0, "the page was asked: no video request too")
        clock.advance(by: 30)
        manager.show(a, focus: false)
        expect(calls() == 1 && ra.browser.lastParams == shown, "back on the call's tab, Chrome closes its window")
        settle()
        clock.advance(by: 2)
        expect(calls() == 0, "once: the window was up long before")
        manager.show(b, focus: false)
        manager.show(a, focus: false)
        expect(calls() == 1 && ra.browser.lastParams == hidden, "coming back again closes nothing: the window it opened is gone")
        ra.browser.reply(to: "Cra.autoPictureInPicture", with: asked)
        await drainMainQueue()
        expect(calls() == 1 && ra.browser.lastParams == shown, "back before Chromium answered: the window is closed")
        settle()
        clock.advance(by: 1)
        expect(calls() == 1 && ra.browser.lastParams == shown, "and again a second later, in case it was still opening")
        settle()

        // A Picture in Picture window this page already has stays when the user comes back.
        manager.show(b, focus: false)
        ra.browser.reply(to: "Cra.autoPictureInPicture", with: #"{"asked":false,"pictureInPicture":true}"#)
        await drainMainQueue()
        manager.show(a, focus: false)
        expect(calls() == 0 && evaluations() == 0 && ra.browser.automaticPictureInPictureRequests == 0, "a Picture in Picture already open is left alone")

        // A page Chrome doesn't ask (no handler, no permission), or a Chromium without the method,
        // gets the video request.
        for reply in [notAsked, nil] {
            manager.show(b, focus: false)
            if let reply { ra.browser.reply(to: "Cra.autoPictureInPicture", with: reply) } else { ra.browser.fail("Cra.autoPictureInPicture", with: "not found") }
            await drainMainQueue()
            expect(evaluations() == 1 && ra.browser.lastParams.contains("})(true, false)"), "leaving its tab falls back to the video request")
            ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"none"}}"#)
            await drainMainQueue()
            manager.show(a, focus: false)
        }

        // The window going out of sight: a silent call is asked through Chrome, and never gets the
        // video request, which would send the page the activation key.
        manager.windowVisibilityChanged(covered: true)
        ra.browser.reply(to: "Cra.autoPictureInPicture", with: notAsked)
        await drainMainQueue()
        expect(evaluations() == 0, "a silent call Chrome didn't ask gets no video request on an app switch")
        manager.windowVisibilityChanged(covered: false)
        manager.windowVisibilityChanged(covered: true)
        ra.browser.reply(to: "Cra.autoPictureInPicture", with: asked)
        await drainMainQueue()
        clock.advance(by: 30)
        manager.windowVisibilityChanged(covered: false)
        expect(calls() == 1 && ra.browser.lastParams == shown, "the window back in sight closes the call's window")
        settle()

        ra.browser.isCapturingMedia = false
        manager.show(b, focus: false)
        expect(calls() == 0, "a page not using the camera or microphone isn't driven through Chrome")
        manager.closeAll()
    }

    // promise: #33
    /// The sidebar player in a Chromium tab: Chromium runs the page's media session handlers
    /// (`Cra.mediaSession`, like Arc's media actions) and reports which it has, however early the
    /// page registered them; a page without a play/pause handler has its media elements played or
    /// paused.
    @MainActor
    private static func playerMediaSessionCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://music.example.test/").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        manager.show(b, focus: false)
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeAudible: true)
        expect(ra.browser.replies.contains { $0.method == "Cra.mediaSession" } && ra.browser.lastParams == "{}",
               "a page that starts playing is asked which media session actions it has")
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"actions":["play","pause","nexttrack"],"pictureInPicture":false}"#)
        await drainMainQueue()
        expect(np.entries.first?.hasNext == true && np.entries.first?.hasPrevious == false, "the card offers the track buttons the page answers")
        ra.browser.replies.removeAll()

        manager.performNowPlaying(a, .next)
        expect(ra.browser.lastParams == #"{"action":"nexttrack"}"#, "next track runs the page's handler")
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"handled":true,"pictureInPicture":false}"#)
        await drainMainQueue()
        expect(!ra.browser.replies.contains { $0.method == "cra:Runtime.evaluate" }, "and nothing else")

        manager.performNowPlaying(a, .togglePlayback)
        expect(ra.browser.lastIsolatedParams.contains(#"(\"state\")"#), "play/pause first reads whether the page plays")
        ra.browser.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"string","value":"playing"}}"#)
        await drainMainQueue()
        expect(ra.browser.lastParams == #"{"action":"pause"}"#, "a playing page is paused through its handler")
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"handled":true,"pictureInPicture":false}"#)
        await drainMainQueue()
        expect(np.entries.first?.playing == false && ra.browser.replies.isEmpty, "the card shows it paused")

        manager.performNowPlaying(a, .togglePlayback)
        ra.browser.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"string","value":"paused"}}"#)
        await drainMainQueue()
        ra.browser.reply(to: "Cra.mediaSession", with: #"{"handled":false,"pictureInPicture":false}"#)
        await drainMainQueue()
        expect(ra.browser.lastIsolatedParams.contains(#"(\"play\")"#), "without a handler the page's media elements play")
        ra.browser.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"string","value":"playing"}}"#)
        await drainMainQueue()
        expect(np.entries.first?.playing == true, "the card shows it playing")
        manager.closeAll()
    }

    /// A window out of sight and not key (another app or desktop in front) leaves its video tab
    /// like a tab switch, as Arc's presentPipForOccludedWindow does, and the video comes back when
    /// the window is key again (X report, 1 Nov 2026). Silent pages aren't asked, and a Picture in
    /// Picture the user opened stays.
    @MainActor
    private static func coveredWindowPictureInPictureCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let a = store.createTab(url: "https://example.test/video").id
        let ra = manager.ensureRuntime(for: a)!
        store.settings.autoPictureInPicture = true
        manager.show(a, focus: false)

        manager.windowVisibilityChanged(covered: true)
        expect(ra.browser.replies.isEmpty, "a covered window doesn't ask a silent page")
        manager.windowVisibilityChanged(covered: false)

        ra.browser.isAudible = true
        manager.windowVisibilityChanged(covered: true)
        expect(ra.browser.lastParams.contains(#""userGesture":false"#) && ra.browser.lastParams.contains("})(true, false)"),
               "a covered window asks its playing page for automatic Picture in Picture")
        ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"ok"}}"#)
        await drainMainQueue()
        ra.browser.isInPictureInPicture = true
        manager.browser(ra.browser, didChangePictureInPicture: true)
        expect(ra.browser.isInPictureInPicture, "the tab is still the one in front, but out of sight: the video stays out")
        manager.windowVisibilityChanged(covered: false)
        expect(!ra.browser.isInPictureInPicture, "the window back in sight brings the video home")
        manager.browser(ra.browser, didChangePictureInPicture: false)

        ra.browser.isInPictureInPicture = true
        manager.browser(ra.browser, didChangePictureInPicture: true)
        manager.windowVisibilityChanged(covered: true)
        expect(!ra.browser.replies.contains { $0.method.hasSuffix("Runtime.evaluate") }, "a page already in Picture in Picture isn't asked again")
        manager.windowVisibilityChanged(covered: false)
        expect(ra.browser.isInPictureInPicture, "Picture in Picture the user opened stays when the window shows again")
        PictureInPictureChrome.shared.actions?.close()
        expect(ra.browser.pictureInPictureCloses == 1 && !ra.browser.isInPictureInPicture,
               "the window's close button pauses the video as it comes home (Arc)")
        manager.closeAll()
    }

    // promise: #46 #84
    /// A woken page's toolbar starts in the colour its page last reported (Arc, #46), and a tab
    /// coming on screen asks its page for its background again unless the page is still loading.
    @MainActor
    private static func pageColoursCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let a = store.createTab(url: "https://example.test/dark").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        expect(ra.themeColor.isEmpty, "a page that never reported has no toolbar colour")
        manager.browser(ra.browser, didReportThemeColor: "#203040")
        expect(store.item(a)?.tab?.themeColor == "#203040", "the reported toolbar colour is kept on the tab")
        manager.unload(a)
        let woken = manager.ensureRuntime(for: a)!
        expect(woken !== ra && woken.themeColor == "#203040", "the woken page's toolbar starts in its saved colour")
        let rb = manager.ensureRuntime(for: b)!
        rb.browser.setLoading(true)
        manager.show(b, focus: false)
        expect(rb.browser.backgroundProbes == 0, "a page still loading is not asked: it has no styles yet")
        manager.show(a, focus: false)
        expect(woken.browser.backgroundProbes == 1, "a loaded page coming on screen is asked for its background")
        manager.show(a, focus: false)
        expect(woken.browser.backgroundProbes == 1, "one already on screen is not asked again")
        manager.closeAll()
    }

    /// A restored tab asked for an extension's page before --load-extension loaded it: Chromium
    /// blocked it (ERR_BLOCKED_BY_CLIENT), and the page is loaded again while the extension comes up.
    @MainActor
    private static func extensionPageRetryCase() {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let ext = "abcdefghijklmnopabcdefghijklmnop", url = "chrome-extension://\(ext)/options.html"
        ExtensionStore.shared.entries = [.init(extensionID: ext)]
        let rt = manager.ensureRuntime(for: store.createTab(url: url).id)!
        manager.browser(rt.browser, didFailLoadingURL: url, errorCode: -20)
        clock.advance(by: 0.2)
        expect(rt.browser.loads.isEmpty, "the page is not loaded again before the first wait ends")
        clock.advance(by: 0.1)
        expect(rt.browser.loads == [url], "the blocked page is loaded again once")
        for _ in 1..<ExtensionPageRetry.attempts {
            manager.browser(rt.browser, didFailLoadingURL: url, errorCode: -20)
            clock.advance(by: 4)
        }
        expect(rt.browser.loads.count == ExtensionPageRetry.attempts, "every attempt loads it again")
        manager.browser(rt.browser, didFailLoadingURL: url, errorCode: -20)
        clock.advance(by: 60)
        expect(rt.browser.loads.count == ExtensionPageRetry.attempts, "after the last attempt the error page stays")
        ExtensionStore.shared.webStoreProfiles = []
        manager.browser(rt.browser, didFinishLoadingURL: url, title: "Options", statusCode: 200)
        expect(ExtensionStore.shared.webStoreProfiles == ["Default"],
               "a loaded page lets its profile's imported Web Store copies install from the store (#203)")
        manager.browser(rt.browser, didFailLoadingURL: url, errorCode: -20)
        clock.advance(by: 0.25)
        expect(rt.browser.loads.count == ExtensionPageRetry.attempts + 1, "a page that loaded starts counting again")

        let other = manager.ensureRuntime(for: store.createTab(url: url).id)!
        manager.browser(other.browser, didFailLoadingURL: url, errorCode: -20)
        other.browser.navigate(to: "https://example.test/")
        clock.advance(by: 1)
        expect(other.browser.loads.isEmpty, "a tab that went elsewhere meanwhile stays there")
        ExtensionStore.shared.entries = []
        other.browser.navigate(to: url)
        manager.browser(other.browser, didFailLoadingURL: url, errorCode: -20)
        clock.advance(by: 60)
        expect(other.browser.loads.isEmpty, "an extension that is off in the tab's profile is not retried")
        manager.closeAll()
    }

    // promise: #286
    /// A page behind the tab in front asks nothing until its tab is shown, as in Chrome, and
    /// sheets come one at a time (#286: a page reconnecting after the Mac woke put its
    /// microphone sheet over the tab being read).
    @MainActor
    private static func permissionWaitsForItsTabCase() async {
        AppDialog.presented = []
        let store = SidebarStore()
        let container = NSView()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(container)
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: container)
        let behind = store.createTab(url: "https://meet.example/call").id
        let front = store.createTab(url: "https://example.test/front").id
        manager.show(behind, focus: false)
        let caller = manager.runtime(for: behind)!.browser
        manager.show(front, focus: false)
        var answers: [String] = []
        manager.browser(caller, requestsPermissionForOrigin: "https://meet.example", kinds: 2) { answers.append("mic \($0)") }
        expect(AppDialog.presented.isEmpty && answers.isEmpty, "a page behind the tab in front asks nothing while it is behind")
        manager.show(behind, focus: false)
        expect(AppDialog.presented.map(\.title) == ["https://meet.example wants to use your microphone"],
               "its tab coming to the front puts its sheet up")
        manager.browser(caller, requestsPermissionForOrigin: "https://meet.example", kinds: 8) { answers.append("notifications \($0)") }
        expect(AppDialog.presented.count == 1, "a second request waits for the sheet before it")
        AppDialog.presented[0].answer(.alertFirstButtonReturn)
        expect(answers == ["mic true"] && AppDialog.presented.map(\.title).last == "https://meet.example wants to show notifications",
               "Allow answers the first request, and the next one asks")
        AppDialog.presented[1].answer(.alertSecondButtonReturn)
        expect(answers == ["mic true", "notifications false"], "Block answers the second")

        // A request whose tab closes (or sleeps) before it is shown is dropped, never answered:
        // Chromium forgets it with the page, and an answer would be remembered for the site.
        let other = manager.ensureRuntime(for: front)!.browser
        manager.browser(other, requestsPermissionForOrigin: "https://example.test", kinds: 1) { answers.append("camera \($0)") }
        manager.unload(front)
        await drainMainQueue()
        manager.show(front, focus: false)
        expect(AppDialog.presented.count == 2 && answers.count == 2, "a closed tab's waiting request never asks or answers")

        // A page that moves to another window takes its waiting request along, and asks there
        // once its tab is in front.
        let mover = store.createTab(url: "https://call.example/room").id
        manager.show(mover, focus: false)
        let moving = manager.runtime(for: mover)!.browser
        manager.show(front, focus: false)
        manager.browser(moving, requestsPermissionForOrigin: "https://call.example", kinds: 1 | 2) { answers.append("call \($0)") }
        let otherContainer = NSView()
        let otherWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20),
                                   styleMask: .borderless, backing: .buffered, defer: true)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        otherWindow.contentView!.addSubview(otherContainer)
        let otherManager = BrowserManager(store: store, favicons: FaviconCache(), container: otherContainer)
        otherManager.takeRuntimeFromOtherWindow = { manager.release($0) }
        otherManager.show(mover, focus: false)
        await drainMainQueue()
        expect(otherManager.runtime(for: mover)?.browser === moving
               && AppDialog.presented.map(\.title).last == "https://call.example wants to use your camera and microphone",
               "a page moved to another window asks there")
        AppDialog.presented.last!.answer(.alertFirstButtonReturn)
        expect(answers.last == "call true", "and its answer reaches the page")

        // Chromium withdrew the request (the page navigated): its sheet goes and nothing answers.
        manager.browser(page(manager, front), requestsPermissionForOrigin: "https://example.test", kinds: 4) { answers.append("location \($0)") }
        let sheet = AppDialog.presented.last!
        expect(sheet.title == "https://example.test wants to use your location" && sheet.isUp, "the tab in front asks at once")
        manager.browserWithdrewPermissionRequest(page(manager, front))
        expect(!sheet.isUp && answers.last == "call true", "a withdrawn request's sheet goes, unanswered")
        manager.browser(caller, requestsPermissionForOrigin: "https://meet.example", kinds: 2) { answers.append("mic again \($0)") }
        let before = AppDialog.presented.count
        manager.browser(page(manager, front), requestsPermissionForOrigin: "https://example.test", kinds: 1) { answers.append("camera again \($0)") }
        AppDialog.presented.last!.answer(.alertSecondButtonReturn)
        manager.browserWithdrewPermissionRequest(caller)
        manager.show(behind, focus: false)
        expect(AppDialog.presented.count == before + 1 && answers.last == "camera again false",
               "a withdrawn request waiting behind never asks")
        manager.closeAll()
        otherManager.closeAll()
    }

    // promise: #371
    /// A page's permission request asks in Arc's card over the top left corner of its tab's page,
    /// not a sheet over the window (#371: "wants to access other devices on your network" took
    /// the whole window). The window stays usable, so a tab switch takes the card down
    /// unanswered, and it asks again when its tab is back.
    @MainActor
    private static func permissionPopoverStepsAsideCase() {
        AppDialog.presented = []
        let store = SidebarStore()
        let container = NSView()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(container)
        let webArea = NSView()
        container.addSubview(webArea)
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: container)
        manager.paneHost = { _ in webArea }
        let asking = store.createTab(url: "https://router.example/").id
        let other = store.createTab(url: "https://example.test/").id
        manager.show(asking, focus: false)
        var answers: [Bool] = []
        manager.browser(page(manager, asking), requestsPermissionForOrigin: "https://router.example", kinds: 1 << 7) { answers.append($0) }
        let first = AppDialog.presented.last
        expect(first?.title == "https://router.example wants to access other devices on your local network"
               && first?.anchor === webArea && first?.isUp == true,
               "the request asks in a card on its tab's page")
        manager.show(other, focus: false)
        expect(first?.isUp == false && answers.isEmpty, "switching tabs takes the card down, unanswered")
        manager.show(asking, focus: false)
        let again = AppDialog.presented.last
        expect(AppDialog.presented.count == 2 && again !== first && again?.isUp == true && again?.title == first?.title,
               "its tab back in front asks again")
        again?.answer(.alertFirstButtonReturn)
        expect(answers == [true], "Allow answers it once")
        manager.closeAll()
    }

    @MainActor
    private static func page(_ manager: BrowserManager, _ id: UUID) -> CraBrowser { manager.runtime(for: id)!.browser }

    /// #273: a tab's back and forward list comes from its page a second after it settles and when
    /// it goes off screen, and a new page for the tab (after a relaunch, a close, a wake) opens with
    /// it, as Arc's do. Not once the tab has moved elsewhere, and never for an incognito page.
    // promise: #273
    @MainActor
    private static func pageHistoryCase() {
        let store = SidebarStore()
        let clock = ManualScheduler()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let id = store.createTab(url: "https://example.test/a").id
        manager.show(id, focus: false)
        let first = manager.runtime(for: id)!.browser
        expect(first.restoredHistory == nil, "a tab with nothing saved opens at its address")
        first.navigate(to: "https://example.test/b")
        first.setLoading(true)
        first.setLoading(false)
        clock.advance(by: 1)
        expect(first.replies.contains { $0.method == "Cra.getHistory" }, "a second after the page settles, Cra asks for its list")
        let list = Data([9, 8, 7]).base64EncodedString()
        first.reply(to: "Cra.getHistory", with: #"{"history":"\#(list)","index":1,"url":"https://example.test/b"}"#)

        manager.unload(id)
        manager.show(id, focus: false)
        let second = manager.runtime(for: id)!.browser
        expect(second.restoredHistory?["history"] as? String == list && second.restoredHistory?["index"] as? Int == 1,
               "the tab's next page opens with the saved list, at the entry it was on")

        store.updateTab(id, url: "https://example.test/elsewhere")
        manager.unload(id)
        manager.show(id, focus: false)
        expect(manager.runtime(for: id)!.browser.restoredHistory == nil, "a tab that moved on since opens fresh at its address")

        let secret = store.createTab(url: "https://example.test/secret").id
        store.incognitoItems.insert(secret)
        manager.show(secret, focus: false)
        let page = manager.runtime(for: secret)!.browser
        page.setLoading(false)
        clock.advance(by: 1)
        manager.show(id, focus: false)
        expect(!page.replies.contains { $0.method == "Cra.getHistory" }, "an incognito page's history is never asked for")
        manager.closeAll()
    }

    @MainActor
    private static func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}

@MainActor
private final class Observer: BrowserManagerDelegate {
    var closedTabs: [UUID] = []
    var activatedTabs: [UUID] = []
    var activatedByPage: [Bool] = []
    var onPageWindowsChanged: (() -> Void)?
    func browserManagerDidUpdate(_ tabID: UUID) {}
    func browserManager(statusMessage: String, tabID: UUID?) {}
    func browserManager(findMatches count: Int, activeMatch: Int) {}
    func browserManager(download: CraDownloadInfo) {}
    func browserManager(fullscreen: Bool, tabID: UUID) {}
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView? { nil }
    func browserManagerDevToolsChanged() {}
    func browserManagerDevToolsPageBoundsChanged() {}
    func browserManagerPageWindowsChanged(focus: Bool) { onPageWindowsChanged?() }
    func browserManagerHandleKey(_ event: NSEvent) -> Bool { false }
    func browserManagerHandleUnhandledKey(_ event: NSEvent) -> Bool { false }
    func browserManagerFocusedBrowser(_ tabID: UUID) {}
    func browserManagerPageClosedTab(_ tabID: UUID) { closedTabs.append(tabID) }
    var translationToasts: [String] = []
    func browserManagerTranslationToast(_ tabID: UUID, text: String) { translationToasts.append(text) }
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool) {
        activatedTabs.append(tabID)
        activatedByPage.append(byPage)
    }
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool, newTab: Bool) -> Bool { false }
    var littleWindowLinks: [(url: String, tab: UUID)] = []
    func browserManagerOpensLittleWindow(url: String, fromTab tabID: UUID) -> Bool {
        littleWindowLinks.append((url, tabID))
        return true
    }
    var openedLinks: [(url: String, kind: CraLinkWindow, space: UUID?, incognito: Bool)] = []
    var capturedImages: [(point: NSPoint, tab: UUID)] = []
    func browserManagerOpenLink(_ url: String, in kind: CraLinkWindow, space: UUID?, fromIncognito: Bool) {
        openedLinks.append((url, kind, space, fromIncognito))
    }
    func browserManagerCaptureImage(at point: NSPoint, tabID: UUID) { capturedImages.append((point, tabID)) }
    var splitLinks: [(url: String, tab: UUID)] = []
    func browserManagerOpenLinkInSplit(_ url: String, fromTab tabID: UUID) { splitLinks.append((url, tabID)) }
}
