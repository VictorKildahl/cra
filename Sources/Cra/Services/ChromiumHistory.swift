import CraCEF
import Foundation

/// The command bar's search of the profile's whole Chromium history (#730, CraCore ChromiumHistorySearch):
/// one engine search per keystroke, its answer kept until the bar closes. While a query's answer loads,
/// the previous one stays, scored against the new text, so the rows don't empty and refill per letter.
@MainActor
final class ChromiumHistory {
    typealias Row = (entry: HistoryEntry, key: SuggestionEngine.Searchable)

    /// Answers by profile and query.
    private var answers: [String: [Row]] = [:]
    private var last: (profile: String, rows: [Row])?
    private var pending: String?

    /// The pages the engine found for `query` on `profile` that history.json doesn't suggest, or the last
    /// answer while this one loads.
    func rows(for query: String, profile: UUID?) -> [Row] {
        guard let q = ChromiumHistorySearch.query(for: query) else { return [] }
        let p = CommandBarProfileScope.key(profile)
        if let hit = answers["\(p)|\(q)"] { return hit }
        guard let last, last.profile == p, pending == "\(p)|\(q)" else { return [] }
        return last.rows
    }

    /// Asks the engine about `query`; `done` runs when its answer is in, to list again. `known`: the
    /// addresses the bar already suggests from history.json.
    func fetch(_ query: String, profile: UUID?, profilePath: String?, known: @escaping @MainActor () -> Set<String>,
               done: @escaping @MainActor () -> Void) {
        guard let q = ChromiumHistorySearch.query(for: query) else { return }
        let p = CommandBarProfileScope.key(profile)
        let key = "\(p)|\(q)"
        guard answers[key] == nil, pending != key else { return }
        pending = key
        CraCEFRuntime.searchHistory(q, profilePath: profilePath, maxCount: ChromiumHistorySearch.maxResults) { [weak self] found in
            MainActor.assumeIsolated {
                // A search the bar no longer waits for (a newer letter, or the bar closed) is dropped.
                guard let self, self.pending == key else { return }
                self.pending = nil
                let pages = found.compactMap { ChromiumHistorySearch.Page(row: $0) }
                let entries = ChromiumHistorySearch.entries(pages, known: known(), profile: profile)
                let keys = SuggestionEngine.searchables(entries.map { ($0.title, $0.url) })
                let rows = Array(zip(entries, keys)).map { Row(entry: $0.0, key: $0.1) }
                self.answers[key] = rows
                self.last = (p, rows)
                done()
            }
        }
    }

    /// A page deleted from the bar (#779): it leaves the answers already in, so the rows don't bring it back
    /// before the next search. That search runs after the delete on the history thread, so it doesn't find it.
    func forget(_ url: String) {
        answers = answers.mapValues { $0.filter { $0.entry.url != url } }
        if let last { self.last = (last.profile, last.rows.filter { $0.entry.url != url }) }
    }

    /// The command bar opened or closed: history may have grown since.
    func reset() {
        answers = [:]
        last = nil
        pending = nil
    }
}
