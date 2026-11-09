import Foundation

/// Each tab's saved back and forward list (PageHistory, GitHub #273), one file a tab in the data
/// folder's PageHistory/, so a navigation rewrites only its own tab's file, not sidebar.json.
/// Incognito pages never get one.
@MainActor
final class PageHistoryStore {
    static let shared = PageHistoryStore()
    static let folder = "PageHistory"
    private var files: [UUID: JSONStore<PageHistory>] = [:]
    /// What was saved this run, ahead of the debounced write.
    private var latest: [UUID: PageHistory] = [:]

    init() {
        try? FileManager.default.createDirectory(at: AppPaths.file(Self.folder), withIntermediateDirectories: true)
    }

    private func file(_ id: UUID) -> JSONStore<PageHistory> {
        if let f = files[id] { return f }
        let f = JSONStore<PageHistory>("\(Self.folder)/\(id.uuidString).json")
        files[id] = f
        return f
    }

    func load(_ id: UUID) -> PageHistory? {
        if let h = latest[id] { return h }
        guard FileManager.default.fileExists(atPath: file(id).url.path) else { return nil }
        let h = file(id).load { PageHistory(engine: .chromium, url: "", state: Data(), savedAt: .distantPast) }
        return h.state.isEmpty ? nil : h
    }

    func save(_ history: PageHistory, for id: UUID, now: Bool = false) {
        latest[id] = history
        now ? file(id).saveNow(history) : file(id).save(history)
    }

    /// Drops every file but `kept`'s (PageHistory.kept), with its .bak.
    func prune(keeping kept: Set<UUID>) {
        let dir = AppPaths.file(Self.folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names {
            let base = name.replacingOccurrences(of: ".json.bak", with: "").replacingOccurrences(of: ".json", with: "")
            guard let id = UUID(uuidString: base), !kept.contains(id) else { continue }
            files[id] = nil
            latest[id] = nil
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
