import Foundation

/// ⌘T finds every page the profile has visited, as Arc's command bar does (#730). Arc keeps no history
/// of its own: it asks the space's profile's Chromium history (ArcCore's `searchHistory:` with a text,
/// a maximum and a matching algorithm). Cra's bar searched only history.json, which keeps the newest
/// 5,000 pages, so most of a long history never came up. Now each keystroke also asks the profile's
/// Chromium history (CraCEFRuntime.searchHistory), and the pages history.json doesn't have are ranked
/// with its rows. The engine keeps that history whole: it no longer deletes visits after 90 days
/// (engine/chromium/patches/cra-history-no-expiry.patch).
public enum ChromiumHistorySearch {
    /// Pages per search, the most recently visited first. The bar shows five rows; the rest let an
    /// often-visited older page outrank newer ones that match as well.
    public static let maxResults = 200
    /// Searched from the second letter: one letter starts a word in nearly every page.
    public static let minimumLength = 2

    /// What to ask Chromium's history for the typed text, nil for nothing.
    public static func query(for typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.count >= minimumLength ? text : nil
    }

    /// One page of the engine's answer.
    public struct Page: Equatable {
        public let url: String
        public let title: String
        public let visitCount: Int
        public let lastVisit: Date

        public init(url: String, title: String, visitCount: Int, lastVisit: Date) {
            self.url = url
            self.title = title
            self.visitCount = visitCount
            self.lastVisit = lastVisit
        }

        /// A row as the bridge hands it over: url, title, visitCount, lastVisit (seconds since 1970).
        public init?(row: [String: Any]) {
            guard let url = row["url"] as? String, !url.isEmpty else { return nil }
            self.url = url
            title = row["title"] as? String ?? ""
            visitCount = (row["visitCount"] as? NSNumber)?.intValue ?? 0
            lastVisit = Date(timeIntervalSince1970: (row["lastVisit"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    /// The visited-page rows the engine adds: its web pages that the bar's own history (`known`, the
    /// addresses history.json suggests in this bar) doesn't list, as entries of `profile`. One that
    /// history.json has keeps its row there, with what Cra recorded about it.
    public static func entries(_ pages: [Page], known: Set<String>, profile: UUID?) -> [HistoryEntry] {
        var seen = known
        var out: [HistoryEntry] = []
        for page in pages where page.url.hasPrefix("http://") || page.url.hasPrefix("https://") {
            guard seen.insert(page.url).inserted else { continue }
            var entry = HistoryEntry(url: page.url, title: page.title, lastVisit: page.lastVisit, visitCount: max(page.visitCount, 1))
            entry.visited(in: profile)
            out.append(entry)
        }
        return out
    }
}
