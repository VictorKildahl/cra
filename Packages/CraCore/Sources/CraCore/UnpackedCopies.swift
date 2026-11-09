import Foundation

/// A folder in Extensions/ that copies an extension a profile also loads in place (GitHub #299).
///
/// Settings ▸ Extensions ▸ Add Unpacked Extension… copies the folder in as
/// Extensions/<folder name>, and an import from Arc, Dia or Chrome copies a "Load unpacked"
/// extension in as Extensions/<its ID>. Chromium loads the copy with --load-extension at the
/// next launch. When the person has also loaded the original folder with chrome://extensions'
/// "Load unpacked" (location 4, UNPACKED), Chromium has two installs: without a manifest key
/// each gets its ID from its own path, so chrome://extensions listed the extension twice after
/// every restart. Chrome has one install per folder, and the one the person works on is the
/// original, so the copy stops loading in that profile.
public enum UnpackedCopies {
    /// Location 4 in Chromium's extensions.settings: chrome://extensions "Load unpacked".
    public static let unpackedLocation = 4

    /// Whether the profile whose extensions.settings is `settings` loads the copy at `copyPath`
    /// in place: an unpacked install from a folder of its own that is the copy's extension. It is
    /// when it has the copy's ID (a manifest key gives both the same one), or the ID the import named the
    /// folder after, or the folder's name (Add Unpacked Extension… adds "-2", "-3" to a name
    /// already taken) and the same manifest name. `manifestName` reads a folder's manifest
    /// `name`, as written (before `__MSG_…__` is looked up).
    public static func isLoadedInPlace(copyFolder: String, copyPath: String, copyExtensionID: String, copyName: String?,
                                       settings: [String: Any], manifestName: (String) -> String?) -> Bool {
        let copy = standardized(copyPath)
        return settings.contains { id, value in
            guard let entry = value as? [String: Any], (entry["location"] as? Int) == unpackedLocation,
                  let path = entry["path"] as? String, path.hasPrefix("/") else { return false }
            let original = standardized(path)
            guard original != copy else { return false }
            if id == copyExtensionID || id == copyFolder { return true }
            let name = (original as NSString).lastPathComponent
            guard copyFolder == name || isNumbered(copyFolder, from: name), let copyName else { return false }
            return manifestName(original) == copyName
        }
    }

    /// "name-2", "name-3"…: what Add Unpacked Extension… calls a second copy of "name".
    static func isNumbered(_ folder: String, from name: String) -> Bool {
        guard folder.hasPrefix(name + "-") else { return false }
        let suffix = folder.dropFirst(name.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy(\.isASCII) && Int(suffix).map { $0 >= 2 } == true
    }

    private static func standardized(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

extension ExtensionProfiles {
    /// `folder` stops loading in `profile`; a folder without a list loaded in every one of
    /// `allProfiles`. True when it loads in no profile any more: the folder can go.
    @discardableResult
    public mutating func stopsLoading(folder: String, inProfile profile: String, allProfiles: Set<String>) -> Bool {
        movedToWebStore(folder: folder, profile: profile, allProfiles: allProfiles)
    }
}
