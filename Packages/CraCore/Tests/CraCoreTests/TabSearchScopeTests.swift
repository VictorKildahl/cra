import CraCore
import Foundation
import Testing

/// The command bar's "%" scope (#49): what offers it and the order of its rows.
struct TabSearchScopeTests {
    typealias C = TabSearchScope.Candidate<String>
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test(arguments: [("%", true), (" % ", true), ("%a", false), ("50%", false), ("%%", false), ("", false)])
    func percentAloneOffersTheScope(query: String, offered: Bool) {
        #expect(TabSearchScope.isOffered(by: query) == offered)
    }

    /// "%" Tab lists the space's tabs: the latest first, tabs not opened since launch after them
    /// in sidebar order.
    @Test func nothingTypedListsByRecency() {
        let tabs = [
            C(id: "unopened-a", score: 0, lastActive: nil),
            C(id: "old", score: 0, lastActive: now.addingTimeInterval(-3600)),
            C(id: "unopened-b", score: 0, lastActive: nil),
            C(id: "new", score: 0, lastActive: now),
        ]
        #expect(TabSearchScope.rank(tabs, typed: false) == ["new", "old", "unopened-a", "unopened-b"])
    }

    /// Typed: scattered-letter matches drop out, the best match leads and recency breaks ties.
    @Test func typedRanksByMatchThenRecency() {
        let tabs = [
            C(id: "scattered", score: 45, lastActive: now),
            C(id: "word", score: 85, lastActive: now.addingTimeInterval(-60)),
            C(id: "prefix-old", score: 100, lastActive: now.addingTimeInterval(-600)),
            C(id: "prefix-new", score: 100, lastActive: now),
            C(id: "url", score: 55, lastActive: nil),
        ]
        #expect(TabSearchScope.rank(tabs, typed: true) == ["prefix-new", "prefix-old", "word", "url"])
    }

    @Test func noTabsNoRows() {
        #expect(TabSearchScope.rank([C](), typed: false).isEmpty)
        #expect(TabSearchScope.rank([C(id: "a", score: 10, lastActive: now)], typed: true).isEmpty)
    }
}
