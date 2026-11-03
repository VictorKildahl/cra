import CraCEF
import Foundation
import SQLite3

/// Chromium's search engines, which chrome://settings/searchEngines edits (ChromiumSearchEngine):
/// the default from the profile's pref, read live, and the keywords from its Web Data, read again
/// when the file changes. Profiles are named as CraCEFRuntime takes them: nil is Default.
@MainActor
final class SearchEngines {
    static let shared = SearchEngines()

    /// The engine picked on the settings page; empty until one is.
    static let chosenPref = "default_search_provider_data.template_url_data"
    /// Chromium's copy of whichever engine is the default, its built-in one included.
    static let currentPref = "default_search_provider_data.mirrored_template_url_data"
    static let settingsPage = "chrome://settings/searchEngines"

    private var keywordCache: [String: (modified: Date, engines: [ChromiumSearchEngine])] = [:]
    /// Profiles whose older Cra engine setting went to Chromium this run (once, whatever came of it).
    private var migrated: Set<String> = []

    /// The engine typed searches go to. `legacy` is Cra's own setting: Chromium gets it once while
    /// it has no default of its own, and it stands in until the profile has loaded.
    func defaultEngine(profilePath: String?, legacy: SearchEngine) -> ChromiumSearchEngine {
        if let chosen = engine(pref: Self.chosenPref, profilePath: profilePath) { return chosen }
        let key = profilePath ?? ""
        // The pref reads as nil until the profile has loaded, as {} once it has and holds no engine.
        if legacy != .google, !migrated.contains(key), CraCEFRuntime.preference(Self.chosenPref, forProfile: profilePath) != nil {
            migrated.insert(key)
            let engine = ChromiumSearchEngine.migrating(legacy, among: keywords(profilePath: profilePath))
            if setDefault(engine, profilePath: profilePath) { return engine }
        }
        return engine(pref: Self.currentPref, profilePath: profilePath) ?? ChromiumSearchEngine(legacy)
    }

    /// Settings' picker: `engine` becomes the default of every profile that has loaded, as their own
    /// row for it where they have one, and Cra's setting follows so the others take it when they load.
    func setDefault(_ engine: ChromiumSearchEngine, store: SidebarStore) {
        let paths = [nil] + store.profiles.map { AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path }
        for path in paths {
            let own = keywords(profilePath: path).first { ($0.isBuiltIn && $0.prepopulateID == engine.prepopulateID) || $0.keyword == engine.keyword }
            setDefault(own ?? engine, profilePath: path)
        }
        if let legacy = SearchEngine.allCases.first(where: { ChromiumSearchEngine($0).keyword == engine.keyword }) {
            store.settings.searchEngine = legacy
        }
    }

    /// Makes `engine` the profile's default, as picking it on the settings page does.
    @discardableResult
    func setDefault(_ engine: ChromiumSearchEngine, profilePath: String?) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: engine.templateURLData),
              let json = String(data: data, encoding: .utf8) else { return false }
        return CraCEFRuntime.setPreference(Self.chosenPref, json: json, forProfile: profilePath)
    }

    private func engine(pref: String, profilePath: String?) -> ChromiumSearchEngine? {
        guard let json = CraCEFRuntime.preference(pref, forProfile: profilePath),
              let d = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        return ChromiumSearchEngine(templateURLData: d)
    }

    /// Every row of the profile's keywords table, as the settings page lists them.
    func keywords(profilePath: String?) -> [ChromiumSearchEngine] {
        let dir = profilePath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        let file = dir.appendingPathComponent("Web Data")
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return [] }
        if let hit = keywordCache[file.path], hit.modified == modified { return hit.engines }
        let engines = Self.readKeywords(file)
        keywordCache[file.path] = (modified, engines)
        return engines
    }

    /// Chromium holds the database open with an exclusive lock, so it is read as immutable: no
    /// locks taken, nothing written. A read that lands mid-write gets nothing and the next one,
    /// after the write changes the file's date, tries again.
    nonisolated static func readKeywords(_ file: URL) -> [ChromiumSearchEngine] {
        guard let path = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT id, short_name, keyword, url, suggest_url, favicon_url, prepopulate_id, safe_for_autoreplace,
               is_active, starter_pack_id, sync_guid FROM keywords
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [ChromiumSearchEngine] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(ChromiumSearchEngine(
                id: sqlite3_column_int64(stmt, 0), name: text(1), keyword: text(2), url: text(3), suggestURL: text(4), faviconURL: text(5),
                prepopulateID: Int(sqlite3_column_int(stmt, 6)), safeForAutoreplace: sqlite3_column_int(stmt, 7) != 0,
                isActive: Int(sqlite3_column_int(stmt, 8)), starterPackID: Int(sqlite3_column_int(stmt, 9)), syncGUID: text(10)))
        }
        return out.filter { !$0.keyword.isEmpty && !$0.url.isEmpty }
    }
}
