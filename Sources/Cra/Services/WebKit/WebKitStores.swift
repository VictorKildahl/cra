import CryptoKit
import Foundation
import WebKit

/// WebKit's cookies, storage and cache, one persistent store per Cra profile (like Chromium's
/// profile folders) and one throwaway store per incognito session. Stores live under
/// ~/Library/WebKit/<bundle id>/WebsiteDataStore/<uuid>; the uuid is derived from the data
/// folder and the profile, so a test instance (CRA_DATA_DIR) never shares the daily one's.
@MainActor
enum WebKitStores {
    private static var persistent: [String: WKWebsiteDataStore] = [:]
    private static var incognito: WKWebsiteDataStore?

    static func store(profilePath: String?, incognito isIncognito: Bool) -> WKWebsiteDataStore {
        if isIncognito {
            if let s = incognito { return s }
            let s = WKWebsiteDataStore.nonPersistent()
            incognito = s
            return s
        }
        let key = profileKey(profilePath)
        if let s = persistent[key] { return s }
        let s = WKWebsiteDataStore(forIdentifier: identifier(forProfileKey: key))
        persistent[key] = s
        return s
    }

    /// The last incognito window closed (CraCEFRuntime.endIncognitoSession): the next incognito
    /// page starts with nothing.
    static func endIncognitoSession() { incognito = nil }

    /// A Cra profile was deleted with its Chromium folder (`name` "Profile <id>"): its WebKit data goes too.
    static func removeProfile(folderName name: String) {
        let key = profileKey(AppPaths.chromiumCache.appendingPathComponent(name, isDirectory: true).path)
        persistent[key] = nil
        WKWebsiteDataStore.remove(forIdentifier: identifier(forProfileKey: key)) { error in
            if let error { NSLog("Cra: removing WebKit data of %@ failed: %@", name, error.localizedDescription) }
        }
    }

    /// "Default", or the profile's folder name ("Profile <id>").
    static func profileKey(_ profilePath: String?) -> String {
        guard let p = profilePath, !p.isEmpty else { return "Default" }
        return URL(fileURLWithPath: p).lastPathComponent
    }

    /// A stable UUID (version 8, name-based) for the data folder plus the profile.
    static func identifier(forProfileKey key: String) -> UUID {
        let digest = SHA256.hash(data: Data("cra-webkit|\(AppPaths.supportDir.standardizedFileURL.path)|\(key)".utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x80
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
