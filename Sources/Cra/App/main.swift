import AppKit
import CraCEF

MainActor.assumeIsolated {
    // Start-up phases count from here, before AppDelegate decodes the data folder's files.
    Perf.launch()
    // Order matters: the CefAppProtocol NSApplication must exist before Chromium
    // initializes, and Chromium must be initialized before any browser is made.
    let app = CraApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    Perf.phase("storeLoaded")

    // The newest copy of Cra runs: an older install opens a newer one, and an older
    // Cra holding the profile quits rather than receiving this launch (NewestCopy).
    NewestCopy.openNewerInstalledCopy()
    NewestCopy.replaceOlderRunningCopy()

    // The icon picked in Settings, before the Dock first shows the running app.
    AppIconManager.shared.applyAtLaunch()

    // Passwords and cookies staged by the import go into the profile while no
    // Chromium has it open: before initializing, and only when no other Cra runs.
    // The run loop has not started, so the list can still hold a Cra that just quit.
    let me = ProcessInfo.processInfo.processIdentifier
    let profileIsFree = !NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != me && kill($0.processIdentifier, 0) == 0 })
    CraLog.startSession(owner: profileIsFree)
    // Cookies and passwords move from the mock keychain to Cra's Keychain item first,
    // staged imports included, so everything below writes with the key Chromium reads.
    SafeStorage.prepare(profileIsFree: profileIsFree)
    if profileIsFree {
        let profile = AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        if CredentialImport.hasPending { CredentialImport.applyPending(root: AppPaths.chromiumCache) }
        CredentialImport.repairImportedCookies(profileDir: profile)
        // WebKit's data for a deleted profile goes with its Chromium folder (PageEngines).
        ProfileCleanup.removed = { name in MainActor.assumeIsolated { WebKitStores.removeProfile(folderName: name) } }
        ProfileCleanup.run()
    }

    NativeMessagingHosts.link(into: AppPaths.chromiumCache)

    let extensions = ExtensionStore.loadList()
    CraCEFRuntime.setExtensionPaths(extensions.paths, profiles: extensions.profiles)
    if let p = extensions.profiles { CraLog.note("extension profiles: \(p)") }

    // Chromium's language follows macOS as in Chrome and Arc: it picks the voice for speech
    // without a lang (#167), Chromium's own pages and dialogs, and pages' default date format.
    let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("Chromium Embedded Framework.framework")
    let locale = ChromiumLocale.pick(available: framework.flatMap { Bundle(url: $0) }?.localizations ?? [],
                                     preferredLanguages: Locale.preferredLanguages)
    CraLog.note("chromium locale: \(locale ?? "en-US (default)") for \(Locale.preferredLanguages.prefix(3).joined(separator: ","))")
    let useChromeStyle = ProcessInfo.processInfo.environment["CRA_CHROME_STYLE"] == "1"
    let started = CraCEFRuntime.initialize(withCachePath: AppPaths.chromiumCache.path,
                                           userAgentProduct: "",
                                           logPath: AppPaths.log.path,
                                           locale: locale,
                                           useChromeStyle: useChromeStyle,
                                           useMockKeychain: !SafeStorage.usesKeychain)
    if !started && CraCEFRuntime.anotherInstanceWasNotified() {
        // The running Cra got our command line; just activate it.
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.kildahl.cra")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate()
        exit(0)
    }
    if !started {
        let alert = NSAlert()
        alert.messageText = "Cra could not start Chromium"
        alert.informativeText = "Chromium Embedded Framework failed to initialize. See \(AppPaths.log.path)."
        alert.runModal()
        exit(1)
    }

    ChromiumBluetoothCache.install()

    // Only now: the "another Cra is running" and failed-start exits above leave no session marker.
    Perf.phase("chromiumStarted")
    let info = Bundle.main.infoDictionary
    PerfRecorder.configure(owner: profileIsFree,
                           recording: PerfSessionRules.recording(setting: delegate.store.settings.perfRecording,
                                                                 environment: ProcessInfo.processInfo.environment),
                           config: .init(folder: AppPaths.file("Perf"), chromiumFolder: AppPaths.chromiumCache),
                           craVersion: "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "?"))",
                           chromiumVersion: CraCEFRuntime.chromiumVersion(), onboarding: delegate.needsOnboarding)

    // Belt and braces: Chromium's run loop drives NSApplication and should call
    // applicationDidFinishLaunching, but bootstrapping is idempotent either way.
    DispatchQueue.main.async { delegate.bootstrapIfNeeded() }
    HitchMonitor.startIfRequested()
    CraCEFRuntime.runMessageLoop()
    PerfRecorder.quit()
    // A log that ends without this line ended in a crash or a forced quit.
    CraLog.note("Cra quits")
    CraLog.flush()
    delegate.applicationWillShutdown()
    CraCEFRuntime.shutdown()
}
