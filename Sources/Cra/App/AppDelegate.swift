import AppKit
import CraCEF
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let store = SidebarStore()
    let bindings = KeyBindingRegistry()
    let favicons = FaviconCache()
    lazy var engine = SuggestionEngine(store: store, bindings: bindings)

    /// Browser windows, one per WindowSession. Closing the last one only hides it.
    private(set) var mainWindows: [MainWindowController] = []
    /// The browser window in use: the key one, or the one last key.
    var main: MainWindowController! {
        mainWindows.first { $0.windowID == store.activeWindowID } ?? mainWindows.first
    }
    private var bootstrapped = false
    private var pendingURLs: [String] = []
    private var autoArchiveTimer: Timer?
    private var tabSleepTimer: Timer?
    private var settingsWindow: NSWindow?
    private var settingsController: SettingsWindowController?
    private var isRelaunching = false
    private lazy var extensionsMenu = ExtensionsMenu(app: self)
    /// Arc's Little Arc windows: small, sidebar-less, disposable (see LittleWindowController).
    private(set) var littleWindows: [LittleWindowController] = []

    /// Shortcuts the app takes before the web page sees them (Chrome calls
    /// these reserved). Everything else goes to the page first.
    static let reservedActions: Set<String> = Set([
        "newTab", "newWindow", "newIncognitoWindow", "closeTab", "closeWindow", "reopenClosedTab", "editURL", "toggleSidebar", "toggleToolbar",
        "nextTab", "previousTab", "recentTab", "recentTabBackward", "nextSpace", "previousSpace", "devTools", "jsConsole", "inspectElement",
        "viewArchive", "openLibrary", "settings", "clearToday", "newLittleWindow", "promoteLittleWindow",
        "addSplitView", "closeSplitPane",
    ] + (1...9).flatMap { ["item\($0)", "space\($0)"] })

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) { bootstrapIfNeeded() }

    func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true
        NSApp.setActivationPolicy(.regular)
        installURLEventHandler()
        CraCEFRuntime.setChromeHosting(store.settings.chromeEngine)
        CraCEFRuntime.setOwnContextMenus(EmbeddedPages.isEnabled)
        CraCEFRuntime.setDocumentStartScript(PageScript.mainWorld, isolatedScript: PageScript.isolatedWorld, world: PageScript.world)
        startContentBlocking()
        SoftwareUpdater.shared.start(app: self)
        buildMenus()
        NotificationCenter.default.addObserver(forName: .craKeyBindingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.buildMenus() }
        }
        mainWindows = store.prefs.windows.map { MainWindowController(app: self, session: $0) }
        followKeyWindow()
        // First launch: the default browser step and the import are the onboarding and
        // the browser window appears once they are done (Dia does the same).
        if needsOnboarding {
            main.showImport(firstRun: true)
        } else {
            // The window in use last comes up in front.
            for w in mainWindows.reversed() { w.showWindow(nil) }
        }
        installKeyFallbackMonitor()
        installCommandFileWatcher()
        store.runAutoArchive()
        autoArchiveTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.runAutoArchive() }
        }
        tabSleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sleepIdleTabs() }
        }
        LiveFolderManager.shared.start(store: store)
        // A restart into an update while the user was away leaves the front app alone.
        if HitchMonitor.background {
            // Measured behind whatever is in front; still on screen, so pages keep drawing.
            for w in mainWindows { w.window?.orderBack(nil) }
        } else if !SoftwareUpdater.shared.launchedByAutoUpdate {
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.installURLEventHandler() }
        // Extension welcome pages and chrome.tabs.create land in Cra, not in a Chrome window.
        // --load-extension extensions count as freshly installed on every launch, so their
        // onInstalled welcome pages come back each time: right after launch, drop them unless
        // an extension is new since the last launch (then open each page once).
        let launchedAt = Date()
        let welcomedFile = AppPaths.file("extensions-welcomed.json")
        let welcomed = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: welcomedFile))) ?? [])
        let installed = ExtensionStore.shared.entries.map(\.extensionID)
        let hasNewExtension = !Set(installed).isSubset(of: welcomed)
        try? JSONEncoder().encode(installed.sorted()).write(to: welcomedFile, options: .atomic)
        CraCEFRuntime.setStrayPageHandler { [weak self] url in
            Task { @MainActor in
                guard let self else { return }
                if Date().timeIntervalSince(launchedAt) < 10,
                   !hasNewExtension || self.store.allTabs().contains(where: { $0.tab?.url == url }) {
                    NSLog("Cra: dropped start-up page from an extension: %@", url)
                    return
                }
                self.useNormalWindow()
                self.store.createTab(url: url, select: true)
                self.main.showWindow(nil)
            }
        }
        CraCEFRuntime.setRelaunchHandler { [weak self] urls in
            Task { @MainActor in
                guard let self else { return }
                // Each URL decides what to raise: a Little Window keeps the main
                // window where it is (Arc), cra://action/… keeps the key window.
                if urls.isEmpty { self.main.showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
                for u in urls { self.openExternalURL(u) }
            }
        }
        let urls = pendingURLs
        pendingURLs = []
        for u in urls { openExternalURL(u) }
    }

    /// A fresh install runs Dia's onboarding (cover, default browser, privacy,
    /// import, pinned tabs, personalization, outro).
    private var needsOnboarding: Bool {
        !store.settings.hasSeenImportPrompt && store.allTabs().count <= 2
    }

    /// End of the import flow. Onboarding counts as done only here, so quitting halfway
    /// shows it again on the next launch.
    func importFinished(_ outcome: ImportOutcome, firstRun: Bool) {
        if firstRun { store.settings.hasSeenImportPrompt = true }
        if let id = outcome.focusSpaceID { store.focusSpace(id) }
        // Chromium reads --load-extension only at start-up, and imported passwords
        // and cookies go into its databases before it starts (CredentialImport).
        if outcome.needsRelaunch { relaunch(); return }
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Saves, quits and starts again once this process is gone (the CEF profile is
    /// single-instance). A CRA_DATA_DIR instance is re-executed directly so it keeps
    /// its environment; an installed one goes through LaunchServices.
    func relaunch() {
        store.saveAll()
        let custom = ProcessInfo.processInfo.environment["CRA_DATA_DIR"] != nil
        let target = custom ? (Bundle.main.executablePath ?? "") : Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; sleep 0.3; " + (custom ? "exec \"$2\"" : "exec /usr/bin/open \"$2\""),
                       "cra-relaunch", String(ProcessInfo.processInfo.processIdentifier), target]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { main.showWindow(nil); return }
        isRelaunching = true
        NSApp.terminate(nil)
    }

    /// Third-party ad and tracker blocking (Settings > Privacy, Dia's onboarding
    /// checkbox). The bundled list (resources/blocklist) is parsed off the main thread;
    /// the switch follows the setting live, no restart.
    private func startContentBlocking() {
        if let path = Bundle.main.path(forResource: "domains", ofType: "txt", inDirectory: "blocklist") {
            CraCEFRuntime.loadBlockedDomains(fromFile: path, completion: nil)
        }
        observeContentBlocking()
        observeHttpsOnly()
    }

    private func sleepIdleTabs() {
        guard store.settings.tabSleepEnabled else { return }
        for w in mainWindows { w.browsers.sleepIdleTabs(hiddenLongerThan: store.settings.tabSleep.seconds) }
    }

    /// Settings > Privacy > "Always use secure connections", live like content blocking.
    private func observeHttpsOnly() {
        let enabled = withObservationTracking {
            store.settings.httpsOnly
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeHttpsOnly() }
        }
        CraCEFRuntime.setHttpsOnlyModeEnabled(enabled)
    }

    private func observeContentBlocking() {
        let enabled = withObservationTracking {
            store.settings.blockAdsAndTrackers
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeContentBlocking() }
        }
        CraCEFRuntime.setContentBlockingEnabled(enabled)
    }

    private func installURLEventHandler() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidBecomeActive(_ notification: Notification) { installURLEventHandler() }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        if bootstrapped { openExternalURL(s) } else { pendingURLs.append(s) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls {
            if bootstrapped { openExternalURL(u.absoluteString) } else { pendingURLs.append(u.absoluteString) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if main?.raiseImport() == true { return true }
        main?.showWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Dia: Advanced ▸ "Warn before quitting". Engine relaunches skip it.
        if store.settings.warnBeforeQuitting, !isRelaunching, !confirmQuit() { return .terminateCancel }
        // Little Windows are not in the sidebar; keep their pages in the Library.
        for w in littleWindows { w.archivePage() }
        store.saveAll()
        return .terminateNow
    }

    func applicationWillShutdown() { store.saveAll() }

    /// Sparkle quits Cra to install an update and starts it again: no quit confirmation.
    func prepareForUpdateRelaunch() {
        isRelaunching = true
        store.saveAll()
    }

    /// Why an automatic update restart should wait (Arc: downloads in progress,
    /// window_dialog_sheet_visible, active tabs). Little Windows go to the Library on quit,
    /// so an open one waits too.
    func autoUpdateBlocker() -> String? {
        if mainWindows.contains(where: { $0.overlay.toasts.contains { $0.state == CraDownloadState.inProgress.rawValue } }) { return "a download is in progress" }
        if NSApp.modalWindow != nil || NSApp.windows.contains(where: { $0.isVisible && $0.attachedSheet != nil }) { return "a dialog is open" }
        if !littleWindows.isEmpty { return "a Little Window is open" }
        if PictureInPictureChrome.shared.isPlaying { return "Picture in Picture is playing" }
        if main.isImportVisible { return "the import is open" }
        return nil
    }

    private func confirmQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit Cra?"
        alert.informativeText = "All windows and tabs will close. They come back when Cra starts again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func openExternalURL(_ url: String) {
        if let u = URL(string: url), u.scheme?.lowercased() == "cra" {
            if Self.isUserFacing(u) || UserDefaults.standard.bool(forKey: "scriptingURLs") {
                handleInternalURL(u)
            } else {
                NSLog("Cra: ignored %@ from another app (defaults write dk.kildahl.cra scriptingURLs -bool YES allows it)", url)
            }
            return
        }
        // Links from other apps never land in an incognito window (Chrome does the same).
        useNormalWindow()
        // Arc's Air Traffic Control: the first matching route, else the default
        // ("Links from other apps open in Little Arc").
        switch store.settings.destination(forExternalURL: url) {
        case .littleWindow:
            openLittleWindow(url: url)
            return
        case .space(let id) where store.space(id) != nil:
            store.createTab(url: url, in: id, select: true)
        case .space, .mostRecentSpace:
            store.createTab(url: url, select: true)
        }
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Browser windows

    /// Menu commands and new tabs follow the browser window the user is in. Its key
    /// window is often a child (a page, the command bar, the find bar).
    private func followKeyWindow() {
        // Synchronous: a shortcut right after a click must already go to the new window.
        // Main covers windows raised while Cra is in the background (Mission Control, the Window menu).
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, var w = note.object as? NSWindow else { return }
                    while let parent = w.parent { w = parent }
                    if let c = self.mainWindows.first(where: { $0.window === w }) { self.store.activeWindowID = c.windowID }
                }
            }
        }
    }

    /// The window links from other apps, the Library and Little Windows go to: the
    /// normal window in use last, never an incognito one.
    @discardableResult
    func useNormalWindow() -> MainWindowController {
        if main.isIncognito, let normal = mainWindows.first(where: { $0.windowID == store.lastNormalWindowID })
            ?? mainWindows.first(where: { !$0.isIncognito }) {
            store.activeWindowID = normal.windowID
        }
        return main
    }

    /// Arc's New Window (⌘N): another window on the space in use, cascaded from the
    /// current one, with the command bar up. With every window closed it brings the
    /// hidden one back instead. New Incognito Window (⇧⌘N) always opens a new one.
    func openNewWindow(incognito: Bool = false) {
        if !incognito, let hidden = mainWindows.first(where: { !$0.isIncognito }),
           !mainWindows.contains(where: { $0.window?.isVisible == true || $0.window?.isMiniaturized == true }) {
            hidden.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var frame: String?
        if let current = main?.window, current.isVisible, !current.styleMask.contains(.fullScreen) {
            var f = current.frame.offsetBy(dx: 22, dy: -22)
            if let screen = (current.screen ?? NSScreen.main)?.visibleFrame, !screen.contains(f) {
                f.origin = NSPoint(x: screen.minX + 22, y: screen.maxY - f.height - 22)
            }
            frame = NSStringFromRect(f)
        }
        let session = incognito ? store.addIncognitoWindow(frame: frame)
            : store.addWindow(spaceID: store.focusedSpaceID(window: store.lastNormalWindowID), frame: frame)
        let c = MainWindowController(app: self, session: session)
        mainWindows.append(c)
        store.activeWindowID = c.windowID
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        c.openCommandBar(.newTab)
    }

    /// Closing one of several windows ends it; the last normal one stays around hidden,
    /// so a Dock click brings the browser back as it was. Incognito windows always end,
    /// and with the last of them the off-the-record profile goes too.
    func mainWindowWillClose(_ c: MainWindowController) {
        guard !isRelaunching, c.isIncognito || mainWindows.contains(where: { $0 !== c && !$0.isIncognito }) else { return }
        mainWindows.removeAll { $0 === c }
        c.tearDown()
        store.removeWindow(c.windowID)
        if c.isIncognito, !mainWindows.contains(where: \.isIncognito) { CraCEFRuntime.endIncognitoSession() }
        // AppKit makes the next window key on its own; until then actions go to the frontmost.
        if let front = NSApp.orderedWindows.compactMap({ w in mainWindows.first { $0.window === w } }).first {
            store.activeWindowID = front.windowID
        }
    }

    /// A tab's live page, whichever window holds it.
    func runtime(for tabID: UUID) -> TabRuntime? {
        for w in mainWindows { if let rt = w.browsers.runtime(for: tabID) { return rt } }
        return nil
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for (title, id) in [("New Window", "newWindow"), ("New Incognito Window", "newIncognitoWindow")] {
            let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Little Windows

    /// The little window that owns the key window (the window itself, or its
    /// Chrome-style page window, which is a child).
    var keyLittleWindow: LittleWindowController? {
        if let key = NSApp.keyWindow {
            return littleWindows.first { $0.window === key || $0.window === key.parent }
        }
        // No key window while the app is inactive (e.g. during a cra:// handoff from a
        // second launch): the frontmost window stands in for it.
        guard let front = NSApp.orderedWindows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return nil }
        return littleWindows.first { $0.window === front || $0.window === front.parent }
    }

    /// Creates a little window without showing it (`url` nil = popup host).
    func makeLittleWindow(url: String?) -> LittleWindowController {
        let w = LittleWindowController(app: self, url: url)
        littleWindows.append(w)
        return w
    }

    @discardableResult
    func openLittleWindow(url: String, activate: Bool = true) -> LittleWindowController {
        let w = makeLittleWindow(url: url)
        if activate { w.show() } else { w.window?.orderFront(nil) }
        return w
    }

    /// Arc's Peek: a Little Window over `parent` that closes when a click lands past it.
    func openPeek(url: String, over parent: MainWindowController) {
        for p in littleWindows where p.peekParent === parent { p.closeWindow() }
        let w = LittleWindowController(app: self, url: url, peekOver: parent)
        littleWindows.append(w)
        w.showAsPeek()
    }

    func removeLittleWindow(_ w: LittleWindowController) {
        littleWindows.removeAll { $0 === w }
    }

    func closeLittleWindows() {
        for w in littleWindows { w.closeWindow() }
    }

    /// cra:// URLs any app may send: they do what the user could do from the Dock.
    /// The rest (action, navigate, key, import, debug, open with a file: or javascript:
    /// URL) run scripts, DevTools Protocol and key presses, so a link in a mail or another
    /// browser must not reach them. CRA_COMMAND_FILE and the scriptingURLs default do.
    static func isUserFacing(_ u: URL) -> Bool {
        switch u.host {
        case "commandbar", "dismiss":
            return true
        case "open":
            let target = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            let scheme = target.flatMap { URL(string: $0)?.scheme?.lowercased() }
            return scheme == "http" || scheme == "https"
        default:
            return false
        }
    }

    /// cra://commandbar?query=…&mode=edit, cra://action/<id>, cra://open?url=…,
    /// cra://dismiss.
    func handleInternalURL(_ u: URL) {
        let comps = URLComponents(url: u, resolvingAgainstBaseURL: false)
        func q(_ name: String) -> String? { comps?.queryItems?.first { $0.name == name }?.value }
        // Actions keep their target: a key Little Window stays key (perform routes to it).
        // A background test instance (CRA_TEST_BACKGROUND) never comes to the front.
        if (u.host != "action" || keyLittleWindow == nil) && !HitchMonitor.background {
            main.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        switch u.host {
        case "commandbar":
            // With the bar already open a new query is the next keystroke, not a new session.
            if !(main.commandBar.isOpen && q("query") != nil) { main.openCommandBar(q("mode") == "edit" ? .editURL : .newTab) }
            if let text = q("query") { main.commandBar.setQuery(text) }
        case "action":
            perform(String(u.path.dropFirst()))
        case "navigate":
            // Load a URL in the focused tab / split pane (scripting).
            if let url = q("url") { main.loadInSelectedTab(url) }
        case "open":
            if let url = q("url"), q("little") == "1" {
                openLittleWindow(url: url)
            } else if let url = q("url") {
                useNormalWindow()
                let tab = store.createTab(url: url, select: q("background") != "1")
                if q("background") == "1" { store.markUnread(tab.id, true); main.browsers.ensureRuntime(for: tab.id) }
            }
        case "key":
            // Scripted key press through the normal event path (testing).
            guard let chars = q("chars"), let window = main.window else { break }
            var flags: NSEvent.ModifierFlags = []
            if q("cmd") == "1" { flags.insert(.command) }
            if q("shift") == "1" { flags.insert(.shift) }
            if q("opt") == "1" { flags.insert(.option) }
            if q("ctrl") == "1" { flags.insert(.control) }
            let codes: [String: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
                                           "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
                                           "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
                                           "k": 40, ";": 41, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "\t": 48, "\r": 36, "\u{1b}": 53]
            let code = codes[chars] ?? 0
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                             isARepeat: false, keyCode: code) {
                    NSApp.sendEvent(ev)
                }
            }
        case "import":
            // Headless import (scripting): cra://import?source=arc&archive=1&settings=1
            let plan = try? (q("source") == "dia" ? DiaImporter.plan() : ArcImporter.plan())
            if let plan {
                let r = store.apply(plan, includeArchive: q("archive") != "0", includeSettings: q("settings") != "0")
                favicons.reset()
                NSLog("Cra: imported %d spaces, %d tabs, %d folders, %d archived", r.spaces, r.tabs, r.folders, r.archived)
            }
        case "debug":
            var dict: [String: String] = [:]
            for item in comps?.queryItems ?? [] { if let v = item.value { dict[item.name] = v } }
            if let js = dict["devtoolsjs"] { main.debugRunInDevTools(js) }
            if dict["embedDump"] != nil { NSLog("%@", main.embeddedPagesDump()); return }
            // Tests that leave the pointer alone: scroll=dy,steps,x,y scrolls the scroll view at a
            // point of the main window (from its top left); swipe=dx,steps plays a space swipe.
            if let g = dict["scroll"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 4, let w = main.window {
                TestGesture.scroll(by: g[0], steps: Int(g[1]), at: NSPoint(x: g[2], y: w.frame.height - g[3]), in: w)
                return
            }
            if let st = dict["status"] { main.browserManager(statusMessage: st); return }
            if let t = dict["selectTab"].flatMap(UUID.init(uuidString:)) { store.selectTab(t, window: main.windowID); return }
            // One tab-sleeping pass with a short threshold (seconds), so it can be tried without waiting.
            if let s = dict["sleepTabs"].flatMap(Double.init) {
                for w in mainWindows { w.browsers.sleepIdleTabs(hiddenLongerThan: s) }
                return
            }
            // Opens what normally needs a pointer or a held key, for screenshots.
            if let v = dict["downloads"] { main.sidebarUI.downloadsListOpen = v == "1"; return }
            if let v = dict["banner"] { SoftwareUpdater.shared.debugUpdated(v == "none" ? nil : v); return }
            if dict["switcher"] != nil { main.debugTabSwitcher(); return }
            if dict["jumpPill"] != nil { SpaceListView.jumpToSelected(for: main.sidebarUI, space: store.focusedSpaceID); return }
            if let f = dict["folderPreview"] {
                if let id = UUID(uuidString: f) { SpaceListView.debugFolderPreview(id, ui: main.sidebarUI) } else { FolderPreviewController.shared.close() }
                return
            }
            if dict["littlePopup"] != nil { littleWindows.first?.togglePopup(); return }
            if let c = dict["combine"], let content = main.window?.contentView {
                let tabs = store.children(of: store.focusedSpace.todayContainerID).filter { $0.tab != nil }
                guard tabs.count > 1 else { return }
                let kind: CombineDropPreview.Kind = c == "folder" ? .folder : .split(leading: c == "leading")
                let pal = store.focusedSpace.theme.palette
                let v = CombineDropPreview(kind: kind, target: tabs[0], dragged: tabs[1], depth: 0, palette: pal, favicons: favicons)
                v.frame = NSRect(x: 10, y: content.bounds.height - 420, width: 300, height: CraMetrics.rowHeight)
                content.addSubview(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { v.removeFromSuperview() }
                return
            }
            if dict["siteControls"] != nil { main.debugSiteControls(); return }
            if let t = dict["tooltip"], let content = main.window?.contentView {
                ArcTooltipController.shared.debugShow(t, in: content, at: NSRect(x: 380, y: content.bounds.height - 120, width: 28, height: 28))
                return
            }
            if let g = dict["swipe"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                main.debugSpaceSwipe(dx: g[0], steps: Int(g[1]))
                return
            }
            if let id = dict["extensionAction"] { main.runExtensionAction(id); return }
            if let f = dict["floatingSidebar"] { if f == "1" { main.floatingSidebar?.show() } else { main.floatingSidebar?.hide(animated: true) }; return }
            if let method = dict["bcdp"] {
                CraCEFRuntime.sendBrowserDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    NSLog("Cra bcdp %@ → %@", method, result ?? "error: \(error ?? "?")")
                }
                return
            }
            if let method = dict["cdp"] {
                // target=little: the newest Little Window's (or Peek's) page.
                let b = dict["target"] == "little" ? littleWindows.last?.browser : main.currentBrowser
                b?.sendDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    NSLog("Cra cdp %@ → %@", method, result ?? "error: \(error ?? "?")")
                }
                return
            }
            if let spikeURL = dict["chromeSpike"] {
                CraCEFRuntime.spikeChromeWindow(withURL: spikeURL) { [weak self] w in
                    guard let self, let host = self.main.window else { return }
                    w.styleMask.insert(.fullSizeContentView)
                    w.titlebarAppearsTransparent = true
                    w.titleVisibility = .hidden
                    w.isMovable = false
                    w.hasShadow = false
                    host.addChildWindow(w, ordered: .above)
                    let rect = self.main.shell.webContainer.convert(self.main.shell.webContainer.bounds, to: nil)
                    w.setFrame(host.convertToScreen(rect), display: true)
                    w.orderFront(nil)
                }
                return
            }
            if dict["windows"] != nil {
                for w in NSApp.windows {
                    let line = "Cra windows: \(w.windowController.map { String(describing: type(of: $0)) } ?? "-") '\(w.title)' frame=\(NSStringFromRect(w.frame)) parent=\(w.parent.map { NSStringFromRect($0.frame) } ?? "-") visible=\(w.isVisible) key=\(w.isKeyWindow) mask=\(w.styleMask.rawValue) class=\(NSStringFromClass(type(of: w))) children=\(w.childWindows?.count ?? 0) contentView=\(w.contentView.map { NSStringFromClass(type(of: $0)) } ?? "-")"
                    NSLog("%@", line)
                }
                let summary = "Cra windows: little=\(littleWindows.count) tabs=\(store.allTabs().count) runtimes=\(main.browsers.runtimes.count) hosts=\(main.browsers.runtimes.values.map { $0.browser.hostWindow.map { NSStringFromRect($0.frame) } ?? "nil" })"
                NSLog("%@", summary)
                return
            }
            CraTuning.shared.apply(dict)
            main.refresh()
            main.shell.refreshLift()
            if let w = main.window {
                let v = main.shell.vibrancy
                NSLog("Cra debug: opaque=%d bg=%@ key=%d main=%d vibHidden=%d state=%ld material=%ld blend=%ld appearance=%@ shellLayerOpaque=%d contentViewIsShell=%d",
                      w.isOpaque ? 1 : 0, String(describing: w.backgroundColor), w.isKeyWindow ? 1 : 0, w.isMainWindow ? 1 : 0,
                      v.isHidden ? 1 : 0, v.state.rawValue, v.material.rawValue, v.blendingMode.rawValue, String(describing: v.effectiveAppearance.name.rawValue),
                      (main.shell.layer?.isOpaque ?? false) ? 1 : 0, (w.contentView === main.shell) ? 1 : 0)
            }
        case "dismiss":
            main.dismissTransientUI()
            settingsWindow?.close()
        default:
            break
        }
    }

    // MARK: Actions

    @objc func menuAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        perform(id)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.representedObject as? String {
        case "toggleSidebar": item.title = main.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
        case "toggleToolbar": item.title = store.settings.showToolbar ? "Hide Toolbar" : "Show Toolbar"
        case "toggleDeveloperMode":
            let on = store.selectedTab?.tab.map { store.settings.isDeveloperMode(url: $0.url) } ?? false
            item.title = on ? "Turn off Developer Mode for this Site" : "Turn on Developer Mode for this Site"
        case "pinTab": item.title = store.selectedTabID.map { store.isPinned($0) ? "Unpin Tab" : "Pin Tab" } ?? "Pin/Unpin Tab"
        case "setDefaultBrowser":
            SystemIntegration.shared.refresh()
            return !SystemIntegration.shared.isDefaultBrowser
        case "pictureInPicture":
            item.title = main.currentBrowser?.isInPictureInPicture == true ? "Exit Picture in Picture" : "Picture in Picture"
        case "promoteLittleWindow": return keyLittleWindow?.hasPage ?? false
        case "closeSplitPane", "separateFromSplit", "flipSplitOrientation":
            return store.selectedTabID.flatMap { store.splitContaining($0) } != nil
        case "addSplitView": return store.selectedTabID != nil
        case "editSpace", "deleteSpace", "nextSpace", "previousSpace": return !main.isIncognito
        case "closeLittleWindows": return !littleWindows.isEmpty
        default: break
        }
        return true
    }

    /// Testing aid: with CRA_COMMAND_FILE set, every line appended to that file
    /// is handled like a cra:// URL (a second instance run with CRA_DATA_DIR
    /// cannot receive cra:// URLs, which LaunchServices routes to the installed app).
    private var commandFileOffset: UInt64 = 0
    private var commandFileTimer: Timer?
    private func installCommandFileWatcher() {
        guard let path = ProcessInfo.processInfo.environment["CRA_COMMAND_FILE"], !path.isEmpty else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        commandFileOffset = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        commandFileTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let h = FileHandle(forReadingAtPath: path) else { return }
                defer { try? h.close() }
                let size = (try? h.seekToEnd()) ?? 0
                guard size > self.commandFileOffset else { return }
                try? h.seek(toOffset: self.commandFileOffset)
                let data = h.readDataToEndOfFile()
                self.commandFileOffset = size
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    HitchMonitor.mark(String(line))
                    if let u = URL(string: line.trimmingCharacters(in: .whitespaces)) { self.handleInternalURL(u) }
                }
            }
        }
    }

    /// Menu key equivalents match characters, so ⌃⇧= and friends fail on
    /// layouts where "=" lives on another key (Danish: ⇧0). When the key
    /// window is one of ours (sidebar focused, no page), fall back to the
    /// physical-key matching in `Shortcut` for ⌘/⌃ shortcuts the menus missed.
    private var keyFallbackMonitor: Any?
    private func installKeyFallbackMonitor() {
        guard keyFallbackMonitor == nil else { return }
        keyFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc drops a ⌘/⇧-click tab selection before anything else sees it.
            if event.keyCode == 53, let ui = self?.main.sidebarUI, !ui.multiSelection.isEmpty {
                ui.clearPicks()
                return nil
            }
            guard let self, event.modifierFlags.intersection([.command, .control]).isEmpty == false,
                  let window = event.window, window.windowController is MainWindowController || window === self.main.window else { return event }
            if self.undoClosedTab(event) { return nil }
            guard let action = self.bindings.action(for: event) else { return event }
            // Let the menu bar take it first (normal path); only act when it cannot.
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return nil }
            self.perform(action.id)
            return nil
        }
    }

    /// Reserved shortcuts (CEF OnPreKeyEvent).
    func handleReservedKey(_ event: NSEvent) -> Bool {
        guard let action = bindings.action(for: event), Self.reservedActions.contains(action.id) else { return false }
        perform(action.id)
        return true
    }

    /// Keys the page let through (CEF OnKeyEvent). Anything we know runs here;
    /// returning false lets CEF pass the key on to the menu bar (⌘Q, ⌘H…).
    func handleUnhandledKey(_ event: NSEvent) -> Bool {
        if undoClosedTab(event) { return true }
        if let action = bindings.action(for: event) {
            perform(action.id)
            return true
        }
        // Chromium hands a ⌘-key the page left alone back to the menu bar through its own
        // window's command dispatcher (⌘C, ⌘V, ⌘A, ⌘Z exist only as Edit menu items). An
        // embedded page sits in Cra's window, which has none: the key was dropped.
        if event.modifierFlags.contains(.command), let key = NSApp.keyWindow,
           !key.responds(to: NSSelectorFromString("commandDispatcher")) {
            return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
        }
        return false
    }

    /// Arc: ⌘Z brings back the tab you closed last (closing registers an undo, GitHub #21),
    /// unless the keyboard is in something with text to undo: a text field, or an editable
    /// element in a page (Chromium's page view reports its ui::TextInputType, 0 = none).
    private func undoClosedTab(_ event: NSEvent) -> Bool {
        guard Shortcut("z", .command).matches(event) else { return false }
        let responder = (event.window ?? NSApp.keyWindow)?.firstResponder
        if responder is NSText { return false }
        if let view = responder as? NSView, NSStringFromClass(type(of: view)) == "RenderWidgetHostViewCocoa",
           view.responds(to: NSSelectorFromString("textInputType")),
           (view.value(forKey: "textInputType") as? Int ?? 0) != 0 { return false }
        perform("reopenClosedTab")
        return true
    }

    func perform(_ id: String) {
        store.recordCommandUse(id)
        // An extension's own window (Arc: BrowserExtensionWindowController.closeCurrentItem:)
        // closes on ⌘W instead of the tab behind it.
        if ["closeTab", "closeWindow"].contains(id), let key = NSApp.keyWindow, CraCEFRuntime.isExtensionWindow(key) {
            key.performClose(nil)
            return
        }
        // A key Little Window takes the page/window actions first (⌘W, ⌘L, ⌘R…).
        if let little = keyLittleWindow, little.handle(action: id) { return }
        let current = store.selectedTabID
        switch id {
        case "newLittleWindow": openLittleWindow(url: "")
        case "closeLittleWindows": closeLittleWindows()
        case "promoteLittleWindow": break  // only meaningful while a little window is key
        case "newTab": main.openCommandBar(.newTab)
        case "newWindow": openNewWindow()
        case "newIncognitoWindow": openNewWindow(incognito: true)
        case "editURL": main.openCommandBar(.editURL)
        case "newFolder":
            let f = store.createFolder(named: "New Folder", in: store.focusedSpace.pinnedContainerID, index: 0)
            main.sidebarUI.renamingID = f.id
        case "newGitHubLiveFolder":
            guard !main.isIncognito else { break }
            let sid = store.focusedSpace.id
            let isNew = store.liveFolder(.github, inSpace: sid) == nil
            guard let f = store.createLiveFolder(.github, inSpace: sid) else { break }
            store.setExpanded(f.id, true)
            if isNew { LiveFolderManager.shared.refresh(f.id) }
        case "newSpace": main.showSpaceEditor(space: nil)
        case "editSpace": if !main.isIncognito { main.showSpaceEditor(space: store.focusedSpace) }
        case "deleteSpace": if !main.isIncognito { confirmDeleteSpace(store.focusedSpace) }
        case "closeTab":
            // Arc: "Close current tab or window".
            if current != nil { main.closeCurrentTab() } else { main.window?.performClose(nil) }
        case "closeWindow": main.window?.performClose(nil)
        case "reopenClosedTab": if !main.isIncognito { store.reopenLastArchived() }  // incognito tabs leave nothing to restore
        case "copyURL":
            if let url = current.flatMap({ store.item($0)?.tab?.url }) {
                copy(url)
                main.sidebarUI.flashStatus("Copied Current URL", symbol: "link")
            }
        case "copyURLMarkdown":
            if let c = current, let it = store.item(c), let url = it.tab?.url {
                copy("[\(it.displayTitle)](\(url))")
                main.sidebarUI.flashStatus("Copied URL as Markdown", symbol: "link")
            }
        case "print": main.currentBrowser?.print()
        case "capturePage": main.capturePage()
        case "find": main.showFindBar()
        case "findNext": main.findNext(forward: true)
        case "findPrevious": main.findNext(forward: false)
        case "toggleSidebar": main.toggleSidebar()
        case "toggleToolbar": store.settings.showToolbar.toggle()
        case "toggleDeveloperMode": if let url = store.selectedTab?.tab?.url { store.settings.toggleDeveloperMode(url: url) }
        case "reload": main.currentBrowser?.reload()
        case "hardReload": main.currentBrowser?.reloadIgnoringCache()
        case "clearCache": main.currentBrowser?.clearSiteDataAndReload(cookies: false)
        case "clearCookies": main.currentBrowser?.clearSiteDataAndReload(cookies: true)
        case "stop": main.currentBrowser?.stopLoading()
        case "zoomIn": main.zoom(by: 0.5)
        case "zoomOut": main.zoom(by: -0.5)
        case "resetZoom": main.currentBrowser?.setZoomLevel(0)
        case "viewSource": main.currentBrowser?.viewSource()
        case "devTools", "jsConsole":
            // Toggle, like Chrome: ⌥⌘I closes the dock when it is already open.
            if let b = main.currentBrowser { b.hasDevTools ? b.closeDevTools() : b.showDevTools() }
        case "inspectElement": main.currentBrowser?.showDevTools()
        // Arc's Library is a mode of the window's sidebar; ⇧⌘J opens it on Downloads.
        case "openLibrary": main.toggleLibrary()
        case "viewArchive": main.showLibrary(.archive)
        case "viewDownloads": main.showLibrary(.downloads)
        case "goBack": main.currentBrowser?.goBack()
        case "goForward": main.currentBrowser?.goForward()
        case "pinTab": if let c = current { store.togglePinned(c) }
        case "favoriteTab":
            if let c = current { store.isFavorite(c) ? store.removeFromFavorites(c) : store.addToFavorites(c) }
        case "renameTab": main.sidebarUI.renamingID = current
        case "duplicateTab": if let c = current { store.duplicateTab(c) }
        case "resetTab": if let c = current { main.resetPinnedTab(c) }
        case "muteTab":
            if let c = current, let t = store.item(c)?.tab {
                store.setMuted(c, !t.muted)
                runtime(for: c)?.browser.setAudioMuted(!t.muted)
            }
        case "clearToday": store.clearToday()
        case "pictureInPicture": main.currentBrowser?.requestPictureInPicture(automatic: false)
        case "nextTab": main.cycleTab(1)
        case "previousTab": main.cycleTab(-1)
        case "recentTab": main.cycleRecentTabs(1, event: NSApp.currentEvent)
        case "recentTabBackward": main.cycleRecentTabs(-1, event: NSApp.currentEvent)
        case "nextSpace": store.focusSpace(offset: 1)
        case "previousSpace": store.focusSpace(offset: -1)
        case "addSplitView": main.addSplitPane()
        case "closeSplitPane": if let c = current { main.closeSplitPane(c) }
        case "separateFromSplit": if let c = current { main.separatePane(c) }
        case "flipSplitOrientation": if let c = current, let s = store.splitContaining(c) { store.flipSplitOrientation(s.id) }
        case "nextSplitPane": main.cycleSplitPane(1)
        case "previousSplitPane": main.cycleSplitPane(-1)
        case "settings": showSettingsWindow()
        case "importData": main.showImport()
        case "setDefaultBrowser": Task { await SystemIntegration.shared.makeDefaultBrowser() }
        default:
            if id.hasPrefix("item"), let n = Int(id.dropFirst(4)) {
                let tabs = store.visibleTabs(in: store.focusedSpaceID)
                if n - 1 < tabs.count { store.selectTab(tabs[n - 1].id) }
            } else if id.hasPrefix("space"), let n = Int(id.dropFirst(5)) {
                if n - 1 < store.spaceOrder.count { store.focusSpace(store.spaceOrder[n - 1]) }
            }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func confirmDeleteSpace(_ space: Space) {
        guard store.spaceOrder.count > 1 else {
            let a = NSAlert()
            a.messageText = "You need at least one space."
            a.runModal()
            return
        }
        let a = NSAlert()
        a.messageText = "Delete “\(space.title)”?"
        a.informativeText = "Its tabs move to the archive, where you can restore them."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { store.deleteSpace(space.id) }
    }

    // MARK: Windows

    func showSettingsWindow() {
        if settingsController == nil {
            let actions = SettingsActions(
                importData: { [weak self] in self?.main.showImport() },
                openURL: { [weak self] url in
                    guard let self else { return }
                    self.useNormalWindow()
                    _ = self.store.createTab(url: url, select: true)
                    self.settingsWindow?.close()
                    self.main.showWindow(nil)
                })
            let c = SettingsWindowController(store: store, bindings: bindings, actions: actions)
            settingsController = c
            settingsWindow = c.window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus (Arc's layout)

    private func item(_ id: String) -> NSMenuItem {
        guard let a = bindings.action(id) else { return NSMenuItem() }
        let m = NSMenuItem(title: a.name, action: #selector(menuAction(_:)), keyEquivalent: "")
        m.representedObject = a.id
        m.target = self
        if let s = a.primary {
            m.keyEquivalent = s.key
            m.keyEquivalentModifierMask = s.flags
        }
        return m
    }

    private func std(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.keyEquivalentModifierMask = mods
        return m
    }

    func buildMenus() {
        let menubar = NSMenu()

        let appMenu = NSMenu(title: "Cra")
        appMenu.addItem(withTitle: "About Cra", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(item("settings"))
        let setDefault = item("setDefaultBrowser")
        if setDefault.keyEquivalent.isEmpty { setDefault.keyEquivalent = "♡"; setDefault.keyEquivalentModifierMask = .command }
        appMenu.addItem(setDefault)
        appMenu.addItem(.separator())
        appMenu.addItem(item("importData"))
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(SoftwareUpdater.checkForUpdates(_:)), keyEquivalent: "")
        update.target = SoftwareUpdater.shared
        appMenu.addItem(update)
        appMenu.addItem(.separator())
        appMenu.addItem(std("Hide Cra", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(std("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(std("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(std("Quit Cra", #selector(NSApplication.terminate(_:)), "q"))
        menubar.addItem(submenu: appMenu, title: "Cra")

        let file = NSMenu(title: "File")
        for id in ["newTab", "newWindow", "newIncognitoWindow", "newLittleWindow", "reopenClosedTab", "editURL", "newFolder", "newSpace"] { file.addItem(item(id)) }
        file.addItem(.separator())
        file.addItem(item("closeWindow")); file.addItem(item("closeTab"))
        file.addItem(.separator())
        file.addItem(item("capturePage")); file.addItem(item("print"))
        menubar.addItem(submenu: file, title: "File")

        let edit = NSMenu(title: "Edit")
        edit.addItem(std("Undo", Selector(("undo:")), "z"))
        edit.addItem(std("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(std("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(std("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("copyURL")); edit.addItem(item("copyURLMarkdown"))
        edit.addItem(std("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(std("Paste and Match Style", Selector(("pasteAsPlainText:")), "v", [.command, .shift]))
        edit.addItem(std("Delete", #selector(NSText.delete(_:))))
        edit.addItem(std("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        find.addItem(item("find")); find.addItem(item("findNext")); find.addItem(item("findPrevious"))
        edit.addItem(submenu: find, title: "Find")
        menubar.addItem(submenu: edit, title: "Edit")

        let view = NSMenu(title: "View")
        view.addItem(item("toggleSidebar")); view.addItem(item("toggleToolbar"))
        view.addItem(.separator())
        view.addItem(item("stop")); view.addItem(item("reload")); view.addItem(item("hardReload"))
        // Arc's View menu order: cookies, then cache.
        view.addItem(item("clearCookies")); view.addItem(item("clearCache"))
        view.addItem(.separator())
        view.addItem(item("resetZoom")); view.addItem(item("zoomIn")); view.addItem(item("zoomOut"))
        view.addItem(.separator())
        view.addItem(item("pictureInPicture"))
        view.addItem(.separator())
        for id in ["addSplitView", "closeSplitPane", "separateFromSplit", "flipSplitOrientation"] { view.addItem(item(id)) }
        view.addItem(.separator())
        let dev = NSMenu(title: "Developer")
        for id in ["viewSource", "devTools", "inspectElement", "jsConsole"] { dev.addItem(item(id)) }
        dev.addItem(.separator())
        dev.addItem(item("toggleDeveloperMode"))
        view.addItem(submenu: dev, title: "Developer")
        view.addItem(.separator())
        view.addItem(std("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        menubar.addItem(submenu: view, title: "View")

        let spaces = NSMenu(title: "Spaces")
        spaces.addItem(item("nextSpace")); spaces.addItem(item("previousSpace"))
        spaces.addItem(.separator())
        spaces.addItem(item("editSpace")); spaces.addItem(item("deleteSpace"))
        spaces.addItem(.separator())
        for n in 1...9 { spaces.addItem(item("space\(n)")) }
        menubar.addItem(submenu: spaces, title: "Spaces")

        let tabs = NSMenu(title: "Tabs")
        for id in ["newTab", "pinTab", "nextTab", "previousTab", "recentTab", "clearToday"] { tabs.addItem(item(id)) }
        tabs.addItem(.separator())
        for id in ["favoriteTab", "renameTab", "duplicateTab", "resetTab", "muteTab"] { tabs.addItem(item(id)) }
        tabs.addItem(.separator())
        for n in 1...9 { tabs.addItem(item("item\(n)")) }
        menubar.addItem(submenu: tabs, title: "Tabs")

        let archive = NSMenu(title: "Archive")
        archive.addItem(item("goBack")); archive.addItem(item("goForward")); archive.addItem(item("viewArchive"))
        menubar.addItem(submenu: archive, title: "Archive")

        // Dia: Extensions sits just before Window.
        menubar.addItem(submenu: extensionsMenu.makeMenu(), title: "Extensions")

        let window = NSMenu(title: "Window")
        window.addItem(std("Minimize Window", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(std("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("openLibrary")); window.addItem(item("viewDownloads"))
        window.addItem(.separator())
        window.addItem(item("promoteLittleWindow")); window.addItem(item("closeLittleWindows"))
        window.addItem(.separator())
        window.addItem(std("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        menubar.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Chromium \(CraCEFRuntime.chromiumVersion()) · CEF \(CraCEFRuntime.cefVersion())", action: nil, keyEquivalent: "")
        help.addItem(.separator())
        for (title, url) in [("Cra Help", "https://crabrowser.app/help"), ("Release Notes", "https://crabrowser.app/release-notes"),
                             ("Report an Issue…", "https://github.com/VictorKildahl/cra/issues"), ("Support Cra…", "https://crabrowser.app/support")] {
            let link = NSMenuItem(title: title, action: #selector(openHelpLink(_:)), keyEquivalent: "")
            link.target = self
            link.representedObject = url
            help.addItem(link)
        }
        menubar.addItem(submenu: help, title: "Help")
        NSApp.helpMenu = help

        NSApp.mainMenu = menubar
    }

    /// Help menu links open as a tab in the normal window in use, like Arc's.
    @objc private func openHelpLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        useNormalWindow()
        store.createTab(url: url, select: true)
        main.showWindow(nil)
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cra",
            .applicationVersion: version,
            .version: "\(build) · Chromium \(CraCEFRuntime.chromiumVersion())",
        ])
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
