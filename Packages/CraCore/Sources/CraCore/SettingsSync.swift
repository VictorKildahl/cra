import Foundation

/// The folder a file provider syncs (iCloud Drive, Dropbox, OneDrive or a similar service) holds a `Cra` folder
/// with a copy of the sidebar, the settings and the shortcut overrides, plus this manifest.
/// Each Mac writes the three files, then the manifest last, so a reader that sees a manifest
/// whose hashes match the files has a whole bundle. Nothing leaves the Mac but through the
/// folder the user chose, and the Chromium profile (logins, cookies, history) never does.
/// Easels go under `easels`, not `files`, which an older Cra reads alone and so still finds whole
/// rather than waiting and writing over; a manifest without the key comes from an older Cra.
public struct SyncManifest: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// The Mac that wrote the bundle, by its computer name: what the question on another Mac shows.
    public var device: String
    /// The Mac that wrote the bundle, so it never applies its own write. Not the computer name:
    /// Migration Assistant gives the new Mac the old one's, and those two are the Macs that sync.
    public var deviceID: String
    public var writtenAt: Date
    /// File name → hash of its bytes, for every file in the bundle.
    public var files: [String: String]
    /// This bundle, and the bundles the writing Mac had written or applied when it wrote it, newest
    /// first (its SyncHistory): the first is the one it was written from. A Mac that has one of
    /// them merges this bundle with what changed there since the newest it has (SidebarMerge). The
    /// whole list, not only the first: a Mac that writes twice before the other looks (iCloud
    /// delivers the later bundle only) would otherwise name a parent the other Mac never saw.
    /// Missing in a bundle from an older Cra, which is applied whole.
    public var id: UUID?
    public var parentIDs: [UUID]?
    /// Tabs the writing Mac's archive pass took lately, by id string → when (SyncAutoArchive): the other Mac keeps one it
    /// had looked at meanwhile. Missing in a bundle from an older Cra.
    public var autoArchived: [String: Date]?
    /// Bundle path → hash of its bytes, for every easel file and picture in the bundle (`SettingsSync.easelPath`).
    /// Missing in a bundle from an older Cra: its easels are unknown, and none is deleted for it.
    public var easels: [String: String]?
    /// The `parentIDs` whose easels the writing Mac had (SyncHistory.easelIDs): only those are a base for its
    /// easels. A bundle an older Cra applied or wrote vouches for none. Missing: no easel base, nothing deleted.
    public var easelParentIDs: [UUID]?

    public init(version: Int = SyncManifest.currentVersion, device: String, deviceID: String, writtenAt: Date, files: [String: String],
                id: UUID? = nil, parentIDs: [UUID]? = nil, autoArchived: [UUID: Date]? = nil, easels: [String: String]? = nil,
                easelParentIDs: [UUID]? = nil) {
        self.version = version
        self.device = device
        self.deviceID = deviceID
        self.writtenAt = writtenAt
        self.files = files
        self.id = id
        self.parentIDs = parentIDs
        self.autoArchived = autoArchived.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.uuidString, $0.value) }) }
        self.easels = easels
        self.easelParentIDs = easelParentIDs
    }

    /// `autoArchived` by id.
    public var autoArchivedTabs: [UUID: Date] {
        var out: [UUID: Date] = [:]
        for (k, v) in autoArchived ?? [:] { if let id = UUID(uuidString: k) { out[id] = v } }
        return out
    }
}

/// What the sync folder holds and when a bundle found there is applied.
public enum SettingsSync {
    /// The subfolder Cra makes inside the folder the user picks, so a folder with other files
    /// in it is never written over.
    public static let folderName = "Cra"
    public static let manifestName = "manifest.json"
    public static let sidebarName = "sidebar.json"
    public static let settingsName = "settings.json"
    public static let keybindingsName = "keybindings.json"
    /// Every file in a bundle besides the manifest.
    public static let fileNames = [sidebarName, settingsName, keybindingsName]

    /// iCloud keeps a file it has not downloaded as `.<name>.icloud`. A bundle whose file is
    /// only a placeholder is not applied; Cra asks iCloud to download it and looks again.
    public static func placeholderName(for name: String) -> String { ".\(name).icloud" }

    /// The folder of easels, in the bundle as in the data folder: `<id>.json`, and its pictures in `<id>/`.
    public static let easelsName = "Easels"

