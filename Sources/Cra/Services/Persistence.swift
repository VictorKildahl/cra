import Foundation

/// Folders of deleted profiles, removed before Chromium starts (it keeps a loaded
/// profile's files open for the rest of the session).
enum ProfileCleanup {
    private static var file: JSONStore<[String]> { JSONStore("deleted-profiles.json") }

    static func schedule(_ directoryName: String) {
        file.saveNow(Array(Set(file.load(or: { [] }) + [directoryName])))
    }

    /// Call before Chromium initializes.
    static func run() {
        let names = file.load(or: { [] })
        guard !names.isEmpty else { return }
        for name in names where name.hasPrefix("Profile ") {
            try? FileManager.default.removeItem(at: AppPaths.chromiumCache.appendingPathComponent(name, isDirectory: true))
        }
        file.saveNow([])
    }
}

enum AppPaths {
    static let supportDir: URL = {
        // CRA_DATA_DIR runs a second, independent Cra (testing next to the installed one).
        // Finder launches have no shell environment. The dev bundle must still stay
        // out of the signed application's profile when opened directly.
        let folder = Bundle.main.bundleIdentifier == "dk.kildahl.cra.dev" ? "CraDev" : "Cra"
        let base = ProcessInfo.processInfo.environment["CRA_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    static var chromiumCache: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static var favicons: URL {
        let u = supportDir.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var log: URL { supportDir.appendingPathComponent("chromium.log") }
    static func file(_ name: String) -> URL { supportDir.appendingPathComponent(name) }
}

/// Where every JSONStore encodes and writes, one file at a time and in call order. Off the
/// main thread, which is also Chromium's UI thread: encoding a 2000-entry archive.json
/// took ~30 ms there, two to four dropped frames after every tab switch.
private let persistenceQueue = DispatchQueue(label: "dk.kildahl.cra.persistence", qos: .utility)

/// One JSON file, loaded once, saved with a short debounce. Writes are atomic
/// and the previous version is kept as `<name>.bak`, which is what Arc does
/// with its timestamped Storable*.json copies, minus the pile-up.
final class JSONStore<T: Codable> {
    let url: URL
    private var pending: DispatchWorkItem?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(_ name: String) { url = AppPaths.file(name) }

    func load(or fallback: () -> T) -> T {
        guard let data = try? Data(contentsOf: url) else { return fallback() }
        if let v = try? decoder.decode(T.self, from: data) { return v }
        // Corrupt file: keep it aside for forensics and start fresh.
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt"))
        return fallback()
    }

    func save(_ value: T, delay: TimeInterval = 0.4) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.write(value) }
        pending = item
        persistenceQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Writes before returning (quit, launch-time bookkeeping), after any write in flight.
    func saveNow(_ value: T) {
        pending?.cancel()
        pending = nil
        persistenceQueue.sync { write(value) }
    }

    private func write(_ value: T) {
        guard let data = try? encoder.encode(value) else { return }
        let fm = FileManager.default
        let bak = url.appendingPathExtension("bak")
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: bak)
            try? fm.copyItem(at: url, to: bak)
        }
        try? data.write(to: url, options: .atomic)
    }
}
