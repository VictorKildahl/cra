import Foundation

/// The folder a file provider syncs (iCloud Drive, Dropbox, OneDrive or a similar service) holds a `Cra` folder
/// with a copy of the sidebar, the settings and the shortcut overrides, plus this manifest.
/// Each Mac writes the three files, then the manifest last, so a reader that sees a manifest
/// whose hashes match the files has a whole bundle. Nothing leaves the Mac but through the
/// folder the user chose, and the Chromium profile (logins, cookies, history) never does.
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

    public init(version: Int = SyncManifest.currentVersion, device: String, deviceID: String, writtenAt: Date, files: [String: String]) {
        self.version = version
        self.device = device
        self.deviceID = deviceID
        self.writtenAt = writtenAt
        self.files = files
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
        if m.files.keys.contains(where: { files[$0] == nil || files[$0] == .missing }) { return .arriving }
        let hashes = files.compactMapValues { if case .present(let h) = $0 { h } else { nil } }
        guard isComplete(m, hashes: hashes) else { return .mixed }
        // The very files the manifest names, which this Cra can't decode: a format from a newer Cra.
        return readable ? .whole : .newer
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
public struct SyncMixWait: Equatable {
    public static let writerDelay: TimeInterval = 60
    public static let otherDelay: TimeInterval = 120

    /// The files' hashes when the mix was first seen, and when that was.
    public private(set) var seen: [String: String]?
    public private(set) var since: Date?

    public init() {}

    /// A look found a mix of these files (name → hash, the manifest's own included): whether this
    /// Mac writes its bundle now.
    public mutating func shouldRewrite(_ files: [String: String], at now: Date, wroteManifest: Bool) -> Bool {
        if files != seen || since.map({ now < $0 }) ?? true {
            seen = files
            since = now
        }
        return now.timeIntervalSince(since!) >= (wroteManifest ? Self.writerDelay : Self.otherDelay)
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
        return s
    }
}
