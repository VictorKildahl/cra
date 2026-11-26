import CryptoKit
import Foundation
import IOKit
import Observation

/// Settings ▸ General ▸ Sync: the sidebar, the settings, the shortcut overrides and the easels kept
/// the same on the user's Macs, through iCloud (the app's iCloud Documents container) or through
/// a folder a file provider syncs (Dropbox, OneDrive or a similar service). Cra writes a bundle
/// into a `Cra` folder there when something changed here and applies a bundle another Mac
/// wrote when it is newer (SettingsSync in CraCore decides). Easels go in its `Easels` folder as in
/// the data folder, each JSON with the pictures its cards show, and apply with the rest or not at all.
/// No server of Cra's own: iCloud or the provider moves the files. Logins, cookies, history and the
/// Chromium profile stay on each Mac.
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
    /// The bundle a Use That Sidebar could not apply: not asked about again, so its error shows until a new one comes.
    private var failedChoice: SyncManifest?

    static let newerCraError = "Your other Mac syncs with a newer version of Cra. Update Cra on this Mac to keep syncing."

    /// Reads keybindings.json again after a bundle wrote it (KeyBindingRegistry.reloadOverrides).
    var keybindingsChanged: @MainActor () -> Void = {}
    /// An easel open in a tab changes on its canvas, which is up to 0.4 s ahead of its file: `change` gets
    /// the canvas's easel and returns what it becomes, nil when the other Mac deleted it. False: no tab has it open.
    var changeOpenEasel: @MainActor (UUID, (Easel) -> Easel?) -> Bool = { _, _ in false }
    /// Library ▸ Easels lists the easels again after a bundle changed them; `removed` are the ones it deleted.
    var easelsChanged: @MainActor (_ removed: Set<UUID>) -> Void = { _ in }

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
    private var easelWatcher: DispatchSourceFileSystemObject?
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
        var easels: [String: String]
    }
    /// This Mac's easel folder: `<id>.json` and the pictures in `<id>/`.
    private let easelFolder: URL

    init(store: SidebarStore, clock: Scheduler, device: String? = nil, deviceID: String? = nil, easels: URL = AppPaths.file(SettingsSync.easelsName)) {
        self.store = store
        easelFolder = easels
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

    /// The sidebar, the settings or an easel changed: a look (and a write) a few seconds after the last change,
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
    private func currentShape() -> Shape { shape(of: localBundle(), easels: localEasels()) }

    private func shape(of bundle: Bundle, easels: LocalEasels) -> Shape {
        Shape(document: bundle.document.withoutActivity(), settings: bundle.settings, keybindings: bundle.keybindings, easels: easels.files)
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
        failedChoice = nil
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
        case .bundle(let manifest, let bundle):
            do { try apply(manifest, bundle, merge: false) } catch {
                easelsNotSaved(manifest, error)
                failedChoice = manifest
            }
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
        failedChoice = nil
        awaitingDownload = false
        error = nil
        state = State(devices: state.devices)
        stateFile.saveNow(state)
        history = SyncHistory()
        historyFile.saveNow(history)
        local = nil
        lastDecoded = nil
        localEaselsMade = nil
        fileHashes = [:]
        folderEasels = [:]
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
                    if manifest != failedChoice { pendingChoice = SyncBundleSummary(manifest: manifest, document: bundle.document) }
                    return
                }
            } else if SettingsSync.shouldApply(remote: manifest, lastApplied: state.lastApplied, deviceID: deviceID) {
                // A later bundle, also one iCloud delivered in parts: applied with no question.
                do { guard try apply(manifest, bundle) else { return } } catch {
                    easelsNotSaved(manifest, error)
                    return
                }
            }
        case .none:
            // No bundle at all (the Cra folder was deleted, or emptied): this Mac's goes back.
            gone = true
            awaitingDownload = false
        }
        if gone || localHashes() != state.lastWritten?.files || localEasels().files != state.lastWritten?.easels { writeBundle() }
    }

    // MARK: Export and import (the same bundle, in a folder the user picks)

    func export(to picked: URL) -> String? {
        let target = Self.bundleFolder(in: picked)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let easels = localEasels()
            guard easels.unreadable.isEmpty else { return Self.unreadableEasels(easels) }
            _ = try write(localFiles().files, easels: easels, to: target)
            return nil
        } catch { return error.localizedDescription }
    }

    func summary(ofBundleIn picked: URL) -> SyncBundleSummary? {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return nil }
        return SyncBundleSummary(manifest: manifest, document: bundle.document)
    }

    /// Nil when imported, else what Settings says.
    func importBundle(from picked: URL) -> String? {
        guard case .bundle(let manifest, let bundle) = look(at: Self.bundleFolder(in: picked)) else { return "The folder holds no Cra settings." }
        do {
            try apply(manifest, bundle, merge: false, remember: false)
            return nil
        } catch { return "Not imported: \(error.localizedDescription)" }
    }

    /// `<picked>/Cra`, or `picked` itself when the user pointed at the Cra folder.
    private static func bundleFolder(in picked: URL) -> URL {
        picked.lastPathComponent == SettingsSync.folderName ? picked : picked.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
    }

    // MARK: Bundles

    /// A bundle as read. `easels` are the folder's, by id (nil: an older Cra's bundle, its easels unknown),
    /// and `folder` is where it was read; this Mac's own easels are `localEasels()`.
    private struct Bundle {
        var document: SidebarDocument
        var settings: AppSettings
        var keybindings: Data
        var easels: [UUID: Easel]? = nil
        var folder: URL? = nil
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

    /// This Mac's easels: each JSON and each picture a card shows, by bundle path with its hash, and the
    /// easels decoded. Listed again only when the folder changed: every save or removal renames in it (#615).
    private struct LocalEasels {
        /// The folder's date when listed; nil lists it again at the next look.
        var folderModified: Date?
        var files: [String: String] = [:]
        var easels: [UUID: Easel] = [:]
        /// Each easel's JSON as hashed: what a write sends, also when the file changed since.
        var json: [UUID: Data] = [:]
        /// Easel files this Mac can't read and has no sent copy of, which another Mac may have: a bundle without
        /// them would delete them there, so none is written.
        var unreadable: Set<String> = []
    }
    private var localEaselsMade: LocalEasels?
    /// Test hooks (#615): how often an easel file or picture was read, and an easel decoded.
    private(set) var easelReads = 0
    private(set) var easelDecodes = 0
    /// Easel files and pictures, here and in the folder, by path: one whose size and date are the same is not read again.
    private var fileHashes: [String: (size: UInt64, modified: Date, hash: String)] = [:]
    /// The folder's easels last decoded, by hash: the same bytes decode the same.
    private var folderEasels: [String: Easel] = [:]

    private func localEasels() -> LocalEasels {
        let fm = FileManager.default
        let modified = (try? fm.attributesOfItem(atPath: easelFolder.path))?[.modificationDate] as? Date
        if let made = localEaselsMade, made.folderModified != nil, made.folderModified == modified { return made }
        let before = localEaselsMade
        var made = LocalEasels(folderModified: modified)
        for name in (try? fm.contentsOfDirectory(atPath: easelFolder.path)) ?? [] {
            let path = "\(SettingsSync.easelsName)/\(name)", url = localURL(path)
            guard let (id, picture) = SettingsSync.easelPath(path), picture == nil, let found = stat(url) else { continue }
            var listed: (hash: String, easel: Easel, json: Data)?
            if let known = fileHashes[url.path], known.size == found.size, known.modified == found.modified, before?.files[path] == known.hash,
               let easel = before?.easels[id], let json = before?.json[id] {
                listed = (known.hash, easel, json)
            } else if let json = try? Data(contentsOf: url) {
                easelReads += 1
                if let easel = decodeEasel(json), easel.id == id {
                    listed = (Self.hash(json), easel, json)
                    fileHashes[url.path] = (found.size, found.modified, Self.hash(json))
                }
            }
            // For a file not read now: the copy listed before, or the one sent last, from the sync folder.
            var last: (hash: String, easel: Easel, json: Data)?
            if listed == nil, let hash = before?.files[path], let easel = before?.easels[id], let json = before?.json[id] {
                last = (hash, easel, json)
            } else if listed == nil {
                last = sentCopy(path)
            }
            switch SettingsSync.easelChoice(readable: listed != nil, lastCopy: last != nil, remembered: listed == nil && history.remembers(easel: id)) {
            case .send: break
            case .carry: listed = last
            case .hold: made.unreadable.insert(name)
            case .leaveOut: break
            }
            // Listed again at the next look, which may read it.
            if listed == nil || last != nil { made.folderModified = nil }
            guard let (hash, easel, json) = listed else { continue }
            made.files[path] = hash
            made.easels[id] = easel
            made.json[id] = json
            // A picture a card names that isn't here stays out: the other Mac would wait for it for ever.
            for picture in Set(easel.items.flatMap(Easel.files(of:))) {
                let picturePath = "\(SettingsSync.easelsName)/\(id.uuidString)/\(picture)"
                guard SettingsSync.easelPath(picturePath) != nil, let hash = fileHash(localURL(picturePath), coordinated: false) else { continue }
                made.files[picturePath] = hash
            }
        }
        localEaselsMade = made
        return made
    }

    /// The copy of an easel file this Mac last wrote or applied, read from the sync folder; nil when it isn't there.
    private func sentCopy(_ path: String) -> (hash: String, easel: Easel, json: Data)? {
        guard let folder, let hash = state.lastWritten?.easels?[path], let (id, _) = SettingsSync.easelPath(path),
              let json = coordinatedRead(folder.appendingPathComponent(path)) else { return nil }
        easelReads += 1
        guard Self.hash(json) == hash, let easel = decodeEasel(json), easel.id == id else { return nil }
        return (hash, easel, json)
    }

    /// What Settings says while an easel file this Mac can't read holds its bundle back.
    private static func unreadableEasels(_ easels: LocalEasels) -> String {
        "Cra can't read the easel file \(easels.unreadable.sorted().joined(separator: ", ")), so sync waits and your other Mac keeps its copy of that easel."
    }

    /// Where a bundle path under `Easels/` is on this Mac.
    private func localURL(_ path: String) -> URL {
        easelFolder.appendingPathComponent(String(path.dropFirst(SettingsSync.easelsName.count + 1)))
    }

    private func stat(_ url: URL) -> (size: UInt64, modified: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value, let modified = attributes[.modificationDate] as? Date else { return nil }
        return (size, modified)
    }

    private func fileHash(_ url: URL, coordinated: Bool) -> String? {
        guard let found = stat(url) else { return nil }
        if let known = fileHashes[url.path], known.size == found.size, known.modified == found.modified { return known.hash }
        guard let data = coordinated ? coordinatedRead(url) : try? Data(contentsOf: url) else { return nil }
        easelReads += 1
        let hash = Self.hash(data)
        fileHashes[url.path] = (found.size, found.modified, hash)
        return hash
    }

    /// A file just written with `hash`: the next look takes the hash without reading it back.
    private func know(_ url: URL, hash: String) {
        guard let found = stat(url) else { return }
        fileHashes[url.path] = (found.size, found.modified, hash)
    }

    private func decodeEasel(_ data: Data) -> Easel? {
        guard let easel = try? Self.decoder.decode(Easel.self, from: data) else { return nil }
        easelDecodes += 1
        return easel
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeBundle() {
        guard let folder else { return }
        do {
            let made = try localFiles()
            let bundle = made.bundle
            let easels = localEasels()
            guard easels.unreadable.isEmpty else {
                // Left out, an easel the other Mac has would go there as deleted.
                error = Self.unreadableEasels(easels)
                return
            }
            let manifest = try write(made.files, easels: easels, to: folder, parentIDs: history.ids, easelParentIDs: history.easelIDs)
            state.lastWritten = manifest
            writtenShape = shape(of: bundle, easels: easels)
            lastSync = manifest.writtenAt
            error = nil
            stateFile.save(state)
            if let id = manifest.id {
                // The easels the bundle holds, which the other Mac's merge with this one goes by.
                let sent = easels.easels.values.filter { manifest.easels?["\(SettingsSync.easelsName)/\($0.id.uuidString).json"] != nil }
                history.remember(id, bundle.document, settings: bundle.settings, easels: sent.sorted { SettingsSync.precedes($0.id, $1.id) })
                historyFile.save(history)
            }
        } catch {
            self.error = "The sync folder could not be written: \(error.localizedDescription)"
            CraLog.fault("sync bundle not written: \(error)")
        }
    }

    /// Pictures, the easels that differ, the files, the manifest last: a reader whose manifest's hashes match has it
    /// all. Through a file coordinator, so iCloud sees whole files; then what `Easels` holds beyond the manifest goes.
    private func write(_ files: [String: Data], easels: LocalEasels, to folder: URL, parentIDs: [UUID] = [], easelParentIDs: [UUID] = []) throws -> SyncManifest {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [String: String] = [:]
        for pictures in [true, false] {
            for (path, hash) in easels.files where (SettingsSync.easelPath(path)?.picture != nil) == pictures {
                let target = folder.appendingPathComponent(path)
                // A picture never changes under its name: one there, or on its way, stays.
                let there = pictures
                    ? FileManager.default.fileExists(atPath: target.path) || FileManager.default.fileExists(atPath: placeholder(of: target).path)
                    : (downloadStatus(target).map { $0 == .current } ?? true) && fileHash(target, coordinated: true) == hash
                if there { written[path] = hash; continue }
                // An easel as listed, so the bundle, the manifest and the history agree; a picture never changes.
                guard let data = pictures ? try? Data(contentsOf: localURL(path)) : SettingsSync.easelPath(path).flatMap({ easels.json[$0.id] })
                else { continue }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try coordinatedWrite(data, to: target)
                written[path] = Self.hash(data)
                know(target, hash: Self.hash(data))
            }
        }
        for (name, data) in files { try coordinatedWrite(data, to: folder.appendingPathComponent(name)) }
        let manifest = SyncManifest(device: device, deviceID: deviceID, writtenAt: clock.now, files: files.mapValues(Self.hash),
                                    id: UUID(), parentIDs: parentIDs,
                                    autoArchived: SyncAutoArchive.listed(store.autoArchivedTabs, now: clock.now), easels: written,
                                    easelParentIDs: easelParentIDs)
        try coordinatedWrite(try Self.encoder.encode(manifest), to: folder.appendingPathComponent(SettingsSync.manifestName))
        prune(folder, keeping: written)
        return manifest
    }

    /// Removes the files in the folder's `Easels` that `named` leaves out, and iCloud's placeholders for them.
    /// Only after this Mac wrote its manifest: a manifest without `easels` (an older Cra's) prunes nothing.
    private func prune(_ folder: URL, keeping named: [String: String]) {
        let fm = FileManager.default
        /// The name is a file `named` has, or iCloud's placeholder for one.
        func kept(_ name: String, in parent: String) -> Bool {
            if named["\(parent)/\(name)"] != nil { return true }
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return false }
            return named["\(parent)/\(name.dropFirst().dropLast(7))"] != nil
        }
        let root = folder.appendingPathComponent(SettingsSync.easelsName, isDirectory: true)
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let url = root.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                if !kept(name, in: SettingsSync.easelsName) { coordinatedRemove(url) }
                continue
            }
            let inside = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            let gone = inside.filter { !kept($0, in: "\(SettingsSync.easelsName)/\(name)") }
            if gone.count == inside.count { coordinatedRemove(url) } else { for f in gone { coordinatedRemove(url.appendingPathComponent(f)) } }
        }
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordinationError ?? writeError.map({ $0 as NSError }) { throw e }
    }

    private func coordinatedRemove(_ url: URL) {
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: nil) { u in
            try? FileManager.default.removeItem(at: u)
        }
    }

    /// iCloud's placeholder for a file it has not downloaded (before macOS 14).
    private func placeholder(of url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(SettingsSync.placeholderName(for: url.lastPathComponent))
    }

    /// A file not downloaded yet, or (iCloud before macOS 14) only its placeholder: asked for, and looked
    /// at again when it has arrived. Since macOS 14 reading it would wait for the download on the main thread.
    private func isArriving(_ url: URL) -> Bool {
        let status = downloadStatus(url)
        guard FileManager.default.fileExists(atPath: placeholder(of: url).path) || (status != nil && status != .current) else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return true
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
            if isArriving(url) {
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
        if let easels = manifest?.easels {
            states.merge(easelStates(easels, in: folder)) { a, _ in a }
        }
        var bundle: Bundle?
        let hashes = states.compactMapValues { if case .present(let h) = $0 { h } else { nil } }
        if let manifest, SettingsSync.isComplete(manifest, hashes: hashes),
           let sidebar = hashes[SettingsSync.sidebarName], let settings = hashes[SettingsSync.settingsName],
           let (document, appSettings) = decoded(sidebar: sidebar, settings: settings, from: data) {
            switch manifest.easels.map({ decodedEasels($0, in: folder) }) {
            case .some(nil): break // An easel that doesn't decode leaves the bundle unread, as an unreadable sidebar does.
            case let easels: bundle = Bundle(document: document, settings: appSettings, keybindings: data[SettingsSync.keybindingsName] ?? Data("{}".utf8),
                                             easels: easels ?? nil, folder: folder)
            }
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

    /// The easel files and pictures a manifest names, as `look` reports the three files; a bad path is never read.
    /// A file whose size and date are as before is not read again (#615).
    private func easelStates(_ paths: [String: String], in folder: URL) -> [String: SyncFileState] {
        var states: [String: SyncFileState] = [:]
        for path in paths.keys where SettingsSync.easelPath(path) != nil {
            let url = folder.appendingPathComponent(path)
            states[path] = isArriving(url) ? .downloading : fileHash(url, coordinated: true).map { .present(hash: $0) } ?? .missing
        }
        return states
    }

    /// The folder's easels by id, decoded only when their bytes are new; nil when one doesn't decode.
    private func decodedEasels(_ paths: [String: String], in folder: URL) -> [UUID: Easel]? {
        var easels: [UUID: Easel] = [:], byHash: [String: Easel] = [:]
        for (path, hash) in paths {
            guard let (id, picture) = SettingsSync.easelPath(path), picture == nil else { continue }
            let read = { () -> Easel? in
                guard let data = self.coordinatedRead(folder.appendingPathComponent(path)) else { return nil }
                self.easelReads += 1
                return Self.hash(data) == hash ? self.decodeEasel(data) : nil
            }
            guard let easel = folderEasels[hash] ?? read(), easel.id == id else { return nil }
            easels[id] = easel
            byHash[hash] = easel
        }
        folderEasels = byHash
        return easels
    }

    /// The `cra://debug?sync=` readout: what the last look found and what this Mac does about it.
    func readout() -> String {
        let since = mixWait.since.map { "\(Int(clock.now.timeIntervalSince($0)))s" } ?? "-"
        return "folder=\(folderState.map { "\($0)" } ?? "-") awaiting=\(awaitingDownload) mixedFor=\(since) asking=\(pendingChoice?.device ?? "-") "
            + "lastWritten=\(state.lastWritten?.writtenAt.timeIntervalSince1970 ?? 0) error=\(error ?? "-") "
            + "encodes=\(localEncodes) decodes=\(folderDecodes) easelReads=\(easelReads)"
    }

    /// `merge`: the bundle was written from one this Mac still has (SyncHistory.base), so what changed
    /// here since is kept (SidebarMerge); the user's "Use That Sidebar" and an import take it whole.
    /// - Returns: false when a canvas took a change it saves in a moment: this look writes nothing.
    /// - Throws: when an easel or a picture could not be copied or saved. Nothing else is applied then.
    @discardableResult
    private func apply(_ manifest: SyncManifest, _ bundle: Bundle, merge: Bool = true, remember: Bool = true) throws -> Bool {
        // Before the sidebar: a synced row `easel://<id>` must not open a blank easel that saves over the real one.
        let easels = try applyEasels(manifest, bundle, base: merge ? history.baseEasels(for: manifest) : nil)
        var document = bundle.document
        var settings = bundle.settings
        if merge, var base = history.base(for: manifest) {
            let local = localBundle()
            // An archive pass that ran before a look on the other Mac reached it is undone (SyncAutoArchive): the base
            // forgets the tab, so the merge keeps the copy one Mac still has.
            let localIDs = Set(local.document.items.map(\.id)), remoteIDs = Set(bundle.document.items.map(\.id))
            let archivedHere = Dictionary(store.autoArchivedTabs.map { ($0.id, $0.at) }, uniquingKeysWith: max)
                .filter { !localIDs.contains($0.key) && remoteIDs.contains($0.key) }
            let archivedThere = manifest.autoArchivedTabs.filter { localIDs.contains($0.key) && !remoteIDs.contains($0.key) }
            let back = SyncAutoArchive.undone(archived: archivedHere, seen: bundle.document.lastActive, limit: store.autoArchiveChoice(forTab:))
                .union(SyncAutoArchive.undone(archived: archivedThere, seen: local.document.lastActive, limit: store.autoArchiveChoice(forTab:)))
            if !back.isEmpty {
                CraLog.note("sync: \(back.count) tabs archived before a look on the other Mac arrived stay in the sidebar")
                base = base.removing(back)
            }
            document = SidebarMerge.merge(base: base, local: local.document, remote: bundle.document)
            // A setting changed here since that bundle stays, as the sidebar's changes do; a history from an older Cra
            // has no settings to merge against, and the bundle's replace this Mac's as before.
            if let baseSettings = history.baseSettings(for: manifest) {
                settings = SettingsMerge.merge(base: baseSettings, local: local.settings, remote: bundle.settings)
            }
            CraLog.note("sync: \(manifest.device)'s bundle merged with what changed here since the one it was written from")
        }
        store.replace(document: document)
        store.forgetAutoArchived(Set(document.items.map(\.id)))
        store.settings = store.settings.applyingSynced(settings)
        try? bundle.keybindings.write(to: AppPaths.file(SettingsSync.keybindingsName), options: .atomic)
        keybindingsChanged()
        if easels.changed { easelsChanged(easels.removed) }
        guard remember else { return !easels.onCanvas }
        state.lastApplied = manifest
        if let id = manifest.id {
            // `[]` for a bundle without easels, nil for an older Cra's: only the first deletes what the base had.
            let sent = bundle.easels.map { $0.values.sorted { SettingsSync.precedes($0.id, $1.id) } }
            history.remember(id, bundle.document, settings: bundle.settings, easels: sent)
            historyFile.save(history)
        }
        // What is here now is what the folder holds: nothing to write back until something changes
        // here. This Mac's own hashes, since a repaired sidebar need not encode to the same bytes.
        // A merge that kept something changed here differs from the folder's: it goes up on this look.
        // Easels were written as the bundle's bytes; an older Cra's bundle, which names none, gets this Mac's back.
        let same = document == bundle.document && settings == bundle.settings
        let hashes = same ? localHashes() ?? manifest.files : manifest.files
        state.lastWritten = SyncManifest(device: manifest.device, deviceID: manifest.deviceID, writtenAt: manifest.writtenAt, files: hashes,
                                         easels: manifest.easels)
        writtenShape = same && localEasels().files == manifest.easels ? currentShape() : nil
        if manifest.deviceID != deviceID, !state.devices.contains(manifest.device) { state.devices.append(manifest.device) }
        otherDevices = state.devices
        lastSync = manifest.writtenAt
        error = nil
        stateFile.save(state)
        return !easels.onCanvas
    }

    /// Settings shows why this Mac stopped syncing: an easel it could not save. The next look tries again.
    private func easelsNotSaved(_ manifest: SyncManifest, _ failure: Error) {
        error = "Easels from \(manifest.device) could not be saved on this Mac: \(failure.localizedDescription)"
        CraLog.fault("sync: \(manifest.device)'s easels not applied, tried again at the next look: \(failure)")
    }

    /// What an apply did to the easels: whether any changed, the ones it deleted, and whether a canvas took a change.
    private struct EaselChanges {
        var changed = false
        var removed: Set<UUID> = []
        var onCanvas = false
    }

    /// The easels the other Mac changed since `base` merged into this Mac's, pictures first (no base: add and
    /// overwrite, delete nothing). Throws, with nothing but pictures written, when a file could not be copied whole.
    private func applyEasels(_ manifest: SyncManifest, _ bundle: Bundle, base: [Easel]?) throws -> EaselChanges {
        var changes = EaselChanges()
        // An older Cra's bundle: its easels are unknown, and this Mac's stay as they are.
        guard let remote = bundle.easels, let paths = manifest.easels, let from = bundle.folder else { return changes }
        let base = base.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        let touched = Set(remote.keys).union(base.map { Array($0.keys) } ?? []).filter { base?[$0] != remote[$0] }
        var bytes: [UUID: Data] = [:]
        let fm = FileManager.default
        for (path, hash) in paths {
            guard let (id, picture) = SettingsSync.easelPath(path), touched.contains(id) else { continue }
            let target = localURL(path)
            if picture != nil, fm.fileExists(atPath: target.path) { continue }
            guard let data = coordinatedRead(from.appendingPathComponent(path)), Self.hash(data) == hash else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path])
            }
            if picture == nil { bytes[id] = data; continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            know(target, hash: hash)
            // A picture lands in the easel's own folder, which the listing's date doesn't cover.
            localEaselsMade?.folderModified = nil
        }
        let local = localEasels().easels
        for id in touched.sorted(by: SettingsSync.precedes) {
            let b = base?[id], r = remote[id]
            var onCanvas: Easel?? = .none
            let open = changeOpenEasel(id) { here in
                let merged = Easel.merge(base: b, local: here, remote: r)
                if merged != here { onCanvas = .some(merged) }
                return merged
            }
            if open {
                guard let merged = onCanvas else { continue }
                changes.changed = true
                changes.onCanvas = true
                if merged == nil { changes.removed.insert(id) }
                continue
            }
            let merged = Easel.merge(base: b, local: local[id], remote: r)
            guard merged != local[id] else { continue }
            changes.changed = true
            guard let merged else {
                EaselFolder.remove(id, in: easelFolder)
                changes.removed.insert(id)
                continue
            }
            // Taken unchanged, as the bundle's bytes: their hash is the manifest's, and nothing goes back.
            let data = try merged == r ? bytes[id] ?? Self.encoder.encode(merged) : Self.encoder.encode(merged)
            let target = localURL("\(SettingsSync.easelsName)/\(id.uuidString).json")
            try fm.createDirectory(at: easelFolder, withIntermediateDirectories: true)
            try JSONStore<Easel>.replace(target, with: data)
            know(target, hash: Self.hash(data))
        }
        return changes
    }

    // MARK: Watching

    private func startWatching() {
        stopWatching()
        guard let folder else { return }
        poller = clock.every(Self.pollInterval) { [weak self] in self?.poll() }
        watcher = watch(folder) { [weak self] in self?.lookSoon() }
        // Every easel save or removal renames in this folder: a change there goes up soon, as the sidebar's does (#598).
        try? FileManager.default.createDirectory(at: easelFolder, withIntermediateDirectories: true)
        easelWatcher = watch(easelFolder) { [weak self] in self?.changedHere() }
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

    private func watch(_ folder: URL, _ changed: @escaping @MainActor () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { changed() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
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
        easelWatcher?.cancel()
        easelWatcher = nil
        metadataQuery?.stop()
        metadataQuery = nil
        for o in queryObservers { NotificationCenter.default.removeObserver(o) }
        queryObservers = []
    }
}
