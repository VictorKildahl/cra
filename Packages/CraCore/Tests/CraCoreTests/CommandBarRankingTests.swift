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
}
