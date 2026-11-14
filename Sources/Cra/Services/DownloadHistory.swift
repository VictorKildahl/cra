import AppKit
import CraCEF
import Observation
import QuickLookThumbnailing

/// Finished downloads, newest last, for the list Arc shows when you hover the Library
/// button (its downloads tray) and on Library ▸ Downloads. Kept in downloads.json; files deleted
/// since drop out. Downloads still running, and ones that failed or were cancelled, are listed
/// in both too (`live`, not saved): Arc shows progress and failures there, not in a toast. Which
/// rows each list shows is `DownloadList` (CraCore).
@MainActor
@Observable
final class DownloadHistory {
    static let shared = DownloadHistory()

    typealias Entry = DownloadList.Entry
    typealias Live = DownloadList.Live
    typealias Listed = DownloadList.Listed

    /// Arc 1.170 listed every recent download it still had on disk (four, oldest at the
    /// top); how many it shows at most was not observed.
    static let listLimit = 5

    private(set) var entries: [Entry]
    /// Quick Look thumbnails by path, made on demand.
    private(set) var thumbnails: [String: NSImage] = [:]
    @ObservationIgnored private let file = JSONStore<[Entry]>("downloads.json")
    @ObservationIgnored private var loading: Set<String> = []

    private init() {
        entries = file.load(or: { [] })
    }

    private(set) var live: [Live] = []
    /// When a download last stopped running (finished, failed or cancelled), for the bin.
    @ObservationIgnored private(set) var lastEnded: Date?

    /// The hover list: newest downloads, oldest first: files still on disk, and running, failed
    /// or cancelled ones.
    var recent: [Listed] {
        DownloadList.tray(entries: entries, live: live, limit: Self.listLimit) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Library ▸ Downloads: every download, newest first, running ones included (#245).
    func library(query: String) -> [Listed] {
        DownloadList.library(entries: entries, live: live, query: query) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Running or paused: quitting would cancel it.
    var hasRunningDownloads: Bool { live.contains(where: \.running) }

    /// The ring on the Library button: the running downloads' progress together (#272).
    var progress: Double? { DownloadList.progress(live) }

    /// Chromium's report on a download: running ones update their row, a finished one leaves for
    /// `add(path:)`, a failed or cancelled one stays listed for this session.
    func report(id: UInt32, name: String, path: String, received: Int64, total: Int64, percent: Int,
                complete: Bool, cancelled: Bool, failed: Bool, paused: Bool = false, now: Date = Date()) {
        if complete {
            if live.contains(where: { $0.id == id }) { lastEnded = now }
            live.removeAll { $0.id == id }
            return
        }
        if (failed || cancelled), live.first(where: { $0.id == id })?.running ?? true { lastEnded = now }
        var l = live.first { $0.id == id } ?? Live(id: id, name: name, path: path, started: now, received: received, total: total,
                                                    percent: percent, updated: now)
        if l.sampleAt == .distantPast {
            (l.sampleBytes, l.sampleAt) = (received, now)
        } else if let speed = DownloadRow.speed(fromBytes: l.sampleBytes, at: l.sampleAt, toBytes: received, at: now) {
            l.bytesPerSecond = speed
            (l.sampleBytes, l.sampleAt) = (received, now)
        }
        l.updated = now
        l.name = name
        if !path.isEmpty { l.path = path }
        l.received = received
        l.total = total
        l.percent = percent
        l.failed = failed
        l.cancelled = cancelled
        l.paused = paused && !failed && !cancelled
        // A paused download has no speed; it starts measuring again when it resumes.
        if l.paused { (l.bytesPerSecond, l.sampleAt) = (nil, .distantPast) }
        if let i = live.firstIndex(where: { $0.id == id }) { live[i] = l } else { live.append(l) }
    }

    // MARK: Acting on a row (#272)

    /// Pauses, resumes or cancels a download still in progress; Chromium's next report shows it.
    func control(_ id: UInt32, _ action: CraDownloadControl) {
        guard CraCEFRuntime.controlDownload(id, action: action) else {
            CraLog.note("download control: no download in progress by that id")
            return
        }
        CraLog.note("download control: \(["pause", "resume", "cancel"][action.rawValue])")
    }

    /// Arc's Hide from Arc: the row leaves both lists, the file stays where it is.
    func hide(_ row: Listed) {
        switch row {
        case .finished(let e):
            entries.removeAll { $0.id == e.id }
            file.save(entries)
        case .live(let l):
            live.removeAll { $0.id == l.id }
        }
    }

    /// Arc's Move to Trash: the file goes to the Bin, the row with it.
    func moveToTrash(_ e: Entry) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: e.path)]) { [weak self] _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hide(.finished(e)) } }
        }
    }

    @discardableResult
    func add(path: String, profile: String? = nil) -> Entry {
        let entry = Entry(id: UUID(), path: path, date: Date(), profile: profile)
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        file.save(entries)
        return entry
    }

    /// A renamed (or reverted) file keeps its place in the list.
    func move(from old: String, to new: String) {
        guard let i = entries.lastIndex(where: { $0.path == old }) else { return }
        entries[i].path = new
        thumbnails[new] = thumbnails.removeValue(forKey: old)
        file.save(entries)
    }

    /// Async renames retain the original row's identity, never whichever row now owns its path.
    @discardableResult
    func move(id: UUID, from old: String, to new: String) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id && $0.path == old }) else { return false }
        entries[i].path = new
        thumbnails[new] = thumbnails.removeValue(forKey: old)
        file.save(entries)
        return true
    }

    func thumbnail(for path: String) -> NSImage? {
        if let image = thumbnails[path] { return image }
        loadThumbnail(path)
        return nil
    }

    private func loadThumbnail(_ path: String) {
        guard !loading.contains(path) else { return }
        loading.insert(path)
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 40, height: 40),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(path)
                self.thumbnails[path] = image ?? NSWorkspace.shared.icon(forFile: path)
            }
        }
    }
}
