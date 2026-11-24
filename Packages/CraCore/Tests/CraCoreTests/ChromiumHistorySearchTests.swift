import CraCore
import Foundation
import Testing

/// ⌘T searches the profile's whole Chromium history, not only history.json's newest 5,000 pages (#730).
struct ChromiumHistorySearchTests {
    let work = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!

    /// The bridge's rows become visited-page entries of the bar's profile: web pages only, each once,
    /// and none that history.json already suggests (its row keeps what Cra recorded). A page Chromium
    /// counted no visits for still counts one, as it was visited.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/730"))
    func enginePagesHistoryJSONDoesntHaveBecomeRows() throws {
        let rows: [[String: Any]] = [
            ["url": "https://deep.example.com/old", "title": "Haystack deep page", "visitCount": 7, "typedCount": 0, "lastVisit": 1_700_000_000.0],
            ["url": "https://known.example.com/", "title": "Known", "visitCount": 3, "typedCount": 1, "lastVisit": 1_760_000_000.0],
            ["url": "chrome://history/", "title": "History", "visitCount": 1, "typedCount": 0, "lastVisit": 1_760_000_000.0],
            ["url": "file:///Users/me/notes.html", "title": "Notes", "visitCount": 1, "typedCount": 0, "lastVisit": 1_760_000_000.0],
            ["url": "http://plain.example.com/", "title": "", "visitCount": 0, "typedCount": 0, "lastVisit": 1_750_000_000.0],
            ["url": "https://deep.example.com/old", "title": "Again", "visitCount": 1, "typedCount": 0, "lastVisit": 1_600_000_000.0],
            ["title": "No address"],
        ]
        let pages = rows.compactMap(ChromiumHistorySearch.Page.init(row:))
        #expect(pages.count == 6)
        let entries = ChromiumHistorySearch.entries(pages, known: ["https://known.example.com/"], profile: work)
        #expect(entries.map(\.url) == ["https://deep.example.com/old", "http://plain.example.com/"])
        let deep = try #require(entries.first)
        #expect(deep.title == "Haystack deep page")
        #expect(deep.visitCount == 7)
        #expect(deep.lastVisit == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(deep.profiles == [work.uuidString])
        #expect(CommandBarProfileScope.suggests(deep, on: work) && !CommandBarProfileScope.suggests(deep, on: nil))
        #expect(entries[1].visitCount == 1)
        #expect(ChromiumHistorySearch.entries(pages, known: [], profile: nil).first?.profiles == ["default"])
    }

    /// Asked from the second letter, trimmed and lowercased (Chromium's search ignores case anyway).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/730"))
    func askedFromTheSecondLetter() {
        #expect(ChromiumHistorySearch.query(for: "") == nil)
        #expect(ChromiumHistorySearch.query(for: " h ") == nil)
        #expect(ChromiumHistorySearch.query(for: "Ha") == "ha")
        #expect(ChromiumHistorySearch.query(for: "  Haystack Deep ") == "haystack deep")
        #expect(ChromiumHistorySearch.maxResults >= 100)
    }
}
