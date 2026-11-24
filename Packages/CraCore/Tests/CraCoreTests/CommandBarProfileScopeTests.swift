import CraCore
import Foundation
import Testing

/// What ⌘T suggests from history and the archive: the bar's profile's own (#609).
struct CommandBarProfileScopeTests {
    let work = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    func entry(_ profiles: [String]?) -> HistoryEntry {
        var e = HistoryEntry(url: "https://example.com/", title: "Example", lastVisit: Date(timeIntervalSince1970: 0), visitCount: 1)
        e.profiles = profiles
        return e
    }

    /// A page visited on one profile isn't suggested on another; one saved before Cra kept profiles is
    /// suggested everywhere (whose it was isn't known). Archived tabs follow their space's profile; one
    /// with no space (a Little Window's) is suggested everywhere, as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/609"))
    func eachProfileSuggestsItsOwn() {
        #expect(CommandBarProfileScope.suggests(entry([work.uuidString]), on: work))
        #expect(!CommandBarProfileScope.suggests(entry([work.uuidString]), on: nil))
        #expect(CommandBarProfileScope.suggests(entry(["default"]), on: nil))
        #expect(!CommandBarProfileScope.suggests(entry(["default"]), on: work))
        #expect(CommandBarProfileScope.suggests(entry(["default", work.uuidString]), on: work))
        #expect(CommandBarProfileScope.suggests(entry(nil), on: work) && CommandBarProfileScope.suggests(entry(nil), on: nil))

        #expect(CommandBarProfileScope.suggests(archivedFrom: .some(work), on: work))
        #expect(!CommandBarProfileScope.suggests(archivedFrom: .some(work), on: nil))
        #expect(CommandBarProfileScope.suggests(archivedFrom: .some(nil), on: nil))
        #expect(!CommandBarProfileScope.suggests(archivedFrom: .some(nil), on: work))
        #expect(CommandBarProfileScope.suggests(archivedFrom: nil, on: work) && CommandBarProfileScope.suggests(archivedFrom: nil, on: nil))
    }

    /// A visit adds its profile once; history.json from before #609 loads with none and saves as it was.
    @Test func visitsAddTheirProfileAndOldFilesStayTheSame() throws {
        var e = entry(nil)
        e.visited(in: work)
        e.visited(in: nil)
        e.visited(in: work)
        #expect(e.profiles == [work.uuidString, "default"])
        let old = #"{"url":"https://example.com/","title":"Example","lastVisit":0,"visitCount":1}"#
        let loaded = try JSONDecoder().decode(HistoryEntry.self, from: Data(old.utf8))
        #expect(loaded.profiles == nil)
        #expect(!String(decoding: try JSONEncoder().encode(loaded), as: UTF8.self).contains("profiles"))
        #expect(try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(e)) == e)
    }

    /// History from before #609 takes its profiles from the profiles' Chromium histories, once: a page
    /// only Work's history has is suggested on Work only, one both have on both, one neither has (older
    /// than Chromium's 90 days) on every profile, as before. Entries that have profiles don't change.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/729"))
    func historyFromBeforeProfilesTakesThemFromChromium() {
        func old(_ url: String) -> HistoryEntry {
            HistoryEntry(url: url, title: "", lastVisit: Date(timeIntervalSince1970: 0), visitCount: 1)
        }
        var tagged = old("https://example.com/tagged")
        tagged.visited(in: nil)
        let entries = [old("https://example.com/work"), old("https://example.com/both"), old("https://example.com/gone"), tagged]
        let chromium: [String: Set<String>] = [
            work.uuidString: ["https://example.com/work", "https://example.com/both", "https://example.com/tagged"],
            "default": ["https://example.com/both"],
        ]
        let changed = Dictionary(uniqueKeysWithValues: CommandBarProfileScope.attributing(entries, chromiumURLs: chromium).map { ($0.url, $0) })
        #expect(changed["https://example.com/work"]?.profiles == [work.uuidString], "only Work's history has it")
        #expect(changed["https://example.com/both"]?.profiles == ["default", work.uuidString], "both histories have it")
        #expect(changed["https://example.com/gone"]?.profiles == ["default", work.uuidString], "no history has it: every profile, as before")
        #expect(changed["https://example.com/tagged"] == nil, "an entry that has its profiles keeps them")
        #expect(changed.count == 3)
        let work = changed["https://example.com/work"]!
        #expect(CommandBarProfileScope.suggests(work, on: self.work) && !CommandBarProfileScope.suggests(work, on: nil))
        #expect(CommandBarProfileScope.attributing(entries, chromiumURLs: [:]).isEmpty, "no profile read: nothing changes")
    }
}
