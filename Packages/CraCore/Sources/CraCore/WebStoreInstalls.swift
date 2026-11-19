import Foundation

/// Web Store extensions live in each profile as Chrome's own store installs (GitHub #203).
///
/// An import from Arc, Dia or Chrome copies an extension's files into Extensions/<id>, which
/// Chromium loads with --load-extension (location 8, COMMAND_LINE). Such a copy never updates,
/// and before Cra's CEF fix a reload (`chrome.runtime.reload()`, chrome://extensions) turned it
/// into an UNPACKED one (location 4), which Chromium turns off without developer mode. A copy
/// of a Web Store extension is installed again from the store in each profile it loads in, the
/// way the store's "Add to Chrome" does (Cra.installFromWebStore): the signed CRX, location 1
/// (INTERNAL), from the Web Store, updated by Chromium. Once a profile has that install on disk,
/// the folder stops loading there from the next launch, and the folder goes when no profile
/// loads it any more (never while Chromium runs, which may still read it). A copy
/// the store doesn't take (offline, delisted, asks for more permissions) keeps loading from
/// the folder. Once the store has said no in a profile, later launches don't ask there again
/// (WebStoreRefusals, #491): each ask downloads the CRX, a file on the Dock icon at every launch.
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

    /// The folder a store install of `extensionID` lives in: Extensions/<id>/<version> in
    /// `profileDirectory`, from the entry's relative or absolute path. nil for anything else,
    /// such as an imported copy whose entry claims the store.
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
    /// has no store install of it yet and the store hasn't refused it (#491), in `profiles` order.
    public static func pendingProfiles(folder: String, extensionID: String, scopes: ExtensionProfiles,
                                       profiles: [String], settings: (String) -> [String: Any],
                                       refused: WebStoreRefusals = WebStoreRefusals()) -> [String] {
        profiles.filter { profile in
            scopes.loads(folder: folder, inProfile: profile)
                && !isStoreInstall(settings: settings(profile)[extensionID] as? [String: Any])
                && !refused.isRefused(folder: folder, inProfile: profile)
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

/// The Web Store copies the store refused to install, by profile (web-store-refused.json, #491):
/// `{"Default": ["<id>", …]}`. A refused copy keeps loading from its folder there and isn't asked
/// for again, since every ask downloads its CRX. Importing the extension again clears it.
public struct WebStoreRefusals: Codable, Equatable, Sendable {
    public var profiles: [String: [String]]

    public init(profiles: [String: [String]] = [:]) {
        self.profiles = profiles
    }

    public func isRefused(folder: String, inProfile profile: String) -> Bool { profiles[profile]?.contains(folder) ?? false }

    /// The store said no to `folder` in `profile`. True when that is new.
    @discardableResult
    public mutating func refuse(folder: String, inProfile profile: String) -> Bool {
        guard !isRefused(folder: folder, inProfile: profile) else { return false }
        profiles[profile] = ((profiles[profile] ?? []) + [folder]).sorted()
        return true
    }

    /// `folder` imported again: every profile may ask the store once more. True when anything changed.
    @discardableResult
    public mutating func forget(folder: String) -> Bool {
        var changed = false
        for (profile, folders) in profiles where folders.contains(folder) {
            let rest = folders.filter { $0 != folder }
            profiles[profile] = rest.isEmpty ? nil : rest
            changed = true
        }
        return changed
    }

    public init(from decoder: Decoder) throws {
        profiles = try decoder.singleValueContainer().decode([String: [String]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(profiles)
    }
}
