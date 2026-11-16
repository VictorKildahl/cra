import AppKit
import CraCEF

// A staged update run once before it is installed, so macOS has checked the new bundle by the
// time the user starts it (UpdatePrewarm). Nothing else of Cra runs.
if ProcessInfo.processInfo.environment[UpdatePrewarm.environmentKey] == "1" { exit(0) }

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--mcp" {
    MCPConnection.bridge(path: CommandLine.arguments[2])
}

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
    // No other Cra runs at all: Cra's Keychain item and the performance recorder are the Mac's, not a folder's.
    let noOtherCra = !NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != me && kill($0.processIdentifier, 0) == 0 })
    // No other Cra has this data folder open (Chromium's profile lock in it): another Cra with a folder of its own,
    // such as a test copy while the installed Cra runs, leaves it to this one (DataFolderOwner, #299).
    let lockTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: AppPaths.chromiumCache.appendingPathComponent("SingletonLock").path)
    var hostBytes = [CChar](repeating: 0, count: 256)
    let host = gethostname(&hostBytes, hostBytes.count) == 0 ? String(cString: hostBytes) : ""
    let profileIsFree = DataFolderOwner.isFree(lockTarget: lockTarget, host: host, me: me) { kill($0, 0) == 0 }
    CraLog.startSession(owner: profileIsFree)
    // Cookies and passwords move from the mock keychain to Cra's Keychain item first,
    // staged imports included, so everything below writes with the key Chromium reads.
    SafeStorage.prepare(profileIsFree: profileIsFree && noOtherCra)
    if profileIsFree {
        let profile = AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        if CredentialImport.hasPending { CredentialImport.applyPending(root: AppPaths.chromiumCache) }
        CredentialImport.repairImportedCookies(profileDir: profile)
        // WebKit's data for a deleted profile goes with its Chromium folder (PageEngines).
        ProfileCleanup.removed = { name in MainActor.assumeIsolated { WebKitStores.removeProfile(folderName: name) } }
        ProfileCleanup.run()
    }

    NativeMessagingHosts.link(into: AppPaths.chromiumCache)

    let extensions = ExtensionStore.loadList(profileIsFree: profileIsFree)
    CraCEFRuntime.setExtensionPaths(extensions.paths, profiles: extensions.profiles)
    if let p = extensions.profiles { CraLog.note("extension profiles: \(p)") }

    // Chromium's language follows macOS as in Chrome and Arc: it picks the voice for speech
    // without a lang (#167), Chromium's own pages and dialogs, and pages' default date format.
    let framework = EngineFramework.bundleURL
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
    // Chromium didn't start: another Cra is running and got our command line (just activate it), or it failed.
    @MainActor func didNotStart() -> Never {
        if CraCEFRuntime.anotherInstanceWasNotified() {
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dk.kildahl.cra")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate()
            exit(0)
        }
        let alert = AppDialog(title: "Cra could not start Chromium",
                              message: "Chromium failed to initialize. See \(AppPaths.log.path).")
        alert.runModal()
        exit(1)
    }
    if !started { didNotStart() }

    // Once Chromium is up: at once with CEF, inside runMessageLoop with Chrome's framework.
    var ready = false
    CraCEFRuntime.whenReady {
        ready = true
        ChromiumBluetoothCache.install()
        ChromiumDockTile.install()
        ChromiumHistorySwipe.install()

        // Only now: the "another Cra is running" and failed-start exits above leave no session marker.
        Perf.phase("chromiumStarted")
        let info = Bundle.main.infoDictionary
        PerfRecorder.configure(owner: profileIsFree && noOtherCra,
                               recording: PerfSessionRules.recording(setting: delegate.store.settings.perfRecording,
                                                                     environment: ProcessInfo.processInfo.environment),
                               config: .init(folder: AppPaths.file("Perf"), chromiumFolder: AppPaths.chromiumCache),
                               craVersion: "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "?"))",
                               chromiumVersion: CraCEFRuntime.chromiumVersion(), onboarding: delegate.needsOnboarding)

        // Belt and braces: Chromium's run loop drives NSApplication and should call
        // applicationDidFinishLaunching, but bootstrapping is idempotent either way.
        DispatchQueue.main.async { delegate.bootstrapIfNeeded() }
        HitchMonitor.startIfRequested()
    }
    CraCEFRuntime.runMessageLoop()
    if !ready { didNotStart() }
    PerfRecorder.quit()
    // A log that ends without this line ended in a crash or a forced quit.
    CraLog.note("Cra quits")
    CraLog.flush()
    delegate.applicationWillShutdown()
    CraCEFRuntime.shutdown()
}
