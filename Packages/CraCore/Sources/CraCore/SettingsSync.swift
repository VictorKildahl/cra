import Foundation

/// The folder a file provider syncs (iCloud Drive, Dropbox, OneDrive or a similar service) holds a `Cra` folder
/// with a copy of the sidebar, the settings and the shortcut overrides, plus this manifest.
/// Each Mac writes the three files, then the manifest last, so a reader that sees a manifest
/// whose hashes match the files has a whole bundle. Nothing leaves the Mac but through the
/// folder the user chose, and the Chromium profile (logins, cookies, history) never does.
public struct SyncManifest: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// The Mac that wrote the bundle (its computer name), so it never applies its own write.
    public var device: String
    public var writtenAt: Date
    /// File name → hash of its bytes, for every file in the bundle.
    public var files: [String: String]

    public init(version: Int = SyncManifest.currentVersion, device: String, writtenAt: Date, files: [String: String]) {
        self.version = version
        self.device = device
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

    /// Whether a file name is a provider's conflict copy ("manifest 2.json" from iCloud,
    /// "manifest (Peter's conflicted copy 2026-11-06).json" from Dropbox, "manifest-MacBook.json"
    /// from OneDrive). Cra never reads them: last writer wins through the manifest.
    public static func isConflictCopy(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension
        if stem.lowercased().contains("conflicted copy") { return true }
        if stem.range(of: #" \d+$"#, options: .regularExpression) != nil { return true }
        if stem.range(of: #"-[^-]+$"#, options: .regularExpression) != nil, !stem.hasPrefix("-") { return true }
        return false
    }

    /// iCloud keeps a file it has not downloaded as `.<name>.icloud`. A bundle whose file is
    /// only a placeholder is not applied; Cra asks iCloud to download it and looks again.
    public static func placeholderName(for name: String) -> String { ".\(name).icloud" }

    /// Whether a manifest read from the folder is applied: written by another Mac, by a Cra
    /// that writes a format this one reads, and later than the one applied last.
    public static func shouldApply(remote: SyncManifest, lastApplied: SyncManifest?, device: String) -> Bool {
        if remote.device == device { return false }
        if remote.version > SyncManifest.currentVersion { return false }
        if let last = lastApplied, remote.writtenAt <= last.writtenAt { return false }
        return true
    }

    /// Whether the files on disk are the ones the manifest names: a provider delivers a bundle
    /// file by file, and the manifest may land before a file it names has finished downloading.
    public static func isComplete(_ manifest: SyncManifest, hashes: [String: String]) -> Bool {
        !manifest.files.isEmpty && manifest.files.allSatisfy { hashes[$0.key] == $0.value }
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

public extension AppSettings {
    /// The settings as written to the sync folder: what is the same on every Mac. Download
    /// folders, the engine choice (a restart), the performance recorder and the one-time prompts
    /// and migrations are each Mac's own.
    func forSync() -> AppSettings {
        var s = self
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
