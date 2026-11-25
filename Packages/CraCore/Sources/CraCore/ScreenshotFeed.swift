import Foundation

/// Screenshots in the downloads list, as Arc's Library button had them (`HomeBadging`, Arc 1.174.2):
/// a screenshot or screen recording taken with the system (⇧⌘3, ⇧⌘4, ⇧⌘5) shows up by itself in the
/// list that hovering the Library button opens, next to the downloads, ready to drag onto a page or
/// into another app. Arc told screenshots apart by macOS's own mark on the file
/// (`com.apple.metadata:kMDItemIsScreenCapture`); Cra finds the marked files through Spotlight, so
/// nothing reads the Desktop folder to list them, and no other picture in the folder shows.
///
/// The Library button's "Show media" menu ticks Screenshots for this too (Arc's
/// `HomeBadgingSourcePreference`), on by default; Library ▸ Media's own Show Media switch doesn't
/// hold it back. A screenshot taken off with Hide from Cra stays off, here and on Library ▸ Media.
public enum ScreenshotFeed {
    /// How long a screenshot stays in the list: the ones taken in the last day.
    public static let window: TimeInterval = 24 * 60 * 60

    /// Screenshots and recordings as the system saves them (Screenshot ▸ Options ▸ format).
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "pdf", "bmp",
                                          "mov", "mp4"]

    /// A file Spotlight found with the screen-capture mark.
    public struct Shot: Equatable, Sendable {
        public var path: String
        public var date: Date
        public init(path: String, date: Date) {
            self.path = path
            self.date = date
        }
    }

    /// Whether the list shows screenshots at all: the "Show media" menu's Screenshots tick.
    public static func enabled(folders: [MediaLibrary.Folder]) -> Bool { folders.contains(.screenshots) }

    /// The screenshots the list shows, as finished-file rows, newest last: marked files of a
    /// screenshot's kind, taken in the last `window` (none from the future, as a clock change can
    /// leave), not hidden, not dotted (the system's file while it is still being written), and not
    /// already listed as a download. Each keeps one row id for its path, so a row stays put while
    /// Spotlight reports it again.
    public static func entries(_ shots: [Shot], enabled: Bool, hidden: Set<String>, downloads: [DownloadList.Entry],
                               now: Date) -> [DownloadList.Entry] {
        guard enabled else { return [] }
        let downloaded = Set(downloads.map(\.path))
        var seen = Set<String>()
        return shots
            .filter { shot in
                let name = (shot.path as NSString).lastPathComponent
                let age = now.timeIntervalSince(shot.date)
                return extensions.contains((name as NSString).pathExtension.lowercased()) && !name.hasPrefix(".")
                    && age >= -60 && age <= window && !hidden.contains(shot.path) && !downloaded.contains(shot.path)
                    && seen.insert(shot.path).inserted
            }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.path < $1.path }
            .map { DownloadList.Entry(id: id(for: $0.path), path: $0.path, date: $0.date) }
    }

    /// One id per path, the same every time (FNV-1a over the path, spread over 16 bytes).
    public static func id(for path: String) -> UUID {
        var a: UInt64 = 0xcbf2_9ce4_8422_2325, b: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in path.utf8 {
            a = (a ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            b = (b ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 ^ (b >> 29)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * i))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
