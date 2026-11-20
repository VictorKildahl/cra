import CryptoKit
import Foundation
import IOKit
import Observation

/// Settings ▸ General ▸ Sync: the sidebar, the settings and the shortcut overrides kept the
/// same on the user's Macs, through iCloud (the app's iCloud Documents container) or through
/// a folder a file provider syncs (Dropbox, OneDrive or a similar service). Cra writes a bundle
/// into a `Cra` folder there when something changed here and applies a bundle another Mac
/// wrote when it is newer (SettingsSync in CraCore decides). No server of Cra's own: iCloud or
/// the provider moves the files. Logins, cookies, history and the Chromium profile stay on each Mac.
@MainActor
@Observable
final class SettingsSyncService {
    /// Where the bundle lives.
    enum Location: Codable, Equatable {
        case iCloud
        case folder(String)
    }

    /// What survives a relaunch: the location and the last bundle written or applied, so a
    /// bundle seen before is not applied again and an unchanged sidebar is not written again.
    struct State: Codable, Equatable {
        var location: Location?
        var lastApplied: SyncManifest?
        var lastWritten: SyncManifest?
        var devices: [String] = []
    }

    /// What turning sync on leads to: the bundle went up; a bundle from another Mac is there and
    /// the user picks which sidebar to keep (`useRemote`, `useLocal`); iCloud still has to
    /// download it (the question comes once it has); or it failed.
    enum Outcome: Equatable {
        case synced
        case bundleFound(SyncBundleSummary)
        case downloading
        case failed(String)
    }

    private(set) var location: Location?
    /// The folder the bundle is in: `<container>/Documents/Cra` for iCloud, `<chosen>/Cra` for a folder.
    private(set) var folder: URL?
    private(set) var lastSync: Date?
    /// The other Macs whose bundles were seen, by computer name.
    private(set) var otherDevices: [String] = []
    private(set) var error: String?
    /// The bundle waiting for the user's choice after sync was turned on.
    private(set) var pendingChoice: SyncBundleSummary?
    /// iCloud is signed in and this build may use Cra's container (a signed build with the
    /// entitlement, or CRA_SYNC_ICLOUD_DIR for a test).
    private(set) var iCloudAvailable = false
    /// A bundle in iCloud is still downloading; the look repeats until it is whole.
    private(set) var awaitingDownload = false
    /// What the last look at the folder found (the `cra://debug?sync=` readout).
    private(set) var folderState: SyncFolderState?
    /// How long the folder has held files from different writes (#378).
    private var mixWait = SyncMixWait()

    static let newerCraError = "Your other Mac syncs with a newer version of Cra. Update Cra on this Mac to keep syncing."

    /// Reads keybindings.json again after a bundle wrote it (KeyBindingRegistry.reloadOverrides).
    var keybindingsChanged: @MainActor () -> Void = {}

    /// How often the folder is looked at besides when a watcher fires: a provider may change
    /// a file without a directory event, and the timer is what a test host drives.
    static let pollInterval: TimeInterval = 30

