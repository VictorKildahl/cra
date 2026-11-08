import AppKit
import IOKit.pwr_mgt
import Observation
import Sparkle

/// Arc's SoftwareUpdaterClient, rebuilt from the same parts (docs/arc-reverse-engineering.md,
/// "Software updates"): Sparkle 2 with an EdDSA-signed appcast, checked every 8 hours,
/// downloaded in the background and installed when Cra quits. A custom user driver
/// replaces Sparkle's windows with the updater window (Check for Updates…) and the
/// sidebar banners, and a downloaded update installs itself once the user is away, the
/// way Arc's auto-update restarts Arc.
@MainActor
@Observable
final class SoftwareUpdater: NSObject {
    static let shared = SoftwareUpdater()

    struct Release: Equatable {
        var version: String
        var build: String
        var notesHTML: String?

        init(version: String, build: String) {
            self.version = version
            self.build = build
        }

        init(_ item: SUAppcastItem) {
            version = item.displayVersionString
            build = item.versionString
            notesHTML = item.itemDescription
        }
    }

    /// What the updater window shows (Arc's UpdaterWindowView).
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case found(Release, downloaded: Bool)
        case downloading(received: UInt64, expected: UInt64)
        case extracting
        case readyToInstall
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Downloaded and waiting for a restart: "An update is ready!" in the sidebar.
    private(set) var readyRelease: Release?
    /// Found by a background check while automatic updates are off.
    private(set) var foundRelease: Release?
    /// The first launch after an update: "Cra Updated!" with See What's New.
    private(set) var updatedTo: String?
    func debugUpdated(_ v: String?) { updatedTo = v }
    /// Shows the "An update is ready!" banner for `version` (screenshots, cra://debug?bannerReady=).
    func debugReady(_ version: String?) { readyRelease = version.map { Release(version: $0, build: $0) } }
    /// The close button on a banner hides it until the next launch (Arc counts these in
    /// autoUpdateBannerDismissalCount).
    var bannerDismissed = false
    /// Arc's "Automatically update my Arc" (Dia: "Automatically update Dia"): download in
    /// the background and restart while the user is away. Off, a found update only shows a
    /// banner. Stored by Sparkle as SUAutomaticallyUpdate.
    var automaticallyUpdates = true {
        didSet { updater?.automaticallyDownloadsUpdates = automaticallyUpdates }
    }
    private(set) var isAvailable = false
    /// Settings ▸ Advanced, next to Check for Updates: when Sparkle last looked.
    var lastCheckSummary: String {
        guard isAvailable else { return "Development builds don’t update." }
        guard let date = updater?.lastUpdateCheckDate else { return "Not checked yet." }
        return "Last checked " + RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()) + "."
    }
    /// This launch came from an automatic restart, so it should not take focus.
    private(set) var launchedByAutoUpdate = false

    /// What's new on the "Cra updated!" card, tagged so the site can count visits from it.
    static let releaseNotesURL = SiteLinks.tagged("https://crabrowser.app/release-notes", from: .whatsNew)
    static let downloadURL = "https://github.com/VictorKildahl/cra/releases/latest"

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private weak var app: AppDelegate?
    @ObservationIgnored private var window: UpdaterWindowController?
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var acknowledgement: (() -> Void)?
    @ObservationIgnored private var autoRestartTimer: ScheduledWork?
    @ObservationIgnored private var inactiveSince: Date?

    private enum Keys {
        static let pendingBuild = "updateSummaryPendingBuild"
        static let autoRelaunch = "automaticUpdateWillRelaunchApp"
    }

    /// Arc's feed override: a feed URL for testing (e.g. a local appcast).
    private var feedOverride: String? { ProcessInfo.processInfo.environment["CRA_UPDATE_FEED"] }
    /// Shortens every wait of the automatic restart to this many seconds, for testing.
    private var quickRestart: TimeInterval? { ProcessInfo.processInfo.environment["CRA_UPDATE_IDLE_SECONDS"].flatMap(TimeInterval.init) }

    func start(app: AppDelegate) {
        self.app = app
        let d = UserDefaults.standard
        launchedByAutoUpdate = d.bool(forKey: Keys.autoRelaunch)
        d.removeObject(forKey: Keys.autoRelaunch)
        if let build = d.string(forKey: Keys.pendingBuild) {
            d.removeObject(forKey: Keys.pendingBuild)
            if build == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                updatedTo = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            }
        }
        // Dev builds carry no feed (scripts/build.sh drops SUFeedURL outside releases), so they
        // never replace themselves with a release.
        guard !ProcessInfo.processInfo.arguments.contains("--disable-software-updater"),
              feedOverride != nil || Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let u = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try u.start()
        } catch {
            NSLog("Cra: software updater did not start: %@", error.localizedDescription)
            return
        }
        updater = u
        isAvailable = true
        automaticallyUpdates = u.automaticallyDownloadsUpdates
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inactiveSince = Date() }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inactiveSince = nil }
        }
        if !NSApp.isActive { inactiveSince = Date() }
    }

    // MARK: Actions

    @objc func checkForUpdates(_ sender: Any?) {
        // A downloaded update is one click from installing; Sparkle would only resume it.
        if readyRelease != nil {
            phase = .readyToInstall
            showWindow()
            return
        }
        if case .found = phase, choiceReply != nil {
            showWindow()
            return
        }
        updater?.checkForUpdates()
    }

    /// Restart into the downloaded update (the banner, Install and Relaunch).
    func installAndRelaunch() {
        if let reply = choiceReply {
            choiceReply = nil
            switch phase {
            case .readyToInstall, .found(_, downloaded: true): app?.prepareForUpdateRelaunch()
            default: break  // .install on an update that isn't downloaded starts the download
            }
            reply(.install)
        } else if let install = installNow {
            // Sparkle accepts the block again if the quit gets cancelled (a page's beforeunload).
            phase = .installing
            app?.prepareForUpdateRelaunch()
            install()
        }
    }

    /// The banner for an update found while automatic updates are off.
    func showFoundUpdate() {
        guard let r = foundRelease else { return }
        phase = .found(r, downloaded: false)
        showWindow()
    }

    /// Later, Cancel, Close and the window's close button.
    func dismissWindowAction(closeWindow: Bool = true) {
        if let reply = choiceReply {
            choiceReply = nil
            foundRelease = nil
            reply(.dismiss)
        }
        cancellation?()
        cancellation = nil
        acknowledgement?()
        acknowledgement = nil
        if readyRelease == nil { phase = .idle }
        if closeWindow { window?.close() }
    }

    /// The banner's close button. A found update is answered "later" so Sparkle goes back
    /// to its schedule; the others hide until the next launch.
    func dismissBanner() {
        if readyRelease != nil {
            bannerDismissed = true
        } else if foundRelease != nil {
            dismissWindowAction()
        } else {
            updatedTo = nil
        }
    }

    static let sponsorsURL = "https://github.com/sponsors/VictorKildahl"

    /// The updated banner's "Sponsor Cra" row (Arc's "Gift Arc").
    func openSponsors() {
        guard let app else { return }
        app.store.createTab(url: Self.sponsorsURL, select: true)
        app.main.showWindow(nil)
    }

    /// The updated banner's "What's new" row. The card stays so Sponsor Cra is still there
    /// after reading; only its ✕ (or the next launch) puts it away.
    func openReleaseNotes() {
        guard let app else { return }
        app.store.createTab(url: Self.releaseNotesURL, select: true)
        app.main.showWindow(nil)
    }

    func openDownloadPage() {
        dismissWindowAction()
        if let u = URL(string: Self.downloadURL) { NSWorkspace.shared.open(u) }
    }

    private func showWindow() {
        if window == nil { window = UpdaterWindowController(updater: self) }
        window?.showWindow(nil)
        window?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidClose() {
        switch phase {
        case .checking, .upToDate, .found, .failed, .downloading: dismissWindowAction(closeWindow: false)
        default: break
        }
    }

    // MARK: Automatic restart

    /// Arc restarts into a downloaded update by itself (auto_update_queued, time_since_last_active,
    /// ignore_user_idle, active_tabs_blocked_update, window_dialog_sheet_visible). Its timing comes
    /// from remote flags (auto-update-inactivity-delay-in-seconds, auto-update-required-idle-
    /// duration-in-seconds); Cra waits until the user is away: Cra in the background for 10
    /// minutes and no input for 2, or no input at all for 30.
    private func scheduleAutoRestart() {
        autoRestartTimer?.cancel()
        autoRestartTimer = (app?.composition.clock ?? LiveScheduler.shared).every(max(1, min(60, quickRestart ?? 60))) { [weak self] in
            self?.considerAutoRestart()
        }
    }

    private func considerAutoRestart() {
        guard automaticallyUpdates, installNow != nil, let app else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let background = inactiveSince.map { Date().timeIntervalSince($0) } ?? 0
        let q = quickRestart
        guard (background >= q ?? 600 && idle >= q ?? 120) || idle >= q ?? 1800 else { return }
        if let reason = app.autoUpdateBlocker() ?? (Self.holdsPowerAssertion ? "a page is playing media" : nil) {
            NSLog("Cra: automatic update waits: %@", reason)
            return
        }
        NSLog("Cra: restarting to install the downloaded update")
        UserDefaults.standard.set(true, forKey: Keys.autoRelaunch)
        installAndRelaunch()
    }

    /// Chromium holds a power assertion while a page plays audio or video and while a
    /// download runs (PowerSaveBlocker), which stands in for Arc's per-tab media check.
    private static var holdsPowerAssertion: Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        return !(all[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []).isEmpty
    }
}

