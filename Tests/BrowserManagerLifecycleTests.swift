import AppKit
import CraCEF

@main
enum BrowserManagerLifecycleTests {
    private static let idleReply = #"{"result":{"type":"string","value":""}}"#
    private static let isolatedProbe = "cra:Runtime.evaluate"
    private static var checks = 0

    @MainActor
    static func main() async {
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
        shortTimerCase()
        recentlyAudibleCase()
        devToolsCase()
        await beforeUnloadCase()
        nowPlayingCase()
        await nowPlayingPictureInPictureCase()
        await leaveVideoTabPictureInPictureCase()
        await coveredWindowPictureInPictureCase()
        pageColoursCase()
        extensionPageRetryCase()
        await sleepCase("malformed or missing replies cannot authorize sleeping", reply: nil) { _, _ in }
        await pageProbeCase()
        print("Browser manager lifecycle: \(checks) checks passed")
    }

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
        manager.sleepIdleTabs(.memoryPressure)
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
        manager.sleepIdleTabs(.memoryPressure)
        expect(probed()[4] && !probed()[5], "the next sweep takes the next page, not one left 4 minutes ago")
        manager.closeAll()
    }

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

    /// ⌥⌘I pressed again while CEF is still closing DevTools opens them once they are gone,
    /// instead of closing them a second time. Console and Network switch panels on open DevTools.
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

    /// The player's Picture in Picture button asks the off-screen page through the protocol, as a
    /// user gesture; only a page with no video of its own (a player in an iframe) gets the
    /// context menu's request.
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
            expect(ra.browser.lastParams.contains(#""userGesture":true"#), "the player's request runs as a user gesture")
            ra.browser.reply(to: "Runtime.evaluate", with: #"{"result":{"type":"string","value":"\#(answer)"}}"#)
            await drainMainQueue()
            expect(ra.browser.pictureInPictureRequests - before == fallback,
                   "\(label) \(fallback == 1 ? "falls back to" : "does not also get") the page request")
        }
        manager.closeAll()
    }

    /// Leaving a video tab (Arc's automatic Picture in Picture) asks the page through the protocol as
    /// a user gesture, for an audible playing video only. The key press the page path lends the page
    /// raced the tab going hidden, so PiP sometimes never opened (X report, 2 Nov 2026).
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
            expect(ra.browser.lastParams.contains(#""userGesture":true"#), "leaving a video tab asks as a user gesture")
            expect(ra.browser.lastParams.contains("})(true)"), "leaving a video tab takes only an audible, playing video")
            let reply = answer.map { #"{"result":{"type":"string","value":"\#($0)"}}"# }
            ra.browser.reply(to: "Runtime.evaluate", with: reply)
            await drainMainQueue()
            expect(ra.browser.automaticPictureInPictureRequests - before == fallback,
                   "\(label) \(fallback == 1 ? "falls back to" : "does not also get") the page request")
            manager.show(a, focus: false)
        }
        store.settings.autoPictureInPicture = false
        manager.show(b, focus: false)
        expect(!ra.browser.replies.contains { $0.method == "Runtime.evaluate" }, "with the setting off, leaving the tab asks nothing")
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
        expect(!ra.browser.replies.contains { $0.method == "Runtime.evaluate" }, "a covered window doesn't ask a silent page")
        manager.windowVisibilityChanged(covered: false)

        ra.browser.isAudible = true
        manager.windowVisibilityChanged(covered: true)
        expect(ra.browser.lastParams.contains(#""userGesture":true"#) && ra.browser.lastParams.contains("})(true)"),
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
        expect(!ra.browser.replies.contains { $0.method == "Runtime.evaluate" }, "a page already in Picture in Picture isn't asked again")
        manager.windowVisibilityChanged(covered: false)
        expect(ra.browser.isInPictureInPicture, "Picture in Picture the user opened stays when the window shows again")
        manager.closeAll()
    }

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
        manager.browser(rt.browser, didFinishLoadingURL: url, title: "Options", statusCode: 200)
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
    func browserManager(statusMessage: String) {}
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
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool) {
        activatedTabs.append(tabID)
        activatedByPage.append(byPage)
    }
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool) -> Bool { false }
}
