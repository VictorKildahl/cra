import Foundation

/// Arc's per-profile "Download location" (Settings ▸ Profiles, `DownloadLocationView`): a folder,
/// or ask where to save each file (`arc.promptForDownload`). GitHub #190.
public struct DownloadLocation: Codable, Equatable, Sendable {
    /// The folder downloads go to; nil is the user's Downloads folder.
    public var folder: String?
    /// Show a save panel for each download, starting in `folder`.
    public var askWhereToSave: Bool

    public init(folder: String? = nil, askWhereToSave: Bool = false) {
        self.folder = folder
        self.askWhereToSave = askWhereToSave
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folder = try c.decodeIfPresent(String.self, forKey: .folder).flatMap { $0.hasPrefix("/") ? $0 : nil }
        askWhereToSave = try c.decodeIfPresent(Bool.self, forKey: .askWhereToSave) ?? false
    }

    /// The key AppSettings.downloadLocations files a profile under (nil is Default).
    public static func key(profileID: UUID?) -> String { profileID?.uuidString ?? "Default" }

    /// The folder to use: the chosen one, or `downloads` when none is chosen or it's gone.
    public func folderURL(downloads: URL, exists: (String) -> Bool) -> URL {
        guard let folder, exists(folder) else { return downloads }
        return URL(fileURLWithPath: folder, isDirectory: true)
    }
}

/// The file a download is saved as: only a name inside `folder` (no path, no "." or "..",
/// not hidden), " (n)" before the extension while the name is taken.
public enum DownloadFileName {
    public static func sanitized(_ suggested: String) -> String {
        var name = suggested.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "download" : name
    }

    public static func unique(_ suggested: String, in folder: URL, exists: (String) -> Bool) -> URL {
        let name = sanitized(suggested)
        var dest = folder.appendingPathComponent(name)
        let base = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
        var n = 1
        while exists(dest.path) {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return dest
    }
}
