import CryptoKit
import Foundation
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

    /// Reads keybindings.json again after a bundle wrote it (KeyBindingRegistry.reloadOverrides).
    var keybindingsChanged: @MainActor () -> Void = {}

    /// How often the folder is looked at besides when a watcher fires: a provider may change
    /// a file without a directory event, and the timer is what a test host drives.
    static let pollInterval: TimeInterval = 30

    let device: String
    private let store: SidebarStore
    private let clock: Scheduler
    private let stateFile = JSONStore<State>("sync.json")
    private var state: State
    private var iCloudContainer: URL?
    private var poller: ScheduledWork?
    private var watcher: DispatchSourceFileSystemObject?
    private var metadataQuery: NSMetadataQuery?
    private var identityObserver: NSObjectProtocol?
    private var queryObservers: [NSObjectProtocol] = []
    private var watcherDebounce: ScheduledWork?

    init(store: SidebarStore, clock: Scheduler, device: String? = nil) {
        self.store = store
        self.clock = clock
        // CRA_SYNC_DEVICE names a test instance (two on one Mac share a computer name).
        self.device = device ?? ProcessInfo.processInfo.environment["CRA_SYNC_DEVICE"] ?? Host.current().localizedName ?? "Mac"
        state = stateFile.load(or: { State() })
        location = state.location
        if case .folder(let path)? = state.location { folder = URL(fileURLWithPath: path, isDirectory: true) }
        otherDevices = state.devices
        lastSync = state.lastWritten?.writtenAt
        // A test host: the folder stands in for the container, no entitlement needed.
        if let dir = ProcessInfo.processInfo.environment["CRA_SYNC_ICLOUD_DIR"] {
            iCloudContainer = URL(fileURLWithPath: dir, isDirectory: true)
            iCloudAvailable = true
            if case .iCloud? = state.location { folder = Self.bundleFolder(inContainer: iCloudContainer!) }
        }
    }

    var isEnabled: Bool { location != nil && pendingChoice == nil && !awaitingDownload }

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
        error = nil
        pendingChoice = nil
        awaitingDownload = false
        stateFile.saveNow(state)
        switch look(at: target) {
        case .bundle(let manifest, let bundle) where manifest.device != device:
            pendingChoice = SyncBundleSummary(manifest: manifest, document: bundle.document)
            return .bundleFound(pendingChoice!)
        case .downloading:
            awaitingDownload = true
            startWatching()
            return .downloading
        case .bundle, .none:
            writeBundle()
            startWatching()
            return error.map { .failed($0) } ?? .synced
        }
    }

    /// The bundle in the folder replaces this Mac's sidebar, settings and shortcuts.
    func useRemote() {
        pendingChoice = nil
        guard let folder, case .bundle(let manifest, let bundle) = look(at: folder) else { writeBundle(); startWatching(); return }
        apply(manifest, bundle)
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
    }

    /// One look: a newer bundle from another Mac is applied, then what changed here is written.
    /// While iCloud still downloads a bundle, nothing is written over it.
    func poll() {
        guard let folder, pendingChoice == nil else { return }
        switch look(at: folder) {
        case .downloading:
            awaitingDownload = true
            return
        case .bundle(let manifest, let bundle):
            if awaitingDownload {
                // The bundle sync was turned on against has arrived: now the user picks.
                awaitingDownload = false
                if manifest.device != device {
                    pendingChoice = SyncBundleSummary(manifest: manifest, document: bundle.document)
                    return
                }
            } else if SettingsSync.shouldApply(remote: manifest, lastApplied: state.lastApplied, device: device) {
                apply(manifest, bundle)
            }
        case .none:
            awaitingDownload = false
        }
        if localHashes() != state.lastWritten?.files { writeBundle() }
    }

    // MARK: Export and import (the same bundle, in a folder the user picks)

    func export(to picked: URL) -> String? {
        let target = Self.bundleFolder(in: picked)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            _ = try write(localBundle(), to: target)
            return nil
        } catch { return error.localizedDescription }
    }

    func summary(ofBundleIn picked: URL) -> SyncBundleSummary? {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return nil }
        return SyncBundleSummary(manifest: manifest, document: bundle.document)
    }

    func importBundle(from picked: URL) -> Bool {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return false }
        apply(manifest, bundle, remember: false)
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

    private func localBundle() -> Bundle {
        var doc = store.document
        // The store keeps items in a dictionary: the same sidebar must encode to the same bytes.
        doc.items.sort { $0.id.uuidString < $1.id.uuidString }
        let keys = (try? Data(contentsOf: AppPaths.file(SettingsSync.keybindingsName))) ?? Data("{}".utf8)
        return Bundle(document: doc, settings: store.settings.forSync(), keybindings: keys)
    }

    private func files(of bundle: Bundle) throws -> [String: Data] {
        [SettingsSync.sidebarName: try Self.encoder.encode(bundle.document),
         SettingsSync.settingsName: try Self.encoder.encode(bundle.settings),
         SettingsSync.keybindingsName: bundle.keybindings]
    }

    private func localHashes() -> [String: String]? {
        guard let files = try? files(of: localBundle()) else { return nil }
        return files.mapValues(Self.hash)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeBundle() {
        guard let folder else { return }
        do {
            let manifest = try write(localBundle(), to: folder)
            state.lastWritten = manifest
            lastSync = manifest.writtenAt
            error = nil
            stateFile.save(state)
        } catch {
            self.error = "The sync folder could not be written: \(error.localizedDescription)"
            CraLog.fault("sync bundle not written: \(error)")
        }
    }

    /// The files first, the manifest last: a reader with a manifest whose hashes match has it all.
    /// Through a file coordinator, so iCloud sees whole files (a plain folder does not mind).
    private func write(_ bundle: Bundle, to folder: URL) throws -> SyncManifest {
        let files = try files(of: bundle)
        for (name, data) in files { try coordinatedWrite(data, to: folder.appendingPathComponent(name)) }
        let manifest = SyncManifest(device: device, writtenAt: clock.now, files: files.mapValues(Self.hash))
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

    /// What a folder holds: a whole bundle, one iCloud is still downloading, or nothing.
    private func look(at folder: URL) -> Look {
        var files: [String: Data] = [:]
        var downloading = false
        for name in [SettingsSync.manifestName] + SettingsSync.fileNames {
            let url = folder.appendingPathComponent(name)
            if let d = coordinatedRead(url) { files[name] = d; continue }
            // iCloud keeps an undownloaded file as a placeholder; ask for it and look again later.
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(SettingsSync.placeholderName(for: name)).path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                downloading = true
            }
        }
        guard let data = files.removeValue(forKey: SettingsSync.manifestName),
              let manifest = try? Self.decoder.decode(SyncManifest.self, from: data) else { return downloading ? .downloading : .none }
        guard SettingsSync.isComplete(manifest, hashes: files.mapValues(Self.hash)),
              let sidebar = files[SettingsSync.sidebarName], let settings = files[SettingsSync.settingsName],
              let document = try? Self.decoder.decode(SidebarDocument.self, from: sidebar),
              let appSettings = try? Self.decoder.decode(AppSettings.self, from: settings) else {
            // A manifest naming a file that is not whole yet: a provider is still delivering it.
            return .downloading
        }
        return .bundle(manifest, Bundle(document: document, settings: appSettings, keybindings: files[SettingsSync.keybindingsName] ?? Data("{}".utf8)))
    }

    private func apply(_ manifest: SyncManifest, _ bundle: Bundle, remember: Bool = true) {
        store.replace(document: bundle.document)
        store.settings = store.settings.applyingSynced(bundle.settings)
        try? bundle.keybindings.write(to: AppPaths.file(SettingsSync.keybindingsName), options: .atomic)
        keybindingsChanged()
        guard remember else { return }
        state.lastApplied = manifest
        // What is here now is what the folder holds: nothing to write back until something changes
        // here. This Mac's own hashes, since a repaired sidebar need not encode to the same bytes.
        state.lastWritten = SyncManifest(device: manifest.device, writtenAt: manifest.writtenAt, files: localHashes() ?? manifest.files)
        if manifest.device != device, !state.devices.contains(manifest.device) { state.devices.append(manifest.device) }
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
        watcher?.cancel()
        watcher = nil
        metadataQuery?.stop()
        metadataQuery = nil
        for o in queryObservers { NotificationCenter.default.removeObserver(o) }
        queryObservers = []
    }
}
