import Foundation

/// What Cra reads of other browsers' own folders, and when (GitHub #757).
///
/// Current macOS can keep a browser's folder (Chrome's and Brave's, under Application Support)
/// from other apps. Reading inside one without the person asking showed "Data Access Blocked:
/// "Cra.app" tried to access your data from other apps" on Cra's first launch, before anything
/// was picked. So before an import, Cra only asks whether a browser's own folder is there (one
/// look at the folder itself, never inside it). A browser's folder is read once the person picks
/// it to import from, and from then on for what follows from that import: its native messaging
/// manifests (1Password, Bitwarden…) and its pinned extensions.
public enum OtherBrowserData {
    /// A browser the import knows: its id, the folder of its own under Application Support, and
    /// where it keeps native messaging manifests (nil for a browser that has none, as Firefox).
    public struct Browser: Equatable, Sendable {
        public let id: String
        public let folder: String
        public let nativeMessagingHosts: String?
        /// Safari's data comes from a file Safari exports, so it is always offered.
        public let alwaysOffered: Bool

        public init(id: String, folder: String, nativeMessagingHosts: String? = nil, alwaysOffered: Bool = false) {
            self.id = id
            self.folder = folder
            self.nativeMessagingHosts = nativeMessagingHosts
            self.alwaysOffered = alwaysOffered
        }
    }

    /// The browsers the import list offers, in `browsers` order: the ones whose own folder is
    /// there. `exists` is asked about each browser's folder and nothing else, so nothing inside
    /// another browser's folder is read before the person picks one.
    public static func offered(_ browsers: [Browser], exists: (String) -> Bool) -> [String] {
        browsers.filter { $0.alwaysOffered || exists($0.folder) }.map(\.id)
    }

    /// The folders Cra links native messaging manifests from before Chromium starts, first one
    /// winning: the NativeMessagingHosts folder of each browser the person imported from (Chrome
    /// first, where every app installs), then the system-wide folders, which macOS doesn't keep
    /// from other apps.
    public static func nativeMessagingFolders(_ browsers: [Browser], imported: ImportedBrowsers, system: [String]) -> [String] {
        let mine = browsers.filter { imported.contains($0.id) }
        let ordered = mine.filter { $0.id == "chrome" } + mine.filter { $0.id != "chrome" }
        return ordered.compactMap(\.nativeMessagingHosts) + system
    }
}

/// imported-browsers.json: the browsers the person has imported from, by import id ("chrome",
/// "arc"…), in the order of their first import. Saved as a plain array.
public struct ImportedBrowsers: Codable, Equatable, Sendable {
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { seen.insert($0).inserted }
    }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public func adding(_ id: String) -> ImportedBrowsers { ImportedBrowsers(ids: ids + [id]) }

    public init(from decoder: Decoder) throws {
        self.init(ids: try decoder.singleValueContainer().decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(ids)
    }

    /// Cra before #757 had no such file and linked every browser's manifests at each launch. On
    /// the first launch with this file missing, the browsers its own NativeMessagingHosts links
    /// still point into count as imported from, so 1Password and the rest keep working for people
    /// who already use Cra; a new Mac has no links and starts with none. `linkTargets` are where
    /// the links in Cra's folder point, read from Cra's own folder.
    public static func migrated(linkTargets: [String], browsers: [OtherBrowserData.Browser]) -> ImportedBrowsers {
        ImportedBrowsers(ids: browsers.filter { browser in
            guard let folder = browser.nativeMessagingHosts else { return false }
            let prefix = folder.hasSuffix("/") ? folder : folder + "/"
            return linkTargets.contains { $0.hasPrefix(prefix) }
        }.map(\.id))
    }
}
