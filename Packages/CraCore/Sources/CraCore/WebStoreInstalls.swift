import Foundation

/// Web Store extensions live in each profile as Chrome's own store installs (GitHub #203).
///
/// An import from Arc, Dia or Chrome copies an extension's files into Extensions/<id>, which
/// Chromium loads with --load-extension (location 8, COMMAND_LINE). Such a copy never updates,
/// and before Cra's CEF fix a reload (`chrome.runtime.reload()`, chrome://extensions) turned it
/// into an UNPACKED one (location 4), which Chromium turns off without developer mode. A copy
/// of a Web Store extension is installed again from the store in each profile it loads in, the
/// way the store's "Add to Chrome" does (Cra.installFromWebStore): the signed CRX, location 1
/// (INTERNAL), from the Web Store, updated by Chromium. Once a profile has that install, the
/// folder stops loading there, and the folder goes when no profile loads it any more. A copy
/// the store doesn't take (offline, delisted, asks for more permissions) keeps loading from
/// the folder; the next launch asks again.
public enum WebStoreInstalls {
    /// The update URL the Web Store writes into every manifest it serves.
    public static let storeUpdateURL = "https://clients2.google.com/service/update2/crx"

    /// Location 1 in Chromium's extensions.settings: installed into the profile (INTERNAL).
    public static let internalLocation = 1

    /// A folder in Extensions/ that holds a Web Store extension: the store's update URL, and
    /// the folder named after the ID its manifest key gives (as the import names it), so the
    /// store's install is the same extension with the same data.
    public static func isWebStoreCopy(folder: String, extensionID: String, updateURL: String?) -> Bool {
        guard let updateURL, normalized(updateURL) == storeUpdateURL else { return false }
        return folder == extensionID && isExtensionID(extensionID)
    }

    /// Chromium's extension IDs: 32 letters a–p.
    public static func isExtensionID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (UInt8(ascii: "a")...UInt8(ascii: "p")).contains($0) }
    }

    /// Whether a profile's extensions.settings entry is a store install.
    public static func isStoreInstall(settings entry: [String: Any]?) -> Bool {
        guard let entry else { return false }
        return (entry["location"] as? Int) == internalLocation && (entry["from_webstore"] as? Bool) == true
    }

    public static func storeInstallDirectory(settings entry: [String: Any]?, extensionID: String, profileDirectory: URL) -> URL? {
        guard isStoreInstall(settings: entry), isExtensionID(extensionID),
              let path = entry?["path"] as? String, !path.isEmpty else { return nil }
        let extensions = profileDirectory.appendingPathComponent("Extensions", isDirectory: true).standardizedFileURL
        let installed = (path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
            : extensions.appendingPathComponent(path, isDirectory: true)).standardizedFileURL
        guard installed.deletingLastPathComponent() == extensions.appendingPathComponent(extensionID, isDirectory: true) else { return nil }
        return installed
    }

    /// The profiles a Web Store copy in `folder` still loads in from the folder, where Chromium
    /// has no store install of it yet, in `profiles` order.
    public static func pendingProfiles(folder: String, extensionID: String, scopes: ExtensionProfiles,
                                       profiles: [String], settings: (String) -> [String: Any]) -> [String] {
        profiles.filter { profile in
            scopes.loads(folder: folder, inProfile: profile)
                && !isStoreInstall(settings: settings(profile)[extensionID] as? [String: Any])
        }
    }

    private static func normalized(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespaces)
        if let q = u.firstIndex(of: "?") { u = String(u[..<q]) }
        while u.hasSuffix("/") { u.removeLast() }
        return u.replacingOccurrences(of: "http://", with: "https://")
    }
}

extension ExtensionProfiles {
    /// `profile` has `folder`'s extension from the Web Store now, so the folder stops loading
    /// there; a folder without a list loaded in every one of `allProfiles`. True when it loads in
    /// no profile any more: the folder can go (and its entry goes with it).
    @discardableResult
    public mutating func movedToWebStore(folder: String, profile: String, allProfiles: Set<String>) -> Bool {
        let remaining = (profiles(ofFolder: folder) ?? allProfiles).subtracting([profile])
        if remaining.isEmpty {
            folders[folder] = nil
            return true
        }
        folders[folder] = remaining.sorted()
        return false
    }
}
