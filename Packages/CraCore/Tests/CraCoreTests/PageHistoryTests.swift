import CraCore
import Foundation
import Testing

/// A tab's back and forward list across a relaunch, as in Arc (GitHub #273).
struct PageHistoryTests {
    private let saved = PageHistory(engine: .chromium, url: "https://example.com/b", state: Data([1, 2, 3]),
                                    savedAt: Date(timeIntervalSince1970: 0))

    /// After a relaunch the tab's page opens with its history: Back goes to the page before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func aTabStillOnItsPageOpensWithItsHistory() {
        #expect(saved.restores(into: .chromium, at: "https://example.com/b"))
    }

    /// History that ends elsewhere, or that the other engine wrote, isn't put back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func aTabThatMovedOnOrChangedEngineStartsFresh() {
        #expect(!saved.restores(into: .chromium, at: "https://example.com/"))
        #expect(!saved.restores(into: .webKit, at: "https://example.com/b"))
        var empty = saved
        empty.state = Data()
        #expect(!empty.restores(into: .chromium, at: "https://example.com/b"))
    }

    /// Sidebar tabs keep theirs, and so do the 25 latest closed tabs, for ⇧⌘T.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func closedTabsKeepTheirsForReopening() {
        let open = UUID()
        let archive = (0..<30).map { _ in UUID() }
        let kept = PageHistory.kept(sidebarTabs: [open], archive: archive)
        #expect(kept.contains(open) && kept.isSuperset(of: archive.prefix(25)) && kept.isDisjoint(with: archive.suffix(5)))
    }

    /// The file round-trips (PageHistory/<tab id>.json).
    @Test func savesAndLoads() throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(PageHistory.self, from: e.encode(saved)) == saved)
    }
}
