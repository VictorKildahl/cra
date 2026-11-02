import Foundation

/// `Application Support/Cra/Perf/`: the black box (the last minute), the 24-hour history, the
/// session marker and the hang files. Written atomically (a temporary file renamed over the
/// old one), not through JSONStore, which copies a `.bak` on every save. Under 2 MB in all.
struct PerfFiles {
    let folder: URL

    init(folder: URL) { self.folder = folder }

    /// Only a Cra that writes makes the folder: a second launch or a recording that is off leaves
    /// the data folder as it was.
    func prepare() { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    var blackBox: URL { folder.appendingPathComponent("blackbox.json") }
    var previousBlackBox: URL { folder.appendingPathComponent("blackbox.previous.json") }
    var history: URL { folder.appendingPathComponent("history.json") }
    var marker: URL { folder.appendingPathComponent("session.open") }
    func hang(session: String, number: Int) -> URL { folder.appendingPathComponent("hang-\(session)-\(number).json") }

    /// Bytes written, 0 when the write failed (a full disk must not stop anything else).
    @discardableResult
    func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) -> Int {
        guard let data = try? PerfReport.encoder(pretty: pretty).encode(value) else { return 0 }
        do { try data.write(to: url, options: .atomic) } catch { return 0 }
        return data.count
    }

    func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? PerfReport.decoder.decode(T.self, from: $0) }
    }

    /// At launch: the last session's black box becomes the previous one, and hang files older
    /// than the last session go: two sessions' worth, three each at most.
    func rotate(keepingHangsOf previousSession: String?) {
        let fm = FileManager.default
        if fm.fileExists(atPath: blackBox.path) {
            try? fm.removeItem(at: previousBlackBox)
            try? fm.moveItem(at: blackBox, to: previousBlackBox)
        }
        let keep = previousSession.map { "hang-\($0)-" }
        for f in hangFiles() where keep.map({ !f.lastPathComponent.hasPrefix($0) }) ?? true {
            try? fm.removeItem(at: f)
        }
    }

    func hangFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("hang-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Settings ▸ Performance ▸ Clear: everything but the marker of the session that is running.
    func clear() {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where f != marker {
            try? fm.removeItem(at: f)
        }
    }
}