    /// What a write does with an easel file on this Mac: `readable`, this Mac read and decoded it now; `lastCopy`, a copy
    /// it listed or sent before is at hand; `remembered`, a bundle in its history held that easel (SyncHistory.remembers).
    public static func easelChoice(readable: Bool, lastCopy: Bool, remembered: Bool) -> SyncEaselChoice {
        if readable { return .send }
        if lastCopy { return .carry }
        return remembered ? .hold : .leaveOut
    }

    /// What a write does when this Mac's `Easels` folder can't be listed: `missing`, no easel was made yet and the folder
    /// lists as none. Else no bundle goes up: one without easels would delete every easel on the other Mac.
    public static func unlistedEaselsChoice(missing: Bool) -> SyncEaselChoice { missing ? .leaveOut : .hold }

    /// The easel a path in `SyncManifest.easels` names, and its picture when it names one:
    /// `Easels/<id>.json` or `Easels/<id>/<plain name>`. Nil for any other path, which is never read or written.
    public static func easelPath(_ path: String) -> (id: UUID, picture: String?)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == easelsName else { return nil }
        switch parts.count {
        case 2:
            guard let id = UUID(uuidString: String(parts[1].dropLast(5))), parts[1] == id.uuidString + ".json" else { return nil }
            return (id, nil)
        case 3:
            guard let id = UUID(uuidString: parts[1]), parts[1] == id.uuidString, Easel.isPlainFileName(parts[2]) else { return nil }
            return (id, parts[2])
        default:
            return nil
        }
    }

    /// Whether `a` sorts before `b` as their `uuidString`s do, from their 16 bytes (#615).
    public static func precedes(_ a: UUID, _ b: UUID) -> Bool {
        withUnsafeBytes(of: a.uuid) { x in
            withUnsafeBytes(of: b.uuid) { y in
                for i in 0..<16 where x[i] != y[i] { return x[i] < y[i] }
                return false
            }
        }
    }

    /// Whether a manifest read from the folder is applied: written by another Mac, by a Cra
    /// that writes a format this one reads, and later than the one applied last.
    public static func shouldApply(remote: SyncManifest, lastApplied: SyncManifest?, deviceID: String) -> Bool {
        if remote.deviceID == deviceID { return false }
        if remote.version > SyncManifest.currentVersion { return false }
        if let last = lastApplied, remote.writtenAt <= last.writtenAt { return false }
        return true
    }

    /// Whether the files on disk are the ones the manifest names: a provider delivers a bundle
    /// file by file, and the manifest may land before a file it names has finished downloading.
    public static func isComplete(_ manifest: SyncManifest, hashes: [String: String]) -> Bool {
        !manifest.files.isEmpty && manifest.files.allSatisfy { hashes[$0.key] == $0.value }
            && (manifest.easels ?? [:]).allSatisfy { easelPath($0.key) != nil && hashes[$0.key] == $0.value }
    }

    /// The version in a manifest this Cra can't otherwise read: a newer Cra may have changed the rest.
    public static func manifestVersion(in data: Data) -> Int? {
        struct Versioned: Decodable { var version: Int }
        return (try? JSONDecoder().decode(Versioned.self, from: data))?.version
    }

    /// What a look at the folder found (#378). Only a file still on its way is waited for without
    /// end. Every file there but not the ones the manifest names is a mix of two writes (two Macs
    /// at once, or a provider that kept one Mac's file and the other's manifest), and it stays that
    /// way until a Mac writes a whole bundle again. `readable` is whether the manifest's files
    /// decode; it only counts when they are the manifest's.
    public static func folderState(manifest: SyncManifestState, files: [String: SyncFileState], readable: Bool) -> SyncFolderState {
        if case .downloading = manifest { return .arriving }
        if files.values.contains(.downloading) { return .arriving }
        let m: SyncManifest
        switch manifest {
        case .missing, .downloading: return .empty
        case .unreadable(let version):
            return (version ?? 0) > SyncManifest.currentVersion ? .newer : .mixed
        case .read(let read): m = read
        }
        // A newer Cra's bundle is never written over, whole or not: that Cra puts it right.
        if m.version > SyncManifest.currentVersion { return .newer }
        if lacksFile(m, files) { return .arriving }
        let hashes = files.compactMapValues { if case .present(let h) = $0 { h } else { nil } }
        guard isComplete(m, hashes: hashes) else { return .mixed }
        // The very files the manifest names, which this Cra can't decode: a format from a newer Cra.
        return readable ? .whole : .newer
    }

    /// Whether a folder that `folderState` finds `.arriving` lacks a file the manifest names with
    /// nothing on its way: no iCloud placeholder, no download (#378). The file was deleted, or a
    /// provider left it out, or one that only lists a file once it has downloaded is still
    /// delivering it. Waited for like a mix, but longer (SyncMixWait), and then written over.
    public static func isLacking(manifest: SyncManifestState, files: [String: SyncFileState]) -> Bool {
        guard case .read(let m) = manifest, m.version <= SyncManifest.currentVersion,
              !files.values.contains(.downloading) else { return false }
        return lacksFile(m, files)
    }

    /// Whether a file the manifest names isn't there. A path in `easels` that names no easel counts as not there.
    private static func lacksFile(_ m: SyncManifest, _ files: [String: SyncFileState]) -> Bool {
        let gone = { (name: String) in files[name] == nil || files[name] == .missing }
        return m.files.keys.contains(where: gone) || (m.easels ?? [:]).keys.contains { easelPath($0) == nil || gone($0) }
    }
}

