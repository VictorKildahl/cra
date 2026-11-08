import AppKit
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

    /// The hover list: newest downloads, oldest first: files still on disk, and running, failed
    /// or cancelled ones.
    var recent: [Listed] {
        DownloadList.tray(entries: entries, live: live, limit: Self.listLimit) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Library ▸ Downloads: every download, newest first, running ones included (#245).
    func library(query: String) -> [Listed] {
        DownloadList.library(entries: entries, live: live, query: query) { FileManager.default.fileExists(atPath: $0) }
    }

    var hasRunningDownloads: Bool { live.contains(where: \.running) }

    /// Chromium's report on a download: running ones update their row, a finished one leaves for
    /// `add(path:)`, a failed or cancelled one stays listed for this session.
    func report(id: UInt32, name: String, path: String, received: Int64, total: Int64, percent: Int,
                complete: Bool, cancelled: Bool, failed: Bool, now: Date = Date()) {
        if complete {
            live.removeAll { $0.id == id }
            return
        }
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
        if let i = live.firstIndex(where: { $0.id == id }) { live[i] = l } else { live.append(l) }
    }

    @discardableResult
    func add(path: String) -> Entry {
        let entry = Entry(id: UUID(), path: path, date: Date())
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
