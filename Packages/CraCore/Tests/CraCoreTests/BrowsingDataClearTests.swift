import CraCore
import Foundation
import Testing

/// Chrome's Delete browsing data dialog also clears the command bar's history.
struct BrowsingDataClearTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let history = BrowsingDataClear.historyDataType

    static let periods: [(Int, Double)] = [(6, 900), (0, 3600), (1, 86400), (2, 604_800), (3, 2_419_200)]

    @Test(arguments: periods)
    func recentPeriods(period: Int, seconds: Double) {
        #expect(BrowsingDataClear.historyRange(dataTypes: [history], timePeriod: period, now: now) == .since(now.addingTimeInterval(-seconds)))
    }

    @Test func allTimeAndOlderThan30Days() {
        #expect(BrowsingDataClear.historyRange(dataTypes: [history], timePeriod: 4, now: now) == .allTime)
        #expect(BrowsingDataClear.historyRange(dataTypes: [history], timePeriod: 5, now: now) == .before(now.addingTimeInterval(-30 * 86400)))
        #expect(BrowsingDataClear.historyRange(dataTypes: [history], timePeriod: 99, now: now) == nil)
    }

    /// Only cookies and cache: the command bar keeps its history.
    @Test func historyNotTicked() {
        #expect(BrowsingDataClear.historyRange(dataTypes: ["browser.clear_data.cookies", "browser.clear_data.cache"], timePeriod: 4, now: now) == nil)
    }

    /// What the page hands over: the message's arguments after the callback id.
    @Test func fromTheMessage() {
        let json = #"[["browser.clear_data.browsing_history","browser.clear_data.cookies"],1]"#
        #expect(BrowsingDataClear.historyRange(messageJSON: json, now: now) == .since(now.addingTimeInterval(-86400)))
        #expect(BrowsingDataClear.historyRange(messageJSON: #"[["browser.clear_data.cache"],4]"#, now: now) == nil)
        #expect(BrowsingDataClear.historyRange(messageJSON: "null", now: now) == nil)
        #expect(BrowsingDataClear.historyRange(messageJSON: #"[[],"x"]"#, now: now) == nil)
    }

    @Test func lastHourDropsWhatWasVisitedInIt() {
        let old = HistoryEntry(url: "https://old.example/", title: "Old", lastVisit: now.addingTimeInterval(-7200), visitCount: 3)
        let new = HistoryEntry(url: "https://new.example/", title: "New", lastVisit: now.addingTimeInterval(-60), visitCount: 1)
        let tab = UUID()
        let ranking = RankingData(recentlySwitchedToTabs: [tab: [now.addingTimeInterval(-7200), now.addingTimeInterval(-60)], UUID(): [now]],
                                  queriesToSelected: ["old": old.url, "new": new.url], commandUsage: ["settings": 2])
        let out = BrowsingDataClear.clearing(.since(now.addingTimeInterval(-3600)), history: [old.url: old, new.url: new], ranking: ranking)
        #expect(Array(out.history.keys) == [old.url])
        #expect(out.ranking.queriesToSelected == ["old": old.url])
        #expect(out.ranking.recentlySwitchedToTabs == [tab: [now.addingTimeInterval(-7200)]])
        #expect(out.ranking.commandUsage == ["settings": 2])
    }

    /// All time also forgets picks of pages that are open tabs (not in history at all).
    @Test func allTimeClearsEverything() {
        let e = HistoryEntry(url: "https://a.example/", title: "A", lastVisit: now, visitCount: 9)
        let ranking = RankingData(recentlySwitchedToTabs: [UUID(): [now]], queriesToSelected: ["a": e.url, "yt": "https://www.youtube.com/"])
        let out = BrowsingDataClear.clearing(.allTime, history: [e.url: e], ranking: ranking)
        #expect(out.history.isEmpty)
        #expect(out.ranking.queriesToSelected.isEmpty)
        #expect(out.ranking.recentlySwitchedToTabs.isEmpty)
    }

    @Test func olderThan30DaysKeepsRecentPages() {
        let old = HistoryEntry(url: "https://old.example/", title: "Old", lastVisit: now.addingTimeInterval(-40 * 86400), visitCount: 1)
        let new = HistoryEntry(url: "https://new.example/", title: "New", lastVisit: now, visitCount: 1)
        let out = BrowsingDataClear.clearing(.before(now.addingTimeInterval(-30 * 86400)), history: [old.url: old, new.url: new], ranking: RankingData())
        #expect(Array(out.history.keys) == [new.url])
    }
}
