import Foundation
import Testing
@testable import CraCore

/// ⌘T completes a site's name to the address typed most on that site (GitHub #667), as Arc's (Chromium's)
/// omnibox does from history's typed counts.
struct TypedCompletionTests {
    private func page(_ url: String, typed: Int) -> TypedCompletion.Page { TypedCompletion.Page(url: url, typedCount: typed)! }

    /// The reporter's Arc history: youtube.com/ typed 541 times, www.youtube.com/ 55, videos a few each.
    private var youtube: [TypedCompletion.Page] {
        [page("https://www.youtube.com/", typed: 55), page("https://www.youtube.com/watch?v=hdMszZ2ah5Q", typed: 3),
         page("https://youtube.com/", typed: 541), page("https://www.youtube.com/watch?v=abc", typed: 2)]
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func aSitesNameLeadsToItsMostTypedShortestAddress() {
        let lead = TypedCompletion.lead(for: "youtube", pages: youtube)
        #expect(lead?.url == "https://youtube.com/")
        #expect(lead?.completion == "youtube.com")
        #expect(TypedCompletion.lead(for: "yout", pages: youtube)?.completion == "youtube.com")
        #expect(TypedCompletion.lead(for: "www.you", pages: youtube)?.completion == "www.youtube.com", "a typed www. keeps it")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func theSiteTypedMostWins() {
        let pages = [page("https://youtube.com/", typed: 4), page("https://youtrack.example/", typed: 9),
                     page("https://youtrack.example/issues/1", typed: 1)]
        #expect(TypedCompletion.lead(for: "you", pages: pages)?.url == "https://youtrack.example/")
        // Counted across the site's pages: three videos typed twice each outweigh another site typed five times.
        let videos = [page("https://youtube.com/watch?v=1", typed: 2), page("https://youtube.com/watch?v=2", typed: 2),
                      page("https://youtube.com/watch?v=3", typed: 2), page("https://youtrack.example/", typed: 5)]
        #expect(TypedCompletion.lead(for: "you", pages: videos)?.completion == "youtube.com/watch?v=1")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func nothingTypedLeavesItToTheOtherRows() {
        // Arc 1.171's semrush copy had visits and no typed counts: its open tab led (CommandBarDedupe).
        #expect(TypedCompletion.lead(for: "semrush", pages: [page("https://www.semrush.com/projects/", typed: 0)]) == nil)
        #expect(TypedCompletion.lead(for: "youtube", pages: []) == nil)
        #expect(TypedCompletion.lead(for: "y", pages: youtube) == nil, "one letter completes nothing")
        #expect(TypedCompletion.lead(for: "youtube.com", pages: youtube) == nil, "nothing left to complete")
        #expect(TypedCompletion.lead(for: "tube", pages: youtube) == nil, "a host only completes from its start")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func aHostWithAPortCompletesWithIt() {
        let pages = [page("http://127.0.0.1:8123/", typed: 1), page("http://127.0.0.1:8123/page.html?n=a", typed: 0)]
        #expect(TypedCompletion.lead(for: "127.0", pages: pages)?.completion == "127.0.0.1:8123")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func anEnteredAddressIsCountedUnderItsPagesKey() {
        #expect(TypedCompletion.key("https://youtube.com") == "https://youtube.com/", "as Chromium records a bare host")
        #expect(TypedCompletion.key("https://youtube.com/watch?v=1") == "https://youtube.com/watch?v=1")
        #expect(TypedCompletion.key("http://127.0.0.1:8123") == "http://127.0.0.1:8123/")
        #expect(TypedCompletion.key("about:blank") == "about:blank")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/667"))
    func historyKeepsItsTypedCountsAndOldFilesStayAsTheyWere() throws {
        var typed = HistoryEntry(url: "https://youtube.com/", title: "YouTube", lastVisit: Date(timeIntervalSince1970: 0), visitCount: 3)
        typed.typedCount = 2
        let again = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(typed))
        #expect(again.typedCount == 2)
        let old = #"{"url":"https://a.example/","title":"A","lastVisit":0,"visitCount":1}"#
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(old.utf8))
        #expect(entry.typedCount == nil)
        let saved = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(!saved.contains("typedCount"), "an entry never typed saves as before")
    }
}
