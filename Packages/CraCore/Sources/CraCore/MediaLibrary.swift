import Foundation

/// Arc's Library ▸ Media (HomeButton/Pages/Media, Arc 1.172.1): the images and videos in a few
/// of the Mac's folders, newest first, in a two-column grid, searched by file name. Arc reads the
/// folders itself (no Spotlight) and shows nothing until "Show Media" is pressed, since reading
/// Desktop and Documents asks macOS for access. The right-click menu on the Library button picks
/// the folders ("Show media": Documents, Desktop, Screenshots, Arc Captures, Downloads; Cra saves
/// captures where you choose, so it has no captures folder).
public enum MediaLibrary {
    public enum Folder: String, Codable, CaseIterable, Sendable {
        case documents, desktop, screenshots, downloads

        public var title: String {
            switch self {
            case .documents: "Documents"
            case .desktop: "Desktop"
            case .screenshots: "Screenshots"
            case .downloads: "Downloads"
            }
        }
    }

    public struct File: Equatable, Sendable {
        public var path: String
        public var date: Date
        public init(path: String, date: Date) {
            self.path = path
            self.date = date
        }
        public var name: String { (path as NSString).lastPathComponent }
    }

    /// What counts as media: pictures and videos Quick Look can draw.
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "avif",
                                          "mov", "mp4", "m4v"]

    public static func isMedia(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased()) && !(path as NSString).lastPathComponent.hasPrefix(".")
    }

    /// The grid's files: media only, each path once (Screenshots is often the Desktop), newest
    /// first, those whose name holds the query, at most `limit`.
    public static func shown(_ files: [File], query: String, hidden: Set<String> = [], limit: Int = 500) -> [File] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        return files
            .filter { isMedia($0.path) && !hidden.contains($0.path) && seen.insert($0.path).inserted }
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.path < $1.path }
            .prefix(limit).map { $0 }
    }

    /// Arc's menu on a picked picture or video (its tile's right-click and the preview's ⋯), 8 Nov 2026:
    /// Copy Image, —, Send via iMessage, AirDrop, —, Show in Finder, —, Hide from Arc.
    public enum Action: CaseIterable, Sendable {
        case copy, sendMessage, airDrop, showInFinder, hide

        public func title(isVideo: Bool) -> String {
            switch self {
            case .copy: return isVideo ? "Copy Video" : "Copy Image"
            case .sendMessage: return "Send via iMessage"
            case .airDrop: return "AirDrop"
            case .showInFinder: return "Show in Finder"
            case .hide: return "Hide from Cra"
            }
        }

        /// A line goes before these.
        public var startsGroup: Bool { self == .sendMessage || self == .showInFinder || self == .hide }
    }

    public static func isVideo(_ path: String) -> Bool { ["mov", "mp4", "m4v"].contains((path as NSString).pathExtension.lowercased()) }

    /// Two to a row, as Arc's grid lays them out.
    public static func rows(_ files: [File]) -> [[File]] {
        stride(from: 0, to: files.count, by: 2).map { Array(files[$0..<min($0 + 2, files.count)]) }
    }
}