/// A bundle file as a look finds it.
public enum SyncFileState: Equatable {
    case missing
    /// An iCloud placeholder, or a file iCloud or a File Provider has not downloaded yet.
    case downloading
    case present(hash: String)
}

/// The manifest as a look finds it.
public enum SyncManifestState: Equatable {
    case missing
    case downloading
    /// There, but not a manifest this Cra reads; `version` if that much decodes.
    case unreadable(version: Int?)
    case read(SyncManifest)
}

/// What the sync folder holds, which decides what a look does.
public enum SyncFolderState: Equatable {
    /// No manifest: this Mac's bundle goes there.
    case empty
    /// A file is still on its way: nothing is applied or written until it is there.
    case arriving
    /// The manifest's files, readable: a bundle to apply.
    case whole
    /// Every file there, but not the ones the manifest names: files from different writes. Waited
    /// for a little (SyncMixWait), in case a provider is still delivering, then written over.
    case mixed
    /// Written by a newer Cra: neither applied nor written over.
    case newer
}

/// How long the folder has held the same mix (#378). A provider still delivering a bundle
/// changes a file on the way, and every change starts the wait again; a mix that stays put for
/// two looks of the 30-second poll is no download, and waiting longer changes nothing. Then this
/// Mac writes its own sidebar, settings and shortcuts as a whole bundle, which the other Mac
/// applies. The Mac whose manifest is in the folder wrote last, so it writes first; another Mac
/// waits twice as long, so that the writer's bundle lands first and is applied there instead.
///
/// A file the manifest names that isn't there at all (`SettingsSync.isLacking`) is waited for the
/// same way, but another Mac gives it ten minutes: a provider may only list a file once it has
/// downloaded. A Mac that has not synced in this folder yet never writes over another Mac's
/// bundle: it hasn't been asked which sidebar to keep, and its bundle would replace the other
/// Mac's. It waits for the writer, then asks.
public struct SyncMixWait: Equatable {
    public static let writerDelay: TimeInterval = 60
    public static let otherDelay: TimeInterval = 120
    public static let otherLackingDelay: TimeInterval = 600

    /// The files' hashes when the mix was first seen, and when that was.
    public private(set) var seen: [String: String]?
    public private(set) var since: Date?

    public init() {}

    /// A look found a mix of these files (name → hash, the manifest's own included), or a file
    /// lacking (`lacking`): whether this Mac writes its bundle now. `synced` is whether this Mac has
    /// written or applied a bundle since sync was turned on.
    public mutating func shouldRewrite(_ files: [String: String], at now: Date, wroteManifest: Bool,
                                       lacking: Bool = false, synced: Bool = true) -> Bool {
        if files != seen || since.map({ now < $0 }) ?? true {
            seen = files
            since = now
        }
        guard wroteManifest || synced else { return false }
        let delay = wroteManifest ? Self.writerDelay : lacking ? Self.otherLackingDelay : Self.otherDelay
        return now.timeIntervalSince(since!) >= delay
    }

    /// The folder holds something else now: a later mix waits from the start.
    public mutating func reset() {
        seen = nil
        since = nil
    }
}

/// What a bundle found in the folder holds, for the question the second Mac gets.
public struct SyncBundleSummary: Equatable {
    public var device: String
    public var writtenAt: Date
    public var spaces: Int
    public var tabs: Int

    public init(device: String, writtenAt: Date, spaces: Int, tabs: Int) {
        self.device = device
        self.writtenAt = writtenAt
        self.spaces = spaces
        self.tabs = tabs
    }

    public init(manifest: SyncManifest, document: SidebarDocument) {
        self.init(device: manifest.device, writtenAt: manifest.writtenAt, spaces: document.spaces.count,
                  tabs: document.items.filter { $0.tab != nil }.count)
    }
}

