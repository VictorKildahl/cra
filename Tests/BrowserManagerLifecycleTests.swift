import AppKit
import CraCEF

@main
enum BrowserManagerLifecycleTests {
    private static let idleReply = #"{"result":{"value":true}}"#
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
        await sleepCase("an exception reply cannot authorize sleeping", reply: #"{"exceptionDetails":{},"result":{"value":true}}"#) { _, _ in }
        await sleepCase("malformed or missing replies cannot authorize sleeping", reply: nil) { _, _ in }
        print("Browser manager lifecycle: \(checks) checks passed")
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

    @MainActor
    private static func sleepCase(_ message: String, shouldSleep: Bool = false, reply: String? = idleReply,
                                  mutate: (BrowserManager, TabRuntime) -> Void) async {
        let store = SidebarStore()
        let manager = BrowserManager(store: store, favicons: FaviconCache(), container: NSView())
        let id = store.createTab(url: "https://example.test/sleep").id
        let runtime = manager.ensureRuntime(for: id)!
        runtime.hiddenAt = Date.distantPast
        manager.sleepIdleTabs(hiddenLongerThan: 60)
        expect(runtime.browser.replies.contains { $0.method == "Runtime.evaluate" }, "eligible page receives an asynchronous sleep probe")
        mutate(manager, runtime)
        runtime.browser.reply(to: "Runtime.evaluate", with: reply)
        await drainMainQueue()
        expect((manager.runtime(for: id) == nil) == shouldSleep, message)
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
}