// MARK: - SPUUpdaterDelegate

extension SoftwareUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { feedOverride }

    /// The update is downloaded and extracted. Keeping the block lets the banner and the
    /// automatic restart install it now; otherwise it installs when Cra quits.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        installNow = immediateInstallationBlock
        readyRelease = Release(item)
        foundRelease = nil
        bannerDismissed = false
        UserDefaults.standard.set(item.versionString, forKey: Keys.pendingBuild)
        scheduleAutoRestart()
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        UserDefaults.standard.set(item.versionString, forKey: Keys.pendingBuild)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("Cra: software update stopped: %@", error.localizedDescription)
    }
}

// MARK: - SPUUserDriver

extension SoftwareUpdater: SPUUserDriver {
    /// Never asked: SUEnableAutomaticChecks is in Info.plist (Arc logs the same).
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
        showWindow()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        choiceReply = reply
        let release = Release(appcastItem)
        phase = .found(release, downloaded: state.stage != .notDownloaded)
        if state.userInitiated {
            showWindow()
        } else {
            foundRelease = release
            bannerDismissed = false
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let html = String(data: downloadData.data, encoding: .utf8)
        if case .found(var r, let downloaded) = phase, let html {
            r.notesHTML = html
            phase = .found(r, downloaded: downloaded)
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        self.acknowledgement = acknowledgement
        phase = .upToDate
        showWindow()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        NSLog("Cra: software update error: %@", error.localizedDescription)
        cancellation = nil
        // Background checks fail quietly (offline, GitHub down); only a window the user
        // is looking at reports it.
        guard window?.window?.isVisible == true else { acknowledgement(); return }
        self.acknowledgement = acknowledgement
        phase = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .downloading(received: 0, expected: 0)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        phase = .downloading(received: 0, expected: expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        if case .downloading(let received, let expected) = phase {
            phase = .downloading(received: received + length, expected: max(expected, received + length))
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        phase = .extracting
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        choiceReply = reply
        phase = .readyToInstall
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        app?.prepareForUpdateRelaunch()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        if phase != .idle { showWindow() }
    }

    func dismissUpdateInstallation() {
        choiceReply = nil
        cancellation = nil
        acknowledgement = nil
        guard readyRelease == nil else { return }
        phase = .idle
        window?.close()
    }
}

extension SoftwareUpdater: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isAvailable && (readyRelease != nil || updater?.canCheckForUpdates == true || choiceReply != nil)
    }
}