public extension SidebarDocument {
    /// The items in the order the sync bundle writes them, so the same sidebar encodes to the same
    /// bytes: by id, the order `uuidString` sorts in. Compared as the id's 16 bytes, which upper-case
    /// hex keeps in order, with no string made per comparison (#615).
    mutating func sortItemsForSync() {
        items.sort { SettingsSync.precedes($0.id, $1.id) }
    }

    /// The sidebar as written to the sync folder: without Blank Windows (#220), which are this
    /// Mac's windows (each holds its own space outside `spaceOrder`, with its tabs).
    func forSync() -> SidebarDocument {
        let blank = spaces.filter { $0.standaloneWindowID != nil }
        guard !blank.isEmpty else { return self }
        let roots = Set(blank.flatMap { [$0.favoritesContainerID, $0.pinnedContainerID, $0.todayContainerID] })
        let parents = Dictionary(items.map { ($0.id, $0.parentID) }, uniquingKeysWith: { a, _ in a })
        /// Up the parent chain to a container (as deep as the store nests, with a bound for a cycle).
        func inBlankWindow(_ id: UUID) -> Bool {
            var cur: UUID? = id
            for _ in 0..<64 {
                guard let c = cur else { return false }
                if roots.contains(c) { return true }
                cur = parents[c] ?? nil
            }
            return false
        }
        var doc = self
        doc.spaces = spaces.filter { $0.standaloneWindowID == nil }
        doc.items = items.filter { !inBlankWindow($0.id) }
        return doc
    }
}

public extension AppSettings {
    /// The settings as written to the sync folder: what is the same on every Mac. Download
    /// folders, the engine choice (a restart), the performance recorder, what the Mac shares
    /// (each Mac's own consent) and the one-time prompts and migrations are each Mac's own.
    func forSync() -> AppSettings {
        var s = self
        s.shareUsageStats = false
        s.crashReports = .ask
        s.askedToShare = false
        s.downloadLocations = [:]
        s.hasSeenImportPrompt = false
        s.chromeEngine = AppSettings().chromeEngine
        s.perfRecording = AppSettings.perfRecordingDefault
        s.perfHidesSiteNames = false
        s.toolbarDefaultMigrated = true
        s.newTabButtonDefaultMigrated = true
        s.commandBarScopeMigrated = true
        return s
    }

    /// Settings from another Mac, with this Mac's own fields kept.
    func applyingSynced(_ remote: AppSettings) -> AppSettings {
        var s = remote
        s.shareUsageStats = shareUsageStats
        s.crashReports = crashReports
        s.askedToShare = askedToShare
        s.downloadLocations = downloadLocations
        s.hasSeenImportPrompt = hasSeenImportPrompt
        s.chromeEngine = chromeEngine
        s.perfRecording = perfRecording
        s.perfHidesSiteNames = perfHidesSiteNames
        s.toolbarDefaultMigrated = true
        s.newTabButtonDefaultMigrated = true
        s.commandBarScopeMigrated = true
        return s
    }
}

// MARK: Writing soon after a change (#598)

extension SettingsSync {
    /// How long after the last change here this Mac writes its bundle. The 30-second look stays, for
    /// the other Mac's bundles and as the fallback; a change made here no longer waits for it (#598).
    public static let writeSoonDelay: TimeInterval = 3
}

extension SidebarDocument {
    /// The document as a write soon sees it: without when each tab and split was last active, or which
    /// pane of a split has focus. Switching tabs changes only those, and with a write on every switch
    /// each one would upload the whole sidebar (about 210 KB for 229 tabs); they go up with the next
    /// 30-second look, as before (#598).
    public func withoutActivity() -> SidebarDocument {
        var doc = self
        for i in doc.items.indices {
            switch doc.items[i].data {
            case .tab(var t):
                t.timeLastActiveAt = nil
                doc.items[i].data = .tab(t)
            case .split(var s):
                s.timeLastActiveAt = nil
                s.focusTabID = nil
                doc.items[i].data = .split(s)
            case .folder, .container: break
            }
        }
        return doc
    }
}

/// SettingsSync.easelChoice. An easel file this Mac can't read is never sent as deleted: the other Mac would delete its copy.
public enum SyncEaselChoice: Equatable, Sendable {
    /// The file as read now.
    case send
    /// The copy listed or sent before, until a look reads the file.
    case carry
    /// No copy to send, and the other Mac may have it: this Mac writes no bundle until the file reads again.
    case hold
    /// No bundle held it, so no Mac merges against it and leaving it out deletes nothing.
    case leaveOut
}
