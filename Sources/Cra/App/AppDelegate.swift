import AppKit
import Carbon.HIToolbox
import CraCEF
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// The store, clock and flags; built the same way by the test hosts.
    let composition = AppComposition()
    var store: SidebarStore { composition.store }
    let bindings = KeyBindingRegistry.shared
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
    private var settingsWindow: NSWindow?
    private var settingsController: SettingsWindowController?
    private var isRelaunching = false
    private lazy var extensionsMenu = ExtensionsMenu(app: self)
    /// Arc's Little Arc windows: small, sidebar-less, disposable (see LittleWindowController).
    private(set) var littleWindows: [LittleWindowController] = []
    /// When each Little Window was last the key window, for Arc's "Archive Little Arcs after:".
    private var littleWindowLastUsed: [ObjectIdentifier: Date] = [:]
    private var littleWindowArchiveCheck: ScheduledWork?

    /// Shortcuts the app takes before the web page sees them (Chrome calls
    /// these reserved). Everything else goes to the page first. Copy URL is reserved like Arc:
    /// Google Docs takes ⇧⌘C for its word count (GitHub #194).
    static let reservedActions: Set<String> = Set([
        "newTab", "newWindow", "newBlankWindow", "newIncognitoWindow", "closeTab", "closeWindow", "reopenClosedTab", "editURL", "toggleSidebar", "toggleToolbar",
        "nextTab", "previousTab", "recentTab", "recentTabBackward", "nextSpace", "previousSpace", "devTools", "jsConsole", "inspectElement",
        "viewArchive", "openLibrary", "settings", "clearToday", "newLittleWindow", "promoteLittleWindow",
        "addSplitView", "closeSplitPane", "copyURL", "copyURLMarkdown",
    ] + (1...9).flatMap { ["item\($0)", "space\($0)", "moveTabToSpace\($0)"] })

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) { bootstrapIfNeeded() }

    func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true
        NSApp.setActivationPolicy(.regular)
        SystemAppearance.shared.start()
        installURLEventHandler()
        PerfCEF.install(app: self)
        CraCEFRuntime.setChromeHosting(store.settings.chromeEngine)
        CraCEFRuntime.setDocumentStartScript(PageScript.mainWorld, isolatedScript: PageScript.isolatedWorld, world: PageScript.world)
        startContentBlocking()
        observeGlobalShortcut()
        observeMenuBarMode()
        SoftwareUpdater.shared.start(app: self)
        buildMenus()
        store.hasPage = { [unowned self] in self.runtime(for: $0).map { !$0.discarded } ?? false }
        store.tabPinned = { [unowned self] in TidyTitlesService.shared.tabPinned($0, store: self.store) }
        // A tip takes the tones of the space its browser window is in (the sidebar may be a
        // floating panel, a child of that window).
        ArcTooltipController.shared.tones = { [unowned self] window in
            var w: NSWindow? = window
            while let x = w {
                if let m = mainWindows.first(where: { $0.window === x }) { return TooltipTones(theme: m.focusedSpace.theme) }
                w = x.parent
            }
            return nil
        }
        // The Boost editor's All Boosts…: Library ▸ Boosts.
        NotificationCenter.default.addObserver(forName: .craShowBoostsLibrary, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.main.showLibrary(.boosts) }
        }
        NotificationCenter.default.addObserver(forName: .craKeyBindingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.buildMenus() }
        }
        // Saved page histories of tabs that are gone, other than the latest closed (PageHistory, #273).
        PageHistoryStore.shared.prune(keeping: PageHistory.kept(
            sidebarTabs: Set(store.allTabs().map(\.id)), archive: store.archive.map(\.id)))
        // Arc's "When opening Arc, restore windows from previous session", off: one window comes back.
        if !store.settings.restoreWindows { store.keepOnlyActiveWindow() }
        // Settings ▸ Advanced "When opening Cra, start on a new tab": the window in front opens on
        // no tab, before any window is made, so the last page isn't loaded only to be hidden.
        // A link that starts Cra arrives before this (application(_:open:)), into pendingURLs.
        // NSApplicationLaunchIsDefaultLaunchKey isn't used: it is false for any start without
        // LaunchServices, a plain one too.
        let launch = LaunchStart.launch(firstRun: needsOnboarding, automaticUpdate: SoftwareUpdater.shared.launchedByAutoUpdate,
                                        withLinks: !pendingURLs.isEmpty)
        let startOnNewTab = LaunchStart.startsOnNewTab(enabled: store.settings.startOnNewTab, launch: launch)
        CraLog.note("launch: \(launch)\(startOnNewTab ? ", on a new tab" : "")")
        if startOnNewTab { store.selectTab(nil, window: store.activeWindowID) }
        // Before any page is made: an easel's tab opens its canvas.
        EaselBrowser.register()
        // Arc's Boosts: each page on a boosted site gets its boosts; an edit shows at once.
        BrowserManager.boostFor = { [store] url in
            guard store.settings.boostsEnabled else { return nil }
            let boosts = Boost.applying(to: url, from: BoostStore.shared.boosts)
            guard !boosts.isEmpty else { return nil }
            return (boosts.map(\.stylesheet).joined(separator: "\n"), boosts.map(\.js).filter { !$0.isEmpty }.joined(separator: ";\n"))
        }
        BoostStore.changed = { [weak self] host in for m in self?.mainWindows ?? [] { m.browsers.reapplyBoosts(host: host) } }
        mainWindows = store.prefs.windows.map { MainWindowController(app: self, session: $0) }
        followKeyWindow()
        observeFlippingRows()
        observeUpdateNotice()
        // First launch: the default browser step and the import are the onboarding and
        // the browser window appears once they are done (Dia does the same).
        if needsOnboarding {
            main.showImport(firstRun: true)
        } else {
            // The window in use last comes up in front.
            for w in mainWindows.reversed() { w.showWindow(nil) }
            // As ⌘T: the command bar makes the new tab, Esc leaves the window empty.
            if startOnNewTab { DispatchQueue.main.async { [weak self] in self?.main.openCommandBar(.newTab) } }
        }
        installKeyFallbackMonitor()
        installSideButtonKeyMonitor()
        installCommandFileWatcher()
        MCPServer.shared.start(app: self)
        composition.startPeriodicWork { [weak self] in self?.sleepIdleTabs() }
        composition.sync.keybindingsChanged = { [weak self] in self?.bindings.reloadOverrides() }
        composition.sync.start()
        SharingService.shared.start(store: store, clock: composition.clock)
        observeSystemWake()
        logSidebarProblems()
        LiveFolderManager.shared.start(store: store)
        // A restart into an update while the user was away leaves the front app alone.
        if HitchMonitor.background {
            // Measured behind whatever is in front; still on screen, so pages keep drawing.
            for w in mainWindows { w.window?.orderBack(nil) }
        } else if !SoftwareUpdater.shared.launchedByAutoUpdate {
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.installURLEventHandler() }
        // The Site Control Center's Share would otherwise pay for finding the share extensions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { SharePicker.warmUp() }
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
        DownloadDestinations.install(store: store)
        AppLinkPrompt.install()
        let dropsStartUpPage = { [weak self] (url: String) -> Bool in
            guard let self, Date().timeIntervalSince(launchedAt) < 10,
                  !hasNewExtension || self.store.allTabs().contains(where: { $0.tab?.url == url }) else { return false }
            NSLog("Cra: dropped start-up page from an extension: %@", url)
            return true
        }
        CraCEFRuntime.setStrayPageHandler { [weak self] url, profile in
            Task { @MainActor in
                guard let self, !dropsStartUpPage(url) else { return }
                // The window in use, and a space on the profile whose extension asked (#107).
                let window = self.useNormalWindow()
                self.openExtensionPage(url, window: window.windowID, profile: profile)
                window.showWindow(nil)
            }
        }
        // chrome.tabs.create: the page Chromium made becomes the new tab's, so the id the
        // extension got back is the tab that loads (#292). Declined (a dropped start-up page, an
        // options page already open), it goes to Chrome's window and the stray page handler.
        CraCEFRuntime.setExtensionTabHandler { [weak self] url, profile, background, opener in
            MainActor.assumeIsolated {
                // A cra: address never opens from a page or an extension, as BrowserManager drops page popups to one.
                guard let self, !url.lowercased().hasPrefix("cra:"), !dropsStartUpPage(url) else { return nil }
                let window = self.useNormalWindow()
                guard let opened = self.openExtensionPage(url, window: window.windowID, profile: profile, select: !background),
                      let controller = self.mainWindows.first(where: { $0.windowID == opened.window }) else { return nil }
                let host = controller.browsers.makePopupHost(for: opened.tab, opener: opener)
                if !background {
                    controller.browsers.show(opened.tab, focus: true)
                    controller.showWindow(nil)
                }
                return host
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
        Perf.phase("windowsShown")
    }

    /// A fresh install runs Dia's onboarding (cover, default browser, privacy,
    /// import, pinned tabs, personalization, outro).
    var needsOnboarding: Bool {
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
        // Arc's "Archive Little Arcs after:": a Little Window left alone that long closes, its page archived.
        littleWindowArchiveCheck = composition.clock.every(60) { [weak self] in self?.archiveIdleLittleWindows() }
        observeChanges(of: { [store] in store.settings.websiteAppearance }) { CraCEFRuntime.setWebsiteAppearance($0.chromiumMode) }
        observeChanges(of: { [store] in store.settings.soundEffects }) { CaptureSound.enabled = $0 }
        observeLinkMenu()
        logSecureDNS()
    }

    /// A sidebar whose links disagree (SidebarIntegrity) says so in the log, one fault a problem.
    private func logSidebarProblems() {
        let problems = store.integrityProblems()
        for p in problems.prefix(20) { CraLog.fault("sidebar: \(p)") }
        if problems.count > 20 { CraLog.fault("sidebar: \(problems.count - 20) more problems") }
    }

    /// AppComposition.tabFreezeAfter; `cra://debug?freezeTabs=` shortens it for a test.
    private var freezeAfter = AppComposition.tabFreezeAfter

    /// The last memory-pressure sweep (TabSleepPolicy.sweepsForPressure).
    private var lastPressureSweep: Date?
    /// The last pass, timer or wake (TabSleepPolicy.passDue).
    private var lastSleepPass: Date?
    /// The level the last pass read, so cra.log says when it changes (#275: a report couldn't
    /// tell a late timer from a level that read normal).
    private var lastPressure: PerfSystemSample.Pressure?

    /// Waking the Mac runs a pass at once (#275): the timer doesn't fire in system sleep, and
    /// one that is late, or held back by App Nap, left a full Mac alone for 24 minutes. The
    /// now-playing cards read their tabs' sound again.
    private func observeSystemWake() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        }
    }

    /// Chromium's audio service as the Mac went to sleep: waking says whether it lived (#286).
    private var audioServiceBeforeSleep: pid_t?

    private func systemWillSleep() {
        audioServiceBeforeSleep = PerfProcessSampler.audioServicePID()
        CraLog.note(AudioServiceWake.sleepLine(pid: audioServiceBeforeSleep))
    }

    private func systemDidWake() {
        CraLog.note("tab sleep: the Mac woke")
        CraLog.note(AudioServiceWake.line(beforeSleep: audioServiceBeforeSleep, now: PerfProcessSampler.audioServicePID()))
        audioServiceBeforeSleep = nil
        for w in mainWindows { w.browsers.systemDidWake() }
        sleepIdleTabs()
    }

    /// Settings ▸ Tabs ▸ Tab Cleanup, read every minute so a change counts from the next pass.
    private func sleepIdleTabs() {
        let now = composition.clock.now
        guard TabSleepPolicy.passDue(lastPass: lastSleepPass, now: now) else { return }
        lastSleepPass = now
        let settings = store.settings
        for w in mainWindows {
            w.browsers.freezeIdleTabs(hiddenLongerThan: freezeAfter)
            w.releaseHiddenFrames(now: composition.clock.now)
            if settings.tabSleepTimerEnabled { w.browsers.sleepIdleTabs(.timer(settings.tabSleepAfter)) }
        }
        let pressure = PerfSystemSample.pressure(level: PerfSystemSampler.pressureLevel())
        if let lastPressure, lastPressure != pressure { CraLog.note("memory pressure \(lastPressure.rawValue) → \(pressure.rawValue)") }
        lastPressure = pressure
        sweepForMemoryPressure(pressure)
    }

    /// "Force tabs out of memory when the Mac is short of memory" (GitHub #153): while macOS
    /// reports memory pressure, the pages hidden longest close, a few per sweep, until it doesn't.
    private func sweepForMemoryPressure(_ pressure: PerfSystemSample.Pressure) {
        let now = composition.clock.now
        guard TabSleepPolicy.sweepsForPressure(pressure, enabled: store.settings.tabSleepOnMemoryPressure,
                                               lastSweep: lastPressureSweep, now: now) else { return }
        lastPressureSweep = now
        let policy = TabSleepPolicy.memoryPressure(pressure)
        CraLog.note("tab sleep: memory pressure \(pressure.rawValue), closing up to \(policy.limit ?? 0) pages per window")
        for w in mainWindows { w.browsers.sleepIdleTabs(policy) }
    }

    /// Settings > Privacy > "Always use secure connections", live like content blocking.
    private func observeHttpsOnly() {
        observeChanges(of: { [store] in store.settings.httpsOnly }, apply: CraCEFRuntime.setHttpsOnlyModeEnabled)
    }

    /// Chromium's secure DNS setting (Settings > Privacy, chrome://settings/security), left on
    /// Chromium's default like Arc: the log says what is in effect at launch and after each
    /// change (#110), and the Settings row follows it (#133).
    private func logSecureDNS() {
        var last: String?
        CraCEFRuntime.setSecureDNSChangeHandler {
            let setting = SecureDNSSetting.shared
            setting.refresh()
            guard let line = setting.inEffect?.line else { return }
            if line != last { last = line; CraLog.note("secure dns: " + line) }
        }
    }

    /// The page context menu's "Open Link in New Tab" (LinkMenu), read when the next menu opens:
    /// behind the page as in Arc unless Settings ▸ Tabs says to switch (#276). It and the image
    /// search item read in Chromium's language, as Arc's do.
    private func observeLinkMenu() {
        let newTab = CraCEFRuntime.chromiumString(.openLinkInNewTab) ?? LinkMenu.newTabTitle
        observeChanges(of: { [store] in store.settings.openLinksInForeground }) { switches in
            let item = LinkMenu.item(switchesToTab: switches, newTabTitle: newTab)
            CraCEFRuntime.setLinkMenuTitle(item.title, opensInBackground: item.opensInBackground)
        }
        CraCEFRuntime.setImageSearchTitle { lens in
            guard let lensTemplate = CraCEFRuntime.chromiumString(.searchLensForImage),
                  let webTemplate = CraCEFRuntime.chromiumString(.searchWebForImage) else { return nil }
            return PageMenuLabels.imageSearch(lensLabel: lens, lensTemplate: lensTemplate, webTemplate: webTemplate)
        }
    }

    /// Arc's "Open Little Arc when I press ⌥⌘N" (#195): New Little Window's shortcut from any app,
    /// following the setting, the shortcut's binding and the keyboard layout. A test copy in the
    /// background leaves the shortcut to the installed Cra.
    private func observeGlobalShortcut() {
        guard !HitchMonitor.background else { return }
        let hotkey = GlobalHotkey { [weak self] in self?.perform("newLittleWindow") }
        globalHotkey = hotkey
        let chord = { [store, bindings] in
            GlobalShortcut.registrable(bindings.action("newLittleWindow")?.shortcuts ?? [], enabled: store.settings.littleWindowShortcutEverywhere)
        }
        observeChanges(of: chord) { hotkey.set($0) }
        // The same chord on another layout can be another key.
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                hotkey.set(nil)
                hotkey.set(chord())
            }
        }
    }

    private var globalHotkey: GlobalHotkey?

    private func observeContentBlocking() {
        observeChanges(of: { [store] in store.settings.blockAdsAndTrackers }, apply: CraCEFRuntime.setContentBlockingEnabled)
    }

    /// The last update notice toasted this launch (UpdateNotice.toast), and how many were.
    private var toldUpdate: UpdateNotice?
    private var updateToasts = 0

    /// An update that turns up, or a sidebar hidden while one waits, toasts in the front window
    /// when that window's sidebar is hidden: the banner can't be seen there.
    private func observeUpdateNotice() {
        observeChanges(of: { [unowned self] in
            UpdateNotice.toast(SoftwareUpdater.shared.notice, told: toldUpdate, sidebarVisible: main?.sidebarVisible ?? true)
        }) { [weak self] notice in
            guard let self, let notice, let w = main, w.window?.isVisible == true else { return }
            toldUpdate = notice
            updateToasts += 1
            w.showUpdateToast(notice)
            CraLog.note("update toast \(updateToasts): \(notice.title) [\(notice.button)] \(notice.version)")
        }
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
        leaveMenuBarForWindow()
        if main?.raiseImport() == true { return true }
        main?.showWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if MenuBarMode.outcome(enabled: store.settings.keepInMenuBar, source: quitSource()) == .stayInMenuBar {
            stayInMenuBar()
            return .terminateCancel
        }
        // Arc asks while a download runs (quitting cancels it); otherwise Dia's Advanced ▸ "Warn
        // before quitting". Restarts skip both (#272).
        switch QuitPrompt.on(source: quitSource(), downloadsRunning: DownloadHistory.shared.hasRunningDownloads,
                             warnBeforeQuitting: store.settings.warnBeforeQuitting) {
        case .downloadsInProgress: if !confirmQuitCancellingDownloads() { return .terminateCancel }
        case .confirmQuit: if !confirmQuit() { return .terminateCancel }
        case .none: break
        }
        // Little Windows are not in the sidebar; keep their pages in the Library.
        for w in littleWindows { w.archivePage() }
        for w in mainWindows { w.saveFrameNow() }
        store.saveAll()
        // Each page's back and forward list, scroll positions included, as it is now (PageHistory,
        // #273). A page that doesn't answer in time keeps what was saved after its last load.
        let group = DispatchGroup()
        for w in mainWindows {
            group.enter()
            w.browsers.saveAllHistory { group.leave() }
        }
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        group.notify(queue: .main, execute: reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: reply)
        return .terminateLater
    }

    func applicationWillShutdown() { MCPServer.shared.stop(); store.saveAll() }

    /// Sparkle quits Cra to install an update and starts it again: no quit confirmation.
    func prepareForUpdateRelaunch() {
        isRelaunching = true
        for w in mainWindows { w.saveFrameNow() }
        store.saveAll()
    }

    /// Why an automatic update restart should wait (Arc: downloads in progress,
    /// window_dialog_sheet_visible, active tabs). Little Windows go to the Library on quit,
    /// so an open one waits too.
    func autoUpdateBlocker() -> String? {
        if DownloadHistory.shared.hasRunningDownloads { return "a download is in progress" }
        if NSApp.modalWindow != nil || NSApp.windows.contains(where: { $0.isVisible && $0.attachedSheet != nil }) { return "a dialog is open" }
        if !littleWindows.isEmpty { return "a Little Window is open" }
        if PictureInPictureChrome.shared.isPlaying { return "Picture in Picture is playing" }
        if main.isImportVisible { return "the import is open" }
        return nil
    }

    /// Arc 1.172's question when quitting would cancel downloads (its words, "Close Arc" made
    /// Cra's). Also asked before Install and Relaunch restarts into an update (#272).
    func confirmQuitCancellingDownloads() -> Bool {
        CraLog.note("quit asks: downloads in progress")
        let alert = AppDialog(title: "Downloads in progress",
                              message: "There are downloads in progress. Closing the application will cancel them.",
                              actions: [DialogAction("Close Cra"), DialogAction("Keep browsing", role: .cancel)],
                              icon: .application)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmQuit() -> Bool {
        let alert = AppDialog(title: "Quit Cra?",
                              actions: [DialogAction("Quit"), .cancel, DialogAction("Quit, and don’t ask again", role: .secondary)],
                              icon: .application, buttonSpacing: 45.5)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertThirdButtonReturn:
            store.settings.warnBeforeQuitting = false
            return true
        default: return false
        }
    }

    func openExternalURL(_ url: String) {
        // A link from another app soon after starting on a new tab: its tab is what the window
        // shows, so the bar that was waiting for a new tab goes.
        if store.settings.startOnNewTab, let m = main, m.commandBar.isOpen, m.selectedTab == nil { m.commandBar.close() }
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
        case .littleWindow(let space):
            // #258: the route's space names the page's profile and where ⌘O sends it.
            openLittleWindow(url: url, space: openableSpace(space))
            return
        case .space(let id) where store.space(id) != nil:
            store.createTab(url: url, in: id, select: true)
        case .space, .mostRecentSpace:
            store.createTab(url: url, select: true)
        }
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Menu bar (#231)

    /// Settings ▸ Advanced ▸ "Keep Cra in the menu bar": the item is there while the setting is
    /// on. A test copy in the background leaves the menu bar to the installed Cra.
    private func observeMenuBarMode() {
        observeChanges(of: { [store] in store.settings.keepInMenuBar }) { [weak self] on in
            guard let self else { return }
            if on, menuBarItem == nil, !HitchMonitor.background {
                menuBarItem = MenuBarItem { [weak self] menu in self?.buildMenuBarItemMenu(menu) }
            } else if !on {
                menuBarItem?.remove()
                menuBarItem = nil
                // Turned off from Settings opened in the menu bar: the windows come back, or
                // nothing of Cra would be left to click.
                if inMenuBar { main.showWindow(nil) }
            }
        }
    }

    private func buildMenuBarItemMenu(_ menu: NSMenu) {
        for id in ["newWindow", "newIncognitoWindow", "newLittleWindow"] { menu.addItem(item(id)) }
        menu.addItem(.separator())
        menu.addItem(item("settings"))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cra", action: #selector(quitFromMenuBar), keyEquivalent: "").target = self
    }

    /// The menu bar item's Quit, and `cra://debug?quit=1`: Cra quits for real.
    @objc func quitFromMenuBar() {
        quittingFromMenuBar = true
        NSApp.terminate(nil)
    }

    private var menuBarItem: MenuBarItem?
    private var quittingFromMenuBar = false
    /// ⌘Q put Cra in the menu bar, and no browser window has been opened since.
    private(set) var inMenuBar = false

    private func quitSource() -> MenuBarMode.QuitSource {
        if isRelaunching { return .relaunch }
        if quittingFromMenuBar { return .menuBarItem }
        if let e = NSAppleEventManager.shared().currentAppleEvent,
           e.eventClass == AEEventClass(kCoreEventClass), e.eventID == AEEventID(kAEQuitApplication) { return .appleEvent }
        return .appMenu
    }

    /// ⌘Q with the setting on: what a quit would close closes (Little Windows into the Library,
    /// incognito windows with their session, every page), the browser windows a relaunch would
    /// bring back are put away, and Cra leaves the Dock. Chromium keeps running, so ⌥⌘N and the
    /// menu bar item open a window at once.
    private func stayInMenuBar() {
        CraLog.note("menu bar: quit keeps Cra in the menu bar")
        closeLittleWindows()
        settingsWindow?.close()
        let plan = MenuBarMode.windowsOnQuit(mainWindows.map { .init(id: $0.windowID, kind: $0.isIncognito ? .incognito : $0.isBlank ? .blank : .normal) },
                                            active: store.activeWindowID, restoreWindows: store.settings.restoreWindows)
        for c in mainWindows where plan.close.contains(c.windowID) { c.window?.close() }
        for c in mainWindows {
            c.saveFrameNow()
            c.putAway()
        }
        store.saveAll()
        inMenuBar = true
        settleDockIcon()
    }

    /// A browser window is about to show: the ones put away come back with it, as after a launch.
    func browserWindowWillShow(_ c: MainWindowController) {
        guard inMenuBar else { return c.bringBack() }
        inMenuBar = false
        leaveMenuBarForWindow()
        CraLog.note("menu bar: browser windows back")
        for w in mainWindows {
            w.bringBack()
            if w !== c { w.window?.orderFront(nil) }
        }
    }

    /// Any window of Cra's about to show: the Dock icon and the app menu come back first, or the
    /// window would come up in an app macOS treats as menu-bar-only.
    private func leaveMenuBarForWindow() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        if NSApp.isHidden { NSApp.unhide(nil) }
    }

    /// In the menu bar with nothing open: no Dock icon, and the app in front before ⌘Q gets the keyboard.
    private func settleDockIcon() {
        let open = littleWindows.contains { $0.window?.isVisible == true } || settingsWindow?.isVisible == true
            || mainWindows.contains { $0.window?.isVisible == true }
        guard !MenuBarMode.showsInDock(inMenuBar: inMenuBar, windowsOpen: open), NSApp.activationPolicy() == .regular else { return }
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
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
                    if let c = self.mainWindows.first(where: { $0.window === w }) {
                        self.store.activeWindowID = c.windowID
                        self.retitleFlippingRows()
                    }
                    self.littleWindows.first { $0.window === w }?.refreshTarget()
                }
            }
        }
    }

    /// A page an extension opens as a tab. Its options page stays one tab, as in Chrome and
    /// Arc: opening it again selects the open one (GitHub #38).
    /// `profile` is the Chromium profile folder whose extension asked, nil for the focused page's.
    /// `singleton`: an open tab with the page in that profile is selected instead of a new one.
    /// `select` false opens a new tab behind (tabs.create's active: false). Returns the new tab and
    /// its window, nil when an open tab was selected.
    @discardableResult
    func openExtensionPage(_ url: String, window: UUID, profile: String? = nil, singleton: Bool = false,
                           select: Bool = true) -> (tab: UUID, window: UUID)? {
        // Extensions run in the normal profile, so Chrome opens their pages in a normal window:
        // in an incognito one the page can't load (#107). Incognito is Default's off the record.
        var window = window, profile = profile
        if mainWindows.first(where: { $0.windowID == window })?.isIncognito == true {
            let normal = useNormalWindow()
            if !normal.isIncognito {
                window = normal.windowID
                profile = profile ?? "Default"
                normal.showWindow(nil)
            }
        }
        let page = { (u: String) in u.split(separator: "#", maxSplits: 1).first.map(String.init) ?? u }
        let space = { (id: UUID) in ExtensionPagePlacement.Space(id: id, profile: self.store.profileDirectoryName(space: id)) }
        let open = store.allTabs().compactMap { t -> (tab: UUID, space: UUID)? in
            guard t.tab.map({ page($0.url) == page(url) }) == true, let sid = store.spaceID(ofItem: t.id) else { return nil }
            return (t.id, sid)
        }
        let target = ExtensionPagePlacement.target(
            focused: space(store.focusedSpaceID(window: window)),
            spaces: store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.map { space($0.id) },
            profile: profile, openTabs: open, singleton: singleton || ExtensionStore.shared.optionsPageOwner(url) != nil)
        switch target {
        case .select(let tab):
            store.selectTab(tab, window: window)
            return nil
        case .create(let sid):
            return (store.createTab(url: url, in: sid, select: select, window: window).id, window)
        }
    }

    /// The window links from other apps, the Library and Little Windows go to: the
    /// normal window in use last, never an incognito or Blank Window.
    @discardableResult
    func useNormalWindow() -> MainWindowController {
        if main.isStandalone, let normal = mainWindows.first(where: { $0.windowID == store.lastNormalWindowID })
            ?? mainWindows.first(where: { !$0.isStandalone }) {
            store.activeWindowID = normal.windowID
        }
        return main
    }

    /// The normal window a page sent to `spaceID` opens in (SpaceWindow): one already showing
    /// the space, else the one in use last, which then switches to it.
    @discardableResult
    func useNormalWindow(forSpace spaceID: UUID) -> MainWindowController {
        let last = useNormalWindow()
        guard !last.isStandalone else { return last }
        var seen = Set<UUID>()
        let normal = NSApp.orderedWindows.compactMap { w in mainWindows.first { $0.window === w } }
            .filter { !$0.isStandalone && seen.insert($0.windowID).inserted }
            .map { (id: $0.windowID, space: store.focusedSpaceID(window: $0.windowID)) }
        store.activeWindowID = SpaceWindow.window(for: spaceID, windows: normal, lastUsed: last.windowID)
        return main
    }

    /// Arc's New Window (⌘N): another window on the space in use, cascaded from the
    /// current one, with the command bar up. With every window closed it brings the
    /// hidden one back instead. New Incognito Window (⇧⌘N) and Blank Window (⌃⌘N) always open
    /// a new one. With `url` (a page's Open Link in New Window) the window opens on that page instead.
    func openNewWindow(incognito: Bool = false, blank: Bool = false, url: String? = nil) {
        if !incognito, !blank, let hidden = mainWindows.first(where: { !$0.isStandalone }),
           !mainWindows.contains(where: { $0.window?.isVisible == true || $0.window?.isMiniaturized == true }) {
            hidden.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let url { store.createTab(url: url, select: true, window: hidden.windowID) }
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
            : blank ? store.addBlankWindow(frame: frame)
            : store.addWindow(spaceID: store.focusedSpaceID(window: store.lastNormalWindowID), frame: frame)
        let c = showNewWindow(session)
        if let url { store.createTab(url: url, select: true, window: c.windowID) } else { c.openCommandBar(.newTab) }
    }

    @discardableResult
    private func showNewWindow(_ session: WindowSession) -> MainWindowController {
        let c = MainWindowController(app: self, session: session)
        mainWindows.append(c)
        store.activeWindowID = c.windowID
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return c
    }

    /// A Blank Window's "Move to…" (Arc 1.172): its tabs go to the top of the space's Today, the one
    /// it had open opens in the main window with its page as it was, and the Blank Window closes.
    func moveBlankWindow(_ c: MainWindowController, toSpace sid: UUID) {
        guard c.isBlank, store.space(sid) != nil, !store.isStandalone(space: sid) else { return }
        let open = store.moveBlankWindowTabs(c.windowID, toSpace: sid)
        let target = useNormalWindow(forSpace: sid)
        if let open {
            store.selectTab(open, window: target.windowID)
            if let rt = c.browsers.release(open) { target.takePage(rt) }
        } else {
            store.focusSpace(sid, window: target.windowID)
        }
        c.window?.close()
        target.showWindow(nil)
    }

    /// A tab dragged out of every Cra window and let go (GitHub #219): as in Arc, it moves into
    /// a new Blank Window placed where it was dropped, with its page as it was (no reload).
    /// `screenPoint` is where the pointer let go; the window takes the size of the one it came from.
    func tearOffTab(_ id: UUID, at screenPoint: NSPoint, from source: MainWindowController) {
        guard store.item(id)?.isTab == true, !store.isIncognito(item: id) else { return }
        let size = source.window?.frame.size ?? NSSize(width: 1200, height: 800)
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? source.window?.screen ?? NSScreen.main
        let frame = TabTearOff.frame(size: size, droppedAt: screenPoint, visible: screen?.visibleFrame ?? .zero)
        let session = store.addBlankWindow(frame: NSStringFromRect(frame))
        store.moveToBlankWindow(id, window: session.id)
        let c = showNewWindow(session)
        // Handed over now, not left for whichever window is in use next to claim it.
        if let rt = source.browsers.release(id) { c.takePage(rt) }
    }

    /// A page's context menu: Arc's Open Link in New Window, Little Arc (Little Window here)
    /// and Incognito Window. From an incognito page a new window is incognito too, as in Chrome,
    /// and nothing opens in a Little Window, whose pages load in the normal profile.
    func openLink(_ url: String, in kind: CraLinkWindow, space: UUID?, fromIncognito: Bool) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        if url.lowercased().hasPrefix("cra:") { return }
        switch kind {
        case .little where !fromIncognito: openLittleWindow(url: url, space: space)
        case .incognito: openNewWindow(incognito: true, url: url)
        default: openNewWindow(incognito: fromIncognito, url: url)
        }
    }

    /// Closing one of several windows ends it; the last normal one stays around hidden,
    /// so a Dock click brings the browser back as it was. Incognito and Blank Windows always end
    /// (a Blank Window's tabs with it, as in Arc), and with the last incognito window the
    /// off-the-record profile goes too.
    func mainWindowWillClose(_ c: MainWindowController) {
        guard !isRelaunching, c.isStandalone || mainWindows.contains(where: { $0 !== c && !$0.isStandalone }) else { return }
        mainWindows.removeAll { $0 === c }
        c.tearDown()
        store.removeWindow(c.windowID)
        if c.isIncognito, !mainWindows.contains(where: \.isIncognito) {
            CraCEFRuntime.endIncognitoSession()
            WebKitStores.endIncognitoSession()
        }
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
            return littleWindows.first { !$0.isParked && ($0.window === key || $0.window === key.parent) }
        }
        // No key window while the app is inactive (e.g. during a cra:// handoff from a
        // second launch): the frontmost window stands in for it.
        guard let front = NSApp.orderedWindows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return nil }
        return littleWindows.first { !$0.isParked && ($0.window === front || $0.window === front.parent) }
    }

    /// A space a link from outside may name (cra://open, an Air Traffic Control Little Window):
    /// one that exists and isn't incognito, else nil, the space in use.
    private func openableSpace(_ id: UUID?) -> UUID? {
        id.flatMap { store.space($0) != nil && !store.isIncognito(space: $0) ? $0 : nil }
    }

    /// Creates a little window without showing it (`url` nil = popup host).
    func makeLittleWindow(url: String?, opener: CraBrowser? = nil, space: UUID? = nil) -> LittleWindowController {
        leaveMenuBarForWindow()
        let w = LittleWindowController(app: self, url: url, opener: opener, space: space)
        littleWindows.append(w)
        return w
    }

    @discardableResult
    func openLittleWindow(url: String, activate: Bool = true, opener: CraBrowser? = nil, space: UUID? = nil) -> LittleWindowController {
        let w = makeLittleWindow(url: url, opener: opener, space: space)
        if activate { w.show() } else { w.orderFrontInBackground() }
        return w
    }

    /// Arc's Peek: a Little Window over `parent` that closes when a click lands past it.
    /// One per tab (#242): a Peek another tab left waiting stays.
    func openPeek(url: String, over parent: MainWindowController, fromTab tabID: UUID? = nil) {
        for p in littleWindows where p.peekParent === parent && (!p.isParked || p.peekSourceTab == tabID) { p.closeWindow() }
        let w = LittleWindowController(app: self, url: url, peekOver: parent, fromTab: tabID)
        littleWindows.append(w)
        // Arc badges the tab the Peek came from with the peeked page's favicon (modalIcon), also
        // while the Peek waits on it.
        if let tabID { parent.sidebarUI.peekBadges[tabID] = .init(iconKey: FaviconKey.key(for: url)) }
        w.showAsPeek(fromTab: tabID)
    }

    func removeLittleWindow(_ w: LittleWindowController) {
        littleWindows.removeAll { $0 === w }
        if inMenuBar { DispatchQueue.main.async { [weak self] in self?.settleDockIcon() } }
        if let parent = w.peekParent, let tab = w.peekSourceTab,
           !littleWindows.contains(where: { $0.peekParent === parent && $0.peekSourceTab == tab }) { parent.sidebarUI.peekBadges[tab] = nil }
    }

    private func archiveIdleLittleWindows() {
        let now = Date(), rule = store.settings.littleWindowArchiveAfter
        let open = Set(littleWindows.map(ObjectIdentifier.init))
        littleWindowLastUsed = littleWindowLastUsed.filter { open.contains($0.key) }
        // A Peek belongs to its tab; only Little Windows of their own are archived (Arc).
        for w in littleWindows where !w.isPeek {
            let id = ObjectIdentifier(w), isKey = w.window?.isKeyWindow == true
            if isKey || littleWindowLastUsed[id] == nil { littleWindowLastUsed[id] = now; continue }
            if rule.expired(lastUsed: littleWindowLastUsed[id]!, now: now, isKey: isKey) {
                CraLog.note("archiving a Little Window left alone for \(rule.label)")
                w.closeWindow()
            }
        }
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

    /// cra://commandbar?query=…&mode=edit, cra://action/<id>,
    /// cra://open?url=…[&space=<space id>][&background=1|&little=1], cra://dismiss.
    func handleInternalURL(_ u: URL) {
        let comps = URLComponents(url: u, resolvingAgainstBaseURL: false)
        func q(_ name: String) -> String? { comps?.queryItems?.first { $0.name == name }?.value }
        // What comes forward is InternalURLRaise's. A background test instance
        // (CRA_TEST_BACKGROUND) never comes to the front.
        let little = u.host == "open" && q("little") == "1"
        let background = u.host == "open" && q("background") == "1"
        if InternalURLRaise.raises(host: u.host, little: little, background: background, littleWindowIsKey: keyLittleWindow != nil),
           !HitchMonitor.background {
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
            guard let url = q("url") else { break }
            // space=<id> (#168): a real, normal space, as Air Traffic Control routes to; an unknown
            // or incognito one opens where it did before, in the space in use.
            let space = openableSpace(q("space").flatMap(UUID.init(uuidString:)))
            if little {
                openLittleWindow(url: url, space: space)
            } else if let space {
                // Held: useNormalWindow(forSpace:) can change which window is main.
                let target = useNormalWindow(forSpace: space)
                let tab = store.createTab(url: url, in: space, select: !background, window: target.windowID)
                if background { store.markUnread(tab.id, true); target.browsers.ensureRuntime(for: tab.id) }
                if !background, !HitchMonitor.background { target.showWindow(nil) }
            } else {
                useNormalWindow()
                let tab = store.createTab(url: url, select: !background)
                if background { store.markUnread(tab.id, true); main.browsers.ensureRuntime(for: tab.id) }
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
            if dict["pageInsets"] != nil { CraLog.note(main.pageInsetsReadout()); return }
            // Tests that leave the pointer alone: scroll=dy,steps,x,y scrolls the scroll view at a
            // point of the main window (from its top left); swipe=dx,steps plays a space swipe.
            if let g = dict["scroll"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 4, let w = main.window {
                TestGesture.scroll(by: g[0], steps: Int(g[1]), at: NSPoint(x: g[2], y: w.frame.height - g[3]), in: w)
                return
            }
            // menuAt=x,y (&button=right): the menu a click there opens, e.g. the ⌄ or a row's (#89);
            // target=little: in the newest Little Window (its profile chip, #172).
            if let g = dict["menuAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2,
               let w = dict["target"] == "little" ? littleWindows.last?.window : main.window {
                TestGesture.openMenu(at: NSPoint(x: g[0], y: w.frame.height - g[1]), in: w, right: dict["button"] == "right")
                return
            }
            // clickAt=x,y: a click there through the event queue, as the pointer's would go (#195);
            // target=little as for menuAt. button=back|forward: that mouse button released there,
            // handed to what the window's otherMouseUp monitor runs (#233); AppKit can't make a
            // window's event with button 3 or 4.
            if let g = dict["clickAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2,
               let w = dict["target"] == "little" ? littleWindows.last?.window : main.window {
                let point = NSPoint(x: g[0], y: w.frame.height - g[1])
                if let b = dict["button"], let button = ["back": MouseButtonSpaceSwitch.back, "forward": MouseButtonSpaceSwitch.forward][b] {
                    let taken = TestGesture.otherMouseUp(at: point, in: w).map { main.mouseButtonSwitchesSpace(button, $0) } ?? false
                    CraLog.note("mouse \(b) at \(Int(g[0])),\(Int(g[1])): \(taken ? "switched space" : "passed on")")
                    return
                }
                // clicks=2: a double-click there (a favorite's Back to Pinned Page, #264); mods=<modifier
                // bits>: keys held through it (524288, Option: a link opens in Split View, #298).
                TestGesture.click(at: point, in: w, clicks: dict["clicks"].flatMap(Int.init) ?? 1,
                                  modifiers: NSEvent.ModifierFlags(rawValue: dict["mods"].flatMap(UInt.init) ?? 0))
                return
            }
            if let st = dict["status"] { main.browserManager(statusMessage: st); return }
            // key=<characters>,<key code>,<modifier bits>: a key press as a layout reports it
            // (Turkish Q's ⌘- is "-",24,1048576), through the app's event queue (#212); the
            // characters are percent-encoded. zoomLevel logs the page's zoom.
            if let k = dict["key"]?.split(separator: ",", omittingEmptySubsequences: false), k.count == 3,
               let code = UInt16(k[1]), let mods = UInt(k[2]), let w = main.window {
                TestGesture.key(String(k[0]), keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: mods), in: w)
                return
            }
            if dict["zoomLevel"] != nil {
                let keys = main.window?.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nothing"
                CraLog.note("zoom level \(main.currentBrowser?.zoomLevel() ?? .nan), keys go to \(keys)")
                return
            }
            // tidy: the divider's Tidy on the window's space, without hovering it; undoTidy: ⌘Z's.
            if dict["tidy"] != nil { TidyTabsService.shared.tidy(store.focusedSpace(window: main.windowID).id, store: store); return }
            if dict["undoTidy"] != nil { _ = store.undoTidy(); return }
            // applescript=<source>: an AppleScript run inside Cra (raw «class …» codes address its own
            // dictionary), its result or error logged; no other app, so no Automation prompt.
            // Off the main thread, as a script from another app would be: commands that wait for a
            // page (execute javascript) answer on the main thread.
            if let source = dict["applescript"] {
                Thread.detachNewThread {
                    var error: NSDictionary?
                    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                    NSLog("Cra applescript → %@", result?.stringValue ?? result.map { "\($0)" } ?? "error \(error?[NSAppleScript.errorNumber] ?? "") \(error?[NSAppleScript.errorMessage] ?? "")")
                }
                return
            }
            // gmailPreview=<unread>: the Gmail favorite's preview card for a sample inbox.
            if let n = dict["gmailPreview"].flatMap(Int.init), let w = main.window { FavoritePreviewCard.shared.demoGmail(unread: n, in: w); return }
            // calendarPreview=1: the Calendar favorite's card for a sample day (a call in 90 s).
            if dict["calendarPreview"] != nil, let w = main.window { FavoritePreviewCard.shared.demoCalendar(in: w); return }
            // previewDismiss=1: the card goes, as when the pointer leaves it.
            if dict["previewDismiss"] != nil { FavoritePreviewCard.shared.dismiss(animated: false); return }
            // boostZap=1|0: Boost editor's Zap on or off for the open page.
            if let z = dict["boostZap"] { main.debugZap(z == "1"); return }
            // boostPick=1|0|copyThis|copyRelated|zapRelated: the code panel's eyedropper on (the
            // menu answered with that action) or off.
            if let p = dict["boostPick"] { main.debugPick(p); return }
            // captureToEasel=1: the page's screenshot, then the capture menu's New Easel.
            if let how = dict["captureToEasel"] { main.debugCaptureToEasel(send: how == "send"); return }
            // mcpAnswer=allow|deny: answers MCP's open "Let … use Cra?" prompt (test copies).
            if let answer = dict["mcpAnswer"] { MCPServer.shared.answerPrompt(allow: answer == "allow"); return }
            // mcpScripts=on|off: Settings ▸ Advanced ▸ Let agents run JavaScript in pages.
            if let scripts = dict["mcpScripts"] { MCPServer.shared.allowsScripts = scripts == "on"; return }
            // mcpHistory=on|off: Settings ▸ Advanced ▸ Let agents read your history.
            if let history = dict["mcpHistory"] { MCPServer.shared.allowsHistory = history == "on"; return }
            // mcpStop=1: the pill's Stop (every agent disconnects, MCP turns off).
            if dict["mcpStop"] != nil { MCPServer.shared.stopFromPill(); return }
            // settingsPane=max: Settings opened on that pane.
            if let p = dict["settingsPane"].flatMap(SettingsPane.init(rawValue:)) {
                showSettingsWindow()
                settingsController?.show(p)
                return
            }
            // Scenario hooks (scripts/scenario.sh): what a journey needs without a pointer.
            if dict["checkStore"] != nil { logSidebarProblems(); return }
            // releaseFrames: hidden tabs' page windows release Chromium's evicted frames now (#195).
            if dict["releaseFrames"] != nil { for w in mainWindows { w.releaseHiddenFrames(now: composition.clock.now) }; return }
            // A main-thread stall of this many milliseconds, for the performance recorder's tests.
            if let ms = dict["stall"].flatMap(Double.init) { usleep(useconds_t(min(max(ms, 0), 30_000) * 1000)); return }
            if let path = dict["perfReport"] {
                PerfRecorder.shared?.snapshot { report in
                    try? PerfReport.encoder().encode(report).write(to: URL(fileURLWithPath: path), options: .atomic)
                }
                return
            }
            if let js = dict["pageJS"] { main.currentBrowser?.executeJavaScript(js); return }
            if let path = dict["installExtension"] {
                do { try ExtensionStore.shared.add(folder: URL(fileURLWithPath: path, isDirectory: true)) } catch {
                    CraLog.note("scenario: extension not installed: \(error.localizedDescription)")
                }
                return
            }
            // pinExtension=<id>: pinned to the toolbar on the Default profile, as the Extensions menu's pin does.
            if let id = dict["pinExtension"] { ExtensionStore.shared.setPinned(id, true, inProfile: "Default"); return }
            if let id = dict["removeExtension"] {
                if let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) { ExtensionStore.shared.remove(e) }
                return
            }
            if let v = dict["fullscreen"], let w = main.window, (v == "1") != w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); return }
            if let spec = dict["snapshot"], let out = dict["out"] { ViewSnapshot.write(spec, in: main.window, to: out); return }
            // hover=TabRowView,1: that sidebar row hovered as if the pointer were on it (snapshots of
            // hover-only controls, #243) until the pointer moves or the sidebar changes. The URL pill
            // and favorite tiles take it too (#293).
            if let spec = dict["hover"] {
                switch ViewSnapshot.find(spec, in: main.window) {
                case let row as SidebarRowView: row.list?.debugHover(row)
                case let pill as SidebarURLPill: pill.debugHover()
                case let tile as FavoriteTileView: tile.debugHover()
                default: CraLog.note("hover: no visible \(spec)")
                }
                return
            }
            // musicNotes=<label>: report visible note overlays and their offsets from tile centers.
            if let label = dict["musicNotes"] {
                var tiles: [FavoriteTileView] = [], notes: [MusicNotesView] = []
                func collect(_ v: NSView) {
                    if let t = v as? FavoriteTileView { tiles.append(t) }
                    if let n = v as? MusicNotesView, !n.isHiddenOrHasHiddenAncestor { notes.append(n) }
                    v.subviews.forEach(collect)
                }
                main.window?.contentView.map(collect)
                func middle(_ v: NSView) -> NSPoint { v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil) }
                let places = notes.map { n -> String in
                    let at = middle(n)
                    guard let tile = tiles.map(middle).min(by: { hypot($0.x - at.x, $0.y - at.y) < hypot($1.x - at.x, $1.y - at.y) }) else { return "no tile" }
                    return String(format: "%.1f across, %.1f up", at.x - tile.x, at.y - tile.y)
                }
                NSLog("Cra music notes %@: %d%@", label, notes.count, places.isEmpty ? "" : " (" + places.joined(separator: "; ") + ")")
                return
            }
            if let size = dict["windowSize"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2, let w = main.window {
                w.setFrame(NSRect(x: w.frame.minX, y: w.frame.maxY - size[1], width: size[0], height: size[1]), display: true)
                return
            }
            // macOS' appearance as the app sees it (light, dark, or system to undo): Auto space
            // themes switch halves without changing the Mac's own setting (#155).
            if let v = dict["systemAppearance"] {
                NSApp.appearance = v == "system" ? nil : NSAppearance(named: v == "dark" ? .darkAqua : .aqua)
                return
            }
            // externalURL=<url>: a link as another app hands it over (Air Traffic Control, #258);
            // the installed Cra would get one sent with `open`.
            if let url = dict["externalURL"] { openExternalURL(url); return }
            // airTrafficControl=<png path>: the Air Traffic Control sheet with the current routes,
            // drawn off screen (#258), so its popups can be checked without taking the screen.
            if let out = dict["airTrafficControl"] {
                let host = NSHostingView(rootView: AirTrafficControlView().environment(store))
                host.frame = NSRect(x: 0, y: 0, width: 508, height: 440)
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 508, height: 440),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    host.layoutSubtreeIfNeeded()
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                    }
                    CraLog.note("air traffic control drawn to \(out)")
                    window.close()
                }
                return
            }
            // littleShown=<label>: the newest Little Window's "Open in" space and page profile.
            // littleCommit=<typed>: the newest Little Window's command bar commits its "Switch to"
            // row for what was typed, as ↩ on it does (#316).
            if let typed = dict["littleCommit"] { littleWindows.last?.debugCommit(typed); return }
            if let label = dict["littleShown"] {
                var space = "-", profile = "-"
                if let w = littleWindows.last {
                    w.refreshTarget()   // as when it takes focus
                    let state: LittleWindowState = w.state
                    space = store.space(state.targetSpaceID)?.title ?? "-"
                    let named: BrowserProfile? = store.profile(state.profileID)
                    profile = named?.name ?? "Default"
                }
                CraLog.note("little shown \(label): windows=\(littleWindows.count) space=\(space) profile=\(profile)")
                return
            }
            // windowState=<label>: each window's full screen, Space, traffic lights (#277), whether a
            // drag can move it (#308) and where the page card sits in it (#315). Lights are "hidden", or
            // their alpha; "-" when a window has none.
            if let label = dict["windowState"] {
                func lights(_ w: NSWindow) -> String {
                    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { type in
                        guard let b = w.standardWindowButton(type) else { return "-" }
                        return b.isHidden ? "hidden" : String(format: "%.1f", b.alphaValue)
                    }.joined(separator: ",")
                }
                func flag(_ b: Bool) -> Int { b ? 1 : 0 }
                // Where the close button sits in the bar that holds it: its frame and the bar's bounds.
                func lightsPlace(_ w: NSWindow) -> String {
                    guard let b = w.standardWindowButton(.closeButton), let bar = b.superview else { return "-" }
                    let f = b.frame
                    return String(format: "%.0f,%.0f,%.0fx%.0f/%.0fx%.0f/%@", f.minX, f.minY, f.width, f.height,
                                  bar.bounds.width, bar.bounds.height, b.window.map { String(describing: type(of: $0)) } ?? "-")
                }
                for (i, m) in mainWindows.enumerated() {
                    guard let w = m.window else { continue }
                    CraLog.note("window state \(label): main\(i) fullscreen=\(flag(w.styleMask.contains(.fullScreen))) "
                        + "visible=\(flag(w.isVisible)) onSpace=\(flag(w.isOnActiveSpace)) "
                        + "layout=\(flag(m.shell.windowFullscreen)) sidebarUI=\(flag(m.sidebarUI.windowFullscreen)) "
                        + "lightsHidden=\(flag((w as? CraWindow)?.trafficLightsHidden ?? false)) lights=\(lights(w)) "
                        + "movable=\(flag(w.isMovable)) backgroundMovable=\(flag(w.isMovableByWindowBackground)) "
                        + "lightsIn=\(lightsPlace(w)) card=\(m.shell.cardReadout)")
                }
                for (i, l) in littleWindows.enumerated() where !l.isPeek {
                    guard let w = l.window else { continue }
                    CraLog.note("window state \(label): little\(i) fullscreen=\(flag(w.styleMask.contains(.fullScreen))) "
                        + "primary=\(flag(w.collectionBehavior.contains(.fullScreenPrimary))) "
                        + "visible=\(flag(w.isVisible)) onSpace=\(flag(w.isOnActiveSpace)) lights=\(lights(w))")
                }
                return
            }
            // themeShown=<label>: which half each window draws now (the space's theme, the window content
            // and the sidebar), without redrawing first, so a missed macOS switch shows (#155).
            if let label = dict["themeShown"] {
                func sidebar(in v: NSView) -> SidebarView? {
                    v as? SidebarView ?? v.subviews.lazy.compactMap { sidebar(in: $0) }.first
                }
                func side(_ dark: Bool) -> String { dark ? "dark" : "light" }
                for m in mainWindows {
                    let space = m.focusedSpace
                    let drawn = m.window?.contentView.flatMap(sidebar(in:)).map { side($0.palette.isDark) } ?? "-"
                    NSLog("Cra theme shown %@: space=%@ follows=%d theme=%@ shell=%@ sidebar=%@", label, space.title, space.theme.followsSystem ? 1 : 0,
                          side(space.theme.shown.isDark), side(m.shell.isDarkTheme), drawn)
                }
                return
            }
            // commandBarRows=<label>: the open command bar's rows, top to bottom, each as kind:address
            // (the title when it has none), so a scenario reads which tabs ⌘T found (#307).
            if let label = dict["commandBarRows"] {
                let bar = main.commandBar
                let rows = bar.result.items.map { row -> String in
                    let kind: String
                    switch row.kind {
                    case .switchToTab: kind = "tab"
                    case .archived: kind = "archived"
                    case .history: kind = "history"
                    default: kind = "other"
                    }
                    return "\(kind):\(row.url ?? row.title)"
                }
                NSLog("Cra command bar rows %@: open=%d %@", label, bar.isOpen ? 1 : 0, rows.joined(separator: " | "))
                return
            }
            // sidebarShown=<label>: whether the main window shows its sidebar, and the View menu's
            // Hide/Show Sidebar row as the menu bar has it: title and the key it answers to, which
            // is the user's own when System Settings ▸ Keyboard ▸ App Shortcuts names the row (#253).
            if let label = dict["sidebarShown"] {
                func row(in menu: NSMenu) -> NSMenuItem? {
                    for i in menu.items {
                        if i.representedObject as? String == "toggleSidebar" { return i }
                        if let sub = i.submenu, let found = row(in: sub) { return found }
                    }
                    return nil
                }
                let item = NSApp.mainMenu.flatMap(row(in:))
                let mods = item.map { m in
                    [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                        .filter { m.keyEquivalentModifierMask.contains($0.0) }.map(\.1).joined()
                } ?? ""
                CraLog.note("sidebar shown \(label): visible=\(main.sidebarVisible ? 1 : 0) menu=\(item?.title ?? "-") key=\(mods)\(item?.keyEquivalent ?? "-")")
                return
            }
            // menuRows=<menu>[&label=<label>]: a menu bar menu's rows as it draws them once validated
            // (hidden rows left out), "|" between rows and "──" for a separator: Arc's File menu (#279).
            if let title = dict["menuRows"] {
                let menu = NSApp.mainMenu?.items.first { $0.title == title }?.submenu
                menu?.update()
                let rows = menu?.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "──" : $0.title } ?? []
                CraLog.note("menu rows \(dict["label"] ?? title): \(rows.joined(separator: "|"))")
                return
            }
            // activations=<label>: whether Cra is the active app, and how many requests to bring it to
            // the front went through while it was in the background (#274).
            if let label = dict["activations"] {
                CraLog.note("activations \(label): active=\(NSApp.isActive ? 1 : 0) background=\(CraApplication.backgroundActivations)")
                return
            }
            // pip=<label>: Chromium's Picture in Picture window as Cra keeps it; pipKey=space|force asks
            // it to become key the ways Chromium can leave it open to that (#262).
            if let label = dict["pip"] { NSLog("Cra pip %@: %@", label, PictureInPictureChrome.shared.readout()); return }
            if let how = dict["pipKey"] { PictureInPictureChrome.shared.debugTakeKey(how); return }
            // peekShown=<label>: the page behind a Peek in each window, faded and drawn back or whole (PR #221).
            if let label = dict["peekShown"] {
                for m in mainWindows { NSLog("Cra peek shown %@: %@", label, m.peekBackdropShown()) }
                return
            }
            // peeks=<label>: each window's Peeks, on screen or waiting on their tab, and their pages (#242).
            if let label = dict["peeks"] {
                for m in mainWindows { NSLog("Cra peeks %@: %@", label, m.peeksShown()) }
                return
            }
            // back=<label>: the front tab's page, whether Back is on for it, and the space's Today tab
            // count; a link's tab closes to the tab it came from on Back (#273).
            // split=<label>: the selected tab's split, its panes' pages in order, and how many
            // downloads there are (an Option-clicked link opens a pane, not a download, #298).
            if let label = dict["split"] {
                let selected = main.selectedTab
                let panes = selected.map { store.paneTabIDs(for: $0.id) } ?? []
                let urls = panes.count > 1 ? panes.compactMap { store.item($0)?.tab?.url }.joined(separator: " | ") : "none"
                CraLog.note("split \(label): panes=\(urls) selected=\(selected?.tab?.url ?? "-") downloads=\(DownloadHistory.shared.live.count + DownloadHistory.shared.entries.count)")
                return
            }
            if let label = dict["back"] {
                let today = store.tabs(under: store.focusedSpace(window: main.windowID).todayContainerID).count
                CraLog.note("back \(label): selected=\(main.selectedTab?.tab?.url ?? "-") back=\(main.sidebarUI.canGoBack ? 1 : 0) today=\(today)")
                return
            }
            // scroll=<label>: how far the front page is scrolled, in cra.log, which a relaunched Cra
            // still writes (its stdout isn't the scenario's): a restored history keeps it (#273).
            if let label = dict["scroll"] {
                main.currentBrowser?.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"Math.round(scrollY)","returnByValue":true}"#) { result, error in
                    let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                        .flatMap { ($0["result"] as? [String: Any])?["value"] }
                    CraLog.note("scroll \(label): \(value.map { "\($0)" } ?? error ?? "-")")
                }
                return
            }
            // peekCatcher=<label>: whether the shown Peek's click catcher leaves the sidebar alone (#242).
            if let label = dict["peekCatcher"] {
                for m in mainWindows { NSLog("Cra peek catcher %@: %@", label, m.peekCatcherReadout()) }
                return
            }
            if dict["relaunch"] != nil { relaunch(); return }
            // quit=1 quits for real, as the menu bar item's Quit; quit=menu is ⌘Q (#231).
            if let q = dict["quit"] { q == "menu" ? NSApp.terminate(nil) : quitFromMenuBar(); return }
            if let t = dict["selectTab"].flatMap(UUID.init(uuidString:)) { store.selectTab(t, window: main.windowID); return }
            // Tab freezing with a short threshold (seconds) from now on, so it can be tried without
            // waiting: the minute's pass would otherwise take the votes back.
            if let s = dict["freezeTabs"].flatMap(Double.init) {
                freezeAfter = s
                for w in mainWindows { w.browsers.freezeIdleTabs(hiddenLongerThan: s) }
                return
            }
            // One tab-sleeping pass with a short threshold (seconds), so it can be tried without waiting
            // or opening 11 tabs: the 10 tabs used last aren't kept.
            if let s = dict["sleepTabs"].flatMap(Double.init) {
                for w in mainWindows { w.browsers.sleepIdleTabs(TabSleepPolicy(hiddenFor: s, keepsRecentTabs: false)) }
                return
            }
            // What waking the Mac does (#275), without sleeping it: the cards re-read, one pass.
            if dict["sleep"] != nil { systemWillSleep(); return }
            if dict["wake"] != nil { systemDidWake(); return }
            // One memory-pressure sweep as if macOS reported this level (warning, critical), without
            // filling memory or waiting out the last sweep. The setting still decides.
            if let level = dict["memoryPressure"].flatMap(PerfSystemSample.Pressure.init(rawValue:)) {
                lastPressureSweep = nil
                sweepForMemoryPressure(level)
                return
            }
            // Opens what normally needs a pointer or a held key, for screenshots.
            if let v = dict["downloads"] { main.sidebarUI.downloadsListOpen = v == "1"; return }
            // What a running download's menu does (pause, resume, cancel), to the newest one in
            // progress; `downloadState` logs how the rows read (#272).
            if let v = dict["download"] {
                let actions: [String: CraDownloadControl] = ["pause": .pause, "resume": .resume, "cancel": .cancel]
                if let action = actions[v], let l = DownloadHistory.shared.live.last(where: \.running) {
                    DownloadHistory.shared.control(l.id, action)
                }
                return
            }
            if let label = dict["downloadState"] {
                let rows = DownloadHistory.shared.live.map { DownloadRow.subtitle($0.row, now: Date()) }
                let progress = DownloadHistory.shared.progress.map { String(format: "%.3f", $0) } ?? "none"
                CraLog.note("download state \(label): running=\(DownloadHistory.shared.hasRunningDownloads) progress=\(progress) rows=\(rows)")
                return
            }
            // The sidebar as if Cra were in front (1) or behind (0), until the app's next activation change:
            // a background test copy is in either state depending on what it was sent.
            if let v = dict["appActive"] { main.sidebarUI.appActive = v == "1"; return }
            // Settings ▸ Privacy sharing now, not in 30 s or tomorrow (only with CRA_SHARING_ENDPOINT
            // in a test copy): stats sends the usage report, crash looks for new crash reports,
            // off unticks onboarding's "Help improve Cra" row.
            if let v = dict["sharing"] {
                if v == "stats" { SharingService.shared.sendStatsIfDue(force: true) }
                if v == "crash" { SharingService.shared.checkCrashReports() }
                if v == "off" { store.settings.setSharesToImproveCra(false) }
                return
            }
            if let v = dict["banner"] { SoftwareUpdater.shared.debugUpdated(v == "none" ? nil : v); return }
            if let v = dict["bannerReady"] { SoftwareUpdater.shared.debugReady(v == "none" ? nil : v); return }
            if dict["switcher"] != nil { main.debugTabSwitcher(); return }
            // The Site Control Center's Safari's Engine switch for the focused page, without the pointer.
            if let v = dict["safariEngine"] { main.debugChooseSafariEngine(v == "on"); return }
            // Script in Cra's isolated world of the focused page: "Cra isolatedJS → <result>" on stdout.
            if let js = dict["isolatedJS"] {
                let params = String(decoding: (try? JSONSerialization.data(withJSONObject: ["expression": js, "returnByValue": true])) ?? Data(), as: UTF8.self)
                main.currentBrowser?.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, error in
                    NSLog("Cra isolatedJS → %@", result ?? "error: \(error ?? "?")")
                }
                return
            }
            // The sidebar player without the pointer: play/pause/next/previous/pip on the newest
            // card ("state" only logs), then its cards: "Cra nowPlaying[<label>] <host> playing=… prev=… next=… video=… pip=…".
            if let op = dict["nowPlaying"], let np = main.browsers.nowPlaying {
                let label = dict["label"].map { "[\($0)]" } ?? ""
                let actions: [String: NowPlaying.Action] = ["toggle": .togglePlayback, "next": .next, "previous": .previous,
                                                           "pip": .pictureInPicture, "dismiss": .dismiss]
                if let action = actions[op], let id = np.entries.last?.id { main.browsers.performNowPlaying(id, action) }
                for e in np.entries {
                    let host = CraLog.host(main.browsers.runtime(for: e.id)?.browser.currentURL ?? "")
                    NSLog("Cra nowPlaying%@ %@ playing=%d prev=%d next=%d video=%d pip=%d", label, host, e.playing ? 1 : 0, e.hasPrevious ? 1 : 0,
                          e.hasNext ? 1 : 0, e.hasVideo ? 1 : 0, np.pictureInPicture.contains(e.id) ? 1 : 0)
                }
                if np.entries.isEmpty { NSLog("Cra nowPlaying%@ none", label) }
                return
            }
            if dict["themeEditor"] != nil { main.showSpaceStyleEditor(space: store.focusedSpace); return }
            if dict["jumpPill"] != nil { SpaceListView.jumpToSelected(for: main.sidebarUI, space: store.focusedSpaceID); return }
            if let f = dict["folderPreview"] {
                if let id = UUID(uuidString: f) { SpaceListView.debugFolderPreview(id, ui: main.sidebarUI) } else { FolderPreviewController.shared.close() }
                return
            }
            if let t = dict["expandFolder"] {
                for item in store.items.values where item.isFolder && item.title == t { store.setExpanded(item.id, true) }
                return
            }
            if dict["littlePopup"] != nil { littleWindows.first?.togglePopup(); return }
            if let c = dict["combine"], let content = main.window?.contentView {
                let tabs = store.children(of: store.focusedSpace.todayContainerID).filter { $0.tab != nil }
                guard tabs.count > 1 else { return }
                let kind = CombineDropPreview.Kind.split(leading: c == "leading")
                let pal = store.focusedSpace.theme.palette
                let v = CombineDropPreview(kind: kind, target: tabs[0], dragged: tabs[1], depth: 0, palette: pal, favicons: favicons)
                v.frame = NSRect(x: 10, y: content.bounds.height - 420, width: 300, height: CraMetrics.rowHeight)
                content.addSubview(v)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { v.removeFromSuperview() }
                return
            }
            if dict["siteControls"] != nil { main.debugSiteControls(); return }
            if let label = dict["captureShown"] { main.debugCapture(label); return }
            // The sidebar's URL field (toolbar hidden): hovered, and a press on one of its buttons (#226).
            if let v = dict["urlFieldHover"] { main.debugURLFieldHover(v == "1"); return }
            if let name = dict["urlFieldPress"] { main.debugURLFieldPress(name); return }
            if dict["commandBarBadge"] != nil { main.debugCommandBarBadgePress(); return }
            // Arc's translate UI (#310): what shows, and a press on its parts.
            if let step = dict["translate"] { main.debugTranslate(step); return }
            // The n-th space icon's tip, without a pointer.
            if let n = dict["spaceTip"].flatMap({ Int($0) }), let content = main.window?.contentView {
                ArcTooltipController.shared.debugShowSpaceTip(n, in: content)
                return
            }
            if let t = dict["tooltip"], let content = main.window?.contentView {
                ArcTooltipController.shared.debugShow(t, in: content, at: NSRect(x: 380, y: content.bounds.height - 120, width: 28, height: 28))
                return
            }
            if let g = dict["swipe"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                main.debugSpaceSwipe(dx: g[0], steps: Int(g[1]))
                return
            }
            if let id = dict["extensionAction"] { main.runExtensionAction(id); return }
            // What the side panel's close button does (scripts/scenario.sh).
            if dict["sidePanel"] == "close" { main.sidePanel.hide(); return }
            // An expression's value in the side panel's page, to cra.log (a relaunched Cra's stdout isn't kept).
            if let js = dict["sidePanelJS"] { main.sidePanel.debugEvaluate(js); return }
            if let path = dict["exportDiagnostics"] {
                Diagnostics.export(windows: mainWindows, store: store, to: URL(fileURLWithPath: path))
                return
            }
            if let f = dict["floatingSidebar"] { if f == "1" { main.floatingSidebar?.show() } else { main.floatingSidebar?.hide(animated: true) }; return }
            if let method = dict["bcdp"] {
                // To cra.log: a scenario reads it after a relaunch too, when stdout isn't kept (#299).
                CraCEFRuntime.sendBrowserDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    CraLog.note("bcdp \(method) → \(result ?? "error: \(error ?? "?")")")
                }
                return
            }
            if let method = dict["cdp"] {
                // target=little: the newest Little Window's (or Peek's) page; tab=<id>: that tab's page.
                let tab = dict["tab"].flatMap(UUID.init(uuidString:)).flatMap { main.browsers.runtime(for: $0)?.browser }
                let b = dict["target"] == "little" ? littleWindows.last?.browser : tab ?? main.currentBrowser
                b?.sendDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    NSLog("Cra cdp %@ → %@", method, result ?? "error: \(error ?? "?")")
                }
                return
            }
            // What the command bar would list for the text (rows, the Tab scope, the search), without opening it.
            if let text = dict["suggest"] {
                let engine = main.commandBar.engine
                engine.resetIndex()
                let r = engine.suggestions(for: text, mode: .newTab, currentTabID: store.selectedTabID)
                let rows = r.items.map { "\($0.kind) \($0.title) \($0.url ?? "")" }.joined(separator: " | ")
                NSLog("Cra suggest %@ → scope=%@ search=%@ rows=%@", text, r.scope.map { "\($0.name) \($0)" } ?? "none",
                      engine.searchURL(text), rows)
                engine.resetIndex()
                return
            }
            // folder=<id>,1 opens a folder, ,0 closes it (its glyph turns as a click's does).
            if let f = dict["folder"]?.split(separator: ","), f.count == 2, let id = UUID(uuidString: String(f[0])) {
                store.setExpanded(id, f[1] == "1")
                return
            }
            // collapsePinned=1 collapses the focused space's pinned tabs, 0 expands them (a header click).
            if let v = dict["collapsePinned"] {
                let sid = store.focusedSpaceID
                if store.isPinnedCollapsed(sid) != (v == "1") { store.togglePinnedCollapsed(sid) }
                return
            }
            // Settings ▸ Advanced's search engine picker, by keyword.
            if let keyword = dict["searchEngine"] {
                if let e = SearchEngines.shared.keywords(profilePath: nil).first(where: { $0.keyword == keyword }) {
                    SearchEngines.shared.setDefault(e, store: store)
                }
                return
            }
            // The focused space's own engine by keyword, as its Search Engine menu sets it (#306); empty is Default.
            if let keyword = dict["spaceSearchEngine"] {
                store.setSearchEngine(keyword, forSpace: store.focusedSpaceID)
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
            // browserWindows=<label>: each browser window's kind, space, tabs (URLs), open tab and frame (#219, #220).
            if let label = dict["browserWindows"] {
                CraLog.note("browser windows \(label): count=\(mainWindows.filter { $0.window?.isVisible == true }.count)")
                for m in mainWindows {
                    let space = m.focusedSpace
                    let tabs = (store.tabs(under: space.pinnedContainerID) + store.tabs(under: space.todayContainerID)).compactMap { $0.tab?.url }
                    let open = store.selectedTabID(window: m.windowID).flatMap { store.item($0)?.tab?.url } ?? "-"
                    let folders = (store.children(of: space.pinnedContainerID) + store.children(of: space.todayContainerID)).filter { $0.isFolder && !$0.isTabGroup }
                    NSLog("Cra browser windows %@: kind=%@ space=%@ listed=%d tabs=[%@] open=%@ page=%d frame=%@ onTop=%d pinnedCollapsed=%d openFolders=%d/%d commandBar=%d pages=%d", label,
                          m.isBlank ? "blank" : m.isIncognito ? "incognito" : "normal", space.title,
                          store.orderedSpaces.contains { $0.id == space.id } ? 1 : 0, tabs.joined(separator: " "), open,
                          store.selectedTabID(window: m.windowID).flatMap { m.browsers.runtime(for: $0) } != nil ? 1 : 0,
                          m.window.map { NSStringFromRect($0.frame) } ?? "-", m.staysOnTop ? 1 : 0,
                          store.isPinnedCollapsed(space.id) ? 1 : 0, folders.filter { store.isExpanded($0.id) }.count, folders.count,
                          m.commandBar.isOpen ? 1 : 0, m.browsers.runtimes.count)
                    // cra.log (which a relaunch keeps) gets no addresses or names: kinds and counts.
                    CraLog.note("browser windows \(label): kind=\(m.isBlank ? "blank" : m.isIncognito ? "incognito" : "normal") "
                        + "listed=\(store.orderedSpaces.contains { $0.id == space.id } ? 1 : 0) tabs=\(tabs.count) open=\(open == "-" ? 0 : 1) "
                        + "commandBar=\(m.commandBar.isOpen ? 1 : 0) pages=\(m.browsers.runtimes.count)")
                }
                return
            }
            // blankMoveTo=<n>: a Blank Window's "Move to…" picking the nth space, as its menu does (#220).
            if let n = dict["blankMoveTo"].flatMap(Int.init) {
                guard main.isBlank, store.spaceOrder.indices.contains(n - 1) else { CraLog.note("blankMoveTo: no Blank Window or space \(n)"); return }
                moveBlankWindow(main, toSpace: store.spaceOrder[n - 1])
                return
            }
            // dragEnd=<text>&at=x,y: the window's tab whose URL holds the text dragged and let go there
            // (from the screen's top left) with nothing taking it, as a drag out of the sidebar ends
            // (#219). Without at: a point of the screen no Cra window covers, a corner if one is free,
            // else anywhere along the screen's edges (a 1000×700 window covers every corner of the
            // CI runners' 1024×768 screen).
            if let text = dict["dragEnd"], let screen = main.window?.screen ?? NSScreen.main {
                let space = main.focusedSpace
                let tab = (store.tabs(under: space.pinnedContainerID) + store.tabs(under: space.todayContainerID))
                    .first { $0.tab?.url.contains(text) == true }
                guard let tab else { CraLog.note("dragEnd: no tab with \(text)"); return }
                var point: NSPoint?
                if let g = dict["at"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                    point = NSPoint(x: screen.frame.minX + g[0], y: screen.frame.maxY - g[1])
                } else {
                    let v = screen.visibleFrame.insetBy(dx: 40, dy: 40)
                    let corners = [NSPoint(x: v.maxX, y: v.minY), NSPoint(x: v.minX, y: v.minY), NSPoint(x: v.maxX, y: v.maxY), NSPoint(x: v.minX, y: v.maxY)]
                    let e = screen.visibleFrame.insetBy(dx: 4, dy: 4)
                    let edges = stride(from: 0.0, through: 1.0, by: 0.02).flatMap { t -> [NSPoint] in
                        let x = e.minX + t * e.width, y = e.minY + t * e.height
                        return [NSPoint(x: x, y: e.minY), NSPoint(x: e.maxX, y: y), NSPoint(x: e.minX, y: y), NSPoint(x: x, y: e.maxY)]
                    }
                    point = (corners + edges).first { !SpaceListView.isOverAppWindow($0) }
                }
                guard let point else { CraLog.note("dragEnd: no point outside Cra's windows on screen \(NSStringFromRect(screen.visibleFrame))"); return }
                CraLog.note("dragEnd: let go at \(NSStringFromPoint(point))")
                main.testDragEnded(tab.id, at: point)
                return
            }
            if dict["windows"] != nil {
                for w in NSApp.windows {
                    let line = "Cra windows: \(w.windowController.map { String(describing: type(of: $0)) } ?? "-") '\(w.title)' frame=\(NSStringFromRect(w.frame)) parent=\(w.parent.map { NSStringFromRect($0.frame) } ?? "-") visible=\(w.isVisible) key=\(w.isKeyWindow) mask=\(w.styleMask.rawValue) class=\(NSStringFromClass(type(of: w))) children=\(w.childWindows?.count ?? 0) contentView=\(w.contentView.map { NSStringFromClass(type(of: $0)) } ?? "-")"
                    NSLog("%@", line)
                }
                NSLog("Cra windows: liveBrowsers=%ld", CraCEFRuntime.liveBrowserCount())
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

    /// Edit → Paste and Match Style (⇧⌘V) sends AppKit's `pasteAsPlainText:`, which text fields and
    /// WebKit tabs answer themselves. A Chromium page names the same command `pasteAndMatchStyle:`,
    /// so here, at the end of the responder chain, the menu item reaches it (GitHub #192).
    private static let chromiumPasteAndMatchStyle = NSSelectorFromString("pasteAndMatchStyle:")
    private var pageTakingPasteAndMatchStyle: NSResponder? {
        guard let responder = NSApp.keyWindow?.firstResponder, responder.responds(to: Self.chromiumPasteAndMatchStyle) else { return nil }
        return responder
    }

    @objc func pasteAsPlainText(_ sender: Any?) {
        guard let page = pageTakingPasteAndMatchStyle else { return }
        NSApp.sendAction(Self.chromiumPasteAndMatchStyle, to: page, from: sender)
    }

    /// The title of a menu row that says what it will do, as Arc's do: Hide Sidebar or Show Sidebar.
    private func flippingTitle(_ id: String) -> String? {
        guard let main = self.main else { return nil }
        switch id {
        case "toggleSidebar": return main.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
        case "toggleToolbar": return store.settings.showToolbar ? "Hide Toolbar" : "Show Toolbar"
        case "collapsePinned": return store.isPinnedCollapsed(main.focusedSpaceID) ? "Expand Pinned Tabs" : "Collapse Pinned Tabs"
        default: return nil
        }
    }
    private static let flippingRows = ["toggleSidebar", "toggleToolbar", "collapsePinned"]

    /// System Settings ▸ Keyboard ▸ App Shortcuts names a menu row by its title, and AppKit looks a
    /// key up among the titles the menu bar has at that moment, before it validates the row. So a
    /// flipping row takes its new title when what it shows changes, not when the menu next opens:
    /// after ⌘S hid the sidebar, a shortcut given to Show Sidebar found only "Hide Sidebar" (#253).
    private func observeFlippingRows() {
        observeChanges(of: { [weak self] in self.map { s in Self.flippingRows.compactMap(s.flippingTitle) } ?? [] }) { [weak self] _ in
            self?.retitleFlippingRows()
        }
    }

    /// Also when another window comes in front (its sidebar may be hidden) and after the menus are rebuilt.
    private func retitleFlippingRows() {
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let id = item.representedObject as? String, let title = flippingTitle(id), item.title != title { item.title = title }
                if let sub = item.submenu { walk(sub) }
            }
        }
        NSApp.mainMenu.map(walk)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(pasteAsPlainText(_:)) { return pageTakingPasteAndMatchStyle != nil }
        if let id = item.representedObject as? String, let title = flippingTitle(id), item.title != title { item.title = title }
        switch item.representedObject as? String {
        case "collapsePinned": return !main.isStandalone
        case "stayOnTop": item.state = main.staysOnTop ? .on : .off
        case "allowAppleEventsJavaScript": item.state = store.settings.allowAppleEventsJavaScript ? .on : .off
        case "appearanceAutomatic", "appearanceLight", "appearanceDark":
            item.state = "appearance" + store.settings.websiteAppearance.title == item.representedObject as? String ? .on : .off
        case "copyURLQuote", "savePageAs", "captureFullPage", "capturePortrait", "revealTab", "share": return store.selectedTabID != nil
        case "closeTab":
            // Arc shows Close Tab only while a tab is selected; ⌘W still closes the window (#279).
            item.isHidden = !FileMenu.shows("closeTab", tabSelected: store.selectedTabID != nil)
        case "newProfile": return !main.isIncognito
        case "clearArchive": return !store.archive.isEmpty
        case "resetSpaceTabs": return !main.isStandalone
        case "toggleDeveloperMode":
            let on = store.selectedTab?.tab.map { store.settings.isDeveloperMode(url: $0.url) } ?? false
            item.title = on ? "Turn off Developer Mode for this Site" : "Turn on Developer Mode for this Site"
        case "pinTab":
            item.title = store.selectedTabID.map { store.isPinned($0) ? "Unpin Tab" : "Pin Tab" } ?? "Pin/Unpin Tab"
            return !main.isBlank  // a Blank Window has no pinned section (Arc)
        case "setDefaultBrowser":
            SystemIntegration.shared.refresh()
            return !SystemIntegration.shared.isDefaultBrowser
        case "pictureInPicture":
            item.title = main.currentBrowser?.isInPictureInPicture == true ? "Exit Picture in Picture" : "Picture in Picture"
        case "promoteLittleWindow", "littleWindowOpenInMenu": return keyLittleWindow?.hasPage ?? false
        case "checkForUpdates": return SoftwareUpdater.shared.validateMenuItem(item)
        case "closeSplitPane", "separateFromSplit", "flipSplitOrientation":
            return store.selectedTabID.flatMap { store.splitContaining($0) } != nil
        case "addSplitView": return store.selectedTabID != nil
        case "editSpace", "deleteSpace", "nextSpace", "previousSpace", "manageSpaces", "changeProfile": return !main.isStandalone
        // A Blank Window has no favorites or pinned section to put a tab in (Arc).
        case "favoriteTab", "newFolder", "resetTab": return !main.isBlank
        case let id? where LiveFolderPluginStore.shared.entry(forCommand: id) != nil: return !main.isStandalone
        case "joinNextMeeting": return LiveCalendarClient.shared.nextCall()?.meetingURL != nil
        case "closeLittleWindows": return !littleWindows.isEmpty
        case let id? where id.hasPrefix("moveTabToSpace"):
            guard let n = Int(id.dropFirst(14)), n >= 1, n <= store.spaceOrder.count else { return false }
            if let little = keyLittleWindow { return little.hasPage }
            return store.selectedTabID != nil && !main.isIncognito
        default: break
        }
        return true
    }

    /// Testing aid: with CRA_COMMAND_FILE set, every line appended to that file
    /// is handled like a cra:// URL (a second instance run with CRA_DATA_DIR
    /// cannot receive cra:// URLs, which LaunchServices routes to the installed app).
    private var commandFileOffset: UInt64 = 0
    private var commandFilePoll: ScheduledWork?
    private func installCommandFileWatcher() {
        guard let path = ProcessInfo.processInfo.environment["CRA_COMMAND_FILE"], !path.isEmpty else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        commandFileOffset = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        // A script writes only after this line: the file above starts empty.
        CraLog.note("pid \(getpid()) reads commands from CRA_COMMAND_FILE")
        commandFilePoll = composition.clock.every(0.15) { [weak self] in
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

    /// Menu key equivalents match characters, so ⌃⇧= and friends fail on
    /// layouts where "=" lives on another key (Danish: ⇧0). When the key
    /// window is one of ours (sidebar focused, no page), fall back to the
    /// physical-key matching in `Shortcut` for ⌘/⌃ shortcuts the menus missed.
    private var keyFallbackMonitor: Any?
    /// ⌥← / ⌥→ from a mouse whose driver types them (Logi Options+, issue #233).
    private var sideButtonKeyMonitor: Any?
    private func installKeyFallbackMonitor() {
        guard keyFallbackMonitor == nil else { return }
        keyFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc drops a ⌘/⇧-click tab selection before anything else sees it.
            if event.keyCode == 53, !(event.window is DialogPanel), let ui = self?.main.sidebarUI, !ui.multiSelection.isEmpty {
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

    /// ⌥← and ⌥→, the keystrokes Logi Options+ types for an MX Master's back and forward
    /// buttons (issue #233). A key goes to the focused page, not the view under the pointer,
    /// so the sidebar check is the pointer's. Over the sidebar that is the previous or next
    /// space; over a page it is history back and forward. A text field always keeps the key
    /// (⌥← moves by word, held or not). Other repeats are swallowed: holding the button must
    /// not walk every space.
    private func installSideButtonKeyMonitor() {
        guard sideButtonKeyMonitor == nil else { return }
        sideButtonKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let key = Shortcut.press(event)?.key ?? ""
            guard let offset = MouseButtonSpaceSwitch.offset(key: key, keyCode: event.keyCode,
                                                              modifiers: event.modifierFlags.rawValue) else { return event }
            let which = offset < 0 ? "back" : "forward"
            let editing = self.textFieldHasKey(event)
            let overSidebar = self.mainWindows.contains { $0.pointerOverSidebar() }
            guard let action = MouseButtonSpaceSwitch.action(offset: offset, pointerOverSidebar: overSidebar,
                                                              editingText: editing, isRepeat: event.isARepeat) else {
                if !event.isARepeat { CraLog.note("mouse key \(which): left for text") }
                return event
            }
            switch action {
            case .swallow:
                return nil
            case .switchSpace(let step):
                if let window = self.mainWindows.first(where: { $0.pointerOverSidebar() }) {
                    self.store.focusSpace(offset: step, window: window.windowID)
                }
                CraLog.note("mouse key \(which): switched space")
            case .history(let step):
                guard let browser = self.keyLittleWindow?.browser ?? self.keyMainWindow()?.currentBrowser else { return event }
                if step < 0 { browser.goBack() } else { browser.goForward() }
                CraLog.note("mouse key \(which): history")
            }
            return nil
        }
    }

    /// The main window that owns the key window (itself, or its page's child window).
    private func keyMainWindow() -> MainWindowController? {
        var w = NSApp.keyWindow
        while let window = w {
            if let m = mainWindows.first(where: { $0.window === window }) { return m }
            w = window.parent
        }
        return nil
    }

    /// A text field, or a page input, has the key: ⌥← moves by word there, and ⌘Z undoes text
    /// rather than the last closed tab. Chromium's page view reports its ui::TextInputType (0 = none).
    private func textFieldHasKey(_ event: NSEvent) -> Bool {
        let responder = (event.window ?? NSApp.keyWindow)?.firstResponder
        if responder is NSText { return true }
        if let view = responder as? NSView, NSStringFromClass(type(of: view)) == "RenderWidgetHostViewCocoa",
           view.responds(to: NSSelectorFromString("textInputType")),
           (view.value(forKey: "textInputType") as? Int ?? 0) != 0 { return true }
        return false
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
        // Chromium hands a ⌘-key the page left alone back to the menu bar through its own
        // window's command dispatcher (⌘C, ⌘V, ⌘A, ⌘Z exist only as Edit menu items). An
        // embedded page sits in Cra's window, which has none, so it goes to the menu bar here,
        // first: the menu runs the keys it shows, which AppKit fits to the keyboard layout
        // (Turkish Q: Zoom In ⌘., Stop ⌘ç, Back ⌘ğ), the way the sidebar's keys go (GitHub #212).
        if event.modifierFlags.contains(.command), let key = NSApp.keyWindow,
           !key.responds(to: NSSelectorFromString("commandDispatcher")),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        if let action = bindings.action(for: event) {
            perform(action.id)
            return true
        }
        return false
    }

    /// Arc: ⌘Z brings back the tab you closed last (closing registers an undo, GitHub #21), or undoes
    /// the last Tidy, unless the keyboard is in something with text to undo: a text field, or an editable
    /// element in a page (Chromium's page view reports its ui::TextInputType, 0 = none).
    private func undoClosedTab(_ event: NSEvent) -> Bool {
        guard Shortcut("z", .command).matches(event), !textFieldHasKey(event) else { return false }
        // The last thing to undo may be a tidy (Arc's "Undo Tidy Tabs"); a tab closed since comes first.
        if !store.undoTidy() { perform("reopenClosedTab") }
        return true
    }

    func perform(_ id: String) {
        if let dialog = NSApp.keyWindow as? DialogPanel, ["closeTab", "closeWindow"].contains(id) {
            dialog.close()
            return
        }
        store.recordCommandUse(id)
        // An extension's own window (Arc: BrowserExtensionWindowController.closeCurrentItem:)
        // closes on ⌘W instead of the tab behind it.
        if ["closeTab", "closeWindow"].contains(id), let key = NSApp.keyWindow, CraCEFRuntime.isExtensionWindow(key) {
            key.performClose(nil)
            return
        }
        // A key Little Window takes the page/window actions first (⌘W, ⌘L, ⌘R…).
        if let little = keyLittleWindow, little.handle(action: id) { return }
        if let entry = LiveFolderPluginStore.shared.entry(forCommand: id) {
            guard !main.isStandalone else { return }
            SidebarMenus.addPluginFolder(entry, space: store.focusedSpace.id, store: store, window: main.window)
            return
        }
        let current = store.selectedTabID
        switch id {
        case "newLittleWindow": openLittleWindow(url: "")
        case "closeLittleWindows": closeLittleWindows()
        case "promoteLittleWindow", "littleWindowOpenInMenu": break  // only meaningful while a little window is key
        case "newTab": main.openCommandBar(.newTab)
        case "newWindow": openNewWindow()
        case "newIncognitoWindow": openNewWindow(incognito: true)
        case "newBlankWindow": openNewWindow(blank: true)
        case "editURL": main.openCommandBar(.editURL)
        case "newFolder":
            guard !main.isBlank else { break }
            let f = store.createFolder(named: "New Folder", in: store.focusedSpace.pinnedContainerID, index: 0)
            main.sidebarUI.renamingID = f.id
        case "newSpace": main.showSpaceEditor(space: nil)
        case "newProfile": if !main.isIncognito, let w = main.window { main.showNewProfileDialog(over: w) }
        case "share": main.shareSelectedPage()
        case "newBoost": main.openBoostEditor()
        case "newEasel":
            guard !main.isIncognito else { break }
            let easel = Easel()
            _ = store.createTab(url: easel.url, title: easel.title, select: true, window: main.windowID)
        case "editSpace": if !main.isStandalone { main.showSpaceEditor(space: store.focusedSpace) }
        case "changeProfile": if !main.isStandalone { main.showChangeProfileDialog(forSpace: store.focusedSpace.id) }
        case "deleteSpace": if !main.isStandalone { confirmDeleteSpace(store.focusedSpace) }
        case "manageSpaces": if !main.isStandalone { main.showManageSpaces() }
        case "closeTab":
            // Arc: "Close current tab or window".
            if current != nil { main.closeCurrentTab() } else { main.window?.performClose(nil) }
        case "closeWindow": main.window?.performClose(nil)
        case "reopenClosedTab":
            guard !main.isIncognito else { break }  // incognito tabs leave nothing to restore
            // Arc: a Peek closed after the last archived tab comes back, over the tab it came from.
            if let peek = main.closedPeek, peek.at > store.archive.first?.archivedAt ?? .distantPast {
                main.closedPeek = nil
                if let id = peek.tabID, store.item(id) != nil { store.selectTab(id, window: main.windowID) }
                openPeek(url: peek.url, over: main, fromTab: peek.tabID)
            } else {
                store.reopenLastArchived()
            }
        case "copyURL":
            // Arc: "Copy the current tab's URL without trackers".
            if let url = current.flatMap({ store.item($0)?.tab?.url }).map(CleanURL.withoutTrackers) {
                copy(url)
                main.showToast("Copied Current URL", action: .share(url))
            }
        case "copyURLMarkdown":
            if let c = current, let it = store.item(c), let url = it.tab?.url {
                copy("[\(it.displayTitle)](\(CleanURL.withoutTrackers(url)))")
                main.showToast("Copied URL as Markdown")
            }
        case "copyURLQuote": main.copyURLAsQuote()
        case "savePageAs": main.savePageAs()
        case "captureFullPage": main.captureFullPage()
        case "capturePortrait": main.capturePortrait()
        case "collapsePinned": if !main.isStandalone { store.togglePinnedCollapsed(main.focusedSpaceID) }
        case "revealTab": main.revealSelectedTab()
        case "resetSpaceTabs": main.resetAllPinnedTabs()
        case "collapseAllFolders": store.setAllFoldersExpanded(false, inSpace: main.focusedSpaceID)
        case "expandAllFolders": store.setAllFoldersExpanded(true, inSpace: main.focusedSpaceID)
        case "openExtensions": main.showSiteControlsFromTheirButton()
        case "manageExtensions": main.openExtensionsPage()
        case "cast": if main.currentBrowser?.runChromeCommand("IDC_ROUTE_MEDIA") != true { main.showToast("Nothing to Cast") }
        case "taskManager": if main.currentBrowser?.runChromeCommand("IDC_TASK_MANAGER") != true { main.showToast("Open a Page First") }
        case "showArchive": main.showLibrary(.archive)
        case "clearArchive": store.clearArchive()
        case "stayOnTop": main.toggleStayOnTop()
        case "allowAppleEventsJavaScript": store.settings.allowAppleEventsJavaScript.toggle()
        case "appearanceAutomatic": store.settings.websiteAppearance = .automatic
        case "appearanceLight": store.settings.websiteAppearance = .light
        case "appearanceDark": store.settings.websiteAppearance = .dark
        case "essentialShortcuts":
            EssentialShortcutsWindow.shared.show(bindings: bindings) { [weak self] in
                self?.showSettingsWindow()
                self?.settingsController?.show(.shortcuts)
            }
        case "revealData": NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDir])
        case "copyAppInfo": copy(appInfo())
        case "print": main.currentBrowser?.print()
        case "capturePage": main.capturePage()
        case "find": main.showFindBar()
        case "findNext": main.findNext(forward: true)
        case "findPrevious": main.findNext(forward: false)
        case "useSelectionForFind": main.useSelectionForFind()
        case "jumpToSelection": main.jumpToSelection()
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
        // Like Arc: ⌥⌘I closes open DevTools; ⌥⌘J and Network switch to their panel and close
        // DevTools only when that panel already shows (DevToolsToggle.run).
        case "devTools": main.browsers.runDevTools(.toggle)
        case "jsConsole": main.browsers.runDevTools(.console)
        case "networkPanel": main.browsers.runDevTools(.network)
        case "inspectElement": main.browsers.runDevTools(.inspect)
        // Arc's Library is a mode of the window's sidebar; ⇧⌘J opens it on Downloads.
        case "openLibrary": main.toggleLibrary()
        case "viewArchive": main.showLibrary(.archive)
        case "viewDownloads": main.showLibrary(.downloads)
        case "viewMedia": main.showLibrary(.media)
        case "viewEasels": main.showLibrary(.easels)
        case "viewBoosts": main.showLibrary(.boosts)
        case "goBack": main.goBack()
        case "goForward": main.currentBrowser?.goForward()
        case "pinTab": if let c = current, !main.isBlank { store.togglePinned(c) }
        case "favoriteTab":
            if let c = current, !main.isBlank { store.isFavorite(c) ? store.removeFromFavorites(c) : store.addToFavorites(c) }
        case "joinNextMeeting":
            if let url = LiveCalendarClient.shared.nextCall()?.meetingURL { main.sidebarActions.openURL(url) } else { NSSound.beep() }
        // A pane has no row of its own: its split's name is edited.
        case "renameTab": main.sidebarUI.renamingID = current.map { store.splitContaining($0)?.id ?? $0 }
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
        case "rebuildArcProfiles": ArcProfileRebuilder.run(store: store) { [weak self] in self?.relaunch() }
        case "setDefaultBrowser": Task { await SystemIntegration.shared.makeDefaultBrowser() }
        case "checkForUpdates": SoftwareUpdater.shared.checkForUpdates(nil)
        case "languageSettings":
            // Chromium's page edits the profile of the space it opens in.
            let normal = useNormalWindow()
            _ = store.createTab(url: BrowserLanguages.settingsPage, select: true)
            normal.showWindow(nil)
        case "clearBrowsingData":
            // Chrome's dialog, in a normal window: what it deletes from history leaves the command bar too.
            let normal = useNormalWindow()
            _ = store.createTab(url: BrowsingDataClear.pageURL, select: true)
            normal.showWindow(nil)
        default:
            if id.hasPrefix("item"), let n = Int(id.dropFirst(4)) {
                let tabs = store.visibleTabs(in: store.focusedSpaceID)
                // ⌘9 is the last one (Arc's "Go to last Sidebar Item").
                if n == 9, let last = tabs.last { store.selectTab(last.id) } else if n - 1 < tabs.count { store.selectTab(tabs[n - 1].id) }
            } else if id.hasPrefix("splitPane"), let n = Int(id.dropFirst(9)) {
                main.selectSplitPane(n)
            } else if id.hasPrefix("space"), let n = Int(id.dropFirst(5)) {
                if n - 1 < store.spaceOrder.count { store.focusSpace(store.spaceOrder[n - 1]) }
            } else if id.hasPrefix("moveTabToSpace"), let n = Int(id.dropFirst(14)) {
                if let c = current, n - 1 < store.spaceOrder.count { store.moveTabAndFollow(c, toSpace: store.spaceOrder[n - 1]) }
            }
        }
    }

    /// Help ▸ Troubleshooting ▸ Copy Cra Info: what a bug report needs about this copy.
    private func appInfo() -> String {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        Cra \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))
        Chromium \(CraCEFRuntime.chromiumVersion()) · CEF \(CraCEFRuntime.cefVersion())
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        """
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func confirmDeleteSpace(_ space: Space, in window: NSWindow? = nil) {
        let window = window ?? main?.window ?? AppDialog.parentWindow
        guard store.spaceOrder.count > 1 else {
            let a = AppDialog(title: "You need at least one space.")
            a.runModal(over: window)
            return
        }
        let a = AppDialog(title: "Delete your “\(space.title)” Space?",
                          message: "This will archive all the tabs and folders inside it.",
                          actions: [DialogAction("Delete", role: .destructive), .cancel])
        if a.runModal(over: window) == .alertFirstButtonReturn { store.deleteSpace(space.id) }
    }

    // MARK: Windows

    func showSettingsWindow() {
        if settingsController == nil {
            let actions = SettingsActions(
                importData: { [weak self] in self?.main.showImport() },
                rebuildArcProfiles: { [weak self] in
                    guard let self else { return }
                    ArcProfileRebuilder.run(store: self.store) { [weak self] in self?.relaunch() }
                },
                openURL: { [weak self] url in
                    guard let self else { return }
                    self.useNormalWindow()
                    _ = self.store.createTab(url: url, select: true)
                    self.settingsWindow?.close()
                    self.main.showWindow(nil)
                },
                openProfilePage: { [weak self] url, profileID in
                    guard let self else { return }
                    let window = self.useNormalWindow()
                    self.openExtensionPage(url, window: window.windowID,
                                           profile: self.store.profile(profileID)?.directoryName ?? "Default", singleton: true)
                    self.settingsWindow?.close()
                    window.showWindow(nil)
                },
                exportDiagnostics: { [weak self] in self?.exportDiagnostics() },
                newProfile: { [weak self] in
                    guard let self, let w = self.settingsWindow else { return }
                    self.main.showNewProfileDialog(over: w)
                })
            let c = SettingsWindowController(store: store, bindings: bindings, sync: composition.sync, actions: actions)
            settingsController = c
            settingsWindow = c.window
            // Settings opened from the menu bar item: closing it puts Cra back in the menu bar.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: c.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard self?.inMenuBar == true else { return }
                    DispatchQueue.main.async { self?.settleDockIcon() }
                }
            }
        }
        leaveMenuBarForWindow()
        settingsController?.didShow()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus (Arc's layout)

    private func item(_ id: String) -> NSMenuItem {
        guard let a = bindings.action(id) else { return NSMenuItem() }
        let m = NSMenuItem(title: a.name, action: #selector(menuAction(_:)), keyEquivalent: "")
        m.representedObject = a.id
        m.target = self
        m.showShortcut(of: id)
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
        appMenu.addItem(item("clearBrowsingData"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("importData"))
        appMenu.addItem(item("checkForUpdates"))
        appMenu.addItem(.separator())
        appMenu.addItem(std("Hide Cra", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(std("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(std("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(std("Quit Cra", #selector(NSApplication.terminate(_:)), "q"))
        menubar.addItem(submenu: appMenu, title: "Cra")

        // Arc's File menu, its sections and rows (FileMenu, #279).
        let file = NSMenu(title: "File")
        for (i, section) in FileMenu.sections.enumerated() {
            if i > 0 { file.addItem(.separator()) }
            for id in section { file.addItem(item(id)) }
        }
        menubar.addItem(submenu: file, title: "File")

        let edit = NSMenu(title: "Edit")
        edit.addItem(std("Undo", Selector(("undo:")), "z"))
        edit.addItem(std("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(std("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(std("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("copyURL")); edit.addItem(item("copyURLMarkdown")); edit.addItem(item("copyURLQuote"))
        edit.addItem(std("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(std("Paste and Match Style", #selector(pasteAsPlainText(_:)), "v", [.command, .shift]))
        edit.addItem(std("Delete", #selector(NSText.delete(_:))))
        edit.addItem(std("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        for id in ["find", "findNext", "findPrevious", "useSelectionForFind", "jumpToSelection"] { find.addItem(item(id)) }
        edit.addItem(submenu: find, title: "Find")
        menubar.addItem(submenu: edit, title: "Edit")

        let view = NSMenu(title: "View")
        // Arc: View ▸ Appearance ▸ "Websites, Easels, and Notes will use:" Automatic / Light / Dark.
        let appearance = NSMenu(title: "Appearance")
        appearance.addItem(withTitle: "Websites will use:", action: nil, keyEquivalent: "").isEnabled = false
        for a in WebsiteAppearance.allCases {
            let m = item("appearance" + a.title)
            m.title = a.title
            appearance.addItem(m)
        }
        view.addItem(submenu: appearance, title: "Appearance")
        view.addItem(.separator())
        view.addItem(item("toggleSidebar")); view.addItem(item("toggleToolbar")); view.addItem(item("collapsePinned"))
        view.addItem(.separator())
        view.addItem(item("stop")); view.addItem(item("reload")); view.addItem(item("hardReload"))
        // Arc's View menu order: cookies, then cache.
        view.addItem(item("clearCookies")); view.addItem(item("clearCache"))
        view.addItem(.separator())
        view.addItem(item("resetZoom")); view.addItem(item("zoomIn")); view.addItem(item("zoomOut"))
        view.addItem(.separator())
        view.addItem(item("pictureInPicture")); view.addItem(item("cast"))
        view.addItem(.separator())
        for id in ["addSplitView", "closeSplitPane", "separateFromSplit", "flipSplitOrientation"] { view.addItem(item(id)) }
        view.addItem(.separator())
        let dev = NSMenu(title: "Developer")
        for id in ["viewSource", "devTools", "inspectElement", "jsConsole"] { dev.addItem(item(id)) }
        dev.addItem(item("allowAppleEventsJavaScript"))
        dev.addItem(.separator())
        dev.addItem(item("toggleDeveloperMode"))
        view.addItem(submenu: dev, title: "Developer")
        view.addItem(.separator())
        view.addItem(std("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        menubar.addItem(submenu: view, title: "View")

        let spaces = NSMenu(title: "Spaces")
        // Arc: New Space… heads the Spaces menu (#279).
        spaces.addItem(item("newSpace"))
        spaces.addItem(item("nextSpace")); spaces.addItem(item("previousSpace"))
        spaces.addItem(.separator())
        for id in ["editSpace", "changeProfile", "deleteSpace", "manageSpaces"] { spaces.addItem(item(id)) }
        spaces.addItem(.separator())
        for n in 1...9 { spaces.addItem(item("space\(n)")) }
        spaces.addItem(.separator())
        for n in 1...9 { spaces.addItem(item("moveTabToSpace\(n)")) }
        menubar.addItem(submenu: spaces, title: "Spaces")

        let tabs = NSMenu(title: "Tabs")
        for id in ["newTab", "pinTab"] { tabs.addItem(item(id)) }
        // Arc: Tabs ▸ New Folder… after Pin/Unpin Tab (#279).
        let newFolder = item("newFolder")
        newFolder.title = "New Folder…"
        tabs.addItem(newFolder)
        for id in ["nextTab", "previousTab", "revealTab", "recentTab", "clearToday", "resetSpaceTabs"] { tabs.addItem(item(id)) }
        tabs.addItem(.separator())
        for id in ["favoriteTab", "renameTab", "duplicateTab", "resetTab", "muteTab"] { tabs.addItem(item(id)) }
        tabs.addItem(.separator())
        for n in 1...9 { tabs.addItem(item("item\(n)")) }
        menubar.addItem(submenu: tabs, title: "Tabs")

        let archive = NSMenu(title: "Archive")
        archive.addItem(item("goBack")); archive.addItem(item("goForward"))
        archive.addItem(.separator())
        for id in ["viewArchive", "showArchive", "clearArchive"] { archive.addItem(item(id)) }
        menubar.addItem(submenu: archive, title: "Archive")

        // Dia: Extensions sits just before Window.
        menubar.addItem(submenu: extensionsMenu.makeMenu(), title: "Extensions")

        let window = NSMenu(title: "Window")
        window.addItem(item("stayOnTop"))
        window.addItem(std("Minimize Window", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(std("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("openLibrary")); window.addItem(item("viewDownloads")); window.addItem(item("viewEasels")); window.addItem(item("viewMedia")); window.addItem(item("viewBoosts"))
        window.addItem(.separator())
        window.addItem(item("promoteLittleWindow")); window.addItem(item("littleWindowOpenInMenu")); window.addItem(item("closeLittleWindows"))
        window.addItem(.separator())
        window.addItem(std("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        menubar.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Chromium \(CraCEFRuntime.chromiumVersion()) · CEF \(CraCEFRuntime.cefVersion())", action: nil, keyEquivalent: "")
        help.addItem(.separator())
        help.addItem(item("essentialShortcuts"))
        for (title, url) in [("Cra Help", "https://crabrowser.app/help"), ("Release Notes", "https://crabrowser.app/release-notes"),
                             ("Report an Issue…", "https://github.com/VictorKildahl/cra/issues"), ("Support Cra…", "https://crabrowser.app/support")] {
            let link = NSMenuItem(title: title, action: #selector(openHelpLink(_:)), keyEquivalent: "")
            link.target = self
            link.representedObject = SiteLinks.tagged(url, from: .helpMenu)
            help.addItem(link)
        }
        help.addItem(.separator())
        // Arc: Help ▸ Troubleshooting.
        let trouble = NSMenu(title: "Troubleshooting")
        trouble.addItem(withTitle: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "").target = self
        trouble.addItem(.separator())
        trouble.addItem(item("taskManager")); trouble.addItem(item("revealData")); trouble.addItem(item("copyAppInfo"))
        help.addItem(submenu: trouble, title: "Troubleshooting")
        menubar.addItem(submenu: help, title: "Help")
        NSApp.helpMenu = help

        NSApp.mainMenu = menubar
        retitleFlippingRows()
    }

    /// Help menu links open as a tab in the normal window in use, like Arc's.
    @objc private func openHelpLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        useNormalWindow()
        store.createTab(url: url, select: true)
        main.showWindow(nil)
    }

    /// A zip of logs and page state for a bug report (Diagnostics.swift).
    @objc private func exportDiagnostics() {
        Diagnostics.export(windows: mainWindows, store: store)
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
