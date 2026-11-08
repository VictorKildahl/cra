import Foundation

/// The downloads Cra lists: finished files (kept in downloads.json) and downloads Chromium is still
/// reporting on, or that ended without a file (this session only). Two places show them: the tray
/// over the Library button and Library ▸ Downloads.
public enum DownloadList {
    /// A finished download, as saved in downloads.json.
    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var path: String
        public var date: Date

        public init(id: UUID, path: String, date: Date) {
            self.id = id
            self.path = path
            self.date = date
        }

        public var name: String { (path as NSString).lastPathComponent }
    }

    /// A download Chromium is still reporting on, or one that ended without a file.
    public struct Live: Identifiable, Equatable, Sendable {
        public let id: UInt32
        public var name: String
        public var path: String
        public var started: Date
        public var received: Int64
        public var total: Int64
        public var percent: Int
        public var bytesPerSecond: Double?
        /// The last point the speed was measured from.
        public var sampleBytes: Int64 = 0
        public var sampleAt = Date.distantPast
        public var failed = false
        public var cancelled = false
        /// When Chromium last reported on it.
        public var updated: Date

        public init(id: UInt32, name: String, path: String, started: Date, received: Int64, total: Int64, percent: Int, updated: Date) {
            self.id = id
            self.name = name
            self.path = path
            self.started = started
            self.received = received
            self.total = total
            self.percent = percent
            self.updated = updated
        }

        public var running: Bool { !failed && !cancelled }
        public var row: DownloadRow.State {
            failed ? .failed : cancelled ? .cancelled : .downloading(received: received, total: total, bytesPerSecond: bytesPerSecond)
        }
    }

    /// A row in either list.
    public enum Listed: Identifiable, Equatable, Sendable {
        case finished(Entry)
        case live(Live)

        public var id: String {
            switch self {
            case .finished(let e): return e.id.uuidString
            case .live(let l): return "live-\(l.id)"
            }
        }
        public var date: Date {
            switch self {
            case .finished(let e): return e.date
            case .live(let l): return l.started
            }
        }
        public var name: String {
            switch self {
            case .finished(let e): return e.name
            case .live(let l): return l.name
            }
        }
    }

    /// The tray: the newest `limit` downloads, oldest first: files still on disk, and running,
    /// failed or cancelled ones.
    public static func tray(entries: [Entry], live: [Live], limit: Int, fileExists: (String) -> Bool) -> [Listed] {
        let finished = entries.filter { fileExists($0.path) }.map(Listed.finished)
        return Array((finished + live.map(Listed.live)).sorted { $0.date < $1.date }.suffix(limit))
    }

    /// Library ▸ Downloads, newest first, narrowed to names containing `query`: the same rows as the
    /// tray, without its limit. A running download is listed too, with its progress (#245); before,
    /// the page showed only finished files, so the one being downloaded was missing exactly where
    /// people go to look for it.
    public static func library(entries: [Entry], live: [Live], query: String, fileExists: (String) -> Bool) -> [Listed] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        let finished = entries.filter { fileExists($0.path) }.map(Listed.finished)
        let all = (finished + live.map(Listed.live)).sorted { $0.date > $1.date }
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    }
}
