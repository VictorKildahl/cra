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

    /// A page's full screen ends with its tab (#636): ⌘W on a video in full screen, or the tab moved to another
    /// window, tells the window the page left full screen, so a window the video took full screen comes back.
    /// Chromium's own "left" for a closed page comes too late, once the tab is no longer the window's.
    // promise: #636
    @MainActor
    private static func fullscreenTabClosedCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let video = store.createTab(url: "https://example.test/video").id
        manager.show(video, focus: false)
        let page = manager.runtime(for: video)!.browser
        manager.browser(page, didChangeFullscreen: true)
        expect(observer.fullscreenChanges.map(\.fullscreen) == [true] && observer.fullscreenChanges.last?.tab == video,
               "a page going full screen reaches the window")
        manager.unload(video)
        expect(observer.fullscreenChanges.map(\.fullscreen) == [true, false] && observer.fullscreenChanges.last?.tab == video,
               "closing the tab whose page is in full screen tells the window it left full screen")
        manager.browser(page, didChangeFullscreen: false)
        page.finishClose()
        expect(observer.fullscreenChanges.count == 2, "the closed page's own late answer changes nothing more")

        let plain = store.createTab(url: "https://example.test/plain").id
        manager.show(plain, focus: false)
        manager.unload(plain)
        expect(observer.fullscreenChanges.count == 2, "closing a tab that was never in full screen says nothing about full screen")

        let left = store.createTab(url: "https://example.test/left").id
        manager.show(left, focus: false)
        let leftPage = manager.runtime(for: left)!.browser
        manager.browser(leftPage, didChangeFullscreen: true)
        manager.browser(leftPage, didChangeFullscreen: false)
        manager.unload(left)
        expect(observer.fullscreenChanges.map(\.fullscreen) == [true, false, true, false],
               "a page that already left full screen says nothing more when its tab closes")

        let moved = store.createTab(url: "https://example.test/moved").id
        manager.show(moved, focus: false)
        let movedPage = manager.runtime(for: moved)!.browser
        manager.browser(movedPage, didChangeFullscreen: true)
        let handedOff = manager.release(moved)
        expect(handedOff?.browser === movedPage && observer.fullscreenChanges.last.map { !$0.fullscreen && $0.tab == moved } == true,
               "a tab moved to another window takes its page out of this window's full screen")
        expect(movedPage.exitFullscreenRequests == 1, "and its page leaves full screen, as Chrome's does when a tab is dragged out")
        handedOff?.browser.close()
    }

    @MainActor
    static func main() async {
        downloadSourceAdoptionCase()
        fullscreenTabClosedCase()
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
        sleptPagesBudgetCase()
        timerAsksSixteenCase()
        freezingVoteCase()
        await keepActiveSitesCase()
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
        nowPlayingSkipsUncontrollableSoundCase()
        nowPlayingFollowsMediaSessionCase()
        await leaveVideoTabPictureInPictureCase()
        await webKitPictureInPictureCase()
        webKitPictureInPictureBackToTabCase()
        await pictureInPicturePerSiteCase()
        await splitCopySleepsPinnedTabCase()
        await coveredWindowPictureInPictureCase()
        pictureInPictureMinimizeCase()
        pictureInPictureMinimizeSilentCase()
        await callPictureInPictureCase()
        await playerMediaSessionCase()
        pageColoursCase()
        await toolbarSampleCase()
        syncedDocumentKeepsLivePagesCase()
        extensionPageRetryCase()
        await sleepCase("malformed or missing replies cannot authorize sleeping", reply: nil) { _, _ in }
        await pageProbeCase()
        await pageEngineCase()
        await protectedVideoCase()
        await backgroundTabToastCase()
        backgroundPageStartsHiddenCase()
        pageHistoryCase()
        await permissionWaitsForItsTabCase()
        permissionPopoverStepsAsideCase()
        await askOnPageQuoteCase()
        await askOnPageSnapshotCase()
        findCorrelationCase()
        print("Browser manager lifecycle: \(checks) checks passed")
    }

    @MainActor
    private static func findCorrelationCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let tab = store.createTab(url: "https://example.test/find").id
        let other = store.createTab(url: "https://example.test/other").id
        manager.show(tab, focus: false)
        let original = manager.visibleRuntime!.browser
        manager.find("absent", forward: true)
        let old = manager.findState.request!
        // A native callback already captured its tag before delivery was queued.
        let oldDelivery = {
            manager.browser(original, didFindMatches: 0, activeMatch: 0, generation: old.id, quote: false, identifier: 1, finalUpdate: true)
        }
        manager.prepareFind("matching")
        oldDelivery()
        expect(manager.findState.count == nil && !manager.canAskFind(query: "matching", enabled: true, forward: true),
               "an old final zero delivered after a synchronous edit cannot authorize Ask")
        let current = manager.findState.request!
        manager.browser(original, didFindMatches: 3, activeMatch: 1, generation: current.id, quote: false, identifier: 2, finalUpdate: true)
        expect(observer.findStates.last?.count == 3 && manager.findState.activeMatch == 1,
               "the current browser's tagged native final updates accepted ordinary Find state")
        manager.find("matching", forward: false)
        expect(manager.findState.request?.id == current.id, "next/previous preserve the current native query session")
        for change in 0..<7 {
            manager.find("absent", forward: true)
            let browser = manager.visibleRuntime!.browser
            let request = manager.findState.request!
            manager.browser(browser, didFindMatches: 0, activeMatch: 0, generation: request.id, quote: false, identifier: 3, finalUpdate: true)
            expect(manager.canAskFind(query: "absent", enabled: true, forward: true), "current final zero is eligible before owner changes")
            switch change {
            case 0: browser.setLoading(true); browser.setLoading(false)
            case 1: manager.show(other, focus: false); manager.show(tab, focus: false)
            case 2: store.profilePaths[tab] = "/different-profile"
            case 3: manager.unload(tab); manager.show(tab, focus: false)
            case 4: manager.show([tab, other], focused: other, focus: false)
            case 5: manager.stopFinding(true)
            default: browser.navigate(to: "https://example.test/find")
            }
            manager.browser(browser, didFindMatches: 0, activeMatch: 0, generation: request.id, quote: false, identifier: 3, finalUpdate: true)
            expect(!manager.canAskFind(query: "absent", enabled: true, forward: true),
                   "late final zero cannot survive reload, focus, profile, runtime, split, close or same-URL change (\(change))")
            store.profilePaths[tab] = nil
            manager.show(tab, focus: false)
        }
        manager.find("absent", forward: true, purpose: .quote)
        let quote = manager.findState.request!
        manager.browser(manager.visibleRuntime!.browser, didFindMatches: 0, activeMatch: 0, generation: quote.id, quote: true, identifier: 4, finalUpdate: true)
        expect(manager.findState.count == 0 && !manager.canAskFind(query: "absent", enabled: true, forward: true),
               "quote navigation has results but cannot complete ordinary Find")
        manager.browser(original, requestsFindAction: .show)
        expect(observer.findActions.isEmpty, "retired browser's native command cannot open the current panel")
        manager.browser(manager.visibleRuntime!.browser, requestsFindAction: .next)
        expect(observer.findActions == [.next], "current native Chrome Find is routed to the app Find owner")
        manager.closeAll()
    }

    @MainActor
    private static func resolveAskDocument(_ manager: BrowserManager, mime: String = "text/html") async {
        manager.refreshAskOnPageDocument()
        guard manager.askOnPageDocumentRead != nil, let browser = manager.visibleRuntime?.browser else { return }
        let reply = String(data: try! JSONSerialization.data(withJSONObject: ["result": ["value": [
            "url": browser.currentURL, "contentType": mime]]]), encoding: .utf8)!
        browser.replies.removeLast().completion(reply, nil)
        // The production native callback enqueues its complete mutation before this FIFO marker.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    // promise: #393
    @MainActor
    private static func askOnPageQuoteCase() async {
        let store = SidebarStore(), observer = Observer()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.delegate = observer
        let tab = store.createTab(url: "https://example.test/article").id
        manager.show(tab, focus: false)
        await resolveAskDocument(manager)
        let browser = manager.visibleRuntime!.browser
        let text = "The café opens at 09:30."
        let hit = #"{"result":{"value":{"found":true,"startNode":0,"startOffset":0,"endNode":0,"endOffset":24}}}"#
        let yes = #"{"result":{"value":{"found":true}}}"#, no = #"{"result":{"value":{"found":false}}}"#
        func turn() async { await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } } }
        var results: [Bool?] = [], usable = true
        func start() -> AskOnPage.FindRequest {
            manager.clearAskOnPageQuote()
            let request = manager.prepareFind(text, matchCase: true, purpose: .quote)!
            manager.findAskOnPageQuote(text, in: manager.askOnPageContext()!, request: request,
                                      isCurrent: { usable }) { results.append($0) }
            return request
        }
        let request = start()
        expect(browser.guardedEvaluations.removeFirst()(), "current lookup passes its final setup authorization")
        browser.replies.removeLast().completion(hit, nil); await turn()
        expect(results.isEmpty && manager.findState.request == request, "lookup alone cannot report found or replace quote generation")
        manager.browser(browser, didFindMatches: 99, activeMatch: 1, generation: request.id, quote: true, identifier: 7, finalUpdate: true)
        expect(results.isEmpty, "generic native Find counts never complete a quote DOM operation")
        expect(browser.guardedEvaluations.removeFirst()(), "current effect passes its final setup authorization")
        browser.replies.removeLast().completion(yes, nil); await turn()
        expect(results.count == 1 && results[0] == true && manager.findState.request == request,
               "only the completed current effect reports found using the same quote generation")
        manager.find("ordinary input", forward: false)
        let ordinary = manager.findState.request!
        manager.find("ordinary input", forward: true)
        expect(ordinary.purpose == .ordinary && manager.findState.request == ordinary,
               "ordinary input restores its own generation and repeated next/previous keeps it")
        results.removeAll()
        _ = start(); _ = browser.guardedEvaluations.removeFirst()()
        browser.replies.removeLast().completion(no, nil); await turn()
        expect(results.count == 1 && results[0] == false && browser.guardedEvaluations.isEmpty,
               "a completed exact not-found lookup has no effect phase or native highlight")
        results.removeAll()
        _ = start(); _ = browser.guardedEvaluations.removeFirst()()
        browser.replies.removeLast().completion(hit, nil); await turn()
        usable = false
        expect(!browser.guardedEvaluations.removeFirst()(), "revoked service authority rejects a late effect setup before dispatch")
        await turn()
        expect(results.count == 1 && results[0] == nil, "unavailable/disabled authority retires status rather than inventing not-found")
        usable = true; results.removeAll()
        _ = start(); _ = browser.guardedEvaluations.removeFirst()()
        browser.replies.removeLast().completion(hit, nil); await turn()
        _ = browser.guardedEvaluations.removeFirst()()
        let committedEffect = browser.replies.removeLast().completion
        manager.find("current ordinary", forward: true)
        let afterCommit = manager.findState
        committedEffect(yes, nil); await turn()
        expect(results.count == 1 && results[0] == nil && manager.findState == afterCommit,
               "invalidation after IPC commit still rejects status/native Find and cannot steal ordinary ownership")
        results.removeAll()
        _ = start(); _ = browser.guardedEvaluations.removeFirst()()
        let late = browser.replies.removeLast().completion
        manager.find("restored question", forward: true)
        let restored = manager.findState
        late(hit, nil); await turn()
        expect(results.count == 1 && results[0] == nil && manager.findState == restored && browser.guardedEvaluations.isEmpty,
               "ordinary Find retires pending quote effects and late lookup cannot steal restored ownership")
        results.removeAll()
        _ = start(); _ = browser.guardedEvaluations.removeFirst()()
        browser.replies.removeLast().completion(hit, nil); await turn()
        browser.setLoading(true); browser.setLoading(false)
        expect(!browser.guardedEvaluations.removeFirst()(), "same-URL new navigation invalidates effect setup")
        await turn()
        expect(results.count == 1 && results[0] == nil, "a retired document never publishes quote status")
        manager.closeAll()
    }

    @MainActor
    private static func askOnPageSnapshotCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let tab = store.createTab(url: "https://example.test/article").id
        let other = store.createTab(url: "https://example.test/other").id
        manager.show(tab, focus: false)
        let text = "A complete synthetic article sentence that can be used as page context and quoted."
        let reply = String(data: try! JSONSerialization.data(withJSONObject: ["result": ["value": [
            "url": "https://example.test/article", "title": "Article", "text": text,
            "contentType": "text/html", "truncated": false]]]), encoding: .utf8)!
        let browser = manager.visibleRuntime!.browser
        expect(manager.askOnPageContext() == nil, "Ask remains disabled before actual current document type resolves")
        await resolveAskDocument(manager)
        let context = manager.askOnPageContext()!
        var received: [AskOnPagePrompt.Page?] = []
        manager.askOnPageSnapshot(context) { received.append($0) }
        browser.replies.removeLast().completion(reply, nil)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(received.count == 1 && received[0]?.text == text, "Ask context is returned from the captured current browser")

        for change in 0..<5 {
            await resolveAskDocument(manager)
            let current = manager.askOnPageContext()!
            let active = manager.visibleRuntime!.browser
            received.removeAll()
            manager.askOnPageSnapshot(current) { received.append($0) }
            let complete = active.replies.removeLast().completion
            switch change {
            case 0: active.setLoading(true); active.setLoading(false)
            case 1: manager.show(other, focus: false); manager.show(tab, focus: false)
            case 2: store.profilePaths[tab] = "/different-profile"
            case 3: manager.unload(tab); manager.show(tab, focus: false)
            default: manager.show([tab, other], focused: other, focus: false)
            }
            complete(reply, nil)
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            expect(received.count == 1 && received[0] == nil,
                   "Ask rejects an obsolete snapshot after reload, focus away/back, profile change, replacement or split focus (case \(change))")
            store.profilePaths[tab] = nil
            manager.show(tab, focus: false)
        }
        received.removeAll()
        manager.askOnPageSnapshot(context) { received.append($0) }
        expect(received.count == 1 && received[0] == nil, "an obsolete request is rejected before page evaluation")
        let internalPage = store.createTab(url: "cra://settings").id
        manager.show(internalPage, focus: false)
        expect(manager.askOnPageContext() == nil, "internal browser pages are ineligible before extraction")
        for (url, mime, privatePage) in [
            ("https://example.test/extensionless-pdf", "application/pdf", false),
            ("https://example.test/extensionless-image", "image/svg+xml", false),
            ("https://example.test/extensionless-movie", "video/mp4", false),
            ("https://search.arc.net/article", "text/html", false),
            ("file:///tmp/article.html", "text/html", false),
            ("https://example.test/private", "text/html", true)] {
            let id = store.createTab(url: url).id
            if privatePage { store.incognitoItems.insert(id) }
            manager.show(id, focus: false)
            await resolveAskDocument(manager, mime: mime)
            expect(manager.askOnPageContext() == nil && manager.findPageContext() != nil,
                   "resolved PDF/image/movie, Arc Search, file and private eligibility never disables ordinary Find: \(url)")
        }
        let disguisedHTML = store.createTab(url: "https://example.test/page.pdf").id
        manager.show(disguisedHTML, focus: false)
        await resolveAskDocument(manager, mime: "text/html")
        expect(manager.askOnPageContext() != nil,
               "actual HTML MIME takes precedence over a misleading .pdf suffix")
        expect(AskOnPageDocument.kind(url: URL(string: "https://example.test/document")!, mimeType: "application/pdf") == .pdf
            && AskOnPageDocument.kind(url: URL(string: "https://example.test/document")!, mimeType: "image/svg+xml") == .image
            && AskOnPageDocument.kind(url: URL(string: "https://example.test/document")!, mimeType: "video/mp4") == .movie,
            "resolved UTType conformance rejects MIME subtypes without relying on filename suffixes")
        manager.invalidateAskOnPageDocument()
        manager.refreshAskOnPageDocument()
        let oldTypeReply = manager.visibleRuntime!.browser.replies.removeLast().completion
        manager.visibleRuntime!.browser.setLoading(true)
        manager.visibleRuntime!.browser.setLoading(false)
        manager.refreshAskOnPageDocument()
        let newTypeReply = manager.visibleRuntime!.browser.replies.removeLast().completion
        let oldType = String(data: try! JSONSerialization.data(withJSONObject: ["result": ["value": [
            "url": "https://example.test/page.pdf", "contentType": "text/html"]]]), encoding: .utf8)!
        oldTypeReply(oldType, nil)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(manager.askOnPageContext() == nil && manager.askOnPageDocumentRead != nil,
               "a late same-URL old type probe cannot enable Ask or consume the current type request")
        let newType = String(data: try! JSONSerialization.data(withJSONObject: ["result": ["value": [
            "url": "https://example.test/page.pdf", "contentType": "application/pdf"]]]), encoding: .utf8)!
        newTypeReply(newType, nil)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(manager.askOnPageContext() == nil && manager.askOnPageDocumentRead == nil,
               "current extensionless/resolved PDF evidence stays ineligible after a stale HTML probe")
        for malformed in ["{}", "not JSON", String(repeating: "x", count: 20_001),
            #"{"result":{"value":{"url":"https://example.test/other","contentType":"text/html"}}}"#,
            #"{"result":{"value":{"url":"https://example.test/page.pdf","contentType":""}}}"#,
            #"{"result":{"value":{}},"exceptionDetails":{}}"#] {
            manager.invalidateAskOnPageDocument()
            manager.refreshAskOnPageDocument()
            manager.visibleRuntime!.browser.replies.removeLast().completion(malformed, nil)
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            expect(manager.askOnPageContext() == nil && manager.askOnPageDocument == nil,
                   "malformed, oversized, exception and wrong-document type metadata cannot enable Ask")
        }
        manager.closeAll()
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

    /// Both runtime handoff paths notify the destination before its delegate takes reports.
    @MainActor
    private static func downloadSourceAdoptionCase() {
        for explicitAdoption in [false, true] {
            let store = SidebarStore()
            let tab = store.createTab(url: "https://example.test/downloading").id
            let source = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
            let destination = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
            source.windowID = UUID()
            destination.windowID = UUID()
            let sourceObserver = Observer(), destinationObserver = Observer()
            source.delegate = sourceObserver
            destination.delegate = destinationObserver
            let runtime = source.ensureRuntime(for: tab)!
            var arrivals: [(UUID, UUID)] = []
            destination.pageAdopted = { id, previousWindow in
                expect(runtime.browser.delegate === source, "the original download owner is known before the delegate is redirected")
                arrivals.append((id, previousWindow))
            }
            var reportedTabs: [UUID?] = []
            destinationObserver.onDownload = { _ in reportedTabs.append(destination.downloadSourceTab) }
            var staleReports = 0
            sourceObserver.onDownload = { _ in staleReports += 1 }
            if explicitAdoption {
                _ = source.release(tab)
                _ = destination.adopt(runtime.browser, for: tab, from: "a downloading window's")
            } else {
                destination.takeRuntimeFromOtherWindow = { source.release($0) }
                _ = destination.ensureRuntime(for: tab)
            }
            expect(arrivals.count == 1 && arrivals[0].0 == tab && arrivals[0].1 == source.windowID,
                   "runtime reparenting delivers the exact tab and old window once for source migration")
            runtime.browser.delegate?.browser(runtime.browser, didUpdateDownload: CraDownloadInfo())
            runtime.browser.delegate?.browser(runtime.browser, didUpdateDownload: CraDownloadInfo())
            expect(reportedTabs == [tab, tab] && staleReports == 0 && destination.downloadSourceTab == nil,
                   "progress and terminal reports follow the adopted page's manager with its stable tab identity")
            _ = destination.ensureRuntime(for: tab)
            expect(arrivals.count == 1, "reusing an already-owned runtime must not transfer or recapture its source")
            destination.closeAll()
            runtime.browser.finishClose()
            source.closeAll()
        }
    }

    // promise: #543
    /// Every tab a page opens behind it reaches the window, which toasts it while the sidebar is hidden
    /// (BackgroundTabToast): a ⌘-click or middle click (Chromium's new page, popupHostForURL) and Open
    /// Link in New Tab (requestsNewTabWithURL), not only ⌘Return in the bar. A tab in front says nothing.
    @MainActor
    private static func backgroundTabToastCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let source = store.createTab(url: "https://example.test/source").id
        manager.show(source, focus: false)
        let page = manager.runtime(for: source)!.browser

        _ = manager.browser(page, popupHostForURL: "https://example.test/clicked", inBackground: true)
        let clicked = store.items.values.first { $0.tab?.url == "https://example.test/clicked" }?.id
        expect(clicked != nil && observer.backgroundTabs == [clicked!], "a ⌘-clicked link's background tab reaches the window")

        manager.browser(page, requestsNewTabWithURL: "https://example.test/menu", inBackground: true)
        let menu = store.items.values.first { $0.tab?.url == "https://example.test/menu" }?.id
        expect(menu != nil && observer.backgroundTabs == [clicked!, menu!], "Open Link in New Tab's background tab reaches the window")

        _ = manager.browser(page, popupHostForURL: "https://example.test/front", inBackground: false)
        manager.browser(page, requestsNewTabWithURL: "https://example.test/front2", inBackground: false)
        expect(observer.backgroundTabs.count == 2, "a tab opened in front is no background tab")
        manager.browser(page, requestsNewTabWithURL: "cra://action/nextTab", inBackground: true)
        expect(observer.backgroundTabs.count == 2, "a cra:// link opens nothing, so nothing is said")
        manager.closeAll()
    }

    // promise: #552
    /// A link opened behind the page (Open Link in New Tab with links opening in the background) gets a page
    /// that starts hidden, so its video waits until its tab is shown, as in Arc 1.173.1 (Chromium's ⌘-click
    /// already makes such a page hidden). Every other page starts shown, as Chromium makes it: a tab shown
    /// in front, a link opened in front, a tab an agent opens without showing it, and a spare made ahead.
    /// A background tab that takes a spare has it hidden before it loads.
    @MainActor
    private static func backgroundPageStartsHiddenCase() {
        SparePages.shared.dropAll()
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let source = store.createTab(url: "https://example.test/source").id
        manager.show(source, focus: false)
        let page = manager.runtime(for: source)!.browser
        expect(!page.startedHidden, "a tab shown in front starts shown")
        func tab(_ url: String) -> UUID? { store.items.values.first { $0.tab?.url == url }?.id }
        func opened(_ url: String) -> CraBrowser? { tab(url).flatMap { manager.runtime(for: $0)?.browser } }

        manager.browser(page, requestsNewTabWithURL: "https://example.test/behind", inBackground: true)
        let behind = opened("https://example.test/behind")
        expect(behind?.startedHidden == true && behind?.takenURL == nil, "Open Link in New Tab behind the page makes its page hidden")

        clock.advance(by: SparePage.refillDelay)
        manager.browser(page, requestsNewTabWithURL: "https://example.test/behind-spare", inBackground: true)
        let spared = opened("https://example.test/behind-spare")
        expect(spared?.takenURL == "https://example.test/behind-spare" && spared?.startedHidden == true,
               "a background link that takes a spare hides it before it loads")

        clock.advance(by: SparePage.refillDelay)
        manager.browser(page, requestsNewTabWithURL: "https://example.test/front", inBackground: false)
        let front = tab("https://example.test/front")
        expect(front != nil, "a link opened in front makes a tab")
        if let front { manager.show(front, focus: true) }
        let frontPage = front.flatMap { manager.runtime(for: $0)?.browser }
        expect(frontPage?.takenURL == "https://example.test/front" && frontPage?.startedHidden == false,
               "a link opened in front takes the spare shown")

        clock.advance(by: SparePage.refillDelay)
        let spare = SparePages.shared.take(profilePath: nil)
        expect(spare != nil && spare?.startedHidden == false, "a spare is made shown: the tab that takes it decides")
        spare?.close()

        let agent = store.createTab(url: "https://example.test/agent", select: false).id
        expect(manager.ensureRuntime(for: agent)?.browser.startedHidden == false,
               "a tab whose page is made without being shown (an agent's tab_open) starts shown")
        let restored = store.createTab(url: "https://example.test/restored").id
        manager.show(restored, focus: true)
        expect(manager.runtime(for: restored)?.browser.startedHidden == false, "a restored tab selected later starts shown")
        manager.closeAll()
        SparePages.shared.dropAll()
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

    /// A mixed site's page (YouTube) that asks for Widevine (ProtectedVideoPages): the window is told to
    /// ask; Once moves that page to WebKit with its place in the video and the site's cookies, in its
    /// pane; the tab's next video goes back to Chromium; with Always the page moves unasked; the Site
    /// Control Center's row takes it back.
    @MainActor
    private static func protectedVideoCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let observer = Observer()
        manager.delegate = observer
        let film = "https://www.youtube.com/watch?v=film1"
        let tab = store.createTab(url: film).id
        let other = store.createTab(url: "https://example.test/b").id
        manager.show([tab, other], focused: other, focus: false)
        func answer(_ value: String) -> String { #"{"result":{"type":"string","value":"\#(value)"}}"# }
        func pending(_ browser: CraBrowser, _ method: String) -> Int { browser.replies.filter { $0.method == method }.count }
        let sites = PageEngines.sites

        // Only a mixed site's Chromium page is asked to tell when it wants Widevine.
        let plain = manager.runtime(for: other)!.browser
        plain.navigate(to: "https://example.test/c")
        expect(pending(plain, "cra:Runtime.evaluate") == 0, "an ordinary site's page isn't asked about Widevine")
        let chromium = manager.runtime(for: tab)!.browser
        expect(!(chromium is WebKitBrowser), "a mixed site's page opens in Chromium")
        chromium.navigate(to: film)
        expect(pending(chromium, "cra:Runtime.evaluate") == 1 && chromium.lastIsolatedParams.contains("drmNext"),
               "a mixed site's page is asked to tell when it wants Widevine, and left waiting")

        // It asks: the window is told, and the page is asked for its next request.
        observer.protectedVideoPrompts = []
        chromium.reply(to: "cra:Runtime.evaluate", with: answer(film))
        await drainMainQueue()
        expect(observer.protectedVideoPrompts == [tab], "the window is told a prompt is due")
        expect(PageEngines.videoPages.prompt(tab: tab, url: film, incognito: false, sites: sites)?.choices == [.once, .always], "Once and Always")
        expect(pending(chromium, "cra:Runtime.evaluate") == 1, "the page is asked for the request after this one")
        expect(manager.runtime(for: tab)?.browser === chromium, "nothing moves before the answer")

        // Once: its place in the video and the site's cookies go along, and the pane keeps its place.
        chromium.reply(to: "cra:Runtime.evaluate", with: answer(""))  // the waiting ask, taken over
        manager.switchToSafariEngine(tab, how: .once)
        manager.switchToSafariEngine(tab, how: .once)
        expect(pending(chromium, "cra:Runtime.evaluate") == 1 && pending(chromium, "Network.getAllCookies") == 1, "asked once for its time and its cookies")
        chromium.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"number","value":754.6}}"#)
        chromium.reply(to: "Network.getAllCookies", with: #"{"cookies":[{"name":"SID","value":"s","domain":".youtube.com","path":"/","expires":-1,"session":true},{"name":"SID","value":"g","domain":".google.com","path":"/","expires":-1,"session":true},{"name":"bank","value":"b","domain":".bank.example","path":"/","expires":-1,"session":true}]}"#)
        await drainMainQueue()
        let moved = manager.runtime(for: tab)?.browser
        expect(moved is WebKitBrowser && moved?.currentURL == film + "&t=754s", "Once opens the page in WebKit at its address and time")
        expect(WebKitStores.added.last?.cookies.map(\.domain) == [".youtube.com"] && WebKitStores.added.last?.incognito == false,
               "the site's own cookies are copied to the profile's WebKit store, not Google's or any other site's")
        expect(chromium.closeRequested && manager.visibleTabIDs == [tab, other] && manager.visibleTabID == other, "the split keeps its panes, order and focus")
        expect(PageEngines.choices.protectedVideos.isEmpty, "Once keeps nothing for the site")
        chromium.finishClose()

        // The same video and the sign-in stay; an address typed for the same video stays too.
        moved!.navigate(to: film + "&t=800s")
        moved!.navigate(to: "https://accounts.google.com/ServiceLogin?service=youtube")
        await drainMainQueue()
        expect(manager.runtime(for: tab)?.browser === moved, "the switched page stays in WebKit for its video and the sign-in")
        expect(!manager.browser(moved!, handsOffNavigationToURL: film, method: "GET"), "its own address typed again stays in WebKit")

        // The next video (YouTube changes the address without a navigation): back to Chromium, in its pane.
        moved!.navigate(to: "https://www.youtube.com/watch?v=cat")
        expect(manager.runtime(for: tab)?.browser === moved, "the page moves a turn later, not inside WebKit's callback")
        await drainMainQueue()
        let back = manager.runtime(for: tab)!.browser
        expect(!(back is WebKitBrowser) && back.currentURL == "https://www.youtube.com/watch?v=cat", "another video is Chromium's again")
        expect(PageEngines.videoPages.switched[tab] == nil && manager.visibleTabIDs == [tab, other], "the switch was that page's only")

        // Always, kept for the site: the next page that asks moves without a prompt.
        let youTube = sites.mixedSite(for: film)!
        PageEngines.switchProtectedVideos(true, on: youTube)
        back.navigate(to: film)
        observer.protectedVideoPrompts = []
        back.reply(to: "cra:Runtime.evaluate", with: answer(film))
        await drainMainQueue()
        expect(PageEngines.videoPages.prompt(tab: tab, url: film, incognito: false, sites: sites) == nil, "with Always there is no prompt")
        back.reply(to: "cra:Runtime.evaluate", with: answer(""))
        back.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"number","value":-1}}"#)
        back.fail("Network.getAllCookies", with: "no cookies today")
        await drainMainQueue()
        let always = manager.runtime(for: tab)?.browser
        expect(always is WebKitBrowser && always?.currentURL == film, "with Always the page moves by itself, even when its cookies can't be copied")
        expect(PageEngines.videoPages.switched[tab]?.how == .always, "it is a page switched for the site's Always")

        // The row turned off on the switched page: back to Chromium, and that page isn't asked about again.
        PageEngines.switchProtectedVideos(false, on: youTube)
        manager.returnToChromium(tab)
        always!.reply(to: "cra:Runtime.evaluate", with: #"{"result":{"type":"number","value":90}}"#)
        await drainMainQueue()
        let returned = manager.runtime(for: tab)!.browser
        expect(!(returned is WebKitBrowser) && returned.currentURL == film + "&t=90s", "turned off, the page is Chromium's again, at its time")
        returned.navigate(to: film + "&t=90s")
        returned.reply(to: "cra:Runtime.evaluate", with: answer(film))
        await drainMainQueue()
        expect(PageEngines.videoPages.prompt(tab: tab, url: film, incognito: false, sites: sites) == nil && manager.runtime(for: tab)?.browser === returned,
               "a page taken back isn't asked about again")
        expect(PageEngines.choices.protectedVideos.isEmpty, "nothing is left of the choice")
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
        BrowserManager.boostFor = { url, engineTints in
            url.contains("example.test") ? (css: "h1 { color: red }", js: "window.boosted = 1", tint: engineTints ? "0.7,0.125,0.27,0.5,0.108,0.838" : nil) : nil
        }
        store.settings.blockCookieBanners = false
        rt.browser.navigate(to: "https://example.test/themed")
        manager.browser(rt.browser, didChangeCommittedLoad: true)
        expect(rt.browser.replies.contains { $0.method == isolatedProbe } && rt.browser.lastIsolatedParams.contains("__craBoost")
               && rt.browser.lastIsolatedParams.contains("h1 { color: red }") && rt.browser.scripts.last == "window.boosted = 1",
               "a boosted site's page gets the boost's CSS and runs its script")
        expect(rt.browser.boostTint == "0.7,0.125,0.27,0.5,0.108,0.838", "and the engine its colours, drawn around images (#602)")
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

    // promise: #616
    /// Hundreds of pages crossing the four-hour line in one minute were all asked at once, three page
    /// evaluations each. The clock's pass asks 16; the rest are asked on the next passes.
    @MainActor
    private static func timerAsksSixteenCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.protectedRecentTabs = 0
        let ids = (0..<24).map { store.createTab(url: "https://example.test/timer\($0)").id }
        let runtimes = ids.map { manager.ensureRuntime(for: $0)! }
        for rt in runtimes { rt.hiddenAt = Date.distantPast }
        manager.sleepIdleTabs(.timer(.fifteenMinutes))
        let asked = runtimes.filter { $0.browser.replies.contains { $0.method == isolatedProbe } }.count
        expect(asked == 16, "one pass of the clock asks 16 pages, not all 24 (#616), asked \(asked)")
        manager.closeAll()
    }

    // promise: #616
    /// Slept pages kept their browser and window for the whole session. Past the window's budget the ones
    /// hidden longest close, a few a pass; the page on screen, pages not slept and busy ones stay, and a
    /// closed one gets a new page when its tab is shown.
    @MainActor
    private static func sleptPagesBudgetCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let ids = (0..<8).map { store.createTab(url: "https://example.test/slept\($0)").id }
        let runtimes = ids.map { manager.ensureRuntime(for: $0)! }
        manager.show(ids[7], focus: false)
        for (n, rt) in runtimes.dropLast().enumerated() {
            rt.hiddenAt = Date(timeIntervalSince1970: Double(n))
            rt.discarded = n != 6  // the one hidden last is still awake
        }
        let closed = manager.closeSleptPages(budget: 3, limit: 2)
        expect(closed == 2 && manager.runtime(for: ids[0]) == nil && manager.runtime(for: ids[1]) == nil,
               "the two slept pages hidden longest close first (#616)")
        expect(manager.closeSleptPages(budget: 3, limit: 2) == 1 && manager.runtime(for: ids[2]) == nil,
               "the next pass closes the rest past the budget")
        expect(manager.closeSleptPages(budget: 3, limit: 2) == 0, "three slept pages are kept")
        expect([3, 4, 5, 6, 7].allSatisfy { manager.runtime(for: ids[$0]) != nil },
               "the latest slept pages, the page not slept and the page on screen keep their pages")
        let again = manager.ensureRuntime(for: ids[0])
        expect(again != nil && again !== runtimes[0] && again?.discarded == false, "a closed page's tab gets a new page when shown")
        manager.closeAll()
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

    // promise: #458
    /// Settings ▸ Tabs ▸ "Always keep these sites active" (#458): a quiet page on a listed site
    /// outlasts the clock and gets no freezing vote, while one on another site sleeps and is voted
    /// to freeze. Under memory pressure it goes after the others. Taking the site off the list makes
    /// it a candidate again on the next pass.
    @MainActor
    private static func keepActiveSitesCase() async {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        manager.protectedRecentTabs = 0
        store.settings.keepActiveHosts = ["dashboard.example.test"]
        let keptID = store.createTab(url: "https://dashboard.example.test/live").id
        let otherID = store.createTab(url: "https://news.example.test/").id
        let kept = manager.ensureRuntime(for: keptID)!, other = manager.ensureRuntime(for: otherID)!
        kept.hiddenAt = clock.now
        other.hiddenAt = clock.now.addingTimeInterval(10)
        clock.advance(by: 9 * 3600)
        func probed(_ rt: TabRuntime) -> Bool { rt.browser.replies.contains { $0.method == isolatedProbe } }
        manager.sleepIdleTabs(.timer(.fifteenMinutes))
        expect(!probed(kept) && probed(other), "past the idle time, the kept site's page isn't asked to sleep; the other site's is")
        manager.freezeIdleTabs(hiddenLongerThan: 60)
        expect(!kept.freezeVoted && other.freezeVoted, "the kept site's page gets no freezing vote; the other one does")
        other.browser.reply(to: isolatedProbe, with: idleReply)
        await drainMainQueue()
        other.browser.reply(to: "Runtime.evaluate", with: idleReply)
        await drainMainQueue()
        await finishSleep(other.browser)
        expect(asleep(manager, otherID) && !asleep(manager, keptID), "the other site's page sleeps; the kept one stays loaded")
        manager.sleepIdleTabs(.memoryPressure(.critical))
        expect(probed(kept), "under memory pressure, with no other page left to ask, the kept site's page is asked last")
        kept.browser.reply(to: isolatedProbe, with: #"{"result":{"type":"string","value":"typed"}}"#)
        await drainMainQueue()
        kept.sleepProbeAfter = nil
        store.settings.keepActiveHosts = []
        manager.freezeIdleTabs(hiddenLongerThan: 60)
        expect(kept.freezeVoted, "taken off the list, its page is voted to freeze on the next pass")
        manager.sleepIdleTabs(.timer(.fifteenMinutes))
        expect(probed(kept), "and the clock asks it to sleep again")
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

    // promise: #411
    /// A notification ding (a sound under 5 s) or Web Audio alone makes no player card (#411):
    /// Arc's player follows Chromium's media session, which Chrome's media controls only offer
    /// once it is controllable. Media that starts in the same tab, even within the ding's 2 s
    /// hold, gets its card.
    @MainActor
    private static func nowPlayingSkipsUncontrollableSoundCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://chat.example.test/").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        manager.show(b, focus: false)
        ra.browser.hasUncontrollableSound = true
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        manager.browser(ra.browser, didChangeAudible: true)
        expect(np.entries.isEmpty, "a notification ding makes no card")
        manager.browser(ra.browser, didChangeSoundPlaying: false)
        ra.browser.hasUncontrollableSound = false
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        expect(np.entries.map(\.id) == [a] && np.entries.first?.playing == true,
               "a video that starts within the ding's hold gets its card")
        manager.closeAll()
    }

    // promise: #411
    /// On Chrome's framework the sidebar player follows the page's media session, as Arc's (#411):
    /// a track that ends leaves 2.5 s later, a pause keeps its card, a next track within the wait
    /// keeps it, and a ding or Web Audio sound (its speaker shows) neither plays a paused card nor
    /// makes one.
    @MainActor
    private static func nowPlayingFollowsMediaSessionCase() {
        let clock = ManualScheduler()
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: clock)
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://music.example.test/").id, b = store.createTab(url: "https://example.test/other").id
        let ra = manager.ensureRuntime(for: a)!
        manager.show(b, focus: false)
        ra.browser.reportsMediaSession = true
        let card = { np.entries.first { $0.id == a } }

        // A ding or Web Audio: the speaker, no card.
        ra.browser.isAudible = true
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        manager.browser(ra.browser, didChangeAudible: true)
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: false)
        expect(np.entries.isEmpty, "a ding makes no card")
        manager.browser(ra.browser, didChangeMediaSessionState: .inactive, controllable: false)
        manager.browser(ra.browser, didChangeSoundPlaying: false)
        manager.browser(ra.browser, didChangeAudible: false)

        // A track plays, then pauses for longer than any hold.
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: true)
        expect(card()?.playing == true, "media playing makes a playing card")
        manager.browser(ra.browser, didChangeMediaSessionState: .suspended, controllable: true)
        clock.advance(by: 60)
        expect(card()?.playing == false, "a paused track keeps its card, paused")

        // A ding in the paused tab: the speaker shows it, the card stays paused.
        manager.browser(ra.browser, didChangeSoundPlaying: true)
        manager.browser(ra.browser, didChangeAudible: true)
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: false)
        expect(card()?.playing == false, "a ding doesn't play a paused card")
        manager.browser(ra.browser, didChangeMediaSessionState: .inactive, controllable: false)
        manager.browser(ra.browser, didChangeSoundPlaying: false)
        manager.browser(ra.browser, didChangeAudible: false)
        clock.advance(by: 10)
        expect(card()?.playing == false, "the ding's session ending leaves the paused card")

        // Played again, then the track ends; the next one starts within the wait.
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: true)
        manager.browser(ra.browser, didChangeMediaSessionState: .inactive, controllable: false)
        clock.advance(by: 1)
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: true)
        clock.advance(by: 5)
        expect(card()?.playing == true, "a next track within the wait keeps the card; the old wait can't remove it")

        // The last track ends, a ding plays within the wait: the card goes all the same.
        manager.browser(ra.browser, didChangeMediaSessionState: .inactive, controllable: false)
        clock.advance(by: 1)
        manager.browser(ra.browser, didChangeMediaSessionState: .active, controllable: false)
        expect(card() != nil, "the card waits before it goes")
        clock.advance(by: 2)
        expect(card() == nil, "a track that ended leaves the player 2.5 s later, a ding or not")
        manager.browser(ra.browser, didChangeMediaSessionState: .inactive, controllable: false)
        expect(np.entries.isEmpty, "the ding's end makes no card")
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

    /// The page's videos (JavaScript object literals) as the look in these Runtime.evaluate params
    /// finds them: "video" when there is one to ask, "none" otherwise.
    private static func runLook(_ params: String, videos: String) -> String {
        let json = try! JSONSerialization.jsonObject(with: Data(params.utf8)) as! [String: Any]
        let context = JSContext()!
        context.evaluateScript("var document = {pictureInPictureElement: null, querySelectorAll: () => \(videos)};")
        return context.evaluateScript(json["expression"] as? String)?.toString() ?? "no reply"
    }

    /// A service in WebKit whose player made its video with `disablePictureInPicture`, as Netflix's
    /// does: the sidebar player's Picture in Picture button found no video and did nothing, and a
    /// WebKit page has no engine request to fall back on (#585). The user's ask takes the video, and
    /// so does leaving its tab; a Chromium page (where Chromium refuses such a video) leaves it alone.
    // promise: #585
    @MainActor
    private static func webKitPictureInPictureCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        manager.nowPlaying = NowPlaying()
        let service = store.createTab(url: "https://www.netflix.com/watch/1").id, plain = store.createTab(url: "https://example.test/video").id
        let webKit = manager.ensureRuntime(for: service)!.browser, chromium = manager.ensureRuntime(for: plain)!.browser
        expect(webKit is WebKitBrowser && !(chromium is WebKitBrowser), "the service's page is WebKit's, the other Chromium's")
        let film = "[{disablePictureInPicture: true, readyState: 4, paused: false, ended: false, muted: false, volume: 1, videoWidth: 1920, "
            + "getBoundingClientRect: () => ({width: 1280, height: 720})}]"

        manager.performNowPlaying(service, .pictureInPicture)
        expect(runLook(webKit.lastParams, videos: film) == "video", "the player's button finds a WebKit page's video whose player opted out")
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"video"}}"#)
        await drainMainQueue()
        expect(webKit.lastParams.contains(#""userGesture":true"#) && webKit.lastParams.contains("webkitSetPresentationMode"),
               "and asks it, with WebKit's own presentation mode behind the standard request")
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"ok"}}"#)
        await drainMainQueue()

        manager.performNowPlaying(service, .pictureInPicture)
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"none"}}"#)
        await drainMainQueue()
        expect(webKit.pictureInPictureRequests == 1, "a WebKit page whose look finds no video goes on to the tab's own request (WebKit's toggle)")
        manager.performNowPlaying(service, .pictureInPicture)
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"video"}}"#)
        await drainMainQueue()
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"NotAllowedError: no gesture"}}"#)
        await drainMainQueue()
        expect(webKit.pictureInPictureRequests == 2, "and so does one that turns the page's request down")

        manager.performNowPlaying(plain, .pictureInPicture)
        expect(runLook(chromium.lastParams, videos: film) == "none", "a Chromium page's opted-out video isn't asked: Chromium would refuse")
        chromium.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"none"}}"#)
        await drainMainQueue()
        expect(chromium.pictureInPictureRequests == 1, "a Chromium page with no video of its own still gets the request in its frames")

        store.settings.autoPictureInPicture = true
        manager.show(service, focus: false)
        manager.show(plain, focus: false)
        expect(webKit.lastParams.contains("})(true, false)") && runLook(webKit.lastParams, videos: film) == "video",
               "leaving the tab finds the WebKit page's video whose player opted out")
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"video"}}"#)
        await drainMainQueue()
        expect(webKit.lastParams.contains("})(true, true)") && webKit.lastParams.contains(#""userGesture":true"#), "and asks it for Picture in Picture")
        webKit.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"ok"}}"#)
        await drainMainQueue()
        manager.show(plain, focus: false)
        manager.show(service, focus: false)
        expect(runLook(chromium.lastParams, videos: film) == "none", "leaving a Chromium tab leaves its opted-out video where it is")
        chromium.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"none"}}"#)
        await drainMainQueue()
        store.settings.autoPictureInPicture = false
        manager.closeAll()
    }

    /// A WebKit page's video is in the system's Picture in Picture window. Its back-to-tab button
    /// did nothing, because WebKit asks for the page to be shown first and its tab stayed hidden.
    /// WebKit says when the button is pressed, and the tab is selected as Back to Tab on Cra's own
    /// window selects a Chromium page's (#585). WebKit moves the video itself.
    // promise: #585
    @MainActor
    private static func webKitPictureInPictureBackToTabCase() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let service = store.createTab(url: "https://www.netflix.com/watch/1").id, other = store.createTab(url: "https://example.test/other").id
        let webKit = manager.ensureRuntime(for: service)!.browser
        manager.show(service, focus: false)
        manager.show(other, focus: false)
        webKit.isInPictureInPicture = true
        manager.browser(webKit, didChangePictureInPicture: true)
        let before = store.selections
        (manager as WebKitPageDelegate).webKitPageReturnsFromPictureInPicture(webKit)
        expect(store.selections == before + [service], "the system window's back to tab selects the WebKit page's tab")
        expect(webKit.isInPictureInPicture, "and leaves moving the video to WebKit, which is doing it")
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

    // promise: #434
    /// Arc's Minimize takes the video out of Picture in Picture without pausing it and without
    /// going to its tab, and the sidebar player has the tab again (#434). Close pauses it.
    @MainActor
    private static func pictureInPictureMinimizeCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://example.test/video").id
        let ra = manager.ensureRuntime(for: a)!
        np.entries.append(.init(id: a, playing: true))
        ra.browser.isInPictureInPicture = true
        manager.browser(ra.browser, didChangePictureInPicture: true)
        expect(np.shown.isEmpty, "a video in Picture in Picture has no card (Arc)")
        let selected = store.selections.count
        PictureInPictureChrome.shared.actions?.minimize()
        expect(!ra.browser.isInPictureInPicture && ra.browser.pictureInPictureCloses == 0,
               "Minimize leaves Picture in Picture without pausing the video")
        expect(store.selections.count == selected, "Minimize doesn't go to the video's tab")
        manager.browser(ra.browser, didChangePictureInPicture: false)
        expect(np.shown.map(\.id) == [a], "the minimized video is in the sidebar player")
        manager.closeAll()
    }

    // promise: #434
    /// A video in Picture in Picture whose tab has no player card (on CEF the card follows sound, so
    /// a muted one has none; the engine drops it after the media session ends): Minimize makes it,
    /// with the Picture in Picture button, or the video would be left with no way back but its tab
    /// (#475, Peter Nielsen).
    @MainActor
    private static func pictureInPictureMinimizeSilentCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let np = NowPlaying()
        manager.nowPlaying = np
        let a = store.createTab(url: "https://example.test/muted").id
        let ra = manager.ensureRuntime(for: a)!
        ra.browser.isInPictureInPicture = true
        manager.browser(ra.browser, didChangePictureInPicture: true)
        PictureInPictureChrome.shared.actions?.minimize()
        expect(!ra.browser.isInPictureInPicture, "Minimize leaves Picture in Picture")
        manager.browser(ra.browser, didChangePictureInPicture: false)
        expect(np.shown.map(\.id) == [a], "a minimized video without a card gets one in the sidebar player")
        expect(np.shown.first?.hasVideo == true, "its card has the Picture in Picture button to bring it back")
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

    // promise: #629
    /// The toolbar takes its colour from the page's pixels when the load ends, as Arc does
    /// (GitHub's light header under its dark theme-color gave Cra a dark bar, #629). A page that
    /// loads behind is read when it comes on screen (a hidden page paints nothing to read), and
    /// a reading that lands after the page moved on is dropped.
    @MainActor
    private static func toolbarSampleCase() async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let a = store.createTab(url: "https://example.test/issues").id, b = store.createTab(url: "https://example.test/dark").id
        let ra = manager.ensureRuntime(for: a)!, rb = manager.ensureRuntime(for: b)!
        func captures(_ rt: TabRuntime) -> Int { rt.browser.replies.filter { $0.method == "Page.captureScreenshot" }.count }
        func settle(_ rt: TabRuntime, to hex: String) async {
            for _ in 0..<200 where rt.themeColor != hex {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        manager.show(a, focus: false)
        ra.browser.setLoading(true)
        ra.browser.setLoading(false)
        expect(captures(ra) == 1, "a page on screen is read when its load ends")
        ra.browser.reply(to: "Page.captureScreenshot", with: screenshot(header: (0xF6, 0xF8, 0xFA), below: (0xFF, 0xFF, 0xFF)))
        await settle(ra, to: "#F6F8FA")
        expect(ra.themeColor == "#F6F8FA" && store.item(a)?.tab?.themeColor == "#F6F8FA",
               "the bar is the page's top-right corner (got \(ra.themeColor))")

        rb.browser.setLoading(true)
        rb.browser.setLoading(false)
        expect(captures(rb) == 0, "a page loading behind isn't read: it paints nothing")
        manager.show(b, focus: false)
        expect(captures(rb) == 1, "it is read when it comes on screen")
        rb.browser.reply(to: "Page.captureScreenshot", with: screenshot(header: (0x20, 0x30, 0x40), below: (0x20, 0x30, 0x40)))
        await settle(rb, to: "#203040")
        expect(rb.themeColor == "#203040", "the page read on screen gives its bar (got \(rb.themeColor))")
        manager.show(a, focus: false)
        manager.show(b, focus: false)
        expect(captures(rb) == 0, "a page already read isn't read again when it comes back")

        rb.browser.setLoading(true)
        rb.browser.setLoading(false)
        rb.browser.setLoading(true)
        rb.browser.reply(to: "Page.captureScreenshot", with: screenshot(header: (0xFF, 0x00, 0x00), below: (0xFF, 0x00, 0x00)))
        await settle(rb, to: "#FF0000")
        expect(rb.themeColor == "#203040", "a reading of the page before a new load doesn't colour the new one")
        manager.closeAll()
    }

    /// Page.captureScreenshot's answer: a 2x viewport 400×200 points, a 64-point header over the page.
    private static func screenshot(header: (Int, Int, Int), below: (Int, Int, Int)) -> String {
        let w = 800, h = 400
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        func fill(_ c: (Int, Int, Int), _ rect: CGRect) {
            ctx.setFillColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
            ctx.fill(rect)
        }
        fill(below, CGRect(x: 0, y: 0, width: w, height: h))
        fill(header, CGRect(x: 0, y: h - 128, width: w, height: 128))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        let json = try! JSONSerialization.data(withJSONObject: ["data": (data as Data).base64EncodedString()])
        return String(decoding: json, as: UTF8.self)
    }

    /// A synced sidebar from the other Mac replaced the document while this Mac's page stayed
    /// where it was: the bar showed the other Mac's address over this page (seen once, 13 Nov
    /// 2026). The page's own address and title go back into its tab. A tab asleep has no page:
    /// the bundle's address is what it loads when it wakes.
    @MainActor
    private static func syncedDocumentKeepsLivePagesCase() {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView(), clock: ManualScheduler())
        let id = store.createTab(url: "https://example.test/here").id
        let rt = manager.ensureRuntime(for: id)!
        rt.browser.currentURL = "https://example.test/here"
        rt.browser.currentTitle = "Here"
        manager.browser(rt.browser, didChangeURL: "https://example.test/here")
        let asleep = store.createTab(url: "https://example.test/sleep").id
        let sleeping = manager.ensureRuntime(for: asleep)!
        sleeping.browser.currentURL = "https://example.test/sleep"
        sleeping.discarded = true
        // The other Mac's bundle has both tabs elsewhere.
        store.items[id]?.tab?.url = "https://example.test/there"
        store.items[id]?.tab?.savedTitle = "There"
        store.items[asleep]?.tab?.url = "https://example.test/sleep-there"
        NotificationCenter.default.post(name: SidebarStore.documentReplaced, object: store)
        expect(store.item(id)?.tab?.url == "https://example.test/here", "a page on screen keeps its own address in the bar after a synced sidebar")
        expect(store.item(id)?.tab?.savedTitle == "Here", "and its own title")
        expect(store.item(asleep)?.tab?.url == "https://example.test/sleep-there", "a tab asleep takes the synced address: it loads that when it wakes")
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
    var onDownload: ((CraDownloadInfo) -> Void)?
    func browserManagerDidUpdate(_ tabID: UUID) {}
    func browserManager(statusMessage: String, tabID: UUID?) {}
    var findStates: [AskOnPage.FindState] = []
    var findActions: [CraFindAction] = []
    func browserManager(findState state: AskOnPage.FindState) { findStates.append(state) }
    func browserManager(findAction action: CraFindAction) { findActions.append(action) }
    func browserManager(download: CraDownloadInfo) { onDownload?(download) }
    var fullscreenChanges: [(fullscreen: Bool, tab: UUID)] = []
    func browserManager(fullscreen: Bool, tabID: UUID) { fullscreenChanges.append((fullscreen, tabID)) }
    func browserManager(exclusiveAccessToast toast: ExclusiveAccessNotice.Toast, tabID: UUID) {}
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView? { nil }
    func browserManagerDevToolsChanged() {}
    func browserManagerTabSharingChanged() {}
    func browserManagerDevToolsPageBoundsChanged() {}
    func browserManagerPageWindowsChanged(focus: Bool) { onPageWindowsChanged?() }
    func browserManagerHandleKey(_ event: NSEvent) -> Bool { false }
    func browserManagerHandleUnhandledKey(_ event: NSEvent) -> Bool { false }
    func browserManagerFocusedBrowser(_ tabID: UUID) {}
    func browserManagerPageClosedTab(_ tabID: UUID) { closedTabs.append(tabID) }
    var translationToasts: [String] = []
    func browserManagerTranslationToast(_ tabID: UUID, text: String) { translationToasts.append(text) }
    var protectedVideoPrompts: [UUID] = []
    func browserManagerProtectedVideoPromptChanged(_ tabID: UUID) { protectedVideoPrompts.append(tabID) }
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
    var backgroundTabs: [UUID] = []
    func browserManagerOpenedInBackground(_ tabID: UUID) { backgroundTabs.append(tabID) }
}
