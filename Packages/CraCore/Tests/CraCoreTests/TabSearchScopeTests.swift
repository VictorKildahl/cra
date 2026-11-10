import CraCore
import Foundation
import Testing

/// The command bar's "%" scope (#49): what offers it and the order of its rows.
struct TabSearchScopeTests {
    typealias C = TabSearchScope.Candidate<String>
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/49"), arguments: [("%", true), (" % ", true), ("%a", false), ("50%", false), ("%%", false), ("", false)])
    func percentAloneOffersTheScope(query: String, offered: Bool) {
        #expect(TabSearchScope.isOffered(by: query) == offered)
    }

    /// "%" Tab lists the space's tabs: the latest first, tabs not opened since launch after them
    /// in sidebar order.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/49"))
    func nothingTypedListsByRecency() {
        let tabs = [
            C(id: "unopened-a", score: 0, lastActive: nil),
            C(id: "old", score: 0, lastActive: now.addingTimeInterval(-3600)),
            C(id: "unopened-b", score: 0, lastActive: nil),
            C(id: "new", score: 0, lastActive: now),
        ]
        #expect(TabSearchScope.rank(tabs, typed: false) == ["new", "old", "unopened-a", "unopened-b"])
    }

    /// Typed: scattered-letter matches drop out, the best match leads and recency breaks ties.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/49"))
    func typedRanksByMatchThenRecency() {
        let tabs = [
            C(id: "scattered", score: 45, lastActive: now),
            C(id: "word", score: 85, lastActive: now.addingTimeInterval(-60)),
            C(id: "prefix-old", score: 100, lastActive: now.addingTimeInterval(-600)),
            C(id: "prefix-new", score: 100, lastActive: now),
            C(id: "url", score: 55, lastActive: nil),
        ]
        #expect(TabSearchScope.rank(tabs, typed: true) == ["prefix-new", "prefix-old", "word", "url"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/49"))
    func noTabsNoRows() {
        #expect(TabSearchScope.rank([C](), typed: false).isEmpty)
        #expect(TabSearchScope.rank([C(id: "a", score: 10, lastActive: now)], typed: true).isEmpty)
    }

    /// ⌘T's scope (#307): off, Arc's bar finds a tab in any space; on, only the window's space's
    /// tabs are searched and listed, in the order given.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/307"))
    func commandBarTabsFollowTheSetting() {
        let home = UUID(), work = UUID()
        let tabs: [(name: String, space: UUID?)] = [("home-a", home), ("work-a", work), ("loose", nil), ("home-b", home)]
        func listed(currentSpaceOnly: Bool, window: UUID) -> [String] {
            TabSearchScope.commandBarTabs(tabs, space: \.space, windowSpace: window, currentSpaceOnly: currentSpaceOnly).map(\.name)
        }
        #expect(listed(currentSpaceOnly: false, window: home) == ["home-a", "work-a", "loose", "home-b"])
        #expect(listed(currentSpaceOnly: true, window: home) == ["home-a", "home-b"])
        #expect(listed(currentSpaceOnly: true, window: work) == ["work-a"])
    }

    /// The setting is off in a settings.json written before #307 and survives a save.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/307"))
    func currentSpaceOnlySettingDefaultsOffAndRoundTrips() throws {
        let decoder = JSONDecoder()
        let older = try decoder.decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!older.commandBarCurrentSpaceOnly)
        var on = older
        on.commandBarCurrentSpaceOnly = true
        #expect(try decoder.decode(AppSettings.self, from: JSONEncoder().encode(on)).commandBarCurrentSpaceOnly)
    }
}
