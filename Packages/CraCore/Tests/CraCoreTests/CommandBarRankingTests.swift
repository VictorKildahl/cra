import CraCore
import Foundation
import Testing

struct CommandBarRankingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// GitHub #617: the empty bar sorted every tab by last activity to take seven. The bounded pick gives
    /// the same seven, in the same order (latest first, ties as given), without sorting 5,000.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/617"))
    func theMostRecentSevenAreTheSortedSeven() {
        var rng = SystemRandomNumberGenerator()
        let items = (0..<5000).map { i in (id: i, date: now.addingTimeInterval(-Double(Int.random(in: 0..<300, using: &rng)) * 60)) }
        let sorted = items.sorted { $0.date > $1.date }.prefix(7).map(\.id)
        #expect(CommandBarRanking.mostRecent(items, count: 7, date: \.date).map(\.id) == Array(sorted))
        // Ties keep their given order, as the stable sort did.
        let tied = (0..<10).map { (id: $0, date: now) }
        #expect(CommandBarRanking.mostRecent(tied, count: 3, date: \.date).map(\.id) == [0, 1, 2])
        #expect(CommandBarRanking.mostRecent([(id: 0, date: now)], count: 7, date: \.date).map(\.id) == [0])
        #expect(CommandBarRanking.mostRecent(tied, count: 0, date: \.date).isEmpty)
    }

    /// The same boosts as before, from one clock reading per keystroke.
    @Test func recencyAndSwitchesFromOneNow() {
        #expect(CommandBarRanking.recencyBoost(age: nil) == 0)
        #expect(CommandBarRanking.recencyBoost(age: 60) == 30)
        #expect(CommandBarRanking.recencyBoost(age: 1800) == 22)
        #expect(CommandBarRanking.recencyBoost(age: 7200) == 14)
        #expect(CommandBarRanking.recencyBoost(age: 3 * 86400) == 7)
        #expect(CommandBarRanking.recencyBoost(age: 8 * 86400) == 0)
        let switches = (0..<15).map { now.addingTimeInterval(-Double($0) * 3600) } + [now.addingTimeInterval(-8 * 86400)]
        #expect(CommandBarRanking.recentSwitches(switches, now: now) == 10)
        #expect(CommandBarRanking.recentSwitches([now.addingTimeInterval(-8 * 86400)], now: now) == 0)
        #expect(CommandBarRanking.recentSwitches(nil, now: now) == 0)
    }

    /// Arc lists the space whose name starts with the typed text first and selects it: "finan" with a space called
    /// FINANCE. Cra's rows are ranked first, and an archived "… Financial …" page outscored "Switch to FINANCE", so
    /// the space never led. Rows are given in rank order, nil for a row that switches to no space.
    @Test func aSpaceTheTextStartsLeads() {
        let rows: [String?] = [nil, nil, "FINANCE", nil]
        #expect(CommandBarRanking.leadingSpace("finan", in: rows, spaceTitle: { $0 }) == 2)
        #expect(CommandBarRanking.leadingSpace("finance", in: rows, spaceTitle: { $0 }) == 2)
        // The first in rank order leads when two names start with the text.
        #expect(CommandBarRanking.leadingSpace("fin", in: [nil, "Fine Art", "Finance"], spaceTitle: { $0 }) == 1)
    }

    /// The whole name only: a word inside it would take Return from a search that shares the word. Nor an address,
    /// a single letter, or text longer than the name.
    @Test func otherwiseNoSpaceLeads() {
        #expect(CommandBarRanking.leadingSpace("proj", in: ["Side Projects"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("localhost", in: ["Localhost"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("cra.app", in: ["cra.app notes"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("f", in: ["Finance"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("finances", in: ["Finance"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("weather", in: [nil, "Finance"], spaceTitle: { $0 }) == nil)
        #expect(CommandBarRanking.leadingSpace("finan", in: [String?](), spaceTitle: { $0 }) == nil)
    }
}
