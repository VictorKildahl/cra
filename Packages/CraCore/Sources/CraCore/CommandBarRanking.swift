import Foundation

/// The command bar's ranking pieces that need no store (SuggestionEngine, GitHub #617): how much a
/// recent visit lifts a row, which switches count, and the empty bar's most recent tabs. At 5,000 tabs a
/// keystroke built a Date() twice per matching tab and the empty bar sorted every tab to take seven.
public enum CommandBarRanking {
    /// Switches to a tab this recent count towards its rank.
    public static let switchWindow: TimeInterval = 7 * 86400

    /// What a visit `age` seconds ago adds to a row's score (nil: never visited).
    public static func recencyBoost(age: TimeInterval?) -> Double {
        guard let age else { return 0 }
        if age < 600 { return 30 }
        if age < 3600 { return 22 }
        if age < 86400 { return 14 }
        if age < switchWindow { return 7 }
        return 0
    }

    /// How many of `switches` fall in the last week before `now`, at most 10.
    public static func recentSwitches(_ switches: [Date]?, now: Date) -> Int {
        guard let switches else { return 0 }
        let since = now.addingTimeInterval(-switchWindow)
        return min(switches.lazy.filter { $0 > since }.count, 10)
    }

    /// The `count` items with the latest `date`, latest first, ties in their given order: what sorting all
    /// of them and taking the first `count` gave, in one pass with no full sort.
    public static func mostRecent<T>(_ items: some Sequence<T>, count: Int, date: (T) -> Date) -> [T] {
        guard count > 0 else { return [] }
        var top: [(item: T, date: Date)] = []
        top.reserveCapacity(count + 1)
        for item in items {
            let d = date(item)
            if top.count == count, let last = top.last, d <= last.date { continue }
            // After the last one with a date at least as late: ties keep their order.
            let at = top.firstIndex { $0.date < d } ?? top.count
            top.insert((item, d), at: at)
            if top.count > count { top.removeLast() }
        }
        return top.map(\.item)
    }
}
