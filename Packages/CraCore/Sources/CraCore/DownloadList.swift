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
        /// The profile folder it was downloaded in ("Default", "Profile 2"; nil before 8 Nov 2026),
        /// for Arc's Filter ▸ Profiles on Library ▸ Downloads.
        public var profile: String?

        public init(id: UUID, path: String, date: Date, profile: String? = nil) {
            self.id = id
            self.path = path
            self.date = date
            self.profile = profile
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
        /// Paused from its menu (#272): still in progress for Chromium, so quitting would cancel it.
        public var paused = false
        /// When Chromium last reported on it.
        public var updated: Date
        /// When it last received bytes (Chromium reports a stalled one again and again, unchanged).
        public var moved: Date

        public init(id: UInt32, name: String, path: String, started: Date, received: Int64, total: Int64, percent: Int, updated: Date) {
            self.id = id
            self.name = name
            self.path = path
            self.started = started
            self.received = received
            self.total = total
            self.percent = percent
            self.updated = updated
            moved = updated
        }

        /// Still in progress, paused or not.
        public var running: Bool { !failed && !cancelled }
        public var row: DownloadRow.State {
            failed ? .failed : cancelled ? .cancelled : paused ? .paused
                : .downloading(received: received, total: total, bytesPerSecond: bytesPerSecond)
        }
    }

    /// How far the downloads still in progress have got together, 0…1, for the ring on the Library
    /// button (#272); nil when none is. One whose size isn't known yet counts as not started.
    public static func progress(_ live: [Live]) -> Double? {
        let running = live.filter(\.running)
        guard !running.isEmpty else { return nil }
        let total = running.reduce(Int64(0)) { $0 + max(0, $1.total) }
        guard total > 0 else { return 0 }
        let received = running.reduce(Int64(0)) { $0 + ($1.total > 0 ? min($1.received, $1.total) : 0) }
        return min(1, Double(received) / Double(total))
    }

    /// How long a running download can go without receiving a byte before the bin stops waiting
    /// for it.
    public static let stuckAfter: TimeInterval = 30

    /// Whether the bin over the Library button stays for these downloads: one still running whose
    /// ring is worth watching (#272). A paused one stays until it resumes or is cancelled. A running
    /// one that hasn't received a byte for `stuckAfter` doesn't hold it: two downloads that never got
    /// a file name sat at "0 bytes", and their bin stayed over the sidebar's buttons for good (#491).
    /// The row keeps showing it, with Cancel in its menu.
    public static func holdsBin(_ live: [Live], now: Date) -> Bool {
        live.contains { $0.running && ($0.paused || now.timeIntervalSince($0.moved) < stuckAfter) }
    }

    /// How a download that Chromium has gone quiet about ended, by its file on disk.
    public enum Ending: Equatable, Sendable { case complete, cancelled }

    /// What the file says about a running download Chromium hasn't reported on for a while
    /// (MainWindowController's watchdog): nil while it may still be running. `partialBesideIt` is
    /// `<path>.crdownload`, `size` the file at `path` (nil when there is none).
    ///
    /// No file means cancelled only on CEF, which cancels a download without a word when its tab
    /// closes and writes straight to the file. The engine reports every cancel itself, and while a
    /// download Safe Browsing may check runs it writes to "Unconfirmed <n>.crdownload" instead, so
    /// neither file is there: a download that got no bytes for a few seconds read as Cancelled (#895).
    public static func quietEnding(total: Int64, partialBesideIt: Bool, size: Int64?, chromiumEngine: Bool) -> Ending? {
        if partialBesideIt { return nil }
        guard let size else { return chromiumEngine ? nil : .cancelled }
        return total > 0 && size >= total ? .complete : nil
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
    /// failed or cancelled ones. Screenshots taken lately (`ScreenshotFeed`) take their place among
    /// them by date, as finished files, as Arc's Library button listed them.
    public static func tray(entries: [Entry], live: [Live], screenshots: [Entry] = [], limit: Int,
                            fileExists: (String) -> Bool) -> [Listed] {
        let finished = (entries + screenshots).filter { fileExists($0.path) }.map(Listed.finished)
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