    /// This Mac's computer name, which the question on another Mac shows.
    let device: String
    /// This Mac in a manifest (`SyncManifest.deviceID`): a hash of its hardware UUID, which is
    /// the same after a reinstall and differs on a Mac Migration Assistant set up from this one.
    let deviceID: String
    /// Whether iCloud (or a provider's File Provider) has a file on disk. Since macOS 14 a file
    /// it has not downloaded keeps its name and reading it waits for the download, so a look
    /// asks for it and comes back instead of reading it on the main thread.
    var downloadStatus: (URL) -> URLUbiquitousItemDownloadingStatus? = { url in
        (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
    }
    private let store: SidebarStore
    private let clock: Scheduler
    private let stateFile = JSONStore<State>("sync.json")
    private var state: State
    /// The last few bundles written or applied here, so a bundle the other Mac wrote from one of
    /// them is merged with what changed here since, not applied whole (SidebarMerge).
    /// Loaded on first use, not at launch: eight sidebars to decode.
    private let historyFile = JSONStore<SyncHistory>("sync-history.json")
    @ObservationIgnored private lazy var history: SyncHistory = historyFile.load(or: { SyncHistory() })
    private var iCloudContainer: URL?
    private var poller: ScheduledWork?
    private var watcher: DispatchSourceFileSystemObject?
    private var metadataQuery: NSMetadataQuery?
    private var identityObserver: NSObjectProtocol?
    private var queryObservers: [NSObjectProtocol] = []
    private var watcherDebounce: ScheduledWork?
    /// A change here, written `SettingsSync.writeSoonDelay` after the last one (#598).
    private var writeSoon: ScheduledWork?
    /// The bundle last written or applied, without last-active times: a change to those alone waits
    /// for the 30-second look. Kept as values and compared with ==, never encoded: at 5,000 tabs an
    /// encode of the sidebar is a 2 MB main-thread job (#615).
    private var writtenShape: Shape?
    private struct Shape: Equatable {
        var document: SidebarDocument
        var settings: AppSettings
        var keybindings: Data
    }

    init(store: SidebarStore, clock: Scheduler, device: String? = nil, deviceID: String? = nil) {
        self.store = store
        self.clock = clock
        // CRA_SYNC_DEVICE names a test instance (two on one Mac share a computer name and hardware).
        let testDevice = ProcessInfo.processInfo.environment["CRA_SYNC_DEVICE"]
        self.device = device ?? testDevice ?? Host.current().localizedName ?? "Mac"
        self.deviceID = deviceID ?? testDevice ?? Self.hardwareDeviceID()
        state = stateFile.load(or: { State() })
        location = state.location
        if case .folder(let path)? = state.location { folder = Self.bundleFolder(in: URL(fileURLWithPath: path, isDirectory: true)) }
        otherDevices = state.devices
        lastSync = state.lastWritten?.writtenAt
        // A test host: the folder stands in for the container, no entitlement needed.
        if let dir = ProcessInfo.processInfo.environment["CRA_SYNC_ICLOUD_DIR"] {
            iCloudContainer = URL(fileURLWithPath: dir, isDirectory: true)
            iCloudAvailable = true
            if case .iCloud? = state.location { folder = Self.bundleFolder(inContainer: iCloudContainer!) }
        }
        store.onChange.append { [weak self] in self?.changedHere() }
    }

    /// The sidebar or the settings changed: a look (and a write) a few seconds after the last change,
    /// if more changed than when tabs were last active (#598).
    private func changedHere() {
        guard isEnabled, folder != nil else { return }
        writeSoon?.cancel()
        writeSoon = clock.after(SettingsSync.writeSoonDelay) { [weak self] in
            guard let self else { return }
            writeSoon = nil
            let shape = currentShape()
            guard shape != writtenShape else { return }
            CraLog.note("sync: a change here, written now rather than at the next look")
            let before = state.lastWritten?.id
            poll()
            // The look wrote nothing and waits for nothing: the folder already has this (a write sets it itself).
            if state.lastWritten?.id == before, !awaitingDownload, pendingChoice == nil, error == nil { writtenShape = shape }
        }
    }

    /// This Mac's bundle without last-active times.
    private func currentShape() -> Shape { shape(of: localBundle()) }

    private func shape(of bundle: Bundle) -> Shape {
        Shape(document: bundle.document.withoutActivity(), settings: bundle.settings, keybindings: bundle.keybindings)
    }

    /// Sync is on and past the first question. A later bundle that iCloud is still downloading
    /// does not turn it off.
    var isEnabled: Bool { location != nil && pendingChoice == nil && (hasSynced || !awaitingDownload) }

    /// This Mac wrote or applied a bundle since sync was turned on: the question about the first
    /// bundle has its answer. Saved, so a relaunch before the answer still asks.
    private var hasSynced: Bool { state.lastApplied != nil || state.lastWritten != nil }

    /// Picks up where the last run left off, and finds out whether iCloud is there.
    func start() {
        resolveICloud()
        identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resolveICloud() }
        }
        if case .folder? = location { startWatching(); poll() }
    }

    /// The container URL comes from a secondary thread (Apple: never the main thread). With it,
    /// iCloud sync that was on resumes; without it (signed out, or an ad-hoc build) it waits.
    private func resolveICloud() {
        guard ProcessInfo.processInfo.environment["CRA_SYNC_ICLOUD_DIR"] == nil else { resumeICloud(); return }
        guard FileManager.default.ubiquityIdentityToken != nil else { iCloudGone(); return }
        Task.detached(priority: .utility) {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            await MainActor.run { [weak self] in
                guard let self else { return }
                iCloudContainer = url
                iCloudAvailable = url != nil
                if url == nil { iCloudGone() } else { resumeICloud() }
            }
        }
    }

    private func resumeICloud() {
        guard case .iCloud? = location, let container = iCloudContainer else { return }
        folder = Self.bundleFolder(inContainer: container)
        try? FileManager.default.createDirectory(at: folder!, withIntermediateDirectories: true)
        error = nil
        startWatching()
        poll()
    }

    private func iCloudGone() {
        iCloudAvailable = false
        iCloudContainer = nil
        guard case .iCloud? = location else { return }
        stopWatching()
        error = "Sign in to iCloud in System Settings to keep syncing."
    }

    /// A hash of the Mac's hardware UUID, so the sync folder never holds the UUID itself.
    static func deviceID(hardwareUUID: String) -> String {
        SHA256.hash(data: Data("cra-sync:\(hardwareUUID)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func hardwareDeviceID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        return deviceID(hardwareUUID: uuid ?? Host.current().localizedName ?? "Mac")
    }

    private static func bundleFolder(inContainer container: URL) -> URL {
        container.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(SettingsSync.folderName, isDirectory: true)
    }

    /// The user turned on iCloud sync.
    func enableICloud() -> Outcome {
        guard let container = iCloudContainer else { return .failed("iCloud is not available on this Mac.") }
        return enable(.iCloud, at: Self.bundleFolder(inContainer: container))
    }

    /// The user chose a folder. Cra's bundle goes into its `Cra` subfolder.
    func enable(folder picked: URL) -> Outcome {
        enable(.folder(picked.path), at: Self.bundleFolder(in: picked))
    }

    /// When another Mac's bundle is already there, the user is asked which sidebar to keep
    /// before anything is written; when iCloud has not downloaded it yet, the question waits.
    private func enable(_ newLocation: Location, at target: URL) -> Outcome {
        do { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) } catch {
            return .failed("The folder could not be made: \(error.localizedDescription)")
        }
        stopWatching()
        location = newLocation
        folder = target
        state.location = newLocation
        state.lastApplied = nil
        state.lastWritten = nil
        history = SyncHistory()
        historyFile.saveNow(history)
        error = nil
        pendingChoice = nil
        awaitingDownload = false
        mixWait.reset()
        stateFile.saveNow(state)
        switch look(at: target) {
        case .bundle(let manifest, let bundle) where manifest.deviceID != deviceID:
            pendingChoice = SyncBundleSummary(manifest: manifest, document: bundle.document)
            return .bundleFound(pendingChoice!)
        case .downloading:
            awaitingDownload = true
            startWatching()
            return .downloading
        case .mixed(let files, let wroteManifest, let lacking):
            // Waited for like a download; a mix that stays put is written over by a later look,
            // here only by the Mac that wrote it: this one hasn't been asked which sidebar to keep.
            _ = mixWait.shouldRewrite(files, at: clock.now, wroteManifest: wroteManifest, lacking: lacking, synced: false)
            awaitingDownload = true
            startWatching()
            return .downloading
        case .newer:
            error = Self.newerCraError
            startWatching()
            return .failed(Self.newerCraError)
        case .bundle, .none:
            writeBundle()
            startWatching()
            return error.map { .failed($0) } ?? .synced
        }
    }

    /// The bundle in the folder replaces this Mac's sidebar, settings and shortcuts.
    func useRemote() {
        pendingChoice = nil
        guard let folder else { return }
        switch look(at: folder) {
        case .bundle(let manifest, let bundle): apply(manifest, bundle, merge: false)
        case .newer: error = Self.newerCraError
        default: writeBundle()
        }
        startWatching()
    }

    /// This Mac's sidebar replaces the bundle in the folder; the other Mac takes it on its next look.
    func useLocal() {
        pendingChoice = nil
        writeBundle()
        startWatching()
    }

    /// Sync stops; what is on this Mac and in the folder or in iCloud stays as it is.
    func disable() {
        stopWatching()
        location = nil
        folder = nil
        pendingChoice = nil
        awaitingDownload = false
        error = nil
        state = State(devices: state.devices)
        stateFile.saveNow(state)
        history = SyncHistory()
        historyFile.saveNow(history)
        local = nil
        lastDecoded = nil
    }

    /// One look: a newer bundle from another Mac is applied, then what changed here is written.
    /// While iCloud still downloads a bundle, nothing is written over it. Files from different
    /// writes, or a file gone with nothing on its way, are waited for a little, then this Mac writes
    /// a whole bundle again (#378), unless it hasn't synced here yet and the manifest is another
    /// Mac's; a newer Cra's bundle is never written over.
    func poll() {
        guard let folder, pendingChoice == nil else { return }
        var gone = false
        let found = look(at: folder)
        if case .mixed = found {} else { mixWait.reset() }
        if case .newer = found {} else if error == Self.newerCraError { error = nil }
        switch found {
        case .downloading:
            awaitingDownload = true
            return
        case .mixed(let files, let wroteManifest, let lacking):
            let since = mixWait.since
            guard mixWait.shouldRewrite(files, at: clock.now, wroteManifest: wroteManifest, lacking: lacking, synced: hasSynced) else {
                awaitingDownload = true
                return
            }
            // No download is coming: this Mac's sidebar, settings and shortcuts go up whole, and
            // the other Mac applies them like any later bundle.
            CraLog.note("sync: the folder held \(lacking ? "a bundle with a file gone" : "files from different writes") for \(Int(clock.now.timeIntervalSince(since ?? clock.now))) s; this Mac's bundle written again")
            mixWait.reset()
            awaitingDownload = false
            gone = true
        case .newer:
            // Nothing applied, nothing written: the newer Cra reads this one's format, not the reverse.
            awaitingDownload = false
            error = Self.newerCraError
            return
        case .bundle(let manifest, let bundle):
            awaitingDownload = false
            if !hasSynced {
                // The bundle sync was turned on against has arrived: now the user picks.
                if manifest.deviceID != deviceID {
                    pendingChoice = SyncBundleSummary(manifest: manifest, document: bundle.document)
                    return
                }
            } else if SettingsSync.shouldApply(remote: manifest, lastApplied: state.lastApplied, deviceID: deviceID) {
                // A later bundle, also one iCloud delivered in parts: applied with no question.
                apply(manifest, bundle)
            }
        case .none:
            // No bundle at all (the Cra folder was deleted, or emptied): this Mac's goes back.
            gone = true
            awaitingDownload = false
        }
        if gone || localHashes() != state.lastWritten?.files { writeBundle() }
    }

    // MARK: Export and import (the same bundle, in a folder the user picks)

    func export(to picked: URL) -> String? {
        let target = Self.bundleFolder(in: picked)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            _ = try write(localFiles().files, to: target)
            return nil
        } catch { return error.localizedDescription }
    }

    func summary(ofBundleIn picked: URL) -> SyncBundleSummary? {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return nil }
        return SyncBundleSummary(manifest: manifest, document: bundle.document)
    }

    func importBundle(from picked: URL) -> Bool {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return false }
        apply(manifest, bundle, merge: false, remember: false)
        return true
    }

    /// `<picked>/Cra`, or `picked` itself when the user pointed at the Cra folder.
    private static func bundleFolder(in picked: URL) -> URL {
        picked.lastPathComponent == SettingsSync.folderName ? picked : picked.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
    }

    // MARK: Bundles

    private struct Bundle {
        var document: SidebarDocument
        var settings: AppSettings
        var keybindings: Data
    }

    private enum Look {
        case none
        case downloading
        /// Every file there, but not the manifest's, or a file the manifest names gone with nothing
        /// on its way (`lacking`): the files' hashes (the manifest's included), and whether this
        /// Mac wrote that manifest.
        case mixed([String: String], wroteManifest: Bool, lacking: Bool)
        case newer
        case bundle(SyncManifest, Bundle)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// This Mac's bundle, encoded, and what it was made from. A look every 30 seconds used to sort,
    /// encode and hash the whole sidebar each time, also when nothing had changed (#615): now that
    /// happens again only when the sidebar, the settings or the shortcuts did.
    private struct Local {
        struct Key: Equatable {
            var document: SidebarStore.DocumentKey
            var settings: AppSettings
            var keybindings: Data
        }
        var key: Key
        var bundle: Bundle
        var files: [String: Data]
        var hashes: [String: String]
    }
    private var local: Local?
    /// Test hooks (#615): how often this Mac's bundle was encoded, and a folder's sidebar decoded.
    private(set) var localEncodes = 0
    private(set) var folderDecodes = 0
    /// The folder's sidebar and settings last decoded, by their hashes: the same bytes decode the same.
    private var lastDecoded: (sidebar: String, settings: String, document: SidebarDocument, appSettings: AppSettings)?

    private func localFiles() throws -> Local {
        let keys = (try? Data(contentsOf: AppPaths.file(SettingsSync.keybindingsName))) ?? Data("{}".utf8)
        let settings = store.settings.forSync()
        let key = Local.Key(document: store.documentKey, settings: settings, keybindings: keys)
        if let local, local.key == key { return local }
        var doc = store.document.forSync()
        // The store keeps items in a dictionary: the same sidebar must encode to the same bytes.
        doc.sortItemsForSync()
        let bundle = Bundle(document: doc, settings: settings, keybindings: keys)
        let files = try files(of: bundle)
        localEncodes += 1
        let made = Local(key: key, bundle: bundle, files: files, hashes: files.mapValues(Self.hash))
        local = made
        return made
    }

    private func localBundle() -> Bundle {
        if let made = try? localFiles() { return made.bundle }
        var doc = store.document.forSync()
        doc.sortItemsForSync()
        let keys = (try? Data(contentsOf: AppPaths.file(SettingsSync.keybindingsName))) ?? Data("{}".utf8)
        return Bundle(document: doc, settings: store.settings.forSync(), keybindings: keys)
    }

    private func files(of bundle: Bundle) throws -> [String: Data] {
        [SettingsSync.sidebarName: try Self.encoder.encode(bundle.document),
         SettingsSync.settingsName: try Self.encoder.encode(bundle.settings),
         SettingsSync.keybindingsName: bundle.keybindings]
    }

    private func localHashes() -> [String: String]? {
        (try? localFiles())?.hashes
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeBundle() {
        guard let folder else { return }
        do {
            let made = try localFiles()
            let bundle = made.bundle
            let manifest = try write(made.files, to: folder, parentIDs: history.ids)
            state.lastWritten = manifest
            writtenShape = shape(of: bundle)
            lastSync = manifest.writtenAt
            error = nil
            stateFile.save(state)
            if let id = manifest.id {
                history.remember(id, bundle.document)
                historyFile.save(history)
            }
        } catch {
            self.error = "The sync folder could not be written: \(error.localizedDescription)"
            CraLog.fault("sync bundle not written: \(error)")
        }
    }

    /// The files first, the manifest last: a reader with a manifest whose hashes match has it all.
    /// Through a file coordinator, so iCloud sees whole files (a plain folder does not mind).
    private func write(_ files: [String: Data], to folder: URL, parentIDs: [UUID] = []) throws -> SyncManifest {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files { try coordinatedWrite(data, to: folder.appendingPathComponent(name)) }
        let manifest = SyncManifest(device: device, deviceID: deviceID, writtenAt: clock.now, files: files.mapValues(Self.hash),
                                    id: UUID(), parentIDs: parentIDs)
        try coordinatedWrite(try Self.encoder.encode(manifest), to: folder.appendingPathComponent(SettingsSync.manifestName))
        return manifest
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordinationError ?? writeError.map({ $0 as NSError }) { throw e }
    }

    private func coordinatedRead(_ url: URL) -> Data? {
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { u in
            data = try? Data(contentsOf: u)
        }
        return data
    }

    /// What a folder holds: a whole bundle, one iCloud is still downloading, files from different
    /// writes, a newer Cra's bundle, or nothing (SettingsSync.folderState decides).
    private func look(at folder: URL) -> Look {
        var states: [String: SyncFileState] = [:]
        var data: [String: Data] = [:]
        for name in [SettingsSync.manifestName] + SettingsSync.fileNames {
            let url = folder.appendingPathComponent(name)
            // A file not downloaded yet, or (iCloud before macOS 14) only its placeholder: ask for
            // it and look again when it has arrived.
            let status = downloadStatus(url)
            let placeholder = FileManager.default.fileExists(atPath: folder.appendingPathComponent(SettingsSync.placeholderName(for: name)).path)
            if placeholder || (status != nil && status != .current) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                states[name] = .downloading
                continue
            }
            if let d = coordinatedRead(url) {
                data[name] = d
                states[name] = .present(hash: Self.hash(d))
            } else {
                states[name] = .missing
            }
        }
        let manifestData = data.removeValue(forKey: SettingsSync.manifestName)
        let manifest = manifestData.flatMap { try? Self.decoder.decode(SyncManifest.self, from: $0) }
        let manifestState: SyncManifestState
        switch states.removeValue(forKey: SettingsSync.manifestName) {
        case .downloading?: manifestState = .downloading
        case .present?: manifestState = manifest.map { .read($0) } ?? .unreadable(version: manifestData.flatMap(SettingsSync.manifestVersion(in:)))
        default: manifestState = .missing
        }
        var bundle: Bundle?
        let hashes = data.mapValues(Self.hash)
        if let manifest, SettingsSync.isComplete(manifest, hashes: hashes),
           let sidebar = hashes[SettingsSync.sidebarName], let settings = hashes[SettingsSync.settingsName],
           let (document, appSettings) = decoded(sidebar: sidebar, settings: settings, from: data) {
            bundle = Bundle(document: document, settings: appSettings, keybindings: data[SettingsSync.keybindingsName] ?? Data("{}".utf8))
        }
        let state = SettingsSync.folderState(manifest: manifestState, files: states, readable: bundle != nil)
        folderState = state
        switch state {
        case .empty: return .none
        case .arriving where !SettingsSync.isLacking(manifest: manifestState, files: states): return .downloading
        case .newer: return .newer
        case .mixed, .arriving:
            var files = hashes
            if let manifestData { files[SettingsSync.manifestName] = Self.hash(manifestData) }
            return .mixed(files, wroteManifest: manifest?.deviceID == deviceID, lacking: state == .arriving)
        case .whole:
            guard let manifest, let bundle else { return .downloading }
            return .bundle(manifest, bundle)
        }
    }

    /// The folder's sidebar and settings, decoded only when their bytes are new: an unchanged
    /// bundle is decoded once, not at every look (#615).
    private func decoded(sidebar: String, settings: String, from data: [String: Data]) -> (SidebarDocument, AppSettings)? {
        if let last = lastDecoded, last.sidebar == sidebar, last.settings == settings { return (last.document, last.appSettings) }
        guard let sidebarData = data[SettingsSync.sidebarName], let settingsData = data[SettingsSync.settingsName],
              let document = try? Self.decoder.decode(SidebarDocument.self, from: sidebarData),
              let appSettings = try? Self.decoder.decode(AppSettings.self, from: settingsData) else { return nil }
        folderDecodes += 1
        lastDecoded = (sidebar, settings, document, appSettings)
        return (document, appSettings)
    }

    /// The `cra://debug?sync=` readout: what the last look found and what this Mac does about it.
    func readout() -> String {
        let since = mixWait.since.map { "\(Int(clock.now.timeIntervalSince($0)))s" } ?? "-"
        return "folder=\(folderState.map { "\($0)" } ?? "-") awaiting=\(awaitingDownload) mixedFor=\(since) asking=\(pendingChoice?.device ?? "-") "
            + "lastWritten=\(state.lastWritten?.writtenAt.timeIntervalSince1970 ?? 0) error=\(error ?? "-") "
            + "encodes=\(localEncodes) decodes=\(folderDecodes)"
    }

    /// `merge`: the bundle was written from one this Mac still has (SyncHistory.base), so what changed
    /// here since is kept (SidebarMerge); the user's "Use That Sidebar" and an import take it whole.
    private func apply(_ manifest: SyncManifest, _ bundle: Bundle, merge: Bool = true, remember: Bool = true) {
        var document = bundle.document
        if merge, let base = history.base(for: manifest) {
            document = SidebarMerge.merge(base: base, local: localBundle().document, remote: bundle.document)
            CraLog.note("sync: \(manifest.device)'s bundle merged with what changed here since the one it was written from")
        }
        store.replace(document: document)
        store.settings = store.settings.applyingSynced(bundle.settings)
        try? bundle.keybindings.write(to: AppPaths.file(SettingsSync.keybindingsName), options: .atomic)
        keybindingsChanged()
        guard remember else { return }
        state.lastApplied = manifest
        if let id = manifest.id {
            history.remember(id, bundle.document)
            historyFile.save(history)
        }
        // What is here now is what the folder holds: nothing to write back until something changes
        // here. This Mac's own hashes, since a repaired sidebar need not encode to the same bytes.
        // A merge that kept something changed here differs from the folder's: it goes up on this look.
        let hashes = document == bundle.document ? localHashes() ?? manifest.files : manifest.files
        state.lastWritten = SyncManifest(device: manifest.device, deviceID: manifest.deviceID, writtenAt: manifest.writtenAt, files: hashes)
        writtenShape = document == bundle.document ? currentShape() : nil
        if manifest.deviceID != deviceID, !state.devices.contains(manifest.device) { state.devices.append(manifest.device) }
        otherDevices = state.devices
        lastSync = manifest.writtenAt
        error = nil
        stateFile.save(state)
    }

    // MARK: Watching

    private func startWatching() {
        stopWatching()
        guard let folder else { return }
        poller = clock.every(Self.pollInterval) { [weak self] in self?.poll() }
        let fd = open(folder.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.lookSoon() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        // iCloud: a download finishing changes no directory entry the source sees; the metadata
        // query reports it (and every other change in the container's Documents).
        if case .iCloud? = location, ProcessInfo.processInfo.environment["CRA_SYNC_ICLOUD_DIR"] == nil {
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
            for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
                queryObservers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.lookSoon() }
                })
            }
            query.start()
            metadataQuery = query
        }
    }

    /// A provider writes a bundle file by file; one look after the last of them.
    private func lookSoon() {
        watcherDebounce?.cancel()
        watcherDebounce = clock.after(1) { [weak self] in self?.poll() }
    }

    private func stopWatching() {
        poller?.cancel()
        poller = nil
        watcherDebounce?.cancel()
        watcherDebounce = nil
        writeSoon?.cancel()
        writeSoon = nil
        watcher?.cancel()
        watcher = nil
        metadataQuery?.stop()
        metadataQuery = nil
        for o in queryObservers { NotificationCenter.default.removeObserver(o) }
        queryObservers = []
    }
}
