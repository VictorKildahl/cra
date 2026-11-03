import Foundation

/// extension-profiles.json: the Chromium profile folders ("Default", "Profile <id>") each folder in
/// Extensions/ loads in, by folder name. Chromium loads those folders with --load-extension, which
/// installs them in every profile; Cra's CEF build skips a profile the list leaves out
/// (--cra-load-extension-profiles), so such an extension is not installed there at all. A folder
/// with no list loads in every profile, as every one did before GitHub #131. The import fills it
/// from the browser profiles that had the extension, as Arc keeps extensions per profile.
public struct ExtensionProfiles: Codable, Equatable, Sendable {
    public var folders: [String: [String]]

    public init(folders: [String: [String]] = [:]) {
        self.folders = folders
    }

    /// The profile folders `folder` loads in; nil for every profile.
    public func profiles(ofFolder folder: String) -> Set<String>? { folders[folder].map(Set.init) }

    public func loads(folder: String, inProfile profile: String) -> Bool { profiles(ofFolder: folder)?.contains(profile) ?? true }

    /// An extension imported into `folder` for `profiles` (nil: every profile). A folder that was
    /// already there without a list keeps loading everywhere; one with a list gets the new profiles too.
    public mutating func add(folder: String, profiles: Set<String>?, folderExisted: Bool) {
        if folderExisted && folders[folder] == nil { return }
        guard let profiles else { folders[folder] = nil; return }
        folders[folder] = profiles.union(folders[folder] ?? []).sorted()
    }

    public mutating func remove(folder: String) { folders[folder] = nil }

    /// --cra-load-extension-profiles for the --load-extension `folders` in that order: each one's
    /// profiles joined by "|", "*" for every profile. nil when every folder loads everywhere.
    public func commandLineValue(forFolders names: [String]) -> String? {
        let values = names.map { name in folders[name].map { $0.sorted().joined(separator: "|") } ?? "*" }
        return values.allSatisfy { $0 == "*" } ? nil : values.joined(separator: ",")
    }

    public init(from decoder: Decoder) throws {
        folders = try decoder.singleValueContainer().decode([String: [String]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(folders)
    }
}

/// Where an import from a browser with profiles lands in Cra's profiles (GitHub #131). Arc binds
/// each space to a Chromium profile in its `User Data` folder; the import gives each of those but
/// Default a Cra profile, and what came from a source profile (sign-ins, pins, extensions) goes
/// to that Cra profile. Source profiles no imported space uses go to Default, where everything
/// went before.
public struct ImportProfileMap: Equatable, Sendable {
    /// Cra's profile folder by source profile folder, for the source profiles of imported spaces.
    public var folders: [String: String]

    public init(folders: [String: String] = [:]) {
        self.folders = folders
    }

    public func craFolder(forSource source: String?) -> String { source.flatMap { folders[$0] } ?? "Default" }

    /// True when the import put a space on a profile of its own.
    public var bindsProfiles: Bool { folders.values.contains { $0 != "Default" } }

    /// The Cra profiles an extension the source had in `sources` loads in: nil (every profile)
    /// when the import bound no profiles, or when that is every profile Cra has (`allFolders`).
    public func extensionProfiles(sources: Set<String>, allFolders: Set<String>) -> Set<String>? {
        guard bindsProfiles else { return nil }
        let targets = Set(sources.map { craFolder(forSource: $0) })
        return targets.isEmpty || allFolders.isSubset(of: targets) ? nil : targets
    }

    /// Arc's `profile` of a space: `{"custom": {"_0": {"directoryBasename": "Profile 2", …}}}`, or
    /// `{"default": true}` for the Default profile (nil).
    public static func arcProfileFolder(_ profile: Any?) -> String? {
        guard let custom = (profile as? [String: Any])?["custom"] as? [String: Any],
              let folder = (custom["_0"] as? [String: Any])?["directoryBasename"] as? String,
              !folder.isEmpty, folder != "Default" else { return nil }
        return folder
    }
}
