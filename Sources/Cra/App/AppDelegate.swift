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
    private var extensionCommandMonitor: Any?
    /// The front window's page offered to the user's iPhone through Handoff (#745).
    private lazy var handoff = HandoffPublisher { [weak self] in self?.handoffPage() }
    private var pendingURLs: [String] = []
    private var settingsWindow: NSWindow?
    private var settingsController: SettingsWindowController?
    private var isRelaunching = false
    private lazy var extensionsMenu = ExtensionsMenu(app: self)
    private lazy var spacesMenu = SpacesMenu(app: self)
    /// Arc's Little Arc windows: small, sidebar-less, disposable (see LittleWindowController).
    private(set) var littleWindows: [LittleWindowController] = []
    /// The browser window's frame when `cra://debug?toolbarDoubleClick` last looked for the toolbar's empty part (#685).
    private var toolbarDoubleClickFrame: NSRect?
    /// When each Little Window was last the key window, for Arc's "Archive Little Arcs after:".
    private var littleWindowLastUsed: [ObjectIdentifier: Date] = [:]
    private var littleWindowArchiveCheck: ScheduledWork?
    /// The app in use before Cra came forward, which a Little Window opened from it goes back to (#430).
    private var frontmostApps = FrontmostAppHistory()

    /// Use Both's presses between OnPreKeyEvent and OnKeyEvent (#374).
    private var useBoth = UseBothPresses()

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) { bootstrapIfNeeded() }

    func bootstrapIfNeeded() {
        guard !bootstrapped else { return }
        bootstrapped = true
        NSApp.setActivationPolicy(.regular)
        // Before any window docks: window managers see one Cra window, not its page and panels (#391).
        DockedWindowAccessibility.install()
        SystemAppearance.shared.start()
        DocumentPictureInPictureSpring.shared.start()
        // Coming forward for a press on Picture in Picture's window (#741), AppKit raised a browser window over the app
        // the user was in for a moment, even one that couldn't take the keyboard (Victor, 24 Nov 2026): those behind
        // another window are out of sight while the activation lands and come back where they were, and meanwhile no
        // browser window takes the keyboard or main.
        PictureInPictureChrome.shared.browserWindowsComingForward = { [unowned self] in
            let behind = BrowserWindowsBehind(mainWindows.compactMap(\.window), stack: StackedWindow.onScreen())
            CraWindow.stayBehindWhileComingForward = true
            behind.takeOut()
            return { last in
                behind.bringBackIn()
                if last { CraWindow.stayBehindWhileComingForward = false }
            }
        }
        installURLEventHandler()
        observeFrontmostApp()
        PerfCEF.install(app: self)
        CraCEFRuntime.setChromeHosting(store.settings.chromeEngine)
        // PageScript's scripts, with the filter lists' scriptlets as the last run left them (#845).
        FilterPageScripts.install(table: nil)
        // WebKit pages' ad blocking, as the last run compiled it, until the lists are read again.
        WebKitContentBlocking.shared.restore()
        startContentBlocking()
        observeGlobalShortcut()
        observeMenuBarMode()
        SoftwareUpdater.shared.start(app: self)
        buildMenus()
        store.hasPage = { [unowned self] in self.runtime(for: $0).map { !$0.discarded } ?? false }
        store.tabPinned = { [unowned self] in TidyTitlesService.shared.tabPinned($0, store: self.store) }
        // On the next turn: the incognito window's own caller may still bring itself forward (#412).
        store.pageLeftIncognito = { [unowned self] id in
            DispatchQueue.main.async {
                let normal = self.mainWindows.first { $0.windowID == id } ?? self.useNormalWindow()
                self.store.activeWindowID = normal.windowID
                normal.showWindow(nil)
            }
        }
        store.tidyDownloadsChanged = { enabled in if !enabled { TidyDownloadsService.shared.cancelAll() } }
        TidyTabsService.shared.downloadsUnavailable = { TidyDownloadsService.shared.cancelAll() }
        store.tidyTabsChanged = { [unowned self] enabled in if !enabled { TidyTabsService.shared.cancelAll(store: self.store) } }
        store.tidyTabsSpaceRemoved = { [unowned self] in TidyTabsService.shared.cancel($0, store: self.store) }
        LinkSummaryPreviewController.shared.bindEligibility(to: store)
        // Screenshots the system takes show up in the downloads list by themselves (Arc's Library button).
        ScreenshotWatcher.shared.start(store: store)
        store.tidyTabTitlesChanged = { enabled in if !enabled { TidyTitlesService.shared.cancelAll() } }
        TidyTabsService.shared.titlesUnavailable = { TidyTitlesService.shared.cancelAll() }
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
        CaptureOverlay.easels = { EaselFiles.all().map { CaptureMenuLayout.Destination(id: $0.id, title: $0.title) } }
        CaptureEditors.make = { frame, image in CaptureEditorView(frame: frame, image: image) }
        EaselBrowser.registerServices(self)
        // Arc's Boosts: each page on a boosted site gets its boosts; an edit shows at once.
        BrowserManager.boostFor = { [store] url, engineTints in
            guard store.settings.boostsEnabled else { return nil }
            let boosts = Boost.applying(to: url, from: BoostStore.shared.boosts)
            guard !boosts.isEmpty else { return nil }
            // One tint, as the stylesheet's filters were: the last boost's wins.
            return (boosts.map { $0.stylesheet(engineTints: engineTints) }.joined(separator: "\n"),
                    boosts.map(\.js).filter { !$0.isEmpty }.joined(separator: ";\n"),
                    boosts.compactMap(\.tint?.engineString).last)
        }
        BoostStore.changed = { [weak self] host in for m in self?.mainWindows ?? [] { m.browsers.reapplyBoosts(host: host) } }
        mainWindows = store.prefs.windows.map { MainWindowController(app: self, session: $0) }
        followKeyWindow()
        observeFlippingRows()
        observeUpdateNotice()
        // First launch: the default browser step and the import are the onboarding and
        // the browser window appears once they are done (Dia does the same).
        if needsOnboarding {
            isOnboarding = true
            main.showImport(firstRun: true)
        } else {
            // The window in use last comes up in front.
            for w in mainWindows.reversed() { w.showWindow(nil) }
            for w in mainWindows { w.enterSavedFullScreen() }
            // As ⌘T: the command bar makes the new tab, Esc leaves the window empty.
            if startOnNewTab { DispatchQueue.main.async { [weak self] in self?.main.openCommandBar(.newTab) } }
        }
        installKeyFallbackMonitor()
        installSideButtonKeyMonitor()
        installCommandFileWatcher()
        handoff.start()
        MCPServer.shared.start(app: self)
        composition.startPeriodicWork(autoArchived: { [weak self] in self?.noteAutoArchived($0) }) { [weak self] in self?.sleepIdleTabs() }
        composition.sync.keybindingsChanged = { [weak self] in self?.bindings.reloadOverrides() }
        composition.sync.start()
        SharingService.shared.start(store: store, clock: composition.clock)
        observeSystemWake()
        logSidebarProblems()
        LiveFolderManager.shared.start(store: store)
        store.attributeHistoryProfiles()
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
        CraBrowser.installViewSourceHandler()
        let dropsStartUpPage = { [weak self] (url: String) -> Bool in
            guard let self, Date().timeIntervalSince(launchedAt) < 10,
                  !hasNewExtension || self.store.allTabs().contains(where: { $0.tab?.url == url }) else { return false }
            NSLog("Cra: dropped start-up page from an extension: %@", url)
            return true
        }
        PageWindowStart.install()
        PageHostWindows.install()
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
    /// This launch shows the onboarding, until it ends: the sidebar's sharing card waits.
    private(set) var isOnboarding = false

    var needsOnboarding: Bool {
        !store.settings.hasSeenImportPrompt && store.allTabs().count <= 2
    }

    /// End of the import flow. Onboarding counts as done only here, so quitting halfway
    /// shows it again on the next launch.
    func importFinished(_ outcome: ImportOutcome, firstRun: Bool) {
        if firstRun {
            isOnboarding = false
            store.settings.hasSeenImportPrompt = true
        }
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
    /// checkbox). The bundled list (resources/blocklist) and the lists added in Settings (#507)
    /// are read off the main thread; the switch and the lists follow the settings live, no restart.
    private func startContentBlocking() {
        observeContentBlocking()
        observeChanges(of: { [store] in store.settings.customBlocklists }) { [composition] in
            BlockLists.shared.set(addresses: $0, clock: composition.clock)
        }
        BlockLists.shared.hidingChanged = { [weak self] in
            for window in self?.mainWindows ?? [] { window.browsers.refreshElementHiding() }
        }
        observeChanges(of: { [store] in store.settings.activePersonalFilters }) {
            BlockLists.shared.setPersonal($0)
        }
        observeHttpsOnly()
        // Arc's "Archive Little Arcs after:": a Little Window left alone that long closes, its page archived.
        littleWindowArchiveCheck = composition.clock.every(60) { [weak self] in self?.archiveIdleLittleWindows() }
        // View ▸ Appearance: pages, and the browser itself as in Arc (its windows, menus, command bar
        // and Auto space themes follow NSApp's appearance), before the first window is made (#362).
        observeChanges(of: { [store] in store.settings.websiteAppearance }) { [weak self] appearance in
            CraCEFRuntime.setWebsiteAppearance(appearance.chromiumMode)
            NSApp.appearance = appearance.forcesDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
            // And every space's sidebar, its own Light or Dark included, as Arc's one setting does (#700).
            SystemAppearance.shared.setForced(appearance.forcesDark)
            self?.mainWindows.forEach { $0.refresh() }
        }
        // Chromium's Mode in chrome://settings/appearance is the same setting, saved as Cra's so the
        // next launch keeps it (#630).
        CraCEFRuntime.setWebsiteAppearanceChangeHandler { [store] mode in
            guard let appearance = WebsiteAppearance(chromiumMode: mode),
                  store.settings.websiteAppearance != appearance else { return }
            CraLog.note("website appearance from Chromium settings: \(appearance.rawValue)")
            store.settings.websiteAppearance = appearance
        }
        observeChanges(of: { [store] in store.settings.soundEffects }) { CaptureSound.enabled = $0 }
        observeLinkMenu()
        logSecureDNS()
        // Extensions' shortcuts outside Global scope: Chrome catches them on its own window, which Cra never
        // shows, so Cra catches them first, pages included, as Chrome does (#701).
        extensionCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.closesExtensionPopup(event) || self.runExtensionCommand(event) ? nil : event
            }
        }
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

    // MARK: "Auto archived N tabs"

    private static let autoArchiveNoticeKey = "autoArchiveNoticePending"
    /// Arc's toast after an archive pass, held until someone is at Cra (AutoArchiveNotice). Kept in the defaults, so
    /// the count from before an update restart overnight is still said in the morning.
    private var autoArchiveNotice = AutoArchiveNotice(pending: UserDefaults.standard.integer(forKey: AppDelegate.autoArchiveNoticeKey)) {
        didSet { UserDefaults.standard.set(autoArchiveNotice.pending, forKey: Self.autoArchiveNoticeKey) }
    }
    /// While a count waits with Cra in front: the first key, click or scroll there means someone is back.
    private var autoArchiveReturnMonitor: Any?

    private func noteAutoArchived(_ count: Int) {
        guard count > 0 else { return }
        autoArchiveNotice.archived(count)
        CraLog.note("auto archive: \(count) tabs, \(autoArchiveNotice.pending) waiting for the toast")
        showAutoArchiveNotice(becameActive: false)
    }

    private func showAutoArchiveNotice(becameActive: Bool) {
        guard autoArchiveNotice.pending > 0, !isOnboarding, !mainWindows.isEmpty else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let present = becameActive || AutoArchiveNotice.userPresent(appActive: NSApp.isActive, idleSeconds: idle)
        guard let text = autoArchiveNotice.take(userPresent: present) else {
            watchForReturnToAutoArchiveNotice()
            return
        }
        if let m = autoArchiveReturnMonitor { NSEvent.removeMonitor(m); autoArchiveReturnMonitor = nil }
        CraLog.note("auto archive toast: \(text)")
        // A click opens the Archive, where the tabs are.
        let window = main
        window?.showToast(text) { [weak window] in window?.showLibrary(.archive) }
    }

    private func watchForReturnToAutoArchiveNotice() {
        guard autoArchiveReturnMonitor == nil else { return }
        autoArchiveReturnMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            // After the event, so a click that lands keeps its target and the toast comes up beside it.
            DispatchQueue.main.async { self?.showAutoArchiveNotice(becameActive: false) }
            return event
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
        // A profile that loaded since the last pass gets the kept-active sites in Chromium's list, and
        // an edit on chrome://settings/performance comes back to Settings (#458).
        ChromeKeepActiveSites.apply(store: store)
        // …and its name, as Cra shows it (#666).
        ChromiumProfileNames.apply(store: store)
        for w in mainWindows {
            w.browsers.freezeIdleTabs(hiddenLongerThan: freezeAfter)
            w.releaseHiddenFrames(now: composition.clock.now)
            if settings.tabSleepTimerEnabled { w.browsers.sleepIdleTabs(.timer(settings.tabSleepAfter)) }
            // Pages already slept hold a browser and a window each for the session: past the budget they close (#616).
            w.browsers.closeSleptPages()
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

    /// Settings > Privacy > "Always use secure connections" and "Fingerprinting protection", live
    /// like content blocking.
    private func observeHttpsOnly() {
        observeChanges(of: { [store] in store.settings.httpsOnly }, apply: CraCEFRuntime.setHttpsOnlyModeEnabled)
        observeChanges(of: { [store] in store.settings.fingerprintingProtection },
                       apply: CraCEFRuntime.setFingerprintingProtectionEnabled)
        // Settings ▸ Tabs ▸ "Always keep these sites active" (#458), for Chromium's own freezing too.
        observeChanges(of: { [store] in store.settings.keepActiveSites }) { [store] _ in ChromeKeepActiveSites.apply(store: store) }
        // Chromium calls each profile what Cra does, after a rename too (#666).
        store.onProfileNamesChanged = { [store] in ChromiumProfileNames.apply(store: store) }
        ChromiumProfileNames.apply(store: store)
        // Shared extensions belong in every profile, one made later too (discussion #595).
        ExtensionStore.profileFoldersSource = { [weak self] in ["Default"] + (self?.store.profiles.map(\.directoryName) ?? []) }
        observeChanges(of: { [store] in store.profiles.map(\.directoryName) }) { _ in ExtensionStore.shared.pushManagedExtensions() }
    }

    /// Chromium's secure DNS setting (Settings > Privacy, chrome://settings/security), left on
    /// Chromium's default like Arc: the log says what is in effect at launch and after each
    /// change (#110), and the Settings row follows it (#133).
    private func logSecureDNS() {
        var last: String?
        CraCEFRuntime.setSecureDNSChangeHandler { [store] in
            // Called first once Chromium is ready: Default has loaded, so it takes its name now (#666).
            ChromiumProfileNames.apply(store: store)
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
        observeChanges(of: { [store] in store.settings.pausedFilterHosts ?? [] }) {
            BlockLists.shared.setPausedHosts($0)
        }
        observeChanges(of: { [store] in store.settings.hasActiveBlockFilters }) {
            CraCEFRuntime.setContentBlockingEnabled($0)
            WebKitContentBlocking.shared.enabled = $0
        }
        observeChanges(of: { [store] in
            (store.settings.adAwayEnabled ? ["adaway"] : []) + (store.settings.anudeepEnabled ? ["anudeep"] : [])
        }) {
            BlockLists.shared.setBundledSources($0)
        }
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

    func applicationDidBecomeActive(_ notification: Notification) {
        comingForward = false
        installURLEventHandler()
        // keyOnComingForward's window=<n>: made key on the next turn, once AppKit has settled the keys on the window it
        // picked, so that window becomes the one in use just before the link is handled, as in the report.
        if let w = debugKeyOnComingForwardWindow {
            debugKeyOnComingForwardWindow = nil
            DispatchQueue.main.async { [self] in
                w.makeKeyAndOrderFront(nil)
                let inUse = mainWindows.first { $0.windowID == store.activeWindowID }?.focusedSpace.title ?? "-"
                CraLog.note("key on coming forward: in use \(inUse)")
            }
        }
        // Someone brought Cra forward: they're here to read what was archived while they were away.
        showAutoArchiveNotice(becameActive: true)
    }

    /// The window order and the browser window in use as Cra comes forward, before AppKit raises its key and main
    /// window: a link clicked in another app brings Cra forward (LaunchServices) before it arrives, so the browser
    /// window had already risen over that app when the Little Window opened (#607), and the window AppKit made key
    /// had become the one in use.
    private var beforeComingForward: BeforeComingForward?
    /// Cra is coming forward (from applicationWillBecomeActive to applicationDidBecomeActive): AppKit picks its key
    /// window then, the browser window at times before a Little Window, which isn't the browser in use (#659).
    private var comingForward = false
    /// cra://debug?keyOnComingForward=1: the next time Cra comes forward, the browser window is made key on the
    /// way, as AppKit does by itself at times (#659).
    private var debugKeyOnComingForward = false
    /// keyOnComingForward's window=<n>: the nth browser window (oldest first), made key as Cra has come forward
    /// (applicationDidBecomeActive). Made key on the way instead, AppKit gave the keys back to the window in use.
    private weak var debugKeyOnComingForwardWindow: NSWindow?
    func applicationWillBecomeActive(_ notification: Notification) {
        beforeComingForward = BeforeComingForward(at: store.clock.now, stack: StackedWindow.onScreen(), window: store.lastNormalWindowID)
        comingForward = true
        if debugKeyOnComingForward {
            debugKeyOnComingForward = false
            if debugKeyOnComingForwardWindow == nil { main?.window?.makeKey() }
        }
    }

    /// Arc's frontmostApplicationHistory: which app was in front before Cra (#430).
    private func observeFrontmostApp() {
        let me = NSRunningApplication.current.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != me {
            frontmostApps = FrontmostAppHistory(frontmost: front)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let isCra = app.processIdentifier == me
                self.frontmostApps.activated(app.processIdentifier, isCra: isCra, at: self.store.clock.now)
                guard isCra else { return }
                for w in self.littleWindows { w.focusReturn.craCameForward(from: self.frontmostApps.beforeCra) }
            }
        }
    }

    /// #430: the browser window or Settings taking the keyboard means Cra is in use, and a Little
    /// Window closes back to it. Panels (command bars, menus, a Peek) don't count.
    private func noteKeyWindow(_ top: NSWindow) {
        if let little = littleWindows.first(where: { $0.window === top }) {
            little.focusReturn.littleWindowBecameKey()
            return
        }
        guard !(top is NSPanel), top.isVisible, top.alphaValue > 0 else { return }
        for w in littleWindows { w.focusReturn.otherWindowBecameKey(whileComingForward: comingForward) }
    }

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
        // One quit at a time (#426): Chromium's exit sends another terminate once the pages start
        // closing, and a restart can send quit events while the question is open.
        switch quitRequests.begin() {
        case .new: break
        case .asking: return .terminateCancel
        case .quitting:
            CraLog.note("quit: already quitting, not asked again")
            return .terminateNow
        }
        if MenuBarMode.outcome(enabled: store.settings.keepInMenuBar, source: quitSource()) == .stayInMenuBar {
            quitRequests.answered(quit: false)
            stayInMenuBar()
            return .terminateCancel
        }
        // Arc asks while a download runs (quitting cancels it); otherwise Dia's Advanced ▸ "Warn
        // before quitting". Restarts skip both (#272).
        let quits: Bool
        switch quitPrompt(source: quitSource()) {
        case .downloadsInProgress: quits = confirmQuitCancellingDownloads()
        case .confirmQuit: quits = confirmQuit()
        case .none: quits = true
        }
        quitRequests.answered(quit: quits)
        guard quits else { return .terminateCancel }
        // A Web Store install the quit cuts short isn't the store's answer (#491).
        ExtensionStore.shared.isQuitting = true
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

    /// What quitting from `source` asks first. The `downloadGuards` readout asks it too, so a download
    /// Cra doesn't list (a Web Store install's CRX, Chrome's own fetches) can't hold it unseen (#491).
    private func quitPrompt(source: MenuBarMode.QuitSource) -> QuitPrompt {
        QuitPrompt.on(source: source, downloadsRunning: DownloadHistory.shared.hasRunningDownloads,
                      warnBeforeQuitting: store.settings.warnBeforeQuitting)
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
        CraLog.note("quit asks: Quit Cra?")
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

    /// Help ▸ Troubleshooting ▸ Open Task Manager: Chrome's own, which belongs to the browser, as in Arc. Any open page's
    /// hidden Chrome window can open it, so no tab in front is no reason to refuse (#855, ChromeCommandPages).
    private func openTaskManager() {
        let elsewhere = mainWindows.filter { $0 !== main }.flatMap { $0.browsers.runtimes.values.map(\.browser) }
            + littleWindows.compactMap(\.browser)
        let pages = ChromeCommandPages.order(front: main.currentBrowser, sameWindow: main.browsers.runtimes.values.map(\.browser),
                                             elsewhere: elsewhere)
        if let page = pages.first(where: { $0.runChromeCommand("IDC_TASK_MANAGER") }) {
            CraLog.note("task manager: opened from \(page === main.currentBrowser ? "the page in front" : "another open page")")
            return
        }
        CraLog.note("task manager: no page open, \"Open a Page First\"")
        main.showToast("Open a Page First")
    }

    func openExternalURL(_ url: String) {
        // A link from another app soon after starting on a new tab: its tab is what the window
        // shows, so the bar that was waiting for a new tab goes.
        if store.settings.startOnNewTab, let m = main, m.commandBar.isOpen, m.selectedTab == nil { m.commandBar.close() }
        // The gallery's Open in Cra (crabrowser.app/boosts) from any browser: asked about first.
        if BoostInstall.isBoostLink(url) {
            main.showWindow(nil)
            if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
            BoostInstall.offer(url, over: main.window, from: "another app")
            return
        }
        // An easel's Open in Cra (crabrowser.app/easel): asked about first, as a boost is.
        if EaselShare.isEaselLink(url) {
            main.showWindow(nil)
            if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
            EaselShare.offer(url, over: main.window, from: "another app")
            return
        }
        if let u = URL(string: url), u.scheme?.lowercased() == "cra" {
            if Self.isUserFacing(u) || UserDefaults.standard.bool(forKey: "scriptingURLs") {
                handleInternalURL(u)
            } else {
                NSLog("Cra: ignored %@ from another app (defaults write dk.kildahl.cra scriptingURLs -bool YES allows it)", url)
            }
            return
        }
        // Cra came forward for this link and AppKit made another browser window key on the way (a full-screen one on
        // another display): the window in use is still the one before, and the link opens in its space and profile.
        if let before = beforeComingForward?.forLink(at: store.clock.now, craActive: NSApp.isActive),
           mainWindows.contains(where: { $0.windowID == before.window && !$0.isStandalone }) {
            store.activeWindowID = before.window
        }
        // Links from other apps never land in an incognito window (Chrome does the same).
        useNormalWindow()
        // Arc's Air Traffic Control: the first matching route, else the default
        // ("Links from other apps open in Little Arc").
        switch store.settings.destination(forExternalURL: url) {
        case .littleWindow(let space):
            // #258: the route's space names the page's profile and where ⌘O sends it.
            openLittleWindow(url: url, space: openableSpace(space), fromOtherApp: true)
            return
        case .space(let id) where store.space(id) != nil:
            store.createTab(url: url, in: id, select: true)
        case .space, .mostRecentSpace:
            let tab = store.createTab(url: url, select: true)
            main.browsers.beginRedirectRouting(for: tab.id, space: store.focusedSpaceID(window: main.windowID))
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
    /// The quit asked about or under way, so one ⌘Q asks once (#426).
    private var quitRequests = QuitRequests()

    /// Chromium stopped the quit (a page's "Leave site?" ▸ Stay): the next ⌘Q asks again.
    func quitWasCancelled() {
        CraLog.note("quit: cancelled by a page")
        quitRequests.cancelled()
    }
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
        AppIconManager.shared.applyAfterReturningToDock()
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
                    if name == NSWindow.didBecomeKeyNotification { self.noteKeyWindow(w) }
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
    /// Returns the window, for AppleScript's `make new window`.
    @discardableResult
    func openNewWindow(incognito: Bool = false, blank: Bool = false, url: String? = nil) -> MainWindowController {
        if !incognito, !blank, let hidden = mainWindows.first(where: { !$0.isStandalone }),
           !mainWindows.contains(where: { $0.window?.isVisible == true || $0.window?.isMiniaturized == true }) {
            hidden.showWindow(nil)
            if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
            if let url { store.createTab(url: url, select: true, window: hidden.windowID) }
            return hidden
        }
        // From a window in full screen, the new one goes full screen on a Space of its own (#528).
        let current = main.flatMap { m in m.window.flatMap { $0.isVisible ? (m, $0) : nil } }
        let placement = NewWindowPlacement.of(
            source: current?.1.frame,
            sourceFullScreen: current.map { $0.1.styleMask.contains(.fullScreen) && store.window($0.0.windowID).fullScreen } ?? false,
            screen: (current?.1.screen ?? NSScreen.main)?.visibleFrame, defaultSize: MainWindowController.defaultSize)
        let frame = placement.frame.map(NSStringFromRect)
        // Incognito from a space goes in that space's profile's off-the-record one, as in Chrome (#620).
        let fromSpace = main.map { $0.focusedSpaceID } ?? store.focusedSpaceID(window: store.lastNormalWindowID)
        let session = incognito ? store.addIncognitoWindow(frame: frame, profileID: store.profileID(space: fromSpace))
            : blank ? store.addBlankWindow(frame: frame)
            : store.addWindow(spaceID: store.focusedSpaceID(window: store.lastNormalWindowID), frame: frame)
        if placement.opensFullScreen { store.updateWindow(session.id) { $0.fullScreen = true } }
        let c = showNewWindow(session)
        if let url { store.createTab(url: url, select: true, window: c.windowID) }
        if placement.opensFullScreen {
            // The bar comes up once the window is on its own Space, not on the one it left.
            c.enterSavedFullScreen(then: url == nil ? { [weak c] in c?.openCommandBar(.newTab) } : nil)
        } else if url == nil {
            c.openCommandBar(.newTab)
        }
        return c
    }

    @discardableResult
    private func showNewWindow(_ session: WindowSession) -> MainWindowController {
        let c = MainWindowController(app: self, session: session)
        mainWindows.append(c)
        store.activeWindowID = c.windowID
        c.showWindow(nil)
        // A background test instance (CRA_TEST_BACKGROUND) never comes to the front.
        if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
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

    /// A tab dragged out of every Cra window and let go (GitHub #219): as in Arc, a Today tab moves into
    /// a new Blank Window placed where it was dropped, with its page as it was (no reload); a pinned
    /// one stays where it is and the window opens a copy (TabTearOff.copiesTab).
    /// `screenPoint` is where the pointer let go; the window takes the size of the one it came from.
    func tearOffTab(_ id: UUID, at screenPoint: NSPoint, from source: MainWindowController) {
        guard store.item(id)?.isTab == true, !store.isIncognito(item: id) else { return }
        let size = source.window?.frame.size ?? NSSize(width: 1200, height: 800)
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? source.window?.screen ?? NSScreen.main
        let frame = TabTearOff.frame(size: size, droppedAt: screenPoint, visible: screen?.visibleFrame ?? .zero)
        let session = store.addBlankWindow(frame: NSStringFromRect(frame))
        // A pinned tab stays in its place (its folder too) with its page, and the window opens a copy (Arc 1.174.2).
        if TabTearOff.copiesTab(pinned: store.isPinned(id)) {
            store.copyToBlankWindow(id, window: session.id)
            _ = showNewWindow(session)
            return
        }
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
        // Never a window no one can see: Chrome's own on the Chromium engine (a page's DevTools window before Cra
        // takes its frontend, the window holding a profile's pages) stays on screen at alpha 0.
        // A Little Window (or Peek) is a panel of its own; other panels (Peek's dimming, tooltips) never count.
        // The window server's order, front to back: NSApp.orderedWindows leaves panels out, so a Little
        // Window was never the front one there and Back (⌘[, cra://action/goBack) sent while Cra wasn't
        // the active app went to the browser window behind it (#495's little-window-typed-back failed so).
        let onScreen = (NSWindow.windowNumbers(options: []) ?? []).compactMap { NSApp.window(withWindowNumber: $0.intValue) }
        guard let front = (onScreen.isEmpty ? NSApp.orderedWindows : onScreen).first(where: { $0.isVisible && $0.alphaValue > 0 && (!($0 is NSPanel) || $0 is LittleWindow) }) else { return nil }
        if let little = littleWindows.first(where: { !$0.isParked && ($0.window === front || $0.window === front.parent) }) { return little }
        // A Peek is a child of the browser window, above it.
        return littleWindows.first { !$0.isParked && $0.window?.isVisible == true && $0.window?.parent === front }
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
    func openLittleWindow(url: String, activate: Bool = true, opener: CraBrowser? = nil, space: UUID? = nil,
                          fromOtherApp: Bool = false) -> LittleWindowController {
        // The browser windows stay where they were (#607): for a link, where they were before Cra came forward for it.
        // They go back at once, before the Little Window is made, and again as it comes up.
        var behind = BrowserWindowsBehind.none
        if activate {
            let before = fromOtherApp ? beforeComingForward?.forLink(at: store.clock.now, craActive: NSApp.isActive)?.stack : nil
            behind = BrowserWindowsBehind(mainWindows.compactMap(\.window), stack: before ?? StackedWindow.onScreen())
            behind.putBack(clickedIfKey: false)
        }
        let w = makeLittleWindow(url: url, opener: opener, space: space)
        // Opened over another app (a link from it, the shortcut pressed in it): it goes back there (#430).
        if activate {
            w.focusReturn = LittleWindowReturn(app: frontmostApps.returnApp(at: store.clock.now))
            w.browsersBehind = behind
            w.show()
        } else {
            w.orderFrontInBackground()
        }
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
        if let tabID { parent.sidebarUI.peekBadges[tabID] = .init(iconKey: FaviconKey.sectionKey(for: url)) }
        w.showAsPeek(fromTab: tabID)
    }

    func removeLittleWindow(_ w: LittleWindowController) {
        littleWindows.removeAll { $0 === w }
        if inMenuBar { DispatchQueue.main.async { [weak self] in self?.settleDockIcon() } }
        if let parent = w.peekParent, let tab = w.peekSourceTab,
           !littleWindows.contains(where: { $0.peekParent === parent && $0.peekSourceTab == tab }) { parent.sidebarUI.peekBadges[tab] = nil }
        // A Peek gone from the list never stands for the sidebar's address field (#706).
        w.peekParent?.syncPeekAddress()
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
            // As for a link from another app (openExternalURL): its tab is what the window shows, so the bar
            // that was waiting for a new tab goes. CEF's new page window took the bar's key and closed it anyway.
            if !background, !little, store.settings.startOnNewTab, let m = main, m.commandBar.isOpen, m.selectedTab == nil {
                m.commandBar.close()
            }
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
            // Headless import (scripting): cra://import?source=arc&archive=1&settings=1, source any
            // ImportSource id that reads from disk (arc, dia, yab, ardia, phi, crest, chrome, zen…).
            let source = ImportSource.allCases.first { $0.id == (q("source") ?? "arc") }
            let plan = try? source.flatMap { $0.needsExportedFile ? nil : try $0.plan() }
            if let plan {
                let r = store.apply(plan, includeArchive: q("archive") != "0", includeSettings: q("settings") != "0")
                favicons.reset()
                NSLog("Cra: imported %d spaces, %d tabs, %d folders, %d archived, %d of %d tabs copied", r.spaces, r.tabs, r.folders, r.archived,
                      r.report[.tabs].copied, r.report[.tabs].total)
            }
        case "debug":
            var dict: [String: String] = [:]
            for item in comps?.queryItems ?? [] { if let v = item.value { dict[item.name] = v } }
            if dict["findQuery"] != nil || dict["findStep"] != nil {
                main.debugFind(query: dict["findQuery"], step: dict["findStep"], quote: dict["findPurpose"] == "quote")
                return
            }
            if let js = dict["devtoolsjs"] { main.debugRunInDevTools(js) }
            if dict["embedDump"] != nil { NSLog("%@", main.embeddedPagesDump()); return }
            if dict["pageInsets"] != nil { CraLog.note(main.pageInsetsReadout()); return }
            // pageScale=<factor> pinch-zooms the front tab's page as a trackpad does; pageScale=read:<label> logs its
            // pinch scale and zoom level (GitHub #825: ⌘0 left a pinch in place).
            if let scale = dict["pageScale"] { main.debugPageScale(scale); return }
            if dict["windowCoverage"] != nil { CraLog.note(main.windowCoverageReadout()); return }
            if let mode = dict["coverWindow"] { main.debugCoverWindow(mode); return }
            if let mode = dict["missionControl"] { main.debugMissionControl(mode); return }
            // littleBreakNextShow=hide|size: the next Little Window to come up leaves its page hidden or laid out at its
            // grow-in's start, as #848's white Little Window; littlePage=<label>: what Cra sees of the newest Little
            // Window's page (LittlePageHealth's verdict and PageProbe's line).
            if let mode = dict["littleBreakNextShow"] { LittleWindowController.debugBreakNextShow = mode; return }
            if let label = dict["littlePage"] {
                guard let w = littleWindows.last else { CraLog.note("little page \(label): no Little Window"); return }
                w.lookAtPage { verdict, said in
                    let v: String
                    switch verdict {
                    case .drawing: v = "drawing"
                    case .notJudged: v = "not judged"
                    case .stuck(let reasons): v = "stuck (" + reasons.joined(separator: ", ") + ")"
                    }
                    CraLog.note("little page \(label): \(v), \(said)")
                }
                return
            }
            // pageDrawn=<label>: whether the front tab's page is in its card and draws there. Its frames
            // come in Chromium's CALayerHost under the page's view; a page Chrome attached to its own
            // never-shown window drew there instead, and the tab stayed blank (GitHub #469).
            if let label = dict["pageDrawn"] {
                func hosts(_ layer: CALayer?) -> Bool {
                    guard let layer else { return false }
                    return String(describing: type(of: layer)) == "CALayerHost" || (layer.sublayers ?? []).contains { hosts($0) }
                }
                let id = main.browsers.visibleTabID
                let view = id.flatMap { main.browsers.runtime(for: $0) }?.browser.containerView
                let inCard = id.map { !main.browsers.waitsForItsPane($0) && view?.window === main.window } ?? false
                CraLog.note("page drawn \(label): inCard=\(inCard ? 1 : 0) drawn=\(hosts(view?.layer) ? 1 : 0)")
                return
            }
            // actionState=<extension id>: what the extension set on its toolbar action, as Cra's buttons show it
            // (chrome.action.setTitle, setBadgeText; GitHub #106).
            if let id = dict["actionState"] {
                let state = ExtensionStore.shared.actions.state(extensionID: id, profile: "Default", tab: nil)
                CraLog.note("action state \(id): title=\(state.title) badge=\(state.badgeText) icon=\(state.icon == nil ? "manifest" : "set")")
                return
            }
            // httpsOnly=1|0: Settings ▸ Privacy's HTTPS-only switch, flipped while pages are open: Chromium takes the
            // change at once (#36: it crashed doing so once onboarding ended).
            // chromePref=<name>: the Default profile's Chrome pref as Chromium holds it now, as JSON (#625).
            // renameProfile=<name>[&profile=<id>]: Settings ▸ Profiles' rename, of Default unless an id is given (#666).
            if let name = dict["renameProfile"] {
                let id = dict["profile"].flatMap(UUID.init(uuidString:))
                store.renameProfile(id, to: name)
                CraLog.note("profile renamed: \(store.profileName(id))")
                return
            }
            // spellCheck=on|off: Settings ▸ Profiles' "Check spelling while typing" for the current space's profile (#715).
            if let v = dict["spellCheck"] {
                let path = store.profilePath(profile: store.focusedSpace(window: main.windowID).profileID)
                if v == "on" || v == "off" { SpellCheckSetting.set(v == "on", profilePath: path) }
                CraLog.note("spell check setting: \(SpellCheckSetting.isOn(profilePath: path) ? "on" : "off")")
                return
            }
            if let name = dict["chromePref"] {
                CraLog.note("chrome pref \(name): " + (CraCEFRuntime.preference(name, forProfile: nil) ?? "none"))
                return
            }
            if let v = dict["httpsOnly"] {
                store.settings.httpsOnly = v == "1"
                CraLog.note("https only: \(store.settings.httpsOnly ? "on" : "off")")
                return
            }
            // toolbar=out|in|sample|state: the floating toolbar (Settings ▸ Tabs), and where it is.
            if let command = dict["toolbar"] { CraLog.note(main.shell.debugToolbar(command)); return }
            // toolbarColor=<label>: the colour the first pane's bar is painted in (#629).
            if let label = dict["toolbarColor"] { CraLog.note(main.shell.toolbarColorReadout(label)); return }
            if let label = dict["toolbarHover"] { CraLog.note(main.shell.toolbarHoverReadout(label)); return }
            if let label = dict["findBar"] { CraLog.note(main.debugFindBar(label)); return }
            // chromiumDialogs=1: the Chromium dialogs showing and where (#349); chromiumDialogs=<button>: that
            // read, then the button with that title pressed (#484).
            // chromiumDialogMove=x,y: the dialog showing moved there, as Chromium moved one off every screen on
            // Nightly's runner (its main display at the top left, Cra's window on the display below).
            if let p = dict["chromiumDialogMove"]?.split(separator: ",").compactMap({ Double($0) }), p.count == 2 {
                CraLog.note(ChromiumDialogs.move(to: NSPoint(x: p[0], y: p[1])))
                return
            }
            if let button = dict["chromiumDialogs"] {
                CraLog.note(ChromiumDialogs.readout())
                if button != "1" { CraLog.note(ChromiumDialogs.press(button)) }
                return
            }
            // pageDialogs=<label>[&target=little][&fill=<a,b>][&press=<button>]: the windows Chromium shows for pages
            // (dialogs, bubbles, popups), where they sit against the page and what they say (PageDialogs).
            if let label = dict["pageDialogs"] {
                let little = dict["target"] == "little" ? littleWindows.last : nil
                let browser = little?.browser ?? main.currentBrowser
                CraLog.note(PageDialogs.readout(label, page: browser?.containerView, window: little?.window ?? main.window,
                                                press: dict["press"], fill: dict["fill"].map { $0.components(separatedBy: ",") }))
                return
            }
            // tabSharing=<label>[&hover=<part of a tab's URL>[&press=1]]: what calls share and Arc's marks for it
            // (TabSharing). hover hovers that tab's row as the pointer would; press clicks the "Share this tab instead"
            // it shows.
            // recordingDot=<label>: each shown tab row's recording dot (RecordingDot), by the tab's URL.
            if let label = dict["recordingDot"] {
                CraLog.note("recording dot \(label): " + main.recordingDotReadout()); return
            }
            if let label = dict["tabSharing"] {
                main.tabSharingReadout(label, hover: dict["hover"], press: dict["press"] == "1") { CraLog.note($0) }
                return
            }
            if let label = dict["switcherWindows"] {
                CraLog.note(SwitcherWindows.readout(label, main: main.window, little: littleWindows.compactMap(\.window))); return
            }
            // windowsMenu=<label>: the Window menu's window rows, which the Dock icon's menu lists too.
            if let label = dict["windowsMenu"] {
                CraLog.note(WindowsMenuRows.readout(label, main: main.window, little: littleWindows.compactMap(\.window))); return
            }
            if let label = dict["windowManagers"] {
                CraLog.note(WindowManagers.readout(label, main: main.window, little: littleWindows.compactMap(\.window))); return
            }
            if let g = dict["screenshotPick"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                let little = dict["target"] == "little"
                let window = little ? littleWindows.last?.window : main.window
                CraLog.note(ScreenshotPick.readout(of: window, named: little ? "little window" : "main window", at: CGPoint(x: g[0], y: g[1]))); return
            }
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
            // hitAt=x,y: the view a press there lands on, as the window's hit test finds it, and its superviews
            // (the toolbar's ← over where the hidden traffic lights were, #449). move=1: each says whether
            // a press on it may move the window (mouseDownCanMoveWindow, "+" or "-", #547).
            if let g = dict["hitAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2, let w = main.window,
               let root = w.contentView?.superview {
                var chain: [String] = []
                var v = root.hitTest(root.superview?.convert(NSPoint(x: g[0], y: w.frame.height - g[1]), from: nil)
                    ?? NSPoint(x: g[0], y: w.frame.height - g[1]))
                while let c = v, chain.count < 12 {
                    chain.append(String(describing: type(of: c)) + (dict["move"] == "1" ? (c.mouseDownCanMoveWindow ? "+" : "-") : ""))
                    v = c.superview
                }
                CraLog.note("hit at \(Int(g[0])),\(Int(g[1])): \(chain.isEmpty ? "nothing" : chain.joined(separator: " < "))")
                return
            }
            // clickToast=1: a click on the toast up now, through the event queue as the pointer's (#543).
            if dict["clickToast"] == "1" { main.clickToastForTest(); return }
            // toastShown=<label>: whether a toast is up in the front window (#543: a click leaves it up).
            if let label = dict["toastShown"] { CraLog.note("toast shown \(label): \(main.toastIsShown ? "yes '\(main.toastText)'" : "no")"); return }
            // dragAt=x,y&by=dx,dy: a press there moved by dx,dy (down is +) and released, through the event
            // queue as clickAt's click (#547); target=floating as for clickAt.
            if let g = dict["dragAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2,
               let d = dict["by"]?.split(separator: ",").compactMap({ Double($0) }), d.count == 2,
               let w = dict["target"] == "floating" ? main.floatingSidebar?.panelWindow : main.window {
                TestGesture.drag(from: NSPoint(x: g[0], y: w.frame.height - g[1]), by: NSPoint(x: d[0], y: -d[1]), in: w)
                return
            }
            // clickAt=x,y: a click there through the event queue, as the pointer's would go (#195);
            // target=little as for menuAt. button=back|forward: that mouse button released there,
            // handed to what the window's otherMouseUp monitor runs (#233); AppKit can't make a
            // window's event with button 3 or 4.
            // target=floating: the sidebar sliding out at the edge, in its own panel (#424).
            if let g = dict["clickAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2,
               let w = dict["target"] == "little" ? littleWindows.last?.window
                    : dict["target"] == "floating" ? main.floatingSidebar?.panelWindow
                    : dict["target"] == "historyMenu" ? main.backForwardMenu.content?.window : main.window {
                let point = NSPoint(x: g[0], y: w.frame.height - g[1])
                if let b = dict["button"], let button = ["back": MouseButtonSpaceSwitch.back, "forward": MouseButtonSpaceSwitch.forward][b] {
                    let taken = TestGesture.otherMouseUp(at: point, in: w).map { main.mouseButtonSwitchesSpace(button, $0) } ?? false
                    CraLog.note("mouse \(b) at \(Int(g[0])),\(Int(g[1])): \(taken ? "switched space" : "passed on")")
                    return
                }
                // button=middle: a middle click through the event queue, which the window's monitors see as
                // they see the mouse's: on a page it closes nothing, on a sidebar row it closes the tab (#208).
                if dict["button"] == "middle" {
                    let under = NSEvent.mouseEvent(with: .otherMouseUp, location: point, modifierFlags: [], timestamp: 0,
                                                   windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
                        .flatMap(SpaceListView.tabID(under:)).flatMap { store.item($0)?.displayTitle }
                    CraLog.note("middle click at \(Int(g[0])),\(Int(g[1])): \(under.map { "tab row \($0)" } ?? "no tab row")")
                    // probe=1: only what is under the point, no click.
                    if dict["probe"] != "1" { TestGesture.middleClick(at: point, in: w) }
                    return
                }
                // clicks=2: a double-click there (a favorite's Back to Pinned Page, #264); mods=<modifier
                // bits>: keys held through it (524288, Option: a link opens in Split View, #298);
                // button=right: a right-click (Back's history menu, #416). target=historyMenu: in that menu's window.
                TestGesture.click(at: point, in: w, clicks: dict["clicks"].flatMap(Int.init) ?? 1,
                                  modifiers: NSEvent.ModifierFlags(rawValue: dict["mods"].flatMap(UInt.init) ?? 0),
                                  right: dict["button"] == "right")
                return
            }
            if let st = dict["status"] { main.browserManager(statusMessage: st, tabID: nil); return }
            // linkPreview=<label>: what the link preview over the page shows (#689). linkPreviewKeys=<modifier
            // bits>: keys pressed or let go, as a flagsChanged event through the app's event queue.
            if let label = dict["linkPreview"] { CraLog.note(main.statusBubble?.readout(label) ?? "Cra link preview \(label): none"); return }
            if let bits = dict["linkPreviewKeys"].flatMap(UInt.init), let w = main.window {
                TestGesture.flags(NSEvent.ModifierFlags(rawValue: bits), in: w)
                return
            }
            // key=<characters>,<key code>,<modifier bits>: a key press as a layout reports it
            // (Turkish Q's ⌘- is "-",24,1048576), through the app's event queue (#212); the
            // characters are percent-encoded. zoomLevel logs the page's zoom. page=1 (devtools=1: its DevTools'): straight to the
            // current page, as the keyboard reaches a page that has it (a background copy has no key window);
            // with target=little, the newest Little Window's or Peek's page (#402).
            // appKey=<keyCode>: a key-down with no characters through the application's sendEvent:, the way a real key
            // comes in, to whatever has the keyboard (key=… goes to a window directly). #794: Eisu (102) and Kana (104).
            if let code = dict["appKey"].flatMap(UInt16.init), let w = NSApp.keyWindow {
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: w.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                            isARepeat: false, keyCode: code) {
                    CraLog.note("app key \(code) to \(String(describing: type(of: w.firstResponder ?? w)))")
                    NSApp.sendEvent(e)
                }
                return
            }
            if let k = dict["key"]?.split(separator: ",", omittingEmptySubsequences: false), k.count == 3,
               let code = UInt16(k[1]), let mods = UInt(k[2]), let w = main.window {
                let flags = NSEvent.ModifierFlags(rawValue: mods)
                if dict["page"] == "1" {
                    let little = dict["target"] == "little" ? littleWindows.last : nil
                    guard let page = little != nil ? little?.browser : main.currentBrowser else { NSLog("Cra TestGesture: no page"); return }
                    let w = little?.window ?? w
                    // devtools=1: the page's DevTools frontend has the keyboard (docked in the card, or its window).
                    let devTools = page.devToolsWindow
                    let roots: [NSView] = dict["devtools"] == "1"
                        ? [EmbeddedDevTools.holder(of: devTools).flatMap { $0.superview != nil ? $0 : nil } ?? devTools?.contentView].compactMap { $0 }
                        : [page.hostWindow?.contentView, page.containerView].compactMap { $0 }
                    TestGesture.pageKey(String(k[0]), keyCode: code, modifiers: flags, in: roots, window: w, fromKeyboard: dict["source"] == "keyboard")
                } else {
                    // The ⌘T bar, while it is open, has the keyboard; target=find sends it to the find bar's panel.
                    // target=popup: an extension's popup has the keyboard, as after a click in it (#727).
                    let target = dict["target"] == "popup" ? ExtensionPopupWindow.keyboardWindow
                        : dict["target"] == "find" ? main.debugFindPanel
                        : dict["target"] == "littleFind" ? littleWindows.last?.finder.debugPanel : main.openCommandPanel
                    // source=keyboard: typed on the keyboard (source process 0), not posted by an app as a mouse driver does (#714).
                    TestGesture.key(String(k[0]), keyCode: code, modifiers: flags, in: target ?? w, fromKeyboard: dict["source"] == "keyboard")
                }
                return
            }
            // flags=<modifier bits>: the modifier keys as they are now, as letting go of ⌘ after ⌘E posts it (#709).
            if let raw = dict["flags"].flatMap(UInt64.init) { TestGesture.flagsChanged(CGEventFlags(rawValue: raw)); return }
            // activate=1: Cra to the front with its window key, for a screen scenario that types (#424).
            if dict["activate"] == "1" { main.showWindow(nil); NSApp.activate(ignoringOtherApps: true); main.window?.makeKey(); return }
            // deactivate=1: Cra goes behind as when the user picks another app (Finder), its windows still on
            // screen (#511). NSApp.deactivate() alone sometimes left Cra the active app with no key window.
            if dict["deactivate"] == "1" {
                if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    NSApp.yieldActivation(to: finder)
                    finder.activate(from: .current, options: [])
                } else {
                    NSApp.deactivate()
                }
                return
            }
            // yieldTo=<pid>: Cra hands the front to that app, as when the user picks it: a scenario's `cover`, which
            // then brings Cra forward as for a link clicked in it (#607). macOS lets only the app in front do either.
            if let pid = dict["yieldTo"].flatMap({ Int32($0) }), let other = NSRunningApplication(processIdentifier: pid) {
                NSApp.yieldActivation(to: other)
                other.activate(from: .current, options: [])
                return
            }
            // secureInput=<label>: whether macOS Secure Input is on (it is for one app at a time, and it stops
            // every other app's global shortcuts), whether Chromium holds it for a page's password field, and
            // whether Cra is the app in front (#511).
            if let label = dict["secureInput"] {
                let held = CraCEFRuntime.responds(to: NSSelectorFromString("holdsSecureInput"))
                    ? (CraCEFRuntime.holdsSecureInput ? "1" : "0") : "?"
                CraLog.note("secure input \(label): system=\(IsSecureEventInputEnabled() ? 1 : 0) held=\(held) "
                    + "active=\(NSApp.isActive ? 1 : 0)")
                return
            }
            // keys=<label>: which window has the keyboard and what in it takes typed keys (#424).
            if let label = dict["keys"] {
                let key = NSApp.keyWindow
                let kind = key == nil ? "none" : key === main.window ? "window"
                    : key === main.floatingSidebar?.panelWindow ? "floating sidebar" : "other"
                let to = key?.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nothing"
                CraLog.note("keys \(label): \(kind), to \(to)\(NSApp.isActive ? "" : " (Cra inactive)")")
                return
            }
            if dict["zoomLevel"] != nil {
                let keys = main.window?.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nothing"
                CraLog.note("zoom level \(main.currentBrowser?.zoomLevel() ?? .nan), keys go to \(keys)")
                return
            }
            // Ask on Page (#393): askOnPage=<label> logs the card's state; ask=<question> opens ⌘F's
            // card and asks; askQuery=<text> types it and presses Return; askFindQuote=<n> presses the
            // last answer's nth Find on Page.
            if let label = dict["askOnPage"] { CraLog.note(main.askOnPage.readout(label)); return }
            // askTone=<label>: the card's appearance and the question's contrast on it (#408).
            if let label = dict["askTone"] { CraLog.note(main.askOnPage.toneReadout(label)); return }
            if let q = dict["ask"] { main.showFindBar(); main.askOnPage.ask(q); return }
            if let q = dict["askQuery"] {
                main.showFindBar()
                main.overlay.findQuery = q
                main.askOnPage.submit(shift: false)
                return
            }
            // instantLinks=<label>: the Instant Links row and the last run, as one line (#407).
            if let v = dict["instantLinksSetting"] { store.settings.instantLinks = v == "on"; return }
            // editAddressInPlace=on|off: Settings ▸ Tabs ▸ "Edit the address in place" switched (#344).
            if let v = dict["editAddressInPlace"] { store.settings.editAddressInPlace = v == "on"; return }
            // pageMarginSetting=<points>: Settings ▸ Pages ▸ Margin moved to that value, as the slider does (Ideas #366).
            if let v = dict["pageMarginSetting"].flatMap(Double.init) { store.settings.pageMargin = v; return }
            // nowPlayingTint=arc|theme: Settings ▸ Tabs ▸ "Player in the space's colour" switched (Ideas #366).
            if let v = dict["nowPlayingTint"].flatMap(NowPlayingTint.init(rawValue:)) { store.settings.nowPlayingTint = v; return }
            // nowPlayingStyle=arc|island: Settings ▸ Tabs ▸ "Player with artwork" switched (Discussion #761).
            if let v = dict["nowPlayingStyle"].flatMap(NowPlayingStyle.init(rawValue:)) { store.settings.nowPlayingStyle = v; return }
            // sidebarSide=left|right: Settings ▸ Sidebar on the right, as its switch sets it (#464).
            if let v = dict["sidebarSide"].flatMap(SidebarSide.init(rawValue:)) { store.settings.sidebarSide = v; return }
            if let v = dict["instantLinksFail"] {
                InstantLinksService.failsOnPurpose = v == "plan"
                InstantLinksService.modelFailsOnPurpose = v == "model"
                return
            }
            if dict["instantLinksDismiss"] != nil { InstantLinksService.shared.dismissFailed(); return }
            if let label = dict["instantLinks"] {
                CraLog.note("Cra " + InstantLinksService.shared.readout(label, store: store, space: store.focusedSpaceID(window: main.windowID)))
                return
            }
            if let n = dict["askFindQuote"].flatMap(Int.init) { main.askOnPage.debugFindQuote(n); return }
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
            // outlookPreview=mail|calendar|signedOut&unread=<n>: an Outlook favorite's card; notionCalendarPreview=1: Notion Calendar's.
            if let which = dict["outlookPreview"], let w = main.window {
                FavoritePreviewCard.shared.demoOutlook(which, unread: dict["unread"].flatMap(Int.init) ?? 3, in: w); return
            }
            if dict["notionCalendarPreview"] != nil, let w = main.window { FavoritePreviewCard.shared.demoNotionCalendar(in: w); return }
            // hiddenPageSignIn=<url>: a hidden page as Outlook's reader makes one; an address with "sign-in" in it
            // answers from inside the page's address change, and the answer closes the page, as OutlookClient does.
            if let url = dict["hiddenPageSignIn"] {
                var page: HiddenPage?
                page = HiddenPage(url: url, profilePath: nil, watch: { _, _ in nil }, isSignIn: { $0.contains("sign-in") }) { answer in
                    NSLog("Cra hidden page answered %@", answer ?? "nothing")
                    page?.close()
                    page = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSLog("Cra hidden page closed") }
                }
                return
            }
            // pageState=<label>: "page state <label>: committed=… loading=…" for the window's shown page (#817: a frame
            // loading after the page doesn't make it uncommitted).
            if let label = dict["pageState"] {
                let b = main.currentBrowser
                CraLog.note("page state \(label): committed=\(b?.hasCommittedLoad == true ? 1 : 0) loading=\(b?.isLoading == true ? 1 : 0)")
                return
            }
            // hiddenPageScript=<url>[&profile=<folder>]: a hidden page as Live Calendar's reader makes one (#817), in that profile: it runs a script once the
            // page has loaded and logs "hidden page script answered <host> after <s> s", or nothing after 25 s.
            if let url = dict["hiddenPageScript"] {
                var page: HiddenPage?
                let started = Date()
                let profilePath = dict["profile"].map { AppPaths.chromiumCache.appendingPathComponent($0, isDirectory: true).path }
                page = HiddenPage(url: url, profilePath: profilePath, script: "Promise.resolve(location.host || 'none')") { answer in
                    CraLog.note("hidden page script answered \(answer ?? "nothing") after \(Int(Date().timeIntervalSince(started))) s")
                    page?.close()
                    page = nil
                }
                return
            }
            // recentPages=<linear|notion|figma|confluence>&pages=<n>: that site's recent pages card (n = 0: Arc's empty line).
            if let site = dict["recentPages"].flatMap(RecentPagesPreview.Site.init(rawValue:)), let w = main.window {
                FavoritePreviewCard.shared.demoRecentPages(site, count: dict["pages"].flatMap(Int.init) ?? 6, in: w); return
            }
            // PR scenario: persist the checkbox across relaunch, and read the real panel.
            if let value = dict["pullRequestPreviews"] { store.settings.pullRequestPreviews = value == "1"; return }
            if let label = dict["previewShown"] {
                CraLog.note("preview card \(label): \(FavoritePreviewCard.shared.isShown ? "shown" : "none")"); return
            }
            // previewDismiss=1: the card goes, as when the pointer leaves it.
            if dict["previewDismiss"] != nil { FavoritePreviewCard.shared.dismiss(animated: false); return }
            // boostZap=1|0: Boost editor's Zap on or off for the open page.
            if let z = dict["boostZap"] { main.debugZap(z == "1"); return }
            // zapHover=<cell>|-1, zapUnzap=<cell>, zapPress=this|related|cancel: the Zap shelf and
            // its popover without the pointer; each logs "zap shelf: cells=… hint=…".
            if dict["zapHover"] != nil || dict["zapUnzap"] != nil || dict["zapPress"] != nil {
                main.debugZapShelf(hover: dict["zapHover"].flatMap(Int.init), unzap: dict["zapUnzap"].flatMap(Int.init), press: dict["zapPress"])
                return
            }
            // boostPick=1|0|copyThis|copyRelated|zapRelated: the code panel's eyedropper on (the
            // menu answered with that action) or off.
            if let p = dict["boostPick"] { main.debugPick(p); return }
            // boostType=<text>: the Code panel's editor clicked and typed into (#478).
            if let t = dict["boostType"] { BoostEditorController.shared.debugType(t); return }
            // boostAdvanced=1|0 (dark=1: in Dark Mode): the editor's Advanced color controls popover (#478).
            if let a = dict["boostAdvanced"] { BoostEditorController.shared.debugAdvanced(a == "1", dark: dict["dark"] == "1"); return }
            // boostFonts=1: how far each font cell's "Aa" sits from the cell's middle (#478).
            if dict["boostFonts"] != nil { BoostFontCell.debugMeasure(); return }
            // capturePick=x,y (deeper=1: ⌥ held): what Capture's click would take there (#451).
            if let g = dict["capturePick"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                main.debugCapturePick(at: NSPoint(x: g[0], y: g[1]), deeper: dict["deeper"] == "1"); return
            }
            // captureMenu=<typed>&run=<row>: the capture menu beside a capture of the page, <typed> in its
            // field; cra.log lists its rows, then the row titled <row> is chosen.
            if let typed = dict["captureMenu"] { main.debugCaptureMenu(typed: typed == "-" ? "" : typed, run: dict["run"]); return }
            // easels=list: the easels Library ▸ Easels and the capture menu list, the latest edited first;
            // easels=open (as=<label>): what the open easel shows and what its file holds; easels=tiles: how many
            // tiles Library ▸ Easels shows.
            if let what = dict["easels"] {
                if what == "tiles" {
                    // The tiles Library ▸ Easels shows now.
                    func count(in view: NSView) -> Int {
                        (view is EaselTile && !view.isHiddenOrHasHiddenAncestor ? 1 : 0) + view.subviews.reduce(0) { $0 + count(in: $1) }
                    }
                    CraLog.note("easel tiles: \(main.window?.contentView.map(count(in:)) ?? 0)")
                } else if what == "open", let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                    let id = canvas.document.id
                    // as=<label> names the line, for a scenario that reads the easel more than once (#680).
                    CraLog.note("easel open\(dict["as"].map { " " + $0 } ?? ""): shown=\(canvas.document.items.count) saved=\(EaselFiles.load(id).items.count) title=\(canvas.document.title)")
                } else {
                    let all = EaselFiles.all()
                    CraLog.note("easels listed: \(all.count) titles=\(all.map(\.title).joined(separator: "|"))")
                }
                return
            }
            // captureToEasel=1: the page's screenshot, then the capture menu's New Easel.
            if let how = dict["captureToEasel"] { main.debugCaptureToEasel(send: how == "send"); return }
            // easelLive=<s>: the open easel's first capture shows the live website; <s> seconds later
            // cra.log says what it holds and how many pictures of the page reached the card.
            if let wait = dict["easelLive"].flatMap(Double.init), let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.debugLive(after: wait); return
            }
            // easelDraw=1: one of each shape on the open easel, as its tools draw them (clips, snapshots).
            if dict["easelDraw"] != nil, let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.sheetView.debugDraw(); return
            }
            // easelCanvas=<x>,<y>|-: the open easel scrolled to a canvas point; cra.log says its zoom, view and extent (#580).
            if let target = dict["easelCanvas"], let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.debugCanvas(target); return
            }
            // easelTextColor=<shade>: the open easel's first text (one is added if there is none) picked and given
            // that colour from the picker; cra.log says whether the picker showed over it and the text's ink (#658).
            if let name = dict["easelTextColor"], let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                CraLog.note("easel text color \(name): " + canvas.sheetView.debugTextColor(name)); return
            }
            // easelPick=<n>: the open easel's n-th item (from 0) picked; cra.log says what shows over it and its menu.
            if let n = dict["easelPick"].flatMap(Int.init), let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.debugPick(n); return
            }
            // easelTool=<key>&hover=<tool>: a tool's key pressed on the open easel and the pointer over a
            // toolbar button; cra.log says which tool is picked and which letters show.
            if let key = dict["easelTool"], let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.debugTool(key: key, hover: dict["hover"]); return
            }
            // libraryHover=1|0: the pointer on the sidebar's Library button, or gone; cra.log says where its
            // glyph was drawn once at rest and in how many frames it got there (#608).
            if let on = dict["libraryHover"] {
                guard let library = main.sidebarUI.libraryAnchor as? LibraryButtonView else { CraLog.note("library glyph: none"); return }
                library.debugHover(on == "1") { CraLog.note("library glyph: \($0)") }
                return
            }
            // libraryRail=<page>[&hover=1|0][&press=1|0]&as=<label>: the pointer on that page's tile of the
            // Library's rail or gone, the button down or up; a second later cra.log says, under that label,
            // which frame its icon rests on and in how many it got there since it was picked, and the tile's
            // colours and wash.
            // libraryBack=1: the Library rail's back arrow, as its click sends it (#726).
            if dict["libraryBack"] != nil {
                let pressed = (main.shell.sidebarHost as? SidebarView)?.debugLibraryBack() == true
                CraLog.note("library back arrow: \(pressed ? "pressed" : "no library")")
                return
            }
            if let name = dict["libraryRail"] {
                guard let page = LibraryPage(rawValue: name), let sidebar = main.shell.sidebarHost as? SidebarView else {
                    CraLog.note("library rail: none"); return
                }
                let label = dict["as"] ?? ""
                sidebar.debugLibraryRail(page: page, hover: dict["hover"].map { $0 == "1" }, press: dict["press"].map { $0 == "1" }) {
                    CraLog.note("library rail \(label): \($0)")
                }
                return
            }
            // easelTileHover=1|0: the pointer over Library ▸ Easels' first tile, or gone; cra.log says
            // how large it is drawn and how bright its backing is.
            if let on = dict["easelTileHover"] {
                func first(in view: NSView) -> EaselTile? {
                    if let tile = view as? EaselTile, !tile.isHiddenOrHasHiddenAncestor { return tile }
                    for sub in view.subviews { if let found = first(in: sub) { return found } }
                    return nil
                }
                guard let tile = main.window?.contentView.flatMap(first(in:)) else { CraLog.note("easel tile: none"); return }
                tile.debugHover(on == "1") { CraLog.note("easel tile: \($0)") }
                return
            }
            // easelLink=<url>: the open easel gets a link card for <url>, as a paste does; cra.log says what it read.
            if let url = dict["easelLink"], let canvas = (main.currentBrowser as? EaselBrowser)?.canvasView {
                canvas.debugLink(url); return
            }
            // mcpAnswer=allow|deny: answers MCP's open "Let … use Cra?" prompt (test copies).
            if let answer = dict["mcpAnswer"] { MCPServer.shared.answerPrompt(allow: answer == "allow"); return }
            // mcpScripts=on|off: Settings ▸ Advanced ▸ Let agents run JavaScript in pages.
            if let scripts = dict["mcpScripts"] { MCPServer.shared.allowsScripts = scripts == "on"; return }
            // mcpHistory=on|off: Settings ▸ Advanced ▸ Let agents read your history.
            if let history = dict["mcpHistory"] { MCPServer.shared.allowsHistory = history == "on"; return }
            // mcpStop=1: the latest pill's Stop (that agent disconnects, MCP stays on).
            if dict["mcpStop"] != nil { MCPServer.shared.stopLatestPill(); return }
            // mcpPill=open|close|takeover: a click on the pill's face (opens the whole pill), on its ×, or ⌘.
            if let part = dict["mcpPill"] { main.pressAgentPill(part); return }
            // mcpWatched=on|off: a shown tab counts as watched even while its window is covered.
            if let watched = dict["mcpWatched"] { MainWindowController.agentTabsWatchedUnseen = watched == "on"; return }
            // translatePrompts=never:<host>|block:<lang>|reset|state[&profile=<name>][&label=<label>]: Settings ▸
            // Advanced ▸ Reset Translated-site Prompts and the translate choices it forgets, in every profile.
            if let t = dict["translatePrompts"] {
                TranslatedSitePrompts.debug(t, profile: dict["profile"], label: dict["label"] ?? t, store: store)
                return
            }
            // settingsPane=max: Settings opened on that tab (the old pane names open the tab that holds them).
            if let p = dict["settingsPane"].flatMap(SettingsTab.init(pane:)) {
                showSettingsWindow(on: p)
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
            // extensionRemove=<id>[&profile=<folder>]: Remove from Cra as its menu row does once the dialog says Remove
            // (#695), the menu being that profile's (default: the window's space's).
            if let id = dict["extensionRemove"] {
                let profile = dict["profile"] ?? store.profileDirectoryName(space: main.focusedSpace.id)
                if let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) { ExtensionsMenu.remove(e, profile: profile) }
                // Chromium's own record of the profile's extensions, and Cra's list.
                let chromium = CraCEFRuntime.extensionSettings(forProfile: ExtensionStore.profilePath(profile))?.contains(id) == true
                let cra = ExtensionStore.shared.entries.contains { $0.extensionID == id }
                CraLog.note("extension remove \(id.prefix(8)): in chromium=\(chromium ? 1 : 0) in cra=\(cra ? 1 : 0)")
                return
            }
            // engineUninstall=<id>&profile=<folder>: the engine asked straight away to uninstall it from that profile, whether
            // or not the profile has it (crash-extension-remove-other-profile).
            if let id = dict["engineUninstall"] {
                let profile = dict["profile"] ?? "Default"
                let removed = CraCEFRuntime.responds(to: #selector(CraCEFRuntime.uninstallExtension(_:profilePath:)))
                    && CraCEFRuntime.uninstallExtension(id, profilePath: ExtensionStore.profilePath(profile))
                CraLog.note("engine uninstall \(id.prefix(8)) from \(profile): removed=\(removed ? 1 : 0)")
                return
            }
            // currentSpace=<label>: the window's space and the profile its pages use, so a scenario set up with spaces on
            // other profiles shows it really ran there (#621's scenarios ran on Default while their seed didn't load).
            if let label = dict["currentSpace"] {
                let space = main.focusedSpace
                CraLog.note("current space \(label): \(space.title) profile=\(main.store.profileName(space.profileID))")
                return
            }
            // extensionMenu=<id>: the toolbar's right-click menu for that pinned extension (#695); press=<row> chooses one,
            // submenu=<row> lists (and presses in) that row's submenu instead.
            if let id = dict["extensionMenu"], let bar = main.shell.paneCards.first?.toolbarHost as? PaneToolbarView {
                CraLog.note("extension menu \(dict["label"] ?? id): " + bar.debugExtensionMenu(id, press: dict["press"], submenu: dict["submenu"]))
                CraLog.note("extension pinned \(dict["label"] ?? id): \(ExtensionStore.shared.pinnedIDs(inProfile: "Default").contains(id) ? 1 : 0)")
                // Which of the menu's pages the selected tab is now, not its address (cra.log keeps no addresses).
                let url = main.store.selectedTabID(window: main.windowID).flatMap { main.store.item($0)?.tab?.url } ?? ""
                let options = ExtensionStore.shared.entries.first { $0.extensionID == id }?.optionsPath.map { ExtensionActionMenu.optionsPage(id: id, path: $0) }
                let page = url == ExtensionActionMenu.managePage(id: id) ? "manage" : url == options ? "options"
                    : url == ExtensionActionMenu.webPermissionsPage(id: id) ? "webPermissions" : "other"
                CraLog.note("extension tab \(dict["label"] ?? id): \(page)")
                return
            }
            // spaceGradient=<label>: the window's space gradient axis and colour count (#669).
            if let label = dict["spaceGradient"] {
                func find(_ v: NSView) -> PagedGradientView? {
                    if let g = v as? PagedGradientView { return g }
                    for c in v.subviews { if let g = find(c) { return g } }
                    return nil
                }
                let g = main.window?.contentView.flatMap(find)
                CraLog.note("space gradient \(label): " + (g?.debugReadout ?? "none"))
                return
            }
            // extensionList=<label>[&window=incognito]: the extensions the window's Extensions menu and
            // toolbar offer (in incognito, only those allowed there, #620), or the newest incognito window's.
            if let label = dict["extensionList"] {
                let target = dict["window"] == "incognito" ? mainWindows.last(where: \.isIncognito) : main
                guard let target else { CraLog.note("extension list \(label): no window"); return }
                ExtensionStore.shared.reload()
                let names = target.extensionEntries.map(\.name).sorted().joined(separator: ", ")
                CraLog.note("extension list \(label): incognito=\(target.pageIsIncognito ? 1 : 0) [\(names)]")
                return
            }
            // extensionProfiles=<label>: the line Settings ▸ Extensions shows under each extension, which profiles have it
            // (discussion #595).
            if let label = dict["extensionProfiles"] {
                ExtensionStore.shared.reload()
                let profiles = [("Default", store.profileName(nil))] + store.profiles.map { ($0.directoryName, $0.name) }
                for e in ExtensionStore.shared.entries {
                    CraLog.note("extension profiles \(label): \(e.extensionID) \(ExtensionStore.shared.profilesLine(for: e, profiles: profiles))")
                }
                return
            }
            // shareExtension=<id>[&profile=<folder>&included=0|1], stopSharing=<id>, removeShared=<id>: what Settings ▸
            // Extensions does for a shared extension, past its confirmations (discussion #595).
            if let id = dict["shareExtension"] {
                ExtensionStore.shared.reload()
                guard let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) else {
                    CraLog.note("shared extension \(id): not installed"); return
                }
                if let profile = dict["profile"] {
                    ExtensionStore.shared.setShared(e, profile: profile, included: dict["included"] != "0")
                } else if let home = dict["home"] {
                    // &home=<folder>&with=<folder>,<folder>: Share across Profiles… (discussion #595's follow-up).
                    let with = (dict["with"] ?? "").split(separator: ",").map(String.init)
                    ExtensionStore.shared.share(e, from: home, with: with)
                } else {
                    ExtensionStore.shared.share(e)
                }
                return
            }
            // extensionOn=<id>&on=0|1: a shared extension's switch in Settings, for all its profiles.
            if let id = dict["extensionOn"], let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) {
                ExtensionStore.shared.setSharedOn(e, dict["on"] != "0")
                return
            }
            // extensionSections=<label>: Settings ▸ Extensions' sections and rows (discussion #595's follow-up).
            if let label = dict["extensionSections"] {
                ExtensionStore.shared.reload()
                let profiles = [("Default", store.profileName(nil))] + store.profiles.map { ($0.directoryName, $0.name) }
                let sections = ExtensionsLayout.sections(
                    items: ExtensionStore.shared.entries.map {
                        ExtensionsLayout.Item(id: $0.extensionID, name: $0.name, installedByChrome: $0.managedByChrome, profiles: $0.profiles)
                    },
                    shares: ExtensionStore.shared.shares, allProfiles: profiles.map(\.0),
                    names: Dictionary(profiles, uniquingKeysWith: { a, _ in a }))
                let text = sections.map { section in
                    section.title + " [" + section.rows.map { $0.id + ($0.profile.map { "@" + $0 } ?? "") }.joined(separator: ", ") + "]"
                }.joined(separator: "; ")
                CraLog.note("extension sections \(label): \(text)")
                for (id, home) in ExtensionStore.shared.shares.storageHomes(allProfiles: profiles.map(\.0)) {
                    CraLog.note("extension sections \(label): \(id) home \(home.home) on=\(ExtensionStore.shared.shares.isOn(id) ? 1 : 0)")
                }
                return
            }
            if let id = dict["stopSharing"] ?? dict["removeShared"],
               let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) {
                if dict["stopSharing"] != nil { ExtensionStore.shared.stopSharing(e) } else { ExtensionStore.shared.removeShared(e) }
                return
            }
            // removePage=<id>[&profile=<folder>]: Settings ▸ Extensions ▸ Remove… of a Web Store install, its
            // chrome://extensions page in a profile that has it, as Settings opens it (#842).
            if let id = dict["removePage"] {
                ExtensionStore.shared.reload()
                guard let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) else {
                    CraLog.note("extension removal \(id): not installed"); return
                }
                let folders = ExtensionRemoval.pageProfiles(installedIn: e.profiles, allProfiles: ExtensionStore.profileFolders)
                CraLog.note("extension removal \(id): pages in [\(folders.joined(separator: ", "))]")
                guard let folder = dict["profile"] ?? folders.first else { return }
                let window = useNormalWindow()
                openExtensionPage("chrome://extensions/?id=\(id)", window: window.windowID, profile: folder, singleton: true)
                return
            }
            if let id = dict["removeExtension"] {
                if let e = ExtensionStore.shared.entries.first(where: { $0.extensionID == id }) { ExtensionStore.shared.remove(e) }
                return
            }
            // fullscreen=state&label=<l>: whether the window is in full screen and what windows.json
            // keeps for it (#426).
            if dict["fullscreen"] == "state", let w = main.window {
                let saved = store.window(main.windowID).fullScreen
                CraLog.note("fullscreen \(dict["label"] ?? "state"): window=\(w.styleMask.contains(.fullScreen) ? 1 : 0) saved=\(saved ? 1 : 0)")
                return
            }
            if let v = dict["fullscreen"], let w = main.window, (v == "1") != w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); return }
            if let spec = dict["snapshot"], let out = dict["out"] { ViewSnapshot.write(spec, in: main.window, to: out); return }
            // newTabRow=<label> (#788): "new tab row <label>: fill=… ink=… lifted=… hovered=…", how the sidebar's New Tab
            // row draws now (NewTabRowView.debugLook).
            if let label = dict["newTabRow"] {
                let row = ViewSnapshot.find("NewTabRowView", in: main.window) as? NewTabRowView
                CraLog.note("new tab row \(label): \(row?.debugLook ?? "none")")
                return
            }
            // hover=TabRowView,1: that sidebar row hovered as if the pointer were on it (snapshots of
            // hover-only controls, #243) until the pointer moves or the sidebar changes. The URL pill
            // and favorite tiles take it too (#293), and the space dock's cells (#252).
            if let spec = dict["hover"] {
                switch ViewSnapshot.find(spec, in: main.window) {
                case let row as SidebarRowView: row.list?.debugHover(row)
                case let pill as SidebarURLPill: pill.debugHover()
                case let tile as FavoriteTileView: tile.debugHover()
                case let cell as SpaceCellView: (cell.superview as? SpaceDockView)?.debugHover(cell)
                default: CraLog.note("hover: no visible \(spec)")
                }
                return
            }
            // pointerOn=<text>&label=<l>: the pointer brought to the middle of the first sidebar tab row (or,
            // with tile=1, favorite tile) whose title has that text, in any space, as AppKit brings it: entered
            // and moved for every sidebar tracking area whose rect holds it, wherever the row is. Logs whether
            // that spot is in the window, what the row's list (or the tile) hovered, and whether the tip
            // controller counts the pointer as on it (tip=1). A row or tile of a space beside the shown one
            // lies under the page; it took the hover and showed its tip there by the pointer (#527).
            if let title = dict["pointerOn"], let window = main.window {
                let label = dict["label"] ?? title
                func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
                let host = main.shell.sidebarHost
                // under=downloads (#770): the pointer on the open Library downloads' first row, and the tab row under it.
                let underDownloads = dict["under"] == "downloads" ? (main.sidebarUI.downloadsTray as? DownloadsTrayView)?.debugFirstRowInWindow : nil
                let found: (any ArcTooltipTarget & NSView)? = if let at = underDownloads {
                    all(host).compactMap { $0 as? TabRowView }.first { $0.window != nil && $0.convert($0.bounds, to: nil).contains(at) && !$0.isHiddenOrHasHiddenAncestor }
                } else if dict["tile"] == "1" {
                    all(host).compactMap { $0 as? FavoriteTileView }.first { $0.text.contains(title) }
                } else {
                    all(host).compactMap { $0 as? TabRowView }.first { $0.text.contains(title) }
                }
                guard let row = found else {
                    CraLog.note("pointer on \(label): no \(dict["tile"] == "1" ? "tile" : "row") \(dict["under"].map { "under \($0)" } ?? title)")
                    return
                }
                let p = underDownloads ?? row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
                let inWindow = window.contentView.map { $0.bounds.contains($0.convert(p, from: nil)) } ?? false
                let time = ProcessInfo.processInfo.systemUptime
                for view in all(host) {
                    for area in view.trackingAreas {
                        let rect = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
                        guard view.convert(rect, to: nil).contains(p), let owner = area.owner as? NSResponder else { continue }
                        if area.options.contains(.mouseEnteredAndExited),
                           let e = NSEvent.enterExitEvent(with: .mouseEntered, location: p, modifierFlags: [], timestamp: time,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                          trackingNumber: 0, userData: nil) {
                            owner.mouseEntered(with: e)
                        }
                        if area.options.contains(.mouseMoved),
                           let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: time,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                      clickCount: 0, pressure: 0) {
                            owner.mouseMoved(with: e)
                        }
                    }
                }
                let hovered: String
                switch row {
                case let r as TabRowView: hovered = r.list?.debugHoveredTitle ?? "none"
                case let t as FavoriteTileView: hovered = t.debugHovering ? t.text : "none"
                default: hovered = "none"
                }
                let tip = ArcTooltipController.ownsTip(row, at: window.convertPoint(toScreen: p))
                CraLog.note("pointer on \(label): in window=\(inWindow ? 1 : 0) hovered=\(hovered) tip=\(tip ? 1 : 0)")
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
            // favoriteBadges=<label>: the favorite tiles wearing a Peek's favicon badge, in grid order,
            // with the badge's frame in the tile and how far it sticks out past the tile's right edge (#381).
            if let label = dict["favoriteBadges"] {
                var tiles: [FavoriteTileView] = []
                func collect(_ v: NSView) {
                    if let t = v as? FavoriteTileView, !t.isHiddenOrHasHiddenAncestor { tiles.append(t) }
                    v.subviews.forEach(collect)
                }
                main.window?.contentView.map(collect)
                tiles.sort { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
                let badges = tiles.enumerated().compactMap { i, t in t.peekBadgeReadout.map { "tile\(i + 1) \($0)" } }
                NSLog("Cra favorite badges %@: %@", label, badges.isEmpty ? "none" : badges.joined(separator: ", "))
                return
            }
            // minimize=1: Window ▸ Minimize Window as ⌘M runs it (performMiniaturize, which AppKit refuses
            // when the minimize button can't take a click: alpha 0, or hidden lights out of the window, #449).
            if dict["minimize"] == "1", let w = main.window {
                w.performMiniaturize(nil)
                return
            }
            // frameAfterMove=1: the window server's report of a drag onto another display.
            if dict["frameAfterMove"] != nil, let w = main.window as? CraWindow {
                CraLog.note(w.frameAfterMoveReadout())
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
            // appLinkOwnedByCra=<scheme>: Cra stands as the Mac's app for it (#821; AppLinkPrompt).
            if let scheme = dict["appLinkOwnedByCra"] {
                AppLinkPrompt.debugSchemesOwnedByCra = scheme.isEmpty ? [] : [scheme.lowercased()]
                return
            }
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
            // littleShown=<label>: the newest Little Window's "Open in" space, page profile, its address
            // pill's padlock and text (#330), and how many browser windows are in front of it on screen (#500).
            // littleCommit=<typed>: the newest Little Window's command bar commits its "Switch to"
            // row for what was typed, as ↩ on it does (#316).
            if let typed = dict["littleCommit"] { littleWindows.last?.debugCommit(typed); return }
            // littleProfile=<name>: the newest Little Window's page moved to the profile of that name
            // ("Default"), as a pick in its address pill's menu with "Don't ask again" on.
            if let name = dict["littleProfile"] { littleWindows.last?.debugChangeProfile(named: name); return }
            // littleKey=<n>: the nth Little Window (oldest first) picked as Mission Control picks one (#581);
            // littleOrder=<label>: Cra's browser and Little Windows, front to back, as the window server has them.
            if let n = dict["littleKey"].flatMap(Int.init), littleWindows.indices.contains(n) { littleWindows[n].debugPick(); return }
            // mainFrame=x,y,w,h / littleFrame=x,y,w,h: the browser window or the newest Little Window placed at that
            // frame, in points from the top left of its screen's visible area, so a scenario can keep them apart
            // (#659). littleClose=point: where the newest Little Window's close button is, in the top-left screen
            // points scenario.sh's `click` uses: "little close point: <x> <y>".
            if let spec = dict["mainFrame"] ?? dict["littleFrame"] {
                let n = spec.split(separator: ",").compactMap { Double($0) }
                let target = dict["mainFrame"] != nil ? main.window : littleWindows.last(where: { !$0.isPeek })?.window
                if n.count == 4, let w = target, let screen = w.screen ?? NSScreen.main {
                    let v = screen.visibleFrame
                    w.setFrame(NSRect(x: v.minX + n[0], y: v.maxY - n[1] - n[3], width: n[2], height: n[3]), display: true)
                }
                return
            }
            if dict["littleClose"] != nil {
                guard let w = littleWindows.last(where: { !$0.isPeek })?.window, let button = w.standardWindowButton(.closeButton),
                      let top = NSScreen.screens.first?.frame.maxY else { CraLog.note("little close point: none"); return }
                let r = w.convertToScreen(button.convert(button.bounds, to: nil))
                CraLog.note("little close point: \(Int(r.midX)) \(Int(top - r.midY))")
                return
            }
            // keyOnComingForward=1: the browser window made key the next time Cra comes forward, before the window
            // AppKit gives the keyboard back to, as AppKit does by itself at times (#659). &window=<n>: the nth browser
            // window (oldest first) instead, one other than the window in use.
            if dict["keyOnComingForward"] != nil {
                debugKeyOnComingForward = true
                debugKeyOnComingForwardWindow = dict["window"].flatMap(Int.init)
                    .flatMap { mainWindows.indices.contains($0) ? mainWindows[$0].window : nil }
                return
            }
            // littleFocus=<label> (#646, #641): whether Cra is the active app, which Little Window (oldest first) has
            // the keys, and how many other apps' windows are over the newest one
            // and (mainOver, #659) the browser window.
            // toolbarDoubleClick=<label> (#685): a double click on the focused page's toolbar where no button is, through the
            // app's event queue as a mouse sends it; cra.log says whether the window zoomed. toolbarDoubleClick=point
            // instead notes where that spot is on screen, top-left points, for scenario.sh's `click toolbar-empty`
            // ("toolbar empty point: <x> <y>"), and toolbarZoom=<label> whether the window has zoomed since.
            // pageTop=point (#685): where scenario.sh's `click page-top` presses, 5 pt into the focused page's top, a third
            // of the way across: "page top point: <x> <y>", top-left screen points. toolbarZoom then says whether it zoomed.
            // sidebarEmpty=point (#722): where scenario.sh's `click sidebar-empty` presses, in the docked sidebar's empty
            // space a third of the way up from its bottom, a spot only the sidebar itself takes: "sidebar empty point: <x> <y>".
            if dict["sidebarEmpty"] == "point" {
                let host = main.shell.sidebarHost
                guard let w = main.window, host.window === w, !host.isHidden, let frame = w.contentView?.superview,
                      let top = NSScreen.screens.first?.frame.maxY else {
                    CraLog.note("sidebar empty point: none"); return
                }
                let inWindow = host.convert(NSPoint(x: host.bounds.midX, y: host.isFlipped ? host.bounds.maxY - host.bounds.height / 3 : host.bounds.minY + host.bounds.height / 3), to: nil)
                let onScreen = w.convertPoint(toScreen: inWindow)
                let hit = frame.hitTest(frame.convert(inWindow, from: nil))
                CraLog.note("sidebar empty hit: \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                CraLog.note("sidebar empty point: \(Int(onScreen.x)) \(Int(top - onScreen.y))")
                return
            }
            if dict["pageTop"] == "point" {
                guard let card = main.shell.focusedCard, let w = main.window, let top = NSScreen.screens.first?.frame.maxY else {
                    CraLog.note("page top point: none"); return
                }
                toolbarDoubleClickFrame = w.frame
                let area = card.webArea.convert(card.webArea.bounds, to: nil)
                let onScreen = w.convertPoint(toScreen: NSPoint(x: area.minX + area.width / 3, y: area.maxY - 5))
                CraLog.note("page top point: \(Int(onScreen.x)) \(Int(top - onScreen.y))")
                return
            }
            if let label = dict["toolbarZoom"], let w = main.window {
                let before = toolbarDoubleClickFrame ?? w.frame
                CraLog.note("toolbar zoom \(label): zoomed=\(w.isZoomed ? 1 : 0) grew=\(w.frame.width > before.width + 1 || w.frame.height > before.height + 1 ? 1 : 0)")
                return
            }
            if let label = dict["toolbarDoubleClick"] {
                guard let bar = main.shell.focusedCard?.toolbarHost as? PaneToolbarView, let w = main.window,
                      let frameView = w.contentView?.superview else {
                    CraLog.note("toolbar double click \(label): no toolbar"); return
                }
                let y = bar.bounds.midY
                // The window's own hit test, not only the bar's: edge to edge the bar reaches the window's edge, where
                // AppKit's resize edge takes a double click (it grows the window to the screen's edge).
                let empty = stride(from: bar.bounds.maxX - 1, to: bar.bounds.minX, by: -4).first { x in
                    let p = bar.convert(NSPoint(x: x, y: y), to: nil)
                    return frameView.hitTest(frameView.convert(p, from: nil)) === bar
                }
                guard let x = empty else { CraLog.note("toolbar double click \(label): no empty spot"); return }
                let at = bar.convert(NSPoint(x: x, y: y), to: nil)
                let before = w.frame
                toolbarDoubleClickFrame = before
                if label == "point" {
                    let onScreen = w.convertPoint(toScreen: at)
                    guard let top = NSScreen.screens.first?.frame.maxY else { CraLog.note("toolbar empty point: none"); return }
                    CraLog.note("toolbar empty point: \(Int(onScreen.x)) \(Int(top - onScreen.y))")
                    return
                }
                for clicks in [1, 2] {
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) {
                            NSApp.postEvent(e, atStart: false)
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    CraLog.note("toolbar double click \(label): zoomed=\(w.isZoomed ? 1 : 0) grew=\(w.frame.width > before.width + 1 || w.frame.height > before.height + 1 ? 1 : 0)")
                }
                return
            }
            // littleOtherDesktop=<n> (#738): the n-th Little Window (oldest first, Peeks left out) counts as on another
            // desktop, as if opened there; a test copy can't make or switch desktops.
            if let n = dict["littleOtherDesktop"].flatMap(Int.init) {
                let lw = littleWindows.filter { !$0.isPeek }
                if lw.indices.contains(n) { lw[n].debugOnOtherDesktop = true }
                return
            }
            if let label = dict["littleFocus"] {
                var key = NSApp.keyWindow
                while let parent = key?.parent { key = parent }
                let lw = littleWindows.filter { !$0.isPeek }
                let i = lw.firstIndex { $0.window === key }
                let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                let over = lw.last?.window.map { String(LittleWindowRaise.othersOver($0.windowNumber, in: info)) } ?? "-"
                // mainOver (#659): other apps' windows over the browser window; 0 once it came forward.
                let mainOver = main.window.map { String(LittleWindowRaise.othersOver($0.windowNumber, in: info)) } ?? "-"
                let mainKey = key != nil && key === main.window ? 1 : 0
                CraLog.note("little focus \(label): active=\(NSApp.isActive ? 1 : 0) key=\(i.map { "little\($0)" } ?? (mainKey == 1 ? "main" : "none")) over=\(over) windows=\(lw.count) mainOver=\(mainOver)")
                return
            }
            if let label = dict["littleOrder"] {
                var names: [Int: String] = [:]
                for (i, m) in mainWindows.enumerated() { if let w = m.window { names[w.windowNumber] = "main\(i)" } }
                for (i, l) in littleWindows.enumerated() where !l.isPeek { if let w = l.window { names[w.windowNumber] = "little\(i)" } }
                let order = (NSWindow.windowNumbers(options: []) ?? []).compactMap { names[$0.intValue] }
                CraLog.note("little order \(label): \(order.joined(separator: " "))")
                return
            }
            // appActivated=1: AppKit's didBecomeActive, as when Cra comes forward (Mission Control's pick of a Little
            // Window, #581); a background test copy is refused the real thing.
            if dict["appActivated"] != nil { NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp); return }
            // littleActivation=<label>: whether the newest Little Window is a non-activating panel (its style and AppKit's
            // own flag, which the WindowServer goes by), and the kind of Space it is on (#581).
            if let label = dict["littleActivation"], let w = littleWindows.last(where: { !$0.isPeek })?.window {
                let prevents = (w as? LittleWindow)?.preventsActivation.map { $0 ? "1" : "0" } ?? "?"
                CraLog.note("little activation \(label): nonactivating=\(w.styleMask.contains(.nonactivatingPanel) ? 1 : 0) prevents=\(prevents) space=\(WindowSpaces.space(of: w))")
                return
            }
            // littleRow=<text>&typed=<text>: the newest Little Window's ⌘L bar picks the row for that page (#599).
            if let address = dict["littleRow"] { littleWindows.last?.debugPickRow(containing: address, typed: dict["typed"] ?? ""); return }
            // littleMenu=<step>: the newest Little Window's "Open in" menu, see debugMenu (#331).
            if let step = dict["littleMenu"] { littleWindows.last?.debugMenu(step); return }
            // littleFind=<label>: the newest Little Window's (or Peek's) find bar: shown, where on its page,
            // the keys, the search and the page's count (#577). key=…&target=littleFind types into it.
            // littleFindQuery=<text>: that text in its field, as typed (each change searches).
            if let q = dict["littleFindQuery"] { littleWindows.last?.finder.overlay.findQuery = q; return }
            if let label = dict["littleFind"] { CraLog.note(littleWindows.last?.finder.readout(label) ?? "little find \(label): no window"); return }
            // littleCard=<step>: the newest Little Window's card, see debugCardStep (#337).
            if let step = dict["littleCard"] { littleWindows.last?.debugCardStep(step); return }
            // littleToolbar=<command>: the newest Little Window's floating toolbar, see debugToolbar (#435).
            if let command = dict["littleToolbar"] { littleWindows.last?.debugToolbar(command); return }
            // deactivate=<label> (any but 1, which hands activation to Finder above): Cra stops being the
            // active app without bringing another one forward, so nothing of Cra's is key; then logs whether
            // the actions (⌘[, ⌘W…) still find the Little Window in front (keyLittleWindow's front-window
            // path, #495).
            if let label = dict["deactivate"] {
                NSApp.deactivate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    CraLog.note("deactivated \(label): active=\(NSApp.isActive ? 1 : 0) key=\(NSApp.keyWindow == nil ? 0 : 1) little=\(self.keyLittleWindow == nil ? 0 : 1)")
                }
                return
            }
            // littleBarSwipe=<label>&fingers=right|left[&points=n]: a two-finger swipe over the newest
            // Little Window's address bar (#495).
            if let label = dict["littleBarSwipe"] {
                littleWindows.last?.debugBarSwipe(label, fingersRight: dict["fingers"] != "left",
                                                  points: dict["points"].flatMap { Double($0) }.map { CGFloat($0) } ?? 120)
                return
            }
            // littleSwipeBack=<label>[&go=1]: what Chromium's two-finger swipe asks the newest Little
            // Window's page before a swipe back starts, and with go=1 what it does at the end (#495).
            if let label = dict["littleSwipeBack"] {
                let b = littleWindows.last?.browser
                let root = b?.hostWindow.flatMap { EmbeddedPages.pageViews(of: $0)?.last ?? $0.contentView } ?? b?.containerView
                CraLog.note("little swipe back \(label): \(root.map { ChromiumHistorySwipe.debugSwipeBack(in: $0, perform: dict["go"] == "1") } ?? "no window")")
                return
            }
            // inspectAt=x,y: Inspect in the page's right-click menu at that point of the page (the
            // newest Little Window's or Peek's with target=little); devToolsShown=<label>: where each
            // Little Window's and Peek's DevTools are, and whether the front tab has any (#348).
            if let g = dict["inspectAt"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                let b = dict["target"] == "little" ? littleWindows.last?.browser : main.currentBrowser
                b?.showDevToolsInspectingPoint(NSPoint(x: g[0], y: g[1]))
                return
            }
            // front=<label>: the Little Window that takes actions now (keyLittleWindow), and the windows in front-to-back
            // order (class, alpha, visible), for a test copy that has no key window.
            if let label = dict["front"] {
                let little = keyLittleWindow.flatMap { l in littleWindows.firstIndex { $0 === l } }.map { "little\($0)" } ?? "none"
                let order = NSApp.orderedWindows.prefix(6).map { w in
                    let name = littleWindows.contains { $0.window === w } ? "Little" : mainWindows.contains { $0.window === w } ? "Main"
                        : String(describing: type(of: w))
                    return "\(name)(a=\(w.alphaValue == 0 ? 0 : 1),v=\(w.isVisible ? 1 : 0))"
                }
                CraLog.note("front \(label): key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none") little=\(little) order=\(order.joined(separator: ","))")
                return
            }
            // devtoolsClick=1: a click in the middle of the current tab's docked DevTools (EmbeddedDevTools.debugClick).
            if dict["devtoolsClick"] != nil {
                if let holder = EmbeddedDevTools.holder(of: main.currentBrowser?.devToolsWindow), holder.superview != nil,
                   let page = main.currentBrowser?.containerView {
                    EmbeddedDevTools.debugClick(holder, page: page)
                }
                return
            }
            if let label = dict["devToolsShown"] {
                for (i, l) in littleWindows.enumerated() { CraLog.note("little devtools \(label): little\(i) \(l.debugDevTools)") }
                // drawn: the frontend draws in Cra's window, which then holds the layer its frames come in
                // (Chromium's CALayerHost, as under every page's view). Chrome drew it into its own (never
                // shown) DevTools window, and the card stayed white (#468).
                func drawn(_ layer: CALayer?) -> Int {
                    guard let layer else { return 0 }
                    let frames = layer.contents != nil || String(describing: type(of: layer)) == "CALayerHost"
                    return (frames ? 1 : 0) + (layer.sublayers ?? []).reduce(0) { $0 + drawn($1) }
                }
                // The engine's frontend docks in the card (EmbeddedDevTools): docked=1 when it is there, in the main
                // window itself (its own window out of sight), with the page's view over the room it left (smaller than
                // the frontend); side= where DevTools sit beside the page. undocked=1 when it is in a window of its own.
                // shellDock=1: the shell's own dock beside the page shows (white until a frontend covers it).
                let window = main.currentBrowser?.devToolsWindow
                let holder = EmbeddedDevTools.holder(of: window).flatMap { $0.superview != nil ? $0 : nil }
                let dev = holder ?? window?.contentView
                var docked = ""
                if let holder, let page = main.currentBrowser?.containerView, page.superview === holder.superview {
                    let h = holder.frame, p = page.frame
                    let split = p.width < h.width - 1 || p.height < h.height - 1
                    let inside = h.contains(p.insetBy(dx: 0.5, dy: 0.5)) && window?.isVisible != true && holder.window === main.window
                    let side = p.height < h.height - 1 ? (p.minY > h.minY + 0.5 ? "bottom" : "top")
                        : p.minX > h.minX + 0.5 ? "left" : "right"
                    docked = " docked=\(split && inside ? 1 : 0)" + (split ? " side=\(side)" : "")
                        + (EmbeddedDevTools.debugHits(holder, page: page).map { " hits=\($0)" } ?? "")
                    // focus=devtools: the frontend has the keys; key=main: Cra's window is the key one (none: a
                    // background test copy has no key window), not Chrome's hidden DevTools window.
                    let responder = main.window?.firstResponder as? NSView
                    let key = NSApp.keyWindow
                    let focus = responder.map { $0.isDescendant(of: holder) } == true ? "devtools"
                        : responder.map { $0.isDescendant(of: page) } == true ? "page" : "other"
                    docked += " focus=\(focus) key=\(key == nil ? "none" : key === main.window ? "main" : "other")"
                } else if window != nil {
                    docked = " docked=0 undocked=\(window?.isVisible == true && window?.styleMask.contains(.titled) == true ? 1 : 0)"
                }
                docked += " shellDock=\(main.shell.devToolsHost.isHidden ? 0 : 1)"
                // chromeKeyable=1: Chrome's own (hidden) DevTools window could take the keys from Cra's window.
                let hidden = NSApp.windows.filter { $0.title.hasPrefix("DevTools") && $0.alphaValue == 0 && $0 !== window }
                docked += " chromeKeyable=\(hidden.contains { $0.canBecomeKey } ? 1 : 0)"
                // chromeExposed=1: one of them is on screen as a window Mission Control and ⌘` would show (empty).
                docked += " chromeExposed=\(hidden.contains { $0.isVisible && !$0.collectionBehavior.contains(.transient) } ? 1 : 0)"
                // panel=: the panel the frontend last said it shows (DevToolsToggle.panel), - before it says one.
                docked += " panel=\(main.browsers.visibleRuntime?.devTools.panel ?? "-")"
                CraLog.note("tab devtools \(label): windows=\(littleWindows.count) open=\(main.currentBrowser?.hasDevTools == true ? 1 : 0)"
                    + (dev.map { " drawn=\(drawn($0.layer) > 0 ? 1 : 0)" } ?? "") + docked)
                return
            }
            if let label = dict["littleShown"] {
                var space = "-", profile = "-", shown = ""
                if let w = littleWindows.last {
                    w.refreshTarget()   // as when it takes focus
                    let state: LittleWindowState = w.state
                    space = store.space(state.targetSpaceID)?.title ?? "-"
                    profile = store.profileName(state.profileID)
                    shown = " \(w.debugCard) \(w.debugReadout)"
                    // The window server's order, front to back.
                    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                    let order = info.compactMap { $0[kCGWindowNumber as String] as? Int }
                    if let mine = w.window.flatMap({ order.firstIndex(of: $0.windowNumber) }) {
                        let browsers = Set(mainWindows.compactMap { $0.window?.windowNumber })
                        shown += " behind=\(order[..<mine].filter { browsers.contains($0) }.count)"
                    } else {
                        shown += " behind=-"
                    }
                    // over=<n>: other apps' windows still in front of the browser window and over it. A Little
                    // Window opened from another app left the browser window where it was; it rose over them (#607).
                    shown += " over=" + (main.window.map { String(LittleWindowRaise.othersOver($0.windowNumber, in: info)) } ?? "-")
                }
                CraLog.note("little shown \(label): windows=\(littleWindows.count) space=\(space) profile=\(profile)\(shown)")
                return
            }
            // windowState=<label>: each window's full screen, Space, traffic lights (#277), whether a
            // drag can move it (#308), where the page card sits in it (#315) and the loading bar over it (#548), whether
            // it floats (Stay On Top) and has a sheet open (#333), and which side its sidebar is on (#464). Lights are "hidden", or
            // their alpha; "-" when a window has none.
            // titleRow=<label>: how far each shown sidebar glyph in the traffic lights' row sits above (+) or below (−) the
            // lights' centre, in points, left to right (#876; Arc's toggle, ← → ↻ share the lights' centre).
            if let label = dict["titleRow"] {
                for (i, m) in mainWindows.enumerated() {
                    guard let w = m.window, let close = w.standardWindowButton(.closeButton), let content = w.contentView else { continue }
                    let lights = close.convert(close.bounds, to: nil).midY
                    func glyphs(_ v: NSView) -> [NSView] {
                        (v is SidebarGlyphButton && !v.isHiddenOrHasHiddenAncestor ? [v] : []) + v.subviews.flatMap(glyphs)
                    }
                    let row = glyphs(content).map { $0.convert($0.bounds, to: nil) }.filter { abs($0.midY - lights) < 12 }
                        .sorted { $0.minX < $1.minX }.map { String(format: "%+.1f", $0.midY - lights) }
                    CraLog.note("title row \(label): main\(i) glyphs=\(row.joined(separator: ","))")
                }
            }
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
                        + "lightsIn=\(lightsPlace(w)) card=\(m.shell.cardReadout) sidebar=\(m.shell.sidebarReadout) "
                        + "floating=\(m.floatingSidebar?.edgeReadout ?? "-") shadow=\(m.floatingSidebar?.shadowReadout ?? "-") "
                        + "onTop=\(flag(m.staysOnTop)) sheet=\(flag(w.attachedSheet != nil)) \(m.shell.loadingReadout) \(m.pageCornerReadout) "
                        + "frameAdjust=\(CraWindow.frameAdjustment)")
                }
                for (i, l) in littleWindows.enumerated() where !l.isPeek {
                    guard let w = l.window else { continue }
                    CraLog.note("window state \(label): little\(i) fullscreen=\(flag(w.styleMask.contains(.fullScreen))) "
                        + "primary=\(flag(w.collectionBehavior.contains(.fullScreenPrimary))) "
                        + "visible=\(flag(w.isVisible)) onSpace=\(flag(w.isOnActiveSpace)) lights=\(lights(w)) "
                        + "onTop=\(flag(w.level == .floating)) sheet=\(flag(w.attachedSheet != nil))")
                }
                if let w = settingsWindow {
                    CraLog.note("window state \(label): settings visible=\(flag(w.isVisible)) front=\(flag(settingsInFront)) "
                        + "tab=\(settingsController?.debugPane ?? "-") size=\(Int(w.frame.width))x\(Int(w.frame.height)) "
                        + "resizable=\(flag(w.styleMask.contains(.resizable))) onSpace=\(flag(w.isOnActiveSpace)) "
                        + "auxiliary=\(flag(w.collectionBehavior.contains(.fullScreenAuxiliary))) "
                        + "movesToActiveSpace=\(flag(w.collectionBehavior.contains(.moveToActiveSpace)))")
                }
                for (i, w) in NSApp.windows.filter({ CraCEFRuntime.isExtensionWindow($0) }).enumerated() {
                    CraLog.note("window state \(label): extension\(i) visible=\(flag(w.isVisible)) onSpace=\(flag(w.isOnActiveSpace)) "
                        + "auxiliary=\(flag(w.collectionBehavior.contains(.fullScreenAuxiliary))) "
                        + "movesToActiveSpace=\(flag(w.collectionBehavior.contains(.moveToActiveSpace))) "
                        + "primary=\(flag(w.collectionBehavior.contains(.fullScreenPrimary))) "
                        + "fullscreen=\(flag(w.styleMask.contains(.fullScreen))) title=\(w.title)")
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
                    // material: the one-colour sidebar's material, Arc's light or dark one (#455); "-" for other themes;
                    // glass-dark or glass-light with Settings ▸ Tabs ▸ Translucent sidebar (#366), for every theme.
                    let material = m.shell.glass ? "glass-" + side(!m.shell.solidLightMaterial)
                        : m.shell.solidBackdrop ? (m.shell.solidDarkGradient && !m.shell.solidLightMaterial ? "dark-gradient" : side(!m.shell.solidLightMaterial)) : "-"
                    // seeThrough: the window shows the blurred desktop under the sidebar, through the material
                    // (dark vibrant) or the backdrop layer (light vibrant, one colour), not an opaque fill (#643).
                    // ground: the backdrop layer's flat grey (0–255) while it draws no capture, an inactive window's (#876);
                    // "blur:<b>/<w>" while it blurs, the material over a black and a white backdrop (#876); "tint" in
                    // full screen, "-" off the layer path.
                    let ground = m.shell.drawnBackdrop.map { b -> String in
                        switch b.source {
                        case .none: return String(format: "%.0f", 255 * b.liftTop)
                        case .blur: return String(format: "blur:%.0f/%.0f", 255 * b.liftTop, 255 * ((1 - b.dim) * (1 - b.liftTop) + b.liftTop))
                        case .desktopTint: return "tint"
                        }
                    } ?? "-"
                    NSLog("Cra theme shown %@: space=%@ follows=%d theme=%@ shell=%@ sidebar=%@ library=%@ material=%@ seeThrough=%d vibrant=%d intensity=%.2f active=%d ground=%@",
                          label, space.title, space.theme.followsSystem ? 1 : 0,
                          side(space.theme.shown.isDark), side(m.shell.isDarkTheme), drawn, m.sidebarUI.libraryPage.map { "\($0)" } ?? "-", material,
                          m.window?.isOpaque == false && !(m.shell.vibrancy.isHidden && m.shell.backdropHost.isHidden) ? 1 : 0,
                          space.theme.shown.vibrant ? 1 : 0, space.theme.shown.intensity, m.shell.windowActive ? 1 : 0, ground)
                }
                return
            }
            // commandBarPick=<text>: the browser window's open bar commits its first row whose address holds
            // <text>, as ↩ on that row does (#645); logs the row's kind.
            if let text = dict["commandBarPick"] {
                guard let row = main.commandBar.result.items.first(where: { $0.url?.contains(text) == true }) else {
                    CraLog.note("command bar pick \(text): none in \(main.commandBar.result.items.count) rows"); return
                }
                if case .switchToTab = row.kind { CraLog.note("command bar pick \(text): tab") } else { CraLog.note("command bar pick \(text): other") }
                main.commandBar.commit(row)
                return
            }
            // commandBarIcon=<text> (#755): the open bar's row whose address holds <text> selected, then its favicon as
            // drawn: on the white tile, and in the row's colour when it is a light mark.
            if let text = dict["commandBarIcon"] {
                let bar = main.commandBar
                guard let i = bar.result.items.firstIndex(where: { $0.url?.contains(text) == true }) else {
                    CraLog.note("command bar icon \(text): none in \(bar.result.items.count) rows"); return
                }
                bar.moveSelection(by: i - bar.selectedIndex)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    CraLog.note("command bar icon \(text): row=\(i) selected=\(self.main.commandBar.selectedIndex) \(self.main.debugCommandBarIcon(i))")
                }
                return
            }
            // commandBarMove=<n> (#805): the open bar's selection moved n rows, as n presses of ↓ (↑ for a negative n) do.
            // commandBarShown=<label>: "command bar shown <label>: listed=… first=… inView=… selected=… height=…", the rows in view.
            if let n = dict["commandBarMove"].flatMap(Int.init) {
                let bar = main.commandBar
                for _ in 0..<abs(n) { bar.moveSelection(by: n < 0 ? -1 : 1) }
                return
            }
            if let label = dict["commandBarShown"] {
                CraLog.note("command bar shown \(label): \(main.debugCommandBarShown)")
                return
            }
            // commandBarDeleteKey=1 (#779): ⌥⌘⌫ pressed in the open bar, through the app as a key press goes (the menus'
            // key equivalents first). A debug readout, so the browser window isn't raised over the bar first.
            if dict["commandBarDeleteKey"] != nil {
                main.debugCommandBarKey(characters: "\u{7f}", keyCode: 51, modifiers: [.command, .option])
                return
            }
            // commandBarDelete=<text> (#779): the open bar's row whose address holds <text> selected, then "command bar
            // delete point: <x> <y>", its ✕ in top-left screen points for scenario.sh's `click bar-delete <text>`, or "none".
            if let text = dict["commandBarDelete"] {
                let bar = main.commandBar
                guard let i = bar.result.items.firstIndex(where: { $0.url?.contains(text) == true }) else {
                    CraLog.note("command bar delete point: none"); return
                }
                bar.moveSelection(by: i - bar.selectedIndex)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let p = self.main.debugCommandBarDeletePoint(i), let top = NSScreen.screens.first?.frame.maxY else {
                        CraLog.note("command bar delete point: none"); return
                    }
                    CraLog.note("command bar delete point: \(Int(p.x)) \(Int(top - p.y))")
                }
                return
            }
            // commandBarReturn=<label>: Return in the browser window's open bar, on the selected row (#667).
            if let label = dict["commandBarReturn"] {
                CraLog.note("command bar return \(label): \(main.commandBar.isOpen ? "pressed" : "no bar")")
                main.commandBar.commit()
                return
            }
            // libraryMore=<label> (#649): the Library's first download row hovered, its ••• and menu.
            if let label = dict["libraryMore"] {
                CraLog.note("library more \(label): " + ((main.shell.sidebarHost as? SidebarView)?.debugLibraryDownloadMore ?? "no sidebar"))
                return
            }
            // libraryShown=<label> (#649): the Library's page on screen, or "closed".
            // tabIcon=picker|emoji:<e>|symbol:<name>|none (#640): Change Icon… on the selected tab, see testTabIcon.
            if let step = dict["tabIcon"] { main.testTabIcon(step); return }
            if let label = dict["libraryShown"] {
                CraLog.note("library shown \(label): \(main.sidebarUI.libraryPage?.rawValue ?? "closed")")
                return
            }
            // commandBarRows=<label>: the open command bar's rows, top to bottom, each as kind:address
            // (the title when it has none), so a scenario reads which tabs ⌘T found (#307), with its
            // mode and the selected row (#379, #382). An open Little Window's or Peek's bar gets a line
            // of its own ("<label> peek:").
            if let label = dict["commandBarRows"] {
                func line(_ name: String, _ bar: CommandBarController) {
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
                    // completion=: the grey text the bar completes to, "-" for none (#667).
                    NSLog("Cra command bar rows %@: open=%d mode=%@ selected=%d %@ completion=%@", name, bar.isOpen ? 1 : 0,
                          bar.mode == .newTab ? "newTab" : "editURL", bar.selectedIndex, rows.joined(separator: " | "),
                          bar.result.inlineCompletion ?? "-")
                }
                line(label, main.commandBar)
                for l in littleWindows where l.commandBar.isOpen { line("\(label) \(l.isPeek ? "peek" : "little")", l.commandBar) }
                return
            }
            // commandBarTime=<query>: how long ⌘T's engine takes for each prefix of <query>, as typing it does,
            // the index built fresh first (#617): the per-keystroke cost at scale, in cra.log.
            if let typed = dict["commandBarTime"] {
                let engine = main.commandBar.engine
                engine.resetIndex()
                // prepared=1: the index built as the bar's opening builds it (off the main thread), a second before typing.
                let prepared = dict["prepared"] == "1"
                if prepared { engine.prepareIndex() }
                let run = { [weak self] in
                    guard let self else { return }
                    var lines: [String] = []
                    for end in 1...max(1, typed.count) {
                        let q = String(typed.prefix(end))
                        let start = DispatchTime.now().uptimeNanoseconds
                        let r = engine.suggestions(for: q, mode: .newTab, currentTabID: nil)
                        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                        lines.append("\(q)=\(String(format: "%.1f", ms))ms(\(r.items.count))")
                    }
                    CraLog.note("command bar time\(prepared ? " prepared" : ""): tabs=\(self.store.allTabs().count) history=\(self.store.history.count) archive=\(self.store.archive.count) " + lines.joined(separator: " "))
                }
                if prepared { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { run() } } } else { run() }
                return
            }
            // sidebarBuild=<label>: the sidebar lists' rebuilds since the last readout, then reset (#618).
            if let label = dict["sidebarBuild"] {
                CraLog.note("sidebar build \(label): \(SpaceListView.stats.line)")
                SpaceListView.stats = .init()
                return
            }
            // commandBarDetail=<label>: the main window's bar rows as kind:subtitle, which only the rows shown
            // get (#617).
            if let label = dict["commandBarDetail"] {
                let rows = main.commandBar.result.items.map { row -> String in
                    switch row.kind {
                    case .switchToTab: return "tab:\(row.subtitle)"
                    case .archived: return "archived:\(row.subtitle)"
                    case .history: return "history:\(row.subtitle)"
                    default: return "other:\(row.subtitle)"
                    }
                }
                CraLog.note("command bar detail \(label): \(rows.joined(separator: " | "))")
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
                // presentation: docked, hidden or heldOpen (SidebarPresentation, #483).
                CraLog.note("sidebar shown \(label): visible=\(main.sidebarVisible ? 1 : 0) menu=\(item?.title ?? "-") key=\(mods)\(item?.keyEquivalent ?? "-") presentation=\(main.sidebarPresentation.mode)")
                return
            }
            // menuRows=<menu>[&label=<label>]: a menu bar menu's rows as it draws them once validated
            // (hidden rows left out), "|" between rows and "──" for a separator: Arc's File menu (#279).
            // marks=1 also puts ✓ before a checked row and " (off)" after a dimmed one (#333);
            // icons=1 puts [icon] before a row with an image; tips=1 puts [tip] before one whose
            // full title is available as a tooltip (#471). hidden=1 lists the hidden rows too, with
            // " (hidden)" after each, or " (hidden, keys)" when it still takes its shortcut (#622).
            // spacesMenuChange=add|moveLastFirst|renameFirst|deleteFirst mutates the temporary scenario
            // store, so reopening this lazy menu proves it follows live Space changes (#471).
            if let change = dict["spacesMenuChange"] {
                switch change {
                case "add":
                    store.createSpace(title: dict["title"] ?? "Added", emoji: dict["emoji"] ?? "", focus: false)
                case "moveLastFirst":
                    if let id = store.spaceOrder.last { store.moveSpace(id, to: 0) }
                case "renameFirst":
                    if let id = store.spaceOrder.first, var space = store.space(id), let title = dict["title"] {
                        space.rename(to: title)
                        store.updateSpace(space)
                    }
                case "removeFirstIcon":
                    if let id = store.spaceOrder.first, var space = store.space(id) {
                        space.icon = .none
                        store.updateSpace(space)
                    }
                case "deleteFirst":
                    if let id = store.spaceOrder.first { store.deleteSpace(id) }
                default:
                    CraLog.note("spaces menu change: unknown \(change)")
                }
                return
            }
            // menuPress=<menu>/<row>: the row chosen from the menu bar as a click chooses it, once AppKit has validated it
            // (#680: Edit ▸ Redo on an easel; a posted ⇧⌘Z doesn't match the menu as a typed one does).
            if let path = dict["menuPress"]?.split(separator: "/").map(String.init), path.count == 2 {
                let menu = NSApp.mainMenu?.items.first { $0.title == path[0] }?.submenu
                menu?.update()
                if let menu, let i = menu.items.firstIndex(where: { $0.title == path[1] }), menu.items[i].isEnabled {
                    menu.performActionForItem(at: i)
                } else {
                    CraLog.note("menu press \(path.joined(separator: "/")): no enabled row")
                }
                return
            }
            if let title = dict["menuRows"] {
                let menu = NSApp.mainMenu?.items.first { $0.title == title }?.submenu
                if let menu { menu.delegate?.menuNeedsUpdate?(menu) }
                menu?.update()
                // A delegate may have inserted new rows after AppKit's validation pass. Validate
                // their explicit targets too, as opening the menu normally does.
                for item in menu?.items ?? [] {
                    if let validator = item.target as? NSMenuItemValidation {
                        item.isEnabled = validator.validateMenuItem(item)
                    }
                }
                let marks = dict["marks"] == "1"
                let icons = dict["icons"] == "1"
                let tips = dict["tips"] == "1"
                let withHidden = dict["hidden"] == "1"
                let rows: [String] = menu?.items.filter { withHidden || !$0.isHidden }.map { item -> String in
                    if item.isSeparatorItem { return "──" }
                    let mark = marks && item.state == .on ? "✓" : ""
                    let icon = icons && item.image != nil ? "[icon]" : ""
                    let tip = tips && item.toolTip != nil ? "[tip]" : ""
                    let disabled = marks && !item.isEnabled ? " (off)" : ""
                    let hidden = item.isHidden ? (item.allowsKeyEquivalentWhenHidden ? " (hidden, keys)" : " (hidden)") : ""
                    return mark + icon + tip + item.title + disabled + hidden
                } ?? []
                CraLog.note("menu rows \(dict["label"] ?? title): \(rows.joined(separator: "|"))")
                return
            }
            // endSheets=1: every open sheet (a save panel, a dialog) cancelled, as Escape would.
            if dict["endSheets"] != nil {
                for w in NSApp.windows { if let sheet = w.attachedSheet { w.endSheet(sheet, returnCode: .cancel) } }
                return
            }
            // activations=<label>: whether Cra is the active app, and how many requests to bring it to
            // the front went through while it was in the background (#274).
            if let label = dict["activations"] {
                CraLog.note("activations \(label): active=\(NSApp.isActive ? 1 : 0) background=\(CraApplication.backgroundActivations)")
                return
            }
            // calendarMeeting=now (#758): the Calendar favorite reads a call that started a minute ago and has a Join
            // link; calendarTick=1 is what the 30 s timer does (the countdown and the Join card move on); meetingCard=
            // <label> says whether the Join card is up and how many other apps' windows are over the browser window.
            if dict["calendarMeeting"] == "now" {
                let now = Date()
                LiveCalendarClient.shared.setDemo([CalendarPreview.Event(title: "Weekly sync", start: now.addingTimeInterval(-60),
                                                                         end: now.addingTimeInterval(3600), meetingURL: "https://zoom.us/j/758")],
                                                  favorite: "https://calendar.google.com/calendar/u/0/r", profilePath: nil)
                return
            }
            if dict["calendarTick"] != nil { NotificationCenter.default.post(name: LiveCalendarClient.changed, object: nil); return }
            if let label = dict["meetingCard"] {
                let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                let mainOver = main.window.map { String(LittleWindowRaise.othersOver($0.windowNumber, in: info)) } ?? "-"
                CraLog.note("meeting card \(label): \(MeetingReminder.shared.debugState) active=\(NSApp.isActive ? 1 : 0) mainOver=\(mainOver)")
                return
            }
            // pageWindows=<label>: the page windows Chromium has shown, how many it showed away from every
            // Cra window on screen, and how many macOS animates in and out (#354).
            if let label = dict["pageWindows"] { CraLog.note("page windows \(label): \(CraCEFRuntime.pageWindowsReadout)"); return }
            // hostBrowserView=<label>: whether Chrome finds the browser element of each profile's hidden Browser, which
            // its Settings looked for; hostBrowserViewHidden=1|0 takes it away (and back), as on the Mac where Clear
            // browsing data's Cancel crashed Cra 0.1.50 (crash-clear-browsing-data-cancel).
            if let label = dict["hostBrowserView"] { CraLog.note("host browser view \(label): \(CraCEFRuntime.pageHostBrowserViewReadout)"); return }
            if let hidden = dict["hostBrowserViewHidden"] { CraCEFRuntime.setPageHostBrowserViewsHidden(hidden == "1"); return }
            // rendererReuse=1: a renderer process started inside the notice that the one before it ended
            // (crash-extensions-renderer-reused-on-exit); its steps go to Chrome's log.
            if dict["rendererReuse"] == "1" { CraCEFRuntime.reuseRendererInsideExitNotice(); return }
            // appWindows=<label>: every window of Cra's on screen, front to back, by class, size and parent: what
            // a page's feature put up when no other readout knows its window (the share picker, web features).
            if let label = dict["appWindows"] {
                for w in (NSWindow.windowNumbers(options: []) ?? []).compactMap({ NSApp.window(withWindowNumber: $0.intValue) })
                where w.isVisible && w.alphaValue > 0 {
                    CraLog.note("app window \(label): \(NSStringFromClass(type(of: w))) \(Int(w.frame.width))x\(Int(w.frame.height)) at \(Int(w.frame.minX)),\(Int(w.frame.minY)) level=\(w.level.rawValue) parent=\(w.parent.map { NSStringFromClass(type(of: $0)) } ?? "-")")
                }
                CraLog.note("app windows \(label): done")
                return
            }
            // taskManagerEnd=<page title>: in Chrome's Task Manager, the page's row picked and "End task" pressed,
            // through the window's accessibility elements as VoiceOver would (#855).
            if let title = dict["taskManagerEnd"] { CraLog.note("task manager end \(title): \(TaskManagerAccess.endTask(title: title))"); return }
            // chromeWindows=<label>: Chromium's own windows (its tab strip and toolbar) a user could see,
            // on screen and not see-through, each named (#472).
            if let label = dict["chromeWindows"] {
                let chrome: AnyClass? = NSClassFromString("NativeWidgetMacNSWindow")
                let all = NSApp.windows.filter { w in chrome.map { w.isKind(of: $0) } == true }
                let seen = all.filter { $0.isVisible && $0.alphaValue > 0 }
                for w in seen {
                    CraLog.note("chrome window \(label): \(NSStringFromClass(type(of: w))) '\(w.title)' alpha=\(w.alphaValue) frame=\(NSStringFromRect(w.frame)) child=\(w.parent != nil ? 1 : 0)")
                }
                CraLog.note("chrome windows \(label): seen=\(seen.count) of \(all.count) (\(all.map { "\(NSStringFromClass(type(of: $0))) \($0.isVisible ? "on" : "off") a\($0.alphaValue) \(Int($0.frame.width))x\(Int($0.frame.height)) parent=\($0.parent.map { NSStringFromClass(type(of: $0)) } ?? "-")" }.joined(separator: ", ")))")
                return
            }
            // pip=<label>: Chromium's Picture in Picture window as Cra keeps it; pipKey=space|force asks
            // it to become key the ways Chromium can leave it open to that (#262); pipDrop=left|right|top|bottom
            // lets it go half past that edge of the screen, as a mouse drag does (#332); pipClick=<n> clicks
            // the video, as the last of n quick clicks (2: a double click, back to the tab); pipSeek=<0…1>
            // presses the scrubber that far along; pipSize=<0…1> resizes it to that share of its
            // display's width; pipButton=back|minimize|close clicks that hover button (#434); pipShow=1
            // shows the hover controls and keeps them up until the pointer comes and goes (#463);
            // pipPointer=readd|enter|move puts Chromium's tracking area back or sends its window the pointer (#535);
            // pipPinch=<m>,<m>… pinches it, one trackpad magnification per value (#534).
            if let label = dict["pip"] { NSLog("Cra pip %@: %@", label, PictureInPictureChrome.shared.readout()); return }
            // docPip=<label>: the Document Picture in Picture windows (Meet's) and whether each is on screen;
            // docPipDrop=left|right|bottom lets the first go half past that edge, as a drag of its top bar does (#702).
            if let label = dict["docPip"] { NSLog("Cra docPip %@: %@", label, DocumentPictureInPictureSpring.shared.readout()); return }
            if let edge = dict["docPipDrop"] { DocumentPictureInPictureSpring.shared.debugDrop(edge); return }
            if let count = dict["pipClick"].flatMap(Int.init) { PictureInPictureChrome.shared.debugClick(count); return }
            if let at = dict["pipSeek"].flatMap(Double.init) { PictureInPictureChrome.shared.debugSeek(at); return }
            if let name = dict["pipButton"] { PictureInPictureChrome.shared.debugPress(name); return }
            if dict["pipShow"] != nil { PictureInPictureChrome.shared.debugShow(); return }
            if let what = dict["pipPointer"] { PictureInPictureChrome.shared.debugPointer(what); return }
            if let how = dict["pipKey"] { PictureInPictureChrome.shared.debugTakeKey(how); return }
            if let what = dict["pipPoke"] { PictureInPictureChrome.shared.debugPoke(what); return }
            if let edge = dict["pipDrop"] { PictureInPictureChrome.shared.debugDrop(edge); return }
            if let share = dict["pipSize"].flatMap(Double.init) { PictureInPictureChrome.shared.debugSize(CGFloat(share)); return }
            if let steps = dict["pipPinch"] { PictureInPictureChrome.shared.debugPinch(steps.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }); return }
            // peekShown=<label>: the page behind a Peek in each window, faded and drawn back or whole (PR #221).
            if let label = dict["peekShown"] {
                for m in mainWindows { NSLog("Cra peek shown %@: %@", label, m.peekBackdropShown()) }
                return
            }
            // peekExpand=plain|command: the front window's Peek's Expand button, clicked with or without ⌘
            // held, then the selected tab's page, its pinned address and the Today tab count (#380).
            if let how = dict["peekExpand"] {
                guard let peek = littleWindows.first(where: { $0.isPeek && !$0.isParked && $0.peekParent === main }) else {
                    CraLog.note("peek expand \(how): no Peek"); return
                }
                peek.expandPeek(commandClick: how == "command")
                let today = store.tabs(under: store.focusedSpace(window: main.windowID).todayContainerID).count
                let tab = main.selectedTab?.tab
                CraLog.note("peek expand \(how): selected=\(tab?.url ?? "-") home=\(tab?.savedURL ?? "-") today=\(today)")
                return
            }
            // peekClose=<label>[&attempt=closeButton|closeShortcut|escape|background]: the front window's
            // Peek after that close attempt: whether it is still open, whether its page uses the camera or
            // microphone, and its Close button, round or Arc's red Confirm pill (#425).
            if let label = dict["peekClose"] {
                guard let peek = littleWindows.first(where: { $0.isPeek && !$0.isParked && $0.peekParent === main }) else {
                    CraLog.note("peek close \(label): no Peek"); return
                }
                let attempt: PeekCloseAttempt? = switch dict["attempt"] {
                case "closeButton": .closeButton
                case "closeShortcut": .closeShortcut
                case "escape": .escape(prefersConfirmation: false)
                case "background": .background
                default: nil
                }
                if let attempt { peek.attemptPeekClose(attempt) }
                CraLog.note("peek close \(label): \(peek.peekCloseReadout())")
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
            // paneReloadMenu=<label>&pane=<n>: a right-click on pane n's ↻ (pointer over its bar). Logs the
            // menu's rows, then, once the window has caught up, the focused pane and the pane whose page the
            // menu's commands reach (BrowserManager.visibleRuntime).
            if let label = dict["paneReloadMenu"], let n = dict["pane"].flatMap({ Int($0) }) {
                let cards = main.shell.paneCards
                guard cards.indices.contains(n), let bar = cards[n].toolbarHost as? PaneToolbarView else {
                    CraLog.note("pane reload menu \(label): no pane \(n)"); return
                }
                let rows = bar.debugRightClickReload()?.items.map { $0.isSeparatorItem ? "-" : $0.title }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak main] in
                    guard let main else { return }
                    let cards = main.shell.paneCards
                    let focused = cards.firstIndex { $0.tabID == main.selectedTab?.id }.map(String.init) ?? "-"
                    let page = cards.firstIndex { $0.tabID == main.browsers.visibleTabID }.map(String.init) ?? "-"
                    CraLog.note("pane reload menu \(label): menu=\(rows?.joined(separator: " | ") ?? "none") focused=\(focused) page=\(page)")
                }
                return
            }
            // paneLengths=<label>: each pane card's length along the split's axis in pane order, the
            // split's stored width factors and which pane is focused (View ▸ Expand Current Split).
            if let label = dict["paneLengths"] {
                let shell = main.shell!
                let horizontal = shell.splitOrientation == .horizontal
                let lengths = shell.paneCards.map { String(format: "%.1f", horizontal ? $0.frame.width : $0.frame.height) }
                let split = main.selectedTab.flatMap { store.splitContaining($0.id) }
                let stored: [UUID: Double] = split?.split?.widthFactors ?? [:]
                let factors: [String] = (split?.children ?? []).map { String(format: "%.2f", stored[$0] ?? -1) }
                let focused = shell.paneCards.firstIndex { $0.tabID == main.selectedTab?.id }.map(String.init) ?? "-"
                CraLog.note("pane lengths \(label): \(lengths.joined(separator: " | ")) factors=\(factors.joined(separator: ",")) focused=\(focused) \(horizontal ? "horizontal" : "vertical")")
                return
            }
            // popups=<label>[&run=open|openAll|allow|block]: the front tab's blocked pop-ups, its
            // toolbar button and URL-field line, the menu's rows, Chrome's site setting and the
            // Today tab count; run= picks a menu row first (#357).
            if let label = dict["popups"], let id = main.selectedTab?.id {
                switch dict["run"] {
                case "open": main.browsers.openBlockedPopups(id, popup: main.browsers.blockedPopups(id).first?.id)
                case "openAll": main.browsers.openBlockedPopups(id)
                case "allow": main.browsers.setPopupsAllowed(id, true)
                case "block": main.browsers.setPopupsAllowed(id, false)
                default: break
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak main] in
                    guard let main else { return }
                    let waiting = main.browsers.blockedPopups(id)
                    let rows = main.blockedPopupsMenu(id).items.map { $0.isSeparatorItem ? "-" : $0.title + ($0.state == .on ? "✓" : "") }
                    let today = self.store.tabs(under: self.store.focusedSpace(window: main.windowID).todayContainerID).count
                    CraLog.note("popups \(label): waiting=\(waiting.count) urls=\(waiting.map(\.url).joined(separator: " ")) "
                                + "button=\(main.sidebarUI.navState(for: id).blockedPopups) line=\((main.shell.sidebarHost as? SidebarView)?.debugTranslateLine ?? "-") "
                                + "allowed=\(main.browsers.popupsAllowed(id) ? 1 : 0) today=\(today) menu=\(rows.joined(separator: " | "))")
                }
                return
            }
            if let label = dict["historyMenu"] { CraLog.note(main.backForwardMenuReadout(label)); return }
            if let label = dict["back"] {
                let today = store.tabs(under: store.focusedSpace(window: main.windowID).todayContainerID).count
                CraLog.note("back \(label): selected=\(main.selectedTab?.tab?.url ?? "-") back=\(main.sidebarUI.canGoBack ? 1 : 0) today=\(today)")
                return
            }
            // todayOrder=<label>: the front space's Today top to bottom, each tab by address, a split's panes in
            // brackets (where a link's tab lands, #532).
            if let label = dict["todayOrder"] {
                func row(_ id: UUID) -> String {
                    guard let it = store.item(id) else { return "?" }
                    if it.isSplit { return "[" + it.children.map(row).joined(separator: " + ") + "]" }
                    if it.isFolder { return it.displayTitle + "{" + it.children.map(row).joined(separator: " , ") + "}" }
                    return it.tab?.url ?? "?"
                }
                let today = store.item(store.focusedSpace(window: main.windowID).todayContainerID)?.children ?? []
                CraLog.note("today order \(label): \(today.map(row).joined(separator: " | "))")
                return
            }
            // swipeBack=<label>[&go=1]: what Chromium's two-finger swipe asks the front page's view
            // before a swipe back starts, and with go=1 what it does at the end (#370).
            if let label = dict["swipeBack"] {
                let rt = main.browsers.visibleRuntime
                let root = rt?.hostWindow.flatMap { EmbeddedPages.pageViews(of: $0)?.last ?? $0.contentView } ?? rt?.browser.containerView
                CraLog.note("swipe back \(label): \(root.map { ChromiumHistorySwipe.debugSwipeBack(in: $0, perform: dict["go"] == "1") } ?? "no tab")")
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
            // peekFrom=<label>&x=&y=[&clicked=1]: where a Peek from the selected tab would grow from with
            // the pointer at x, y (fractions of the page, y down), just clicked or resting: "link W×H",
            // "click W×H" or "area" (#359).
            if let label = dict["peekFrom"] {
                let x = dict["x"].flatMap(Double.init) ?? 0.5, y = dict["y"].flatMap(Double.init) ?? 0.5
                main.peekSourceReadout(x: x, y: y, clicked: dict["clicked"] == "1") { CraLog.note("peek from \(label): \($0)") }
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
            // emptyCard=<label>: the front window's card while no tab is selected, its veil and shadow (#483).
            if let label = dict["emptyCard"] {
                CraLog.note("empty card \(label): \(main.shell.emptyCardReadout)")
                return
            }
            // selectedTab=<label>: the front window's open tab, by address (⌘1…⌘9 scenarios).
            if let label = dict["selectedTab"] {
                CraLog.note("selected tab \(label): \(store.selectedTabID(window: main.windowID).flatMap { store.item($0)?.tab?.url } ?? "none")")
                return
            }
            // selectTab=<tab id, or text in the tab's address>: that tab selected in the front window.
            if let v = dict["selectTab"] {
                let t = UUID(uuidString: v) ?? store.allTabs().first { $0.tab?.url.contains(v) == true }?.id
                if let t { store.selectTab(t, window: main.windowID) } else { CraLog.note("selectTab: no tab \(v)") }
                return
            }
            // Tab freezing with a short threshold (seconds) from now on, so it can be tried without
            // waiting: the minute's pass would otherwise take the votes back.
            if dict["freezingState"] != nil { for w in mainWindows { w.browsers.logFreezingStates() }; return }
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
            // closeSleptPages=1: the slept-page budget's pass now, not at the next minute (#616).
            if dict["closeSleptPages"] != nil { for w in mainWindows { w.browsers.closeSleptPages() }; return }
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
            // downloadDestination=cancel: the downloads CRA_TEST_HOLD_DOWNLOAD_DESTINATION held answered as
            // a save panel's Cancel is (#491).
            if dict["downloadDestination"] == "cancel" { DownloadDestinations.debugCancelHeld(); return }
            // What a running download's menu does (pause, resume, cancel), to the newest one in
            // progress; `downloadState` logs how the rows read (#272).
            if let v = dict["download"] {
                let actions: [String: CraDownloadControl] = ["pause": .pause, "resume": .resume, "cancel": .cancel]
                if let action = actions[v], let l = DownloadHistory.shared.live.last(where: \.running) {
                    DownloadHistory.shared.control(l.id, action)
                }
                return
            }
            // What the Dock tile and the ⌘-Tab switcher show for Cra (#319).
            // What the last look at the sync folder found, and whether a mix is being waited out (#378).
            if let label = dict["sync"] { CraLog.note("sync \(label): \(composition.sync.readout())"); return }
            // handoff=<label>: the page Handoff offers the user's iPhone now (#745).
            if let label = dict["handoff"] { CraLog.note("handoff \(label): \(handoff.offered?.absoluteString ?? "none")"); return }
            if let label = dict["dockTile"] { CraLog.note("dock tile \(label): \(AppIconManager.shared.dockTileReadout())"); return }
            // appIcon=<id>: picks an icon without remembering it; bundleIcon=<label>: Finder's icon on the app.
            if let id = dict["appIcon"] { AppIconManager.shared.select(id, remember: false); return }
            if let label = dict["bundleIcon"] { AppIconManager.shared.logBundleIcon(label); return }
            // bundleIconPut=<id>: that icon on Cra.app as 0.1.54 put it, for a launch to take off (#724).
            if let id = dict["bundleIconPut"] { AppIconManager.shared.putBundleIconForTest(id); return }
            // How far the open downloads list's hover reaches below its rows, and what a press there hits (#575).
            // fakeScreenshot=<name>: a small picture in ~/Pictures carrying macOS's screen-capture mark, as
            // ⇧⌘4 leaves one, for Spotlight to find; fakeScreenshot=-<name> deletes it again.
            if let name = dict["fakeScreenshot"] {
                ScreenshotWatcher.writeFakeScreenshot(named: name)
                return
            }
            // downloadsList=<label>: the hover list's rows, oldest first, screenshots marked (Arc's Library button).
            if let label = dict["downloadsList"] {
                let rows = DownloadHistory.shared.recent.map { row -> String in
                    if case .finished(let e) = row, DownloadHistory.shared.isScreenshot(e) { return "screenshot:" + row.name }
                    return row.name
                }
                CraLog.note("downloads list \(label): \(rows.joined(separator: " | "))")
                return
            }
            if let label = dict["downloadsTray"] {
                let trayView = main.sidebarUI.downloadsTray as? DownloadsTrayView
                let tray = trayView?.hoverReadout ?? "none"
                // &row=hover|press|release|leave (#896): the first row after that pointer event, and its fill.
                let row = dict["row"].map { " " + (trayView?.debugFirstRow($0) ?? "row=none") } ?? ""
                CraLog.note("downloads tray \(label): open=\(main.sidebarUI.downloadsListOpen) \(tray)\(row)")
                return
            }
            if let label = dict["downloadState"] {
                let rows = DownloadHistory.shared.live.map { DownloadRow.subtitle($0.row, now: Date()) }
                let progress = DownloadHistory.shared.progress.map { String(format: "%.3f", $0) } ?? "none"
                // finished: downloads reported finished in this launch, across windows (an old one from the
                // profile's history must not be one).
                let finished = mainWindows.reduce(0) { $0 + $1.finishedDownloadCount }
                // bin: the file over the Library button, and what its edge takes (#491).
                let bin = (main.sidebarUI.libraryAnchor as? LibraryButtonView)?.binReadout ?? "none"
                CraLog.note("download state \(label): running=\(DownloadHistory.shared.hasRunningDownloads) progress=\(progress) rows=\(rows) bin=\(bin) finished=\(finished)")
                return
            }
            // What the guards a running download holds would do now: ⌘Q's question, the automatic update
            // restart's wait and Install and Relaunch's question (#272). Downloads Cra doesn't list must
            // hold none of them (#491).
            // updaterRelaunch=<button>: Install and Relaunch clicked in the updater window and <button> of its
            // question clicked, see SoftwareUpdater.debugRelaunchClick (X, 17 Nov 2026).
            if let button = dict["updaterRelaunch"] { SoftwareUpdater.shared.debugRelaunchClick(answer: button); return }
            if let label = dict["downloadGuards"] {
                let quit: String = switch quitPrompt(source: .appMenu) {
                case .downloadsInProgress: "downloads in progress"
                case .confirmQuit: "Quit Cra?"
                case .none: "none"
                }
                let relaunch = SoftwareUpdater.shared.relaunchAsksAboutDownloads ? "asks" : "none"
                CraLog.note("download guards \(label): quit=\(quit) autoUpdate=\(autoUpdateBlocker() ?? "none") installAndRelaunch=\(relaunch)")
                return
            }
            // The sidebar as if Cra were in front (1) or behind (0), until the app's next activation change:
            // a background test copy is in either state depending on what it was sent.
            if let v = dict["appActive"] { main.sidebarUI.appActive = v == "1"; return }
            // raise=firstResponderAfterResigning: AppKit's "-_newFirstResponderAfterResigning is not a valid
            // message outside of …" from the run loop, as a focus change raised it in 0.1.53's crash reports
            // (crash-first-responder-after-resigning); Cra logs it and keeps running.
            if dict["raise"] == "firstResponderAfterResigning" {
                let window = main.window
                RunLoop.main.perform(inModes: [.common]) {
                    _ = window?.perform(NSSelectorFromString("_newFirstResponderAfterResigning"))
                }
                return
            }
            // Settings ▸ Privacy sharing now, not in 30 s or tomorrow (only with CRA_SHARING_ENDPOINT
            // in a test copy): stats sends the usage report, checkin the daily install check-in,
            // crash looks for new crash reports, on and off tick and untick onboarding's
            // "Help improve Cra" row.
            if let v = dict["sharing"] {
                if v == "stats" { SharingService.shared.sendStatsIfDue(force: true) }
                if v == "checkin" { SharingService.shared.sendCheckInIfDue(force: true) }
                if v == "crash" { SharingService.shared.checkCrashReports() }
                if v == "on" { store.settings.setSharesToImproveCra(true) }
                if v == "card-share" { SharingCard.answer(share: true) }
                if v == "card-close" { SharingCard.answer(share: false) }
                if v == "off" { store.settings.setSharesToImproveCra(false) }
                return
            }
            // Settings ▸ Privacy ▸ Fingerprinting protection on or off, as its switch sets it.
            if let v = dict["fingerprinting"] { store.settings.fingerprintingProtection = v == "on"; return }
            // Settings ▸ Privacy without the pointer (#507): blockLists=<address,…>|none sets the added
            // block lists, blockAds=on|off both offline sources.
            if let url = dict["toggleSiteFilters"], let host = AppSettings.filterHost(url) {
                store.settings.toggleFilters(on: host)
                return
            }
            if let v = dict["blockLists"] { store.settings.customBlocklists = v == "none" ? [] : v.split(separator: ",").map(String.init); return }
            if let v = dict["blockAds"] {
                store.settings.blockAdsAndTrackers = v == "on"
                CraLog.note("block ads and trackers: \(v == "on" ? "on" : "off")")
                return
            }
            // personalFilters=<text, \n between lines>|none: Settings ▸ Privacy ▸ Advanced… ▸ My filters, saved and in use.
            if let v = dict["personalFilters"] {
                store.settings.personalBlockFilters = v == "none" ? nil : v.replacingOccurrences(of: "\\n", with: "\n")
                store.settings.personalFiltersEnabled = v != "none"
                return
            }
            // blockListCounts=<label>: the rule counts the Privacy pane and its Advanced… sheet show, as they read them.
            if let label = dict["blockListCounts"] {
                let lists = BlockLists.shared
                var parts = ["inUse=" + (lists.inUse.map { BlockListCount.inUse(rules: $0.rules, lists: $0.lists) } ?? "-")]
                for source in BlockLists.builtInSources { parts.append("\(source)=\(lists.builtInCounts[source]?.summary ?? "-")") }
                for address in store.settings.customBlocklists {
                    parts.append("\(URL(string: address)?.lastPathComponent ?? "?")=\(lists.count(address)?.summary ?? "-")")
                }
                parts.append("mine=\(lists.personalCount(store.settings.personalBlockFilters).summary)")
                CraLog.note("block list counts \(label): " + parts.joined(separator: " | "))
                return
            }
            if let v = dict["banner"] { SoftwareUpdater.shared.debugUpdated(v == "none" ? nil : v); return }
            if let v = dict["bannerReady"] { SoftwareUpdater.shared.debugReady(v == "none" ? nil : v); return }
            // updateNotice=<label>: what the update banner says ("update notice <label>: …"); =click clicks it, as
            // for a Cra.app replaced while it runs (app-replaced-while-running).
            if let v = dict["updateNotice"] {
                let u = SoftwareUpdater.shared
                if v == "click" { if let n = u.notice { u.act(on: n) } else { CraLog.note("update notice click: none") }; return }
                CraLog.note("update notice \(v): \(u.notice.map { "\($0.title) \($0.subtitle) (\($0.version))" } ?? "none")")
                return
            }
            // switcher=held: open as from ⌃Tab with ⌃ held, so keys go to it and letting go switches (#696);
            // switcher=state logs the selected card.
            if dict["switcher"] == "state" { main.debugTabSwitcherState(); return }
            if let mode = dict["switcher"] { main.debugTabSwitcher(allSpaces: mode == "all", held: mode == "held" ? .control : []); return }
            // modifierFlags=<bits>: keys held or let go, a flagsChanged event through the app's queue.
            if let bits = dict["modifierFlags"].flatMap(UInt.init), let w = main.window {
                TestGesture.flags(NSEvent.ModifierFlags(rawValue: bits), in: w)
                return
            }
            // The Site Control Center's Safari's Engine switch for the focused page, without the pointer.
            if let v = dict["safariEngine"] { main.debugChooseSafariEngine(v == "on"); return }
            // The protected video prompt of a mixed site's page: state, Once, Always, close, row.
            if let step = dict["protectedVideo"] { main.debugProtectedVideo(step, label: dict["step"] ?? ""); return }
            // Script in Cra's isolated world of the focused page: "Cra isolatedJS → <result>" on stdout.
            if let js = dict["isolatedJS"] {
                let params = String(decoding: (try? JSONSerialization.data(withJSONObject: ["expression": js, "returnByValue": true])) ?? Data(), as: UTF8.self)
                main.currentBrowser?.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, error in
                    NSLog("Cra isolatedJS → %@", result ?? "error: \(error ?? "?")")
                }
                return
            }
            // pipBackToTab=1: the ↖ (back to tab) button of the system's Picture in Picture window, as
            // WebKit reports it for the WebKit page whose video is out (#585).
            if dict["pipBackToTab"] != nil {
                for rt in main.browsers.runtimes.values { (rt.browser as? WebKitBrowser)?.debugPressPictureInPictureBackToTab() }
                return
            }
            // The sidebar player without the pointer: play/pause/next/previous/pip on the newest
            // card ("state" only logs), then its cards: "Cra nowPlaying[<label>] <host> playing=… prev=… next=… video=… pip=…".
            if let op = dict["nowPlaying"], let np = main.browsers.nowPlaying {
                let label = dict["label"].map { "[\($0)]" } ?? ""
                let actions: [String: NowPlaying.Action] = ["toggle": .togglePlayback, "next": .next, "previous": .previous,
                                                           "pip": .pictureInPicture, "dismiss": .dismiss]
                if let action = actions[op], let id = np.entries.last?.id { main.browsers.performNowPlaying(id, action) }
                // open and fold: the stack as a hover opens and folds it.
                if op == "open" || op == "fold" { (main.shell.sidebarHost as? SidebarView)?.debugSetPlayerOpen(op == "open") }
                // skip=<seconds> and seek=<seconds>: the island's skip buttons and progress bar (Discussion #761).
                if op == "skip", let s = dict["seconds"].flatMap(Double.init), let id = np.entries.last?.id { main.browsers.performNowPlaying(id, .skip(s)) }
                if op == "seek", let s = dict["seconds"].flatMap(Double.init), let id = np.entries.last?.id { main.browsers.performNowPlaying(id, .seek(s)) }
                // What the island read: "Cra nowPlaying[<label>] media <host> title="…" artist="…" pos=… dur=… art=<WxH|loading|failed|none>".
                for e in np.entries where store.settings.nowPlayingStyle == .island {
                    let host = CraLog.host(main.browsers.runtime(for: e.id)?.browser.currentURL ?? "")
                    let m = e.media
                    let dur = m?.duration.map { $0.isFinite ? String(format: "%.0f", $0) : "live" } ?? "none"
                    let pos = e.clock.map { String(format: "%.0f", $0.position(at: Date().timeIntervalSinceReferenceDate)) } ?? "none"
                    NSLog("Cra nowPlaying%@ media %@ title=\"%@\" artist=\"%@\" pos=%@ dur=%@ art=%@", label, host, m?.title ?? "", m?.artist ?? "",
                          pos, dur, NowPlayingArtwork.shared.debugState(m?.artworkURL(forPixels: NowPlayingArtwork.pixels)))
                }
                // The cards as drawn, front first: "Cra nowPlaying[<label>] card island h=30 open=0 line=… art=… tint=#… …".
                for c in (main.shell.sidebarHost as? SidebarView)?.debugPlayerCards ?? [] { NSLog("Cra nowPlaying%@ card %@", label, c) }
                for e in np.entries {
                    let host = CraLog.host(main.browsers.runtime(for: e.id)?.browser.currentURL ?? "")
                    NSLog("Cra nowPlaying%@ %@ playing=%d prev=%d next=%d video=%d pip=%d", label, host, e.playing ? 1 : 0, e.hasPrevious ? 1 : 0,
                          e.hasNext ? 1 : 0, e.hasVideo ? 1 : 0, np.pictureInPicture.contains(e.id) ? 1 : 0)
                }
                if np.entries.isEmpty { NSLog("Cra nowPlaying%@ none", label) }
                // The cards' colour: "Cra nowPlaying[<label>] tint=<arc|theme> fill=#RRGGBB" (Ideas #366).
                NSLog("Cra nowPlaying%@ tint=%@ fill=%@", label, store.settings.nowPlayingTint.rawValue,
                      (main.shell.sidebarHost as? SidebarView)?.debugPlayerFill ?? "none")
                // Tabs whose speaker shows, card or not: "Cra nowPlaying[<label>] sounding <host> uncontrollable=…" (#411).
                for rt in main.browsers.runtimes.values where rt.browser.isAudible {
                    NSLog("Cra nowPlaying%@ sounding %@ uncontrollable=%d", label, CraLog.host(rt.browser.currentURL),
                          rt.browser.hasUncontrollableSound ? 1 : 0)
                }
                return
            }
            // pasteAndGo=<text>: ⌥⌘V with that text in place of the clipboard, which a test copy shares with the Mac (#610).
            if let text = dict["pasteAndGo"] { pasteAndGo(clipboard: text, in: main); return }
            // setPasteboard=<text>: what ⌥⌘V reads next, on the CRA_TEST_PASTEBOARD board only (#610).
            if let text = dict["setPasteboard"], ProcessInfo.processInfo.environment["CRA_TEST_PASTEBOARD"] != nil {
                Self.pasteboard.clearContents()
                Self.pasteboard.setString(text, forType: .string)
                return
            }
            // themeEditor=1 opens it; themeEditor=intensity:<0…1> or noise:<0…1> moves its slider or
            // dial as a drag would, and logs how many ticks that played; swatch:<page><index>, add:1 and
            // remove:1 press a swatch, + or −, press:<pt> presses the pad that far right of its centre (#754), and
            // log "theme editor pad <n>: wheel=… key=…" (#632).
            if let step = dict["themeEditor"] {
                let parts = step.split(separator: ":").map(String.init)
                guard parts.count == 2, let v = Double(parts[1]) else { main.showSpaceStyleEditor(space: store.focusedSpace); return }
                let before = SpaceStyleTick.count
                NotificationCenter.default.post(name: SpaceStyleTick.debugSet, object: nil, userInfo: [parts[0]: v])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    CraLog.note("theme editor \(parts[0]) \(parts[1]): ticks +\(SpaceStyleTick.count - before)")
                }
                return
            }
            if dict["jumpPill"] != nil { SpaceListView.jumpToSelected(for: main.sidebarUI, space: store.focusedSpaceID); return }
            // The open folder preview: the pointer resting on a row, the list scrolled under it, and
            // "Cra folderPreview <label>: lit=<rows> top=<pt>", the rows with the pointer's highlight and how far
            // the list is scrolled (#544).
            if let n = dict["folderPreviewPointer"].flatMap(Int.init) { FolderPreviewController.shared.preview?.debugPointer(onRow: n); return }
            if let n = dict["folderPreviewScroll"].flatMap(Int.init) { FolderPreviewController.shared.preview?.debugScroll(rows: n); return }
            if let label = dict["folderPreviewLit"] {
                guard let preview = FolderPreviewController.shared.preview else { NSLog("Cra folderPreview %@: closed", label); return }
                NSLog("Cra folderPreview %@: lit=%@ top=%.0f", label, preview.debugLit.map(String.init).joined(separator: ","), preview.debugTop)
                return
            }
            // clickRow=<id>&mods=<modifier bits>: a click on the middle of that item's sidebar row through the event
            // queue, as clickAt's (524288, Option: the tab opens in Split View with the open one, as in Arc).
            if let r = dict["clickRow"] {
                guard let id = UUID(uuidString: r), let (p, w) = SpaceListView.debugRowWindowPoint(id, ui: main.sidebarUI) else {
                    CraLog.note("click row: none"); return
                }
                CraLog.note("click row: \(store.item(id)?.displayTitle ?? "?")")
                TestGesture.click(at: p, in: w, modifiers: NSEvent.ModifierFlags(rawValue: dict["mods"].flatMap(UInt.init) ?? 0))
                return
            }
            // rowPoint=<id>: "row point: <x> <y>", where scenario.sh's `click row <id> move` rests the real pointer (#743).
            if let r = dict["rowPoint"] {
                guard let id = UUID(uuidString: r), let p = SpaceListView.debugRowPoint(id, ui: main.sidebarUI) else {
                    CraLog.note("row point: none"); return
                }
                CraLog.note("row point: \(Int(p.x)) \(Int(p.y))")
                return
            }
            // reorder=<label>&drag=<id>&path=<row id>:<f>,…: the row dragged over each row f of the way down,
            // as a drag would; "reorder <label>: ticks=<n> places=<…>" (#883).
            if let label = dict["reorder"] {
                let path = (dict["path"] ?? "").split(separator: ",").compactMap { step -> (row: UUID, f: CGFloat)? in
                    let parts = step.split(separator: ":")
                    guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let f = Double(parts[1]) else { return nil }
                    return (id, CGFloat(f))
                }
                guard let id = dict["drag"].flatMap(UUID.init(uuidString:)),
                      let r = SpaceListView.debugReorder(id, path: path, ui: main.sidebarUI) else {
                    CraLog.note("reorder \(label): no row"); return
                }
                CraLog.note("reorder \(label): ticks=\(r.ticks) places=\(r.places.joined(separator: ","))")
                return
            }
            // folderPreviewOpen=<label>: "Cra folderPreview <label>: open=<folder id>" or "open=none" (#743).
            if let label = dict["folderPreviewOpen"] {
                let open = FolderPreviewController.shared.isOpen ? FolderPreviewController.shared.folderID?.uuidString ?? "none" : "none"
                NSLog("Cra folderPreview %@: open=%@", label, open)
                return
            }
            if let f = dict["folderPreview"] {
                if let id = UUID(uuidString: f) { SpaceListView.debugFolderPreview(id, ui: main.sidebarUI) } else {
                    FolderPreviewController.shared.preview?.debugPointer(onRow: -1)
                    FolderPreviewController.shared.close()
                }
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
            // siteControlsRead=1, siteControlsPress=<label>[&accessory=1]: the open Site Control
            // Center's action buttons and Boost rows, read or pressed (#478).
            if let label = dict["siteControlsRead"] { main.debugSiteControlsRead(label: label); return }
            if let label = dict["siteControlsPress"] { main.debugSiteControlsPress(label, accessory: dict["accessory"] == "1"); return }
            // The sidebar's URL field (toolbar hidden): hovered, and a press on one of its buttons (#226).
            if let v = dict["urlFieldHover"] { main.debugURLFieldHover(v == "1"); return }
            if let name = dict["urlFieldPress"] { main.debugURLFieldPress(name); return }
            // The URL field edited in place (#344): a click on it, then typing and Return or Escape.
            if let step = dict["urlFieldEdit"] { main.debugURLFieldEdit(step); return }
            // The toolbar's address edited in place (Settings ▸ Tabs, with the toolbar shown).
            if let step = dict["toolbarAddressEdit"] { main.debugToolbarAddressEdit(step); return }
            // The sidebar header's address row (#648): "sidebar address <label>: url=… back=… forward=…",
            // and a press on its back, forward or reload.
            if let label = dict["sidebarAddress"] {
                CraLog.note("sidebar address \(label): " + ((main.shell.sidebarHost as? SidebarView)?.debugAddressRow ?? "none"))
                return
            }
            if let key = dict["sidebarAddressPress"] {
                let pressed = (main.shell.sidebarHost as? SidebarView)?.debugPressAddressRow(key) == true
                CraLog.note("sidebar address press \(key): \(pressed ? "pressed" : "not pressed")")
                return
            }
            if let step = dict["commandBarNotice"] { main.debugCommandBarNotice(step); return }
            if let step = dict["commandBarScope"] { main.debugCommandBarScope(step); return }
            // Arc's translate UI (#310): what shows, and a press on its parts.
            if let step = dict["translate"] { main.debugTranslate(step); return }
            // The n-th space icon's tip, without a pointer.
            if let n = dict["spaceTip"].flatMap({ Int($0) }), let content = main.window?.contentView {
                ArcTooltipController.shared.debugShowSpaceTip(n, in: content)
                return
            }
            // tooltipShown=<label>: whether a tip is on screen.
            if let label = dict["tooltipShown"] {
                CraLog.note("tooltip \(label): shown=\(ArcTooltipController.shared.debugShown ? 1 : 0)")
                return
            }
            if let t = dict["tooltip"], let content = main.window?.contentView {
                ArcTooltipController.shared.debugShow(t, in: content, at: NSRect(x: 380, y: content.bounds.height - 120, width: 28, height: 28))
                return
            }
            // newSpacePull=<pt>: Arc's "+" with the list overscrolled that far past the last space, and
            // what it shows; newSpacePull=lift lets go, and &lift=1 lets go in the same breath.
            if let pull = dict["newSpacePull"] {
                main.debugNewSpacePull(Double(pull).map { CGFloat($0) }, lift: pull == "lift" || dict["lift"] != nil)
                return
            }
            // spaceCreation=state|type:<name>|icon:<emoji>|symbol:<name>|theme:<n>|profile:<n>|engine:<keyword>|create|cancel: Arc's
            // Create a Space page, one step on it, and what it and the dock then show.
            // plusMenu=<label>: the colours the sidebar's + menu opens with (#822: dark or light with the Mac's appearance).
            if let label = dict["plusMenu"] {
                CraLog.note("plus menu \(label): " + ((main.shell.sidebarHost as? SidebarView)?.debugCreationMenuColors() ?? "no sidebar"))
                return
            }
            // arcMenus=<label>: the colours the capture menu, Back's history menu and the ••• menu open with (#822).
            if let label = dict["arcMenus"] { CraLog.note(main.debugArcMenuColors(label)); return }
            if let step = dict["spaceCreation"] { main.debugSpaceCreation(step); return }
            if let g = dict["swipe"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
                // &releaseStall=<ms>: the main thread held that long after the release, as a busy space switch holds it (#613).
                main.debugSpaceSwipe(dx: g[0], steps: Int(g[1]), stall: Int(dict["releaseStall"] ?? "") ?? 0)
                return
            }
            // hiddenLibraryReveal=<0…1>: the Library held that far in from a hidden sidebar, and where
            // it, the page and the floating sidebar are; hiddenLibraryReveal=lift lets go.
            if let r = dict["hiddenLibraryReveal"] {
                main.debugHiddenLibraryReveal(CGFloat(Double(r) ?? 0), lift: r == "lift")
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
            // floatingSidebar=1 out, =0 away, =hold out and kept there whatever the pointer does (#424).
            // =release lets the pointer decide again without sending it away; =state:<step> logs it (#531).
            if let f = dict["floatingSidebar"], f.hasPrefix("state") { main.debugFloatingSidebarState(String(f.dropFirst(6))); return }
            // floatingSidebar=still<label> (#635): whether the edge strip waits for the pointer to move.
            if dict["floatingSidebar"] == "stillreset" { main.floatingSidebar?.debugPointerMoved(); return }
            if let f = dict["floatingSidebar"], f.hasPrefix("still") {
                CraLog.note("floating sidebar \(f): waits=\(main.floatingSidebar?.stillPointer == nil ? 0 : 1)")
                return
            }
            if dict["floatingSidebar"] == "release" { main.floatingSidebar?.heldOut = false; return }
            // floatingSidebar=pointerAway: the pointer left it, as the poll would find, so it goes unless something
            // keeps it out (FloatingSidebarKeepOut: its address being edited, #691).
            if dict["floatingSidebar"] == "pointerAway" { main.floatingSidebar?.requestAutomaticHide(); return }
            // extensionPopup=<step>: whether an extension's popup is up and where it hangs (#531).
            if let step = dict["extensionPopup"] { main.debugExtensionPopup(step); return }
            if let f = dict["floatingSidebar"] {
                main.floatingSidebar?.heldOut = f == "hold"
                if f == "1" || f == "hold" { main.floatingSidebar?.show(why: "a scenario") } else { main.floatingSidebar?.hide(animated: true) }
                return
            }
            if let method = dict["bcdp"] {
                // To cra.log: a scenario reads it after a relaunch too, when stdout isn't kept (#299).
                CraCEFRuntime.sendBrowserDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    CraLog.note("bcdp \(method) → \(result ?? "error: \(error ?? "?")")")
                }
                return
            }
            // nextPageMenuCommand=<IDC name>: the next page right-click runs that item of Chromium's menu
            // instead of showing it (#348: View Page Source); pair it with a right-click through cdp.
            if let name = dict["nextPageMenuCommand"] {
                NSLog("Cra next page menu command %@: %@", name, CraCEFRuntime.runNextPageMenuCommand(name) ? "set" : "unknown")
                return
            }
            // menuShown=next: the next menu that opens logs its rows and closes. A page's right-click menu has to
            // open on screen, not only be built (#466: 0.1.44 built it and never showed it).
            if dict["menuShown"] == "next" {
                var token: NSObjectProtocol?
                token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
                    guard let menu = note.object as? NSMenu else { return }
                    if let token { NotificationCenter.default.removeObserver(token) }
                    token = nil
                    let rows = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
                    NSLog("Cra menu shown: %@", rows.joined(separator: "|"))
                    RunLoop.main.perform(inModes: [.eventTracking, .default]) { menu.cancelTrackingWithoutAnimation() }
                }
                NSLog("Cra menu shown: waiting")
                return
            }
            // pagePixel=<label>&x=<css px>&y=<css px>: the current page's colour there as drawn, a one-pixel
            // DevTools capture, logged as sRGB r/g/b (boost-tint, #602).
            if let label = dict["pagePixel"], let x = dict["x"].flatMap(Double.init), let y = dict["y"].flatMap(Double.init) {
                let params = "{\"format\":\"png\",\"clip\":{\"x\":\(x),\"y\":\(y),\"width\":1,\"height\":1,\"scale\":1}}"
                main.currentBrowser?.sendDevToolsMethod("Page.captureScreenshot", params: params) { result, error in
                    guard let json = result?.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                          let base64 = object["data"] as? String, let png = Data(base64Encoded: base64),
                          let pixel = NSBitmapImageRep(data: png)?.converting(to: .sRGB, renderingIntent: .default)?.colorAt(x: 0, y: 0)
                    else { CraLog.note("Cra page pixel \(label): none \(error ?? "")"); return }
                    func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
                    CraLog.note("Cra page pixel \(label): \(byte(pixel.redComponent))/\(byte(pixel.greenComponent))/\(byte(pixel.blueComponent))")
                }
                return
            }
            // pageColours=<label>&seconds=<s>[&target=little]: the colours on screen at the centre of the current page,
            // or of the next Little Window or Peek to open, every frame for that long, as runs: a page opening on a
            // dark site shows Arc's canvas until it draws, never Chromium's white (X, 22 Nov).
            if let label = dict["pageColours"] {
                let seconds = dict["seconds"].flatMap(Double.init) ?? 3
                let before = littleWindows.count
                let little = dict["target"] == "little"
                WindowColourProbe.record(seconds: seconds, view: { [weak self] in
                    guard let self else { return nil }
                    if little { return self.littleWindows.count > before ? self.littleWindows.last?.browser?.containerView : nil }
                    return self.main.currentBrowser?.containerView
                }) { CraLog.note("Cra page colours \(label): \($0)") }
                return
            }
            if let method = dict["cdp"] {
                // target=little: the newest Little Window's (or Peek's) page; tab=<id>: that tab's page.
                let tab = dict["tab"].flatMap(UUID.init(uuidString:)).flatMap { main.browsers.runtime(for: $0)?.browser }
                let b = dict["target"] == "little" ? littleWindows.last?.browser : tab ?? main.currentBrowser
                b?.sendDevToolsMethod(method, params: dict["params"] ?? "{}") { result, error in
                    CraLog.note("Cra cdp \(method) → \(result ?? "error: \(error ?? "?")")")
                }
                return
            }
            // pluginFetch=<url>: the session fetch a live folder's plug-in makes; logs what the plug-in would see.
            if let url = dict["pluginFetch"] {
                CraCEFRuntime.fetchPluginURL(url, headers: nil, profilePath: nil) { status, finalURL, _, body in
                    CraLog.note("plugin fetch status=\(status) body=\(body.isEmpty ? "empty" : "\(body.count) chars") url=\(finalURL)")
                }
                return
            }
            // glyphs=<View[,n]>: the sidebar glyph buttons in that view (as `snapshot` finds it), each as
            // its symbol and tip: a live folder's key or warning (#521). press=1 then clicks the first.
            if let spec = dict["glyphs"] {
                var buttons: [SidebarGlyphButton] = []
                func walk(_ v: NSView) {
                    if let b = v as? SidebarGlyphButton, !b.isHidden { buttons.append(b) }
                    v.subviews.forEach(walk)
                }
                if let view = ViewSnapshot.find(spec, in: main.window) { walk(view) }
                CraLog.note("Cra glyphs \(spec): \(buttons.map(\.debugReadout).joined(separator: " | "))")
                if dict["press"] == "1" { buttons.first?.action() }
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
            // browserWindows=<label>: each browser window's kind, space, tabs (URLs), open tab and frame (#219, #220),
            // and the Library page its sidebar shows (#590).
            if let label = dict["browserWindows"] {
                CraLog.note("browser windows \(label): count=\(mainWindows.filter { $0.window?.isVisible == true }.count)")
                for m in mainWindows {
                    let space = m.focusedSpace
                    let tabs = (store.tabs(under: space.pinnedContainerID) + store.tabs(under: space.todayContainerID)).compactMap { $0.tab?.url }
                    let open = store.selectedTabID(window: m.windowID).flatMap { store.item($0)?.tab?.url } ?? "-"
                    let folders = (store.children(of: space.pinnedContainerID) + store.children(of: space.todayContainerID)).filter { $0.isFolder && !$0.isTabGroup }
                    NSLog("Cra browser windows %@: kind=%@ space=%@ listed=%d tabs=[%@] open=%@ page=%d frame=%@ onTop=%d pinnedCollapsed=%d openFolders=%d/%d commandBar=%d pages=%d active=%d library=%@", label,
                          m.isBlank ? "blank" : m.isIncognito ? "incognito" : "normal", space.title,
                          store.orderedSpaces.contains { $0.id == space.id } ? 1 : 0, tabs.joined(separator: " "), open,
                          store.selectedTabID(window: m.windowID).flatMap { m.browsers.runtime(for: $0) } != nil ? 1 : 0,
                          m.window.map { NSStringFromRect($0.frame) } ?? "-", m.staysOnTop ? 1 : 0,
                          store.isPinnedCollapsed(space.id) ? 1 : 0, folders.filter { store.isExpanded($0.id) }.count, folders.count,
                          m.commandBar.isOpen ? 1 : 0, m.browsers.runtimes.count, store.activeWindowID == m.windowID ? 1 : 0,
                          m.sidebarUI.libraryPage?.rawValue ?? "-")
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
            // answerDialog=<button>: presses that button of the open dialog sheet and logs its title and
            // what the button copied (#356: the share warning before a link is copied).
            if let button = dict["answerDialog"] {
                guard let dialog = AppDialog.presented, let index = dialog.actions.buttons.firstIndex(where: { $0.title == button }) else {
                    CraLog.note("dialog answer \(button): no dialog"); return
                }
                // tick=1: its checkbox ticked first ("Always allow", "Never show me this again", #785).
                if dict["tick"] == "1" { dialog.isSuppressed = true }
                let copied = MainWindowController.probeClipboard { dialog.select(index) }
                CraLog.note("dialog \(dialog.title) answered \(button): \(copied)")
                return
            }
            // permissionCard[=<button>]: the permission card up, where it sits on its page and
            // whether it took the window's key, then presses that button (#371).
            if let button = dict["permissionCard"] {
                CraLog.note(PermissionPopover.debug(press: button.isEmpty || button == "1" ? nil : button))
                return
            }
            // pickedMenu=<n>[&label=][&run=<row>]: the menu on n picked tabs, see testPickedMenu (#356).
            if let n = dict["pickedMenu"].flatMap(Int.init) {
                main.testPickedMenu(count: n, label: dict["label"] ?? "\(n)", run: dict["run"])
                return
            }
            // incognitoWindow=<url>: a page's Open Link in Incognito Window, a new incognito window
            // showing that page, without the command bar's keys (#412).
            if let url = dict["incognitoWindow"] {
                openLink(url, in: .incognito, space: nil, fromIncognito: false)
                return
            }
            // spaceMenu=<label>[&window=incognito]: the open space's header menu in the window in use,
            // or the newest incognito window (#413).
            if let label = dict["spaceMenu"] {
                let target = dict["window"] == "incognito" ? mainWindows.last(where: \.isIncognito) : main
                guard let target else { CraLog.note("space menu \(label): no window"); return }
                target.testSpaceMenu(label: label)
                return
            }
            // tabMenu=<n>[&label=][&run=<row>]: the n-th listed tab's menu, see testTabMenu (#600).
            if let n = dict["tabMenu"].flatMap(Int.init) {
                main.testTabMenu(n, label: dict["label"] ?? "\(n)", run: dict["run"])
                return
            }
            // splitMenu=<n>[&label=][&run=<row>]: the n-th split row's menu, from the top (#600).
            if let n = dict["splitMenu"].flatMap(Int.init) {
                main.testTabMenu(n, label: dict["label"] ?? "\(n)", run: dict["run"], split: true)
                return
            }
            // folderMenu=<n>[&label=][&run=<row>]: the n-th visible folder's menu (#662).
            if let n = dict["folderMenu"].flatMap(Int.init) {
                main.testTabMenu(n, label: dict["label"] ?? "\(n)", run: dict["run"], folder: true)
                return
            }
            // favoriteMenu=<n>[&label=][&run=<row>]: the n-th favorite tile's menu, see testFavoriteMenu (#387); run=- reads the lists only.
            if let n = dict["favoriteMenu"].flatMap(Int.init) {
                main.testFavoriteMenu(tile: n, label: dict["label"] ?? "\(n)", run: dict["run"])
                return
            }
            // liveTabs=<label>: each live folder's tabs, the address each shows and its item's, so a scenario sees
            // which ones a refresh or the expiry pass left (#697).
            if let label = dict["liveTabs"] {
                let rows = store.liveFolders.map { folder in
                    "\(folder.title ?? "folder") [" + store.tabs(under: folder.id).compactMap { c in
                        c.tab.map { "\($0.url)\($0.liveItemURL.map { " (item \($0))" } ?? "")" }
                    }.joined(separator: ", ") + "]"
                }
                CraLog.note("live tabs \(label): \(rows.isEmpty ? "none" : rows.joined(separator: "; "))")
                return
            }
            // tabMute=<label>: every loaded page's mute, as the tab saved it and as its engine has the
            // page, so a muted tab that comes back (relaunch, sleep, a popup) is seen to stay quiet (#387).
            if let label = dict["tabMute"] {
                let rows = mainWindows.flatMap { $0.browsers.runtimes.values }.compactMap { rt -> String? in
                    guard let tab = store.item(rt.tabID)?.tab else { return nil }
                    return "\(tab.url) saved=\(tab.muted ? "muted" : "unmuted") page=\(rt.browser.isAudioMuted() ? "muted" : "unmuted")"
                }.sorted()
                CraLog.note("tab mute \(label): \(rows.isEmpty ? "none" : rows.joined(separator: ", "))")
                return
            }
            // pickedCopy=<c2,s3…>[&label=]: rows ⌘/⇧-clicked, then ⇧⌘C typed; see testPickedCopy (#322).
            if let clicks = dict["pickedCopy"] {
                main.testPickedCopy(clicks: clicks, label: dict["label"] ?? clicks)
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
            // sidebarEdge=doubleClick: a double click on the sidebar's edge (#819).
            if dict["sidebarEdge"] == "doubleClick" { main.testSidebarEdgeDoubleClick(); return }
            // edgeDrag=next|previous[&hold=<seconds>]: a row's drag held just past the sidebar's right or
            // left edge, which pages to the space on that side every SidebarEdgeDrag.delay (#499).
            if let edge = dict["edgeDrag"] {
                main.testEdgeDrag(edge == "previous" ? .previous : .next, hold: dict["hold"].flatMap(Double.init) ?? 0.8)
                return
            }
            // dropLink=<url>[&name=<link text>][&before=<text>|&onto=<text>]: a link let go on the focused
            // space's list, below the last row, or on the top or the middle of the row whose tab's URL
            // holds the text (#419).
            if let url = dict["dropLink"] {
                main.testDropLink(url, name: dict["name"], row: dict["before"] ?? dict["onto"], onto: dict["onto"] != nil)
                return
            }
            // dropFile=<path>: that file let go in the middle of the shown page, as from the Finder (#593).
            if let path = dict["dropFile"], let container = main.currentBrowser?.containerView {
                DebugFileDrop.drop(path, on: container)
                return
            }
            // dropSplit=<text>[&link=1][&name=<link text>]&x=<0…1>&y=<0…1>: the tab whose URL holds the
            // text (or a page's link to it) let go over the panes, at that fraction from their top left (#419).
            if let text = dict["dropSplit"] {
                main.splitDrop.test(text, link: dict["link"] != nil, name: dict["name"],
                                    x: Double(dict["x"] ?? "") ?? 0.5, y: Double(dict["y"] ?? "") ?? 0.5)
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
        // The menu bar's Tabs rows can act only when there is something to act on (CraCore TabsMenu, #622).
        if let id = item.representedObject as? String, item.menu === tabsMenu, let state = tabsMenuState(id) {
            if let title = state.title, item.title != title { item.title = title }
            return state.enabled
        }
        switch item.representedObject as? String {
        case "collapsePinned": return !main.isStandalone
        // A Little Window in front answers for itself (#333).
        case "stayOnTop": item.state = (keyLittleWindow?.staysOnTop ?? main.staysOnTop) ? .on : .off
        case "allowAppleEventsJavaScript": item.state = store.settings.allowAppleEventsJavaScript ? .on : .off
        case "appearanceAutomatic", "appearanceLight", "appearanceDark":
            item.state = "appearance" + store.settings.websiteAppearance.title == item.representedObject as? String ? .on : .off
        case "copyURLQuote", "savePageAs", "captureFullPage", "capturePortrait", "share":
            if let little = keyLittleWindow { return little.hasPage }
            return store.selectedTabID != nil
        case "revealTab": return store.selectedTabID != nil
        case "closeTab":
            // Arc shows Close Tab only while a tab is selected; ⌘W still closes the window (#279).
            item.isHidden = !FileMenu.shows("closeTab", tabSelected: store.selectedTabID != nil)
        case "newProfile": return !main.isIncognito
        case "clearArchive": return !store.archive.isEmpty
        case "resetSpaceTabs": return !main.isStandalone
        case "toggleDeveloperMode":
            let url = keyLittleWindow.map { $0.hasPage ? $0.currentURL : nil } ?? store.selectedTab?.tab?.url
            let on = url.map { store.settings.isDeveloperMode(url: $0) } ?? false
            item.title = on ? "Turn off Developer Mode for this Site" : "Turn on Developer Mode for this Site"
        case "pinTab":
            item.title = store.selectedTabID.map { store.isPinned($0) ? "Unpin Tab" : "Pin Tab" } ?? "Pin/Unpin Tab"
            return !main.isBlank  // a Blank Window has no pinned section (Arc)
        case "setDefaultBrowser":
            SystemIntegration.shared.refresh()
            return !SystemIntegration.shared.isDefaultBrowser
        case "pictureInPicture":
            let browser = keyLittleWindow.map { $0.browser } ?? main.currentBrowser
            item.title = browser?.isInPictureInPicture == true ? "Exit Picture in Picture" : "Picture in Picture"
        // Arc: Tabs ▸ "Open in <space>", there only while a Little Window or Peek is in front.
        case TabsMenu.openIn:
            let little = keyLittleWindow.flatMap { $0.hasPage ? $0 : nil }
            item.isHidden = !TabsMenu.showsOpenIn(littleWindowWithPage: little != nil)
            if let space = little?.openInSpace {
                let title = SpaceMenuTitle.named(space.title, prefix: "Open in ")
                SpaceMenuTitle.apply(title, to: item)
                item.image = SpaceMenuIcon.image(for: space)
            }
            return little != nil
        case "littleWindowOpenInMenu": return keyLittleWindow?.hasPage ?? false
        case "checkForUpdates": return SoftwareUpdater.shared.validateMenuItem(item)
        case "closeSplitPane", "separateFromSplit", "flipSplitOrientation", "expandSplitPane":
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
    /// The swipe Logi Options+ posts for its own Back and Forward, and a three-finger swipe.
    private var sideButtonSwipeMonitor: Any?
    private func installKeyFallbackMonitor() {
        guard keyFallbackMonitor == nil else { return }
        keyFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc drops a ⌘/⇧-click tab selection before anything else sees it.
            if event.keyCode == 53, !(event.window is DialogPanel), let ui = self?.main.sidebarUI, !ui.multiSelection.isEmpty {
                ui.clearPicks()
                return nil
            }
            guard let self, event.modifierFlags.intersection([.command, .control]).isEmpty == false,
                  let window = event.window else { return event }
            // The command bar's own panel keeps its keys (its field's ⌘A, ⌘Z…) but ⌘W, which goes to the
            // bar's window: in a window with no tab the File menu hides Close Tab and the panel has no close
            // button of its own, so ⌘W went nowhere (#644).
            let fromBar = window === self.main?.openCommandPanel
            guard window.windowController is MainWindowController || window === self.main.window || fromBar else { return event }
            if !fromBar, self.undoClosedTab(event) { return nil }
            guard let action = self.bindings.action(for: event), !fromBar || action.id == "closeTab" else { return event }
            // Let the menu bar take it first (normal path); only act when it cannot. A row the menu hides
            // still matches its key and runs nothing: Close Tab with no tab selected, where ⌘W is the
            // window's (FileMenu.shows, #644).
            let rowHidden = !FileMenu.shows(action.id, tabSelected: self.store.selectedTabID != nil)
            if !rowHidden, NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return nil }
            // A dimmed row's key goes on to an extension that has it, as in Arc: Obsidian Web Clipper's ⌘⇧O in a
            // browser window, where Show Little Window "Open In" Menu can't run (#744).
            if ExtensionCommands.extensionTakes(craMenuRanIt: false, craRowHidden: rowHidden), self.runExtensionCommand(event) { return nil }
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
            // Typed on the keyboard it is the page's (YouTube's chapters, #714); only a mouse driver's posted one acts.
            let keyboard = MouseButtonSpaceSwitch.typedOnKeyboard(sourcePID: event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0)
            guard let action = MouseButtonSpaceSwitch.action(offset: offset, pointerOverSidebar: overSidebar, editingText: editing,
                                                              isRepeat: event.isARepeat, typedOnKeyboard: keyboard) else {
                if !event.isARepeat { CraLog.note("mouse key \(which): left for \(editing ? "text" : "the page, typed on the keyboard")") }
                return event
            }
            switch action {
            case .swallow:
                return nil
            case .switchSpace(let step):
                if let window = self.mainWindows.first(where: { $0.pointerOverSidebar() }) {
                    window.stepSidebarPage(step)
                }
                CraLog.note("mouse key \(which): switched space")
            case .history(let step):
                guard let browser = self.keyLittleWindow?.browser ?? self.keyMainWindow()?.currentBrowser else {
                    CraLog.note("mouse key \(which): history, no window in front")
                    return event
                }
                if step < 0 { browser.goBack() } else { browser.goForward() }
                CraLog.note("mouse key \(which): history")
            }
            return nil
        }
        // Logi Options+'s own Back and Forward (an MX Ergo's or MX Master's default) and a
        // trackpad's three-finger swipe between pages post a swipe event, not a button or a key.
        // Chromium's page view leaves `swipeWithEvent:` to Chrome's browser window, which Cra's
        // pages don't have, so nothing went back. A swipe goes to the page under the pointer and
        // stays in that page's own history, like Arc's mouse back button: a tab a link opened
        // doesn't close back to its opener here (only the toolbar's Back and ⌘[ do that, #273).
        sideButtonSwipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            guard let self, let offset = MouseButtonSpaceSwitch.offset(swipeDeltaX: event.deltaX, deltaY: event.deltaY),
                  let target = event.window else { return event }
            let which = offset < 0 ? "back" : "forward"
            if let window = self.mainWindows.first(where: { $0.pointerOverSidebar() }) {
                window.stepSidebarPage(offset)
                CraLog.note("mouse swipe \(which): switched space")
                return nil
            }
            if let little = self.littleWindows.first(where: { !$0.isParked && $0.window != nil && (target === $0.window || target.parent === $0.window) }),
               let browser = little.browser {
                if offset < 0 { browser.goBack() } else { browser.goForward() }
            } else if let hit = self.mainWindows.lazy.compactMap({ m in m.pageTab(under: event).map { (main: m, id: $0) } }).first {
                let browser = hit.main.browsers.runtime(for: hit.id)?.browser
                if offset < 0 { browser?.goBack() } else { browser?.goForward() }
            } else {
                return event
            }
            CraLog.note("mouse swipe \(which): history")
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

    /// The clipboard ⌥⌘V reads: the Mac's, or with CRA_TEST_PASTEBOARD a named one of the test copy's own,
    /// so a scenario never touches what the user copied (cra://debug?setPasteboard=).
    static let pasteboard: NSPasteboard = ProcessInfo.processInfo.environment["CRA_TEST_PASTEBOARD"]
        .map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general

    /// ⌥⌘V: the clipboard as a new tab, an address or a search, or a paste where you type (#610).
    private func pasteAndGo(clipboard: String?, in main: MainWindowController) {
        // The key window's field, or with none (Cra in the background) the shown page's.
        let window = NSApp.keyWindow ?? main.currentBrowser?.hostWindow ?? main.window
        switch PasteAndGo.outcome(typing: textFieldHasKey(in: window), clipboard: clipboard) {
        case .paste:
            CraLog.note("paste and go: pasted into the field")
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case .open(let text):
            CraLog.note("paste and go: \(SuggestionEngine.looksLikeURL(text) ? "address" : "search")")
            main.sidebarActions.openTyped(text)
        case .nothing:
            CraLog.note("paste and go: nothing to open")
            NSSound.beep()
        }
    }

    /// A text field, or a page input, has the key: ⌥← moves by word there, and ⌘Z undoes text
    /// rather than the last closed tab. Chromium's page view reports its ui::TextInputType (0 = none).
    private func textFieldHasKey(_ event: NSEvent) -> Bool { textFieldHasKey(in: event.window ?? NSApp.keyWindow) }

    private func textFieldHasKey(in window: NSWindow?) -> Bool {
        let responder = window?.firstResponder
        if responder is NSText { return true }
        if let view = responder as? NSView, NSStringFromClass(type(of: view)) == "RenderWidgetHostViewCocoa",
           view.responds(to: NSSelectorFromString("textInputType")),
           (view.value(forKey: "textInputType") as? Int ?? 0) != 0 { return true }
        return false
    }

    /// A key before the page sees it: Cra takes native window commands, the shortcuts that prefer
    /// Cra, and Use Both's second press of a shortcut the page kept (Settings ▸ Shortcuts, #374).
    /// The rest go to the page and come back through handleUnhandledKey if it leaves them alone.
    /// An extension's shortcut (chrome://extensions/shortcuts) pressed in a browser window: the ones that
    /// open its popup run as a click on its button does (#701); its own commands (chrome.commands.onCommand) go to
    /// the extension through the engine, with the page as the active tab. Global ones are the system's hot keys.
    /// Close Tab or Close Window typed in an extension's popup: the popup closes, not the tab behind it (#727). Chrome's
    /// bubble has the keyboard and would take the key before Cra's menu.
    private func closesExtensionPopup(_ event: NSEvent) -> Bool {
        guard !event.isARepeat, let id = bindings.action(for: event)?.id, ["closeTab", "closeWindow"].contains(id),
              ExtensionPopupWindow.closes(forCloseCommandIn: event.window ?? NSApp.keyWindow) else { return false }
        CraLog.note("extension popup: \(id) closes it")
        return true
    }

    /// A key a page in a browser window is about to get (the engine's key hook, before the page): an extension's shortcut
    /// comes first, as in Chrome and Arc. Cra hands ⌘ keys to the page that has the keyboard before the app-wide watch
    /// that runs extensions' shortcuts sees them (CraApplication.sendEvent), so the clipper's ⌘⇧O, and any ⌘ key set for
    /// "Activate the extension", reached only the page and then Cra's own command (#744). A key whose Cra row can run
    /// here stays Cra's.
    func runExtensionCommandBeforePage(_ event: NSEvent) -> Bool {
        // Typing: an extension's shortcut always holds ⌘, ⌥ or ⌃.
        guard !event.modifierFlags.isDisjoint(with: [.command, .option, .control]) else { return false }
        let action = bindings.action(for: event)
        let hidden = action.map { !FileMenu.shows($0.id, tabSelected: store.selectedTabID != nil) } ?? false
        let canRun = action.map { a in menuRow(a.id).map { validateMenuItem($0) } ?? true }
        guard ExtensionCommands.extensionTakesBeforePage(craRowCanRun: canRun, craRowHidden: hidden) else { return false }
        return runExtensionCommand(event)
    }

    /// The menu bar's row for one of Cra's commands, if it has one.
    private func menuRow(_ id: String) -> NSMenuItem? {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.representedObject as? String == id, item.target === self { return item }
                if let sub = item.submenu, let found = find(sub) { return found }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(find)
    }

    /// The key press an extension's shortcut last ran for: the app-wide watch and the page's key hook can both see one.
    private var extensionCommandPress: TimeInterval?

    private func runExtensionCommand(_ event: NSEvent) -> Bool {
        let held = event.modifierFlags.intersection([.command, .option, .control])
        guard !held.isEmpty, !event.isARepeat, let main, event.window === main.window || event.window?.parent === main.window else { return false }
        if extensionCommandPress == event.timestamp { return true }
        // chrome://extensions/shortcuts records a key by its press: Chrome holds its shortcuts back there.
        if main.selectedTab?.tab?.url.hasPrefix("chrome://extensions") == true { return false }
        let path = store.profilePath(profile: main.focusedSpace.profileID)
        guard let json = CraCEFRuntime.preference("extensions.commands", forProfile: path) else { return false }
        let bindings = ExtensionCommands.bindings(prefJSON: json)
        guard !bindings.isEmpty,
              let binding = ExtensionCommands.binding(in: bindings, characters: event.charactersIgnoringModifiers ?? "",
                                                      keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue) else { return false }
        extensionCommandPress = event.timestamp
        guard ExtensionCommands.opensPopup(binding.command) else {
            // Its own command: the engine delivers it to the extension with this page as the active tab (engine -19).
            let page = main.currentBrowser
            let sent = page?.responds(to: #selector(CraBrowser.runExtensionCommand(_:extension:))) == true
                && page?.runExtensionCommand(binding.command, extension: binding.extensionID) == true
            CraLog.note("extension command \(binding.extensionID.prefix(8)) \(binding.command): \(sent ? "sent" : "not sent")")
            return sent
        }
        CraLog.note("extension command \(binding.extensionID.prefix(8)): opens its popup")
        main.runExtensionAction(binding.extensionID)
        return true
    }

    /// The page Handoff offers: a Little Window's or Peek's while it is in front, else the active window's selected tab.
    private func handoffPage() -> HandoffPublisher.Page? {
        if let little = keyLittleWindow {
            return .init(address: little.state.url, offTheRecord: little.browser?.isIncognito ?? false)
        }
        guard let main else { return nil }
        return .init(address: main.selectedTab?.tab?.url ?? "", offTheRecord: main.isIncognito)
    }

    func handleReservedKey(_ event: NSEvent) -> Bool {
        if performNativePageShortcut(event) { return true }
        guard let action = bindings.action(for: event) else { return false }
        let priority = bindings.priority(of: action.id)
        let takes: Bool
        if priority == .useBoth {
            takes = useBoth.beforePage(action.id, at: event.timestamp, isRepeat: event.isARepeat)
            if !takes, !event.isARepeat { watchUseBoth(action, pressedAt: event.timestamp, window: event.window) }
        } else {
            takes = priority.takesBeforePage()
        }
        guard takes else { return false }
        perform(action.id)
        return true
    }

    /// Quit, Hide, Hide Others, Minimize and Full Screen, as buildMenus makes them (`beforePage`).
    private var nativePageShortcuts: [NSMenuItem] = []

    /// A page can't keep the keys of the app and window commands macOS gives every app: Quit, Hide,
    /// Hide Others and Minimize run before the page sees them, so a page that cancels every key
    /// still lets Cra quit, hide and minimize (#480). Arc does the same with ⌘Q and ⌘M (measured
    /// 17 Nov 2026, Arc 1.172.2). Full Screen's keys go first only to leave full screen: Arc lets a
    /// page keep ⌃⌘F to enter it, and Chrome reserves it only in full screen
    /// (BrowserCommandController::IsReservedCommandOrKey). Keys the user gave a Cra shortcut are
    /// that shortcut's, with its own priority (Settings ▸ Shortcuts, #374).
    private func performNativePageShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, bindings.action(for: event) == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        guard !modifiers.isEmpty else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        let typed = event.characters?.lowercased()
        func matches(_ item: NSMenuItem) -> Bool {
            let equivalent = item.keyEquivalent
            let letter = equivalent.lowercased()
            guard letter == key || letter == typed else { return false }
            // AppKit also lets a menu encode Shift with an uppercase letter.
            var mask = item.keyEquivalentModifierMask
            if equivalent != letter { mask.insert(.shift) }
            return mask == modifiers
        }
        let shortcut = nativePageShortcuts.lazy.compactMap { item -> NSMenuItem? in
            if matches(item) { return item.copy() as? NSMenuItem }
            // macOS also installs an alternate for Full Screen (Fn+F and Control-Command-F).
            guard item.action == #selector(NSWindow.toggleFullScreen(_:)) else { return nil }
            return item.menu?.items.first { $0.action == item.action && matches($0) }?.copy() as? NSMenuItem
        }.first
        guard let shortcut else { return false }
        if shortcut.isAlternate { shortcut.isAlternate = false }

        if shortcut.action == #selector(NSWindow.performMiniaturize(_:)) || shortcut.action == #selector(NSWindow.toggleFullScreen(_:)) {
            // Chromium's page may own the keyboard in a child window. Act on its Cra window.
            // Stop at a Little Window or Peek before reaching the browser window behind it.
            var target = event.window ?? NSApp.keyWindow
            while let parent = target?.parent, !(target is CraWindow), !(target is LittleWindow) {
                target = parent
            }
            guard let target else { return false }
            if shortcut.action == #selector(NSWindow.toggleFullScreen(_:)), !target.styleMask.contains(.fullScreen) { return false }
            shortcut.target = target
        }

        // A menu of its own runs the native item alone, validated as the menu bar's is: Cra's quit
        // rules (Keep in menu bar, Quit Cra?) and whether the window can minimize (a Peek can't).
        let menu = NSMenu()
        menu.addItem(shortcut)
        menu.update()
        guard shortcut.isEnabled else { return false }
        return menu.performKeyEquivalent(with: event)
    }

    /// Use Both: a press the page hasn't handed back by UseBothPresses.answerTime was the page's. Cra
    /// says so in the window it was pressed in, as Arc's `webContentConsumedHotkey` toast does
    /// ("Press ⌘W again to Close Tab", with "Edit the shortcut"), and takes the next press while it shows.
    private func watchUseBoth(_ action: KeyAction, pressedAt: TimeInterval, window: NSWindow?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + UseBothPresses.answerTime) { [weak self, weak window] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard useBoth.pageKept(action.id, pressedAt: pressedAt, now: now, offerTime: ShinyToast.visibleFor) else { return }
            CraLog.note("shortcut \(action.id): the page kept it, Use Both offers the next press")
            let keys = bindings.action(action.id)?.primary?.display ?? ""
            let edit = ShinyToast.Action(title: "Edit the shortcut") { [weak self] in self?.showShortcutSettings(action.id) }
            let text = "Press \(keys) again to \(action.name.trimmingCharacters(in: CharacterSet(charactersIn: "…")))"
            // The page is a child window of the browser window or Little Window it shows in.
            var w = window
            while let x = w {
                if let little = littleWindows.first(where: { $0.window === x }) { little.showToast(text, action: edit); return }
                if let m = mainWindows.first(where: { $0.window === x }) { m.showToast(text, action: edit); return }
                w = x.parent
            }
            main.showToast(text, action: edit)
        }
    }

    /// Keys the page let through (CEF OnKeyEvent). Anything we know runs here;
    /// returning false lets CEF pass the key on to the menu bar (⌘Q, ⌘H…).
    func handleUnhandledKey(_ event: NSEvent) -> Bool {
        if undoClosedTab(event) { return true }
        // Chromium's page view takes every key equivalent before the menu bar, ⌘ or not, and
        // hands one the page left alone back to the menu bar through its own window's command
        // dispatcher (⌘C, ⌘V, ⌘A, ⌘Z exist only as Edit menu items). An embedded page sits in
        // Cra's window, which has none, so it goes to the menu bar here, first: the menu runs
        // the keys it shows, which AppKit fits to the keyboard layout (Turkish Q: Zoom In ⌘.,
        // Stop ⌘ç, Back ⌘ğ), the way the sidebar's keys go (GitHub #212). ⌃, ⌥ and F-keys too:
        // a System Settings App Shortcut such as ⌃` for Hide/Show Sidebar is a menu key (#253).
        if !event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty,
           let window = event.window ?? NSApp.keyWindow,
           !window.responds(to: NSSelectorFromString("commandDispatcher")),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        if let action = bindings.action(for: event) {
            perform(action.id)
            return true
        }
        return false
    }

    /// Arc: ⌘Z brings back the tab you closed last (closing registers an undo, GitHub #21), undoes
    /// the last Tidy, or puts back a favorite taken off with Remove Favorite (#806), unless the keyboard
    /// is in something with text to undo: a text field, or an editable element in a page (Chromium's
    /// page view reports its ui::TextInputType, 0 = none). On an Easel, ⌘Z undoes canvas edits instead.
    private func undoClosedTab(_ event: NSEvent) -> Bool {
        guard Shortcut("z", .command).matches(event), !textFieldHasKey(event), !easelHasKey(event) else { return false }
        // The last thing to undo may be a tidy (Arc's "Undo Tidy Tabs"); a tab closed since comes first.
        if store.undoTidy() || undoRemoveFavorite() { return true }
        perform("reopenClosedTab")
        return true
    }

    /// ⌘Z's Remove Favorite undo in the front window, unless something closed since comes back first.
    private func undoRemoveFavorite() -> Bool {
        guard keyLittleWindow == nil, !main.isIncognito else { return false }
        let peek = main.closedPeek.map { ReopenClosedTab.ClosedPeek(url: $0.url, tabID: $0.tabID, closedAt: $0.at) }
        return store.undoRemoveFavorite(in: main.windowID, peek: peek)
    }

    private func easelHasKey(_ event: NSEvent) -> Bool { easelHasKey(in: event.window ?? NSApp.keyWindow) }

    private func easelHasKey(in window: NSWindow?) -> Bool {
        let responder = window?.firstResponder
        if responder is EaselSheetView || responder is EaselCanvasView { return true }
        if let view = responder as? NSView {
            var curr: NSView? = view
            while let c = curr {
                if c is EaselSheetView || c is EaselCanvasView { return true }
                curr = c.superview
            }
        }
        if let main = window?.windowController as? MainWindowController, main.currentBrowser is EaselBrowser {
            return true
        }
        if let little = window?.windowController as? LittleWindowController, little.browser is EaselBrowser {
            return true
        }
        return false
    }

    func perform(_ id: String) {
        // A Use Both press the page left alone comes back by OnKeyEvent or, redispatched by Chromium,
        // through the menu bar: either way it ends here, so the page didn't keep it (#374).
        useBoth.pageLeft(id)
        // A Tabs row dimmed in the menu does nothing from its shortcut or the command bar either, and
        // isn't counted as used (#622).
        if tabsMenuState(id)?.enabled == false { return }
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
        // An extension's popup in front, its menu item picked (#727).
        if ["closeTab", "closeWindow"].contains(id), ExtensionPopupWindow.closes(forCloseCommandIn: NSApp.keyWindow) { return }
        // Settings in front closes on ⌘W, not the tab in the browser window behind it. With a
        // sheet up (an open panel) nothing closes: the sheet is answered first.
        if ["closeTab", "closeWindow"].contains(id), settingsInFront {
            if let settings = settingsWindow, settings.attachedSheet == nil { settings.performClose(nil) }
            return
        }
        // Every page in every window, whichever window is key (#438).
        if id == "pauseAllMedia" { pauseAllMediaFromCommand(); return }
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
        case "newSpace": main.beginSpaceCreation()
        case "newProfile": if !main.isIncognito, let w = main.window { main.showNewProfileDialog(over: w) }
        case "share": main.shareSelectedPage()
        case "newBoost": main.openBoostEditor()
        case "newEasel":
            guard !main.isIncognito else { break }
            let easel = Easel()
            _ = store.createTab(url: easel.url, title: easel.title, select: true, window: main.windowID)
        case NewDocumentApp.commandID:
            // The profile's "New documents" app, in a new tab of the current space (#375).
            guard !main.isIncognito,
                  let doc = store.settings.newDocumentApp(profileID: store.profileID(space: main.focusedSpaceID)) else { break }
            _ = store.createTab(url: doc.url, select: true, window: main.windowID)
        case "editSpace": if !main.isStandalone { main.showSpaceEditor(space: store.focusedSpace) }
        case "changeProfile": if !main.isStandalone { main.showChangeProfileDialog(forSpace: store.focusedSpace.id) }
        case "deleteSpace": if !main.isStandalone { confirmDeleteSpace(store.focusedSpace) }
        case "manageSpaces": if !main.isStandalone { main.showManageSpaces() }
        case "closeTab":
            // Arc: "Close current tab or window". With the command bar open over a tab, ⌘W closes the bar,
            // as Escape does, and the tab stays (#497); a window with no tab closes, bar and all (#644).
            let target = FileMenu.closeTab(commandBarOpen: main.commandBar.isOpen, tabSelected: current != nil)
            CraLog.note("close tab: \(target.rawValue)")
            switch target {
            case .commandBar: main.commandBar.close()
            case .tab: main.closeCurrentTab()
            case .window: main.window?.performClose(nil)
            }
        case "closeWindow": main.window?.performClose(nil)
        case "reopenClosedTab":
            guard !main.isIncognito else { break }  // incognito tabs leave nothing to restore
            // Arc: ⇧⌘T brings back the tab closed last, whether pinned, archived or a closed Peek.
            let peek = main.closedPeek.map { ReopenClosedTab.ClosedPeek(url: $0.url, tabID: $0.tabID, closedAt: $0.at) }
            let outcome = store.reopenLastClosed(in: main.windowID, peek: peek)
            if case .peek(let url, let tabID)? = outcome {
                main.closedPeek = nil
                if let tabID, store.item(tabID) != nil { store.selectTab(tabID, window: main.windowID) }
                openPeek(url: url, over: main, fromTab: tabID)
            }
        case "copyURL":
            // Arc: "Copy the current tab's URL without trackers"; with tabs picked in the sidebar,
            // every picked tab's, one per line ("Copied item links", #322).
            let ids = CleanURL.tabsToCopy(picked: main.sidebarUI.multiSelection,
                                          listed: store.listedTabIDs(in: main.focusedSpaceID), open: current)
            let urls = ids.compactMap { store.item($0)?.tab?.url }
            if urls.count > 1 {
                copy(CleanURL.links(urls))
                main.showToast("Copied item links")  // Arc's wording, lower case as in Arc
            } else if let url = urls.first.map(CleanURL.withoutTrackers) {
                copy(url)
                main.showToast("Copied Current URL", action: .share(url))
            }
        case "copyURLMarkdown":
            if let c = current, let it = store.item(c), let url = it.tab?.url {
                copy("[\(it.displayTitle)](\(CleanURL.withoutTrackers(url)))")
                main.showToast("Copied URL as Markdown")
            }
        case "copyURLQuote": main.copyURLAsQuote()
        case "pasteAndGo":
            // Read on the press: the user asked for the paste, so macOS lets it through or asks once.
            pasteAndGo(clipboard: Self.pasteboard.string(forType: .string), in: main)
        case "savePageAs": main.savePageAs()
        case "captureFullPage": main.captureFullPage()
        case "capturePortrait": main.capturePortrait()
        case "collapsePinned": if !main.isStandalone { store.togglePinnedCollapsed(main.focusedSpaceID) }
        case "revealTab": main.revealSelectedTab()
        case "resetSpaceTabs": main.resetAllPinnedTabs()
        case "collapseAllFolders": store.setAllFoldersExpanded(false, inSpace: main.focusedSpaceID)
        case "expandAllFolders": store.setAllFoldersExpanded(true, inSpace: main.focusedSpaceID)
        case "openExtensions":
            // From the keyboard with ⌘ held: Arc's picker (#709). The command bar's Return and a click carry no ⌘.
            let held = NSApp.currentEvent.map { $0.type == .keyDown && $0.modifierFlags.contains(.command) } ?? false
            main.openExtensions(commandHeld: held) { [bindings] e in bindings.action(for: e)?.id == "openExtensions" }
        case "manageExtensions": main.openExtensionsPage()
        case "cast": if main.currentBrowser?.runChromeCommand("IDC_ROUTE_MEDIA") != true { main.showToast("Nothing to Cast") }
        case "taskManager": openTaskManager()
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
        case "copyAppInfo":
            copy(appInfo())
            main.showToast("Copied Cra Info!")  // Arc's `basicInfoCopied` toast, "Copied Arc Info!"
        case "print": main.currentBrowser?.print()
        case "capturePage": main.capturePage()
        case ChatGPTCommandBar.actionID: main.newChatGPTMessage()
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
        case "clearCache": main.currentBrowser?.clearSiteDataAndReload(.cache)
        case "clearCookies": main.currentBrowser?.clearSiteDataAndReload(.cookies)
        case "clearSiteData": main.currentBrowser?.clearSiteDataAndReload(.siteData)
        // View ▸ Stop Loading while an agent's pill is up in the window: its Take Over (AgentPill).
        case "stop": if !main.takeOverFromAgent() { main.currentBrowser?.stopLoading() }
        case "zoomIn": main.zoom(in: true)
        case "zoomOut": main.zoom(in: false)
        case "resetZoom": main.resetPageZoom()
        case "viewSource": main.currentBrowser?.viewSource()
        // Like Arc: ⌥⌘I closes open DevTools; ⌥⌘J and Network switch to their panel and close
        // DevTools only when that panel already shows (DevToolsToggle.run).
        case "devTools": main.browsers.runDevTools(.toggle)
        case "jsConsole": main.browsers.runDevTools(.console)
        case "networkPanel": main.browsers.runDevTools(.network)
        case "inspectElement": main.browsers.runDevTools(.inspect)
        // Arc's Library is a mode of the window's sidebar; ⇧⌘J opens it on Downloads.
        case "openLibrary": main.toggleLibrary()
        // Arc's View History (⌘Y): Chromium's page in the space's profile, not the archive (#590).
        case HistoryPage.action:
            let normal = useNormalWindow()
            _ = store.createTab(url: HistoryPage.url, select: true)
            normal.showWindow(nil)
        // View Downloads (⇧⌘J) is a show/hide toggle like Open Library, as in Arc (LibraryShortcut, #649). The other
        // pages' commands (no key of their own) show their page: the command bar and scripts ask for a page.
        case "viewDownloads": main.toggleLibrary(.downloads)
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
        // Arc's Duplicate Current Tab (command bar) leaves the copy in the background too (#600).
        case "duplicateTab": if let c = current { store.duplicateTab(c, window: main.windowID) }
        case "resetTab": if let c = current { main.resetPinnedTab(c) }
        case "muteTab":
            if let c = current, let t = store.item(c)?.tab {
                store.setMuted(c, !t.muted)
                runtime(for: c)?.browser.setAudioMuted(!t.muted)
            }
        case "clearToday": store.clearToday(playing: main.sidebarUI.audibleTabIDs)
        case "pictureInPicture": main.currentBrowser?.requestPictureInPicture(automatic: false)
        case "nextTab": main.cycleTab(1)
        case "previousTab": main.cycleTab(-1)
        case "recentTab": main.cycleRecentTabs(1, event: NSApp.currentEvent)
        case "recentTabBackward": main.cycleRecentTabs(-1, event: NSApp.currentEvent)
        case "recentTabAllSpaces": main.cycleRecentTabs(1, event: NSApp.currentEvent, allSpaces: true)
        case "recentTabAllSpacesBackward": main.cycleRecentTabs(-1, event: NSApp.currentEvent, allSpaces: true)
        // The Library is the page before the first space, as for a swipe or a mouse's back button (#707).
        case "nextSpace": main.stepSidebarPage(1, menu: true)
        case "previousSpace": main.stepSidebarPage(-1, menu: true)
        case "addSplitView": main.addSplitPane()
        case "closeSplitPane": if let c = current { main.closeSplitPane(c) }
        case "separateFromSplit": if let c = current { main.separatePane(c) }
        case "expandSplitPane": if let c = current { main.expandSplitPane(c) }
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
                let tabs = store.numberedTabs(in: store.focusedSpaceID)
                // ⌘9 is the last one (Arc's "Go to last Sidebar Item").
                if n == 9, let last = tabs.last { store.selectTab(last) } else if n - 1 < tabs.count { store.selectTab(tabs[n - 1]) }
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
        \(EngineVersion.label(chromium: CraCEFRuntime.chromiumVersion(), cef: CraCEFRuntime.cefVersion()))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        """
    }

    /// Settings ▸ Advanced ▸ About: a click on the version copies it on one line (GitHub #461) and says so with
    /// Arc's `didCopyVersionToClipboard` toast, "Arc version copied to clipboard".
    private func copyVersion() {
        let info = Bundle.main.infoDictionary
        copy(CraVersion.line(short: info?["CFBundleShortVersionString"] as? String ?? "dev",
                             build: info?["CFBundleVersion"] as? String ?? "",
                             engine: EngineVersion.label(chromium: CraCEFRuntime.chromiumVersion(), cef: CraCEFRuntime.cefVersion())))
        settingsController?.showToast("Cra version copied to clipboard", colors: ShinyToast.colors(main.focusedSpace.theme))
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

    /// Settings opened on `tab` (the command bar's Search Settings… opens Profiles, where the engine and the
    /// suggestions switch are since #372; it opened Advanced before, #314).
    func showSettingsWindow(on tab: SettingsTab) {
        showSettingsWindow()
        settingsController?.show(tab)
    }

    /// Settings ▸ Shortcuts with `action` chosen (Use Both's "Edit the shortcut", #374).
    func showShortcutSettings(_ action: String) {
        showSettingsWindow()
        settingsController?.showShortcut(action)
    }

    /// Settings is the window in front: the key window, or the frontmost one while Cra isn't
    /// active (as keyLittleWindow reads it). A sheet on Settings (an open panel) counts as Settings.
    var settingsInFront: Bool {
        guard let settings = settingsWindow, settings.isVisible else { return false }
        let front = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.alphaValue > 0 && !($0 is NSPanel) }
        return front === settings || front?.sheetParent === settings
    }

    /// Scenario readout: the Settings pane on screen, nil while Settings is closed.
    var debugSettingsPane: String? { settingsWindow?.isVisible == true ? settingsController?.debugPane : nil }

    /// A page opened in a new tab of a normal window, from a Little Window too.
    func openInNormalWindow(_ url: String) {
        let window = useNormalWindow()
        _ = store.createTab(url: url, select: true, window: window.windowID)
        window.showWindow(nil)
    }

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
                },
                resetTranslatedSitePrompts: { [weak self] in
                    guard let self else { return }
                    TranslatedSitePrompts.reset(store: self.store)
                },
                essentialShortcuts: { [weak self] in self?.perform("essentialShortcuts") },
                copyVersion: { [weak self] in self?.copyVersion() })
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
        settingsController?.showFirstTabIfClosed()
        settingsController?.didShow()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus (Arc's layout)

    /// The menu bar's Tabs menu, as last built: its decided rows follow CraCore TabsMenu (#622).
    private weak var tabsMenu: NSMenu?

    /// Whether a Tabs row can act now, and its title: the same answer for the menu and the action (#622).
    private func tabsMenuState(_ id: String) -> TabsMenu.RowState? {
        guard TabsMenu.decides(id) else { return nil }
        return TabsMenu.state(of: id, main.tabsMenuFacts(littleWindowInFront: keyLittleWindow != nil))
    }

    private func item(_ id: String) -> NSMenuItem {
        guard let a = bindings.action(id) else { return NSMenuItem() }
        let m = NSMenuItem(title: a.name, action: #selector(menuAction(_:)), keyEquivalent: "")
        m.representedObject = a.id
        m.target = self
        m.showShortcut(of: id)
        return m
    }

    private func std(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                     beforePage: Bool = false) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.keyEquivalentModifierMask = mods
        if beforePage { nativePageShortcuts.append(m) }
        return m
    }

    func buildMenus() {
        nativePageShortcuts.removeAll()
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
        appMenu.addItem(std("Hide Cra", #selector(NSApplication.hide(_:)), "h", beforePage: true))
        appMenu.addItem(std("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], beforePage: true))
        appMenu.addItem(std("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(std("Quit Cra", #selector(NSApplication.terminate(_:)), "q", beforePage: true))
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
        edit.addItem(item("pasteAndGo"))
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
        // Cra's Clear Site Data and Refresh (#853) sits with them.
        view.addItem(item("clearCookies")); view.addItem(item("clearCache")); view.addItem(item("clearSiteData"))
        view.addItem(.separator())
        view.addItem(item("resetZoom")); view.addItem(item("zoomIn")); view.addItem(item("zoomOut"))
        view.addItem(.separator())
        view.addItem(item("pictureInPicture")); view.addItem(item("cast"))
        view.addItem(.separator())
        // Arc's order: Add, Close, Separate, Expand Current Split (Cra's Flip after them).
        for id in ["addSplitView", "closeSplitPane", "separateFromSplit", "expandSplitPane", "flipSplitOrientation"] { view.addItem(item(id)) }
        view.addItem(.separator())
        let dev = NSMenu(title: "Developer")
        for id in ["viewSource", "devTools", "inspectElement", "jsConsole"] { dev.addItem(item(id)) }
        dev.addItem(item("allowAppleEventsJavaScript"))
        dev.addItem(.separator())
        dev.addItem(item("toggleDeveloperMode"))
        view.addItem(submenu: dev, title: "Developer")
        view.addItem(.separator())
        view.addItem(std("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], beforePage: true))
        menubar.addItem(submenu: view, title: "View")

        menubar.addItem(submenu: spacesMenu.makeMenu(), title: "Spaces")

        let tabs = NSMenu(title: "Tabs")
        tabsMenu = tabs
        // Arc's three groups (#622); Open in <space> shows only while a Little Window or Peek is in front (#279).
        for (i, section) in TabsMenu.sections.enumerated() {
            if i > 0 { tabs.addItem(.separator()) }
            for id in section {
                let row = item(id)
                if id == "newFolder" { row.title = "New Folder…" }
                tabs.addItem(row)
            }
        }
        // The rows Cra had and Arc keeps out of its menu; hidden, they still take their shortcuts (⌃⇥, ⌘1–⌘9,
        // any set in Settings ▸ Shortcuts) through the menu bar.
        for id in TabsMenu.hidden {
            let row = item(id)
            row.isHidden = true
            row.allowsKeyEquivalentWhenHidden = true
            tabs.addItem(row)
        }
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
        window.addItem(std("Minimize Window", #selector(NSWindow.performMiniaturize(_:)), "m", beforePage: true))
        window.addItem(std("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("openLibrary")); window.addItem(item("viewDownloads")); window.addItem(item("viewEasels")); window.addItem(item("viewMedia")); window.addItem(item("viewBoosts"))
        window.addItem(.separator())
        window.addItem(item("littleWindowOpenInMenu")); window.addItem(item("closeLittleWindows"))
        window.addItem(.separator())
        window.addItem(std("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        menubar.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(withTitle: EngineVersion.label(chromium: CraCEFRuntime.chromiumVersion(), cef: CraCEFRuntime.cefVersion()), action: nil, keyEquivalent: "")
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
