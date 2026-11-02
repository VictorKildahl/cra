import CraCore
import Testing

/// The command bar lists a page once, and an open tab keeps its row.
struct CommandBarDedupeTests {
    typealias Row = CommandBarDedupe.Row

    @Test func comparableAddress() {
        #expect(CommandBarDedupe.comparableURL("https://www.semrush.com/projects/") == "https://semrush.com/projects")
        #expect(CommandBarDedupe.comparableURL("https://semrush.com/projects") == "https://semrush.com/projects")
        #expect(CommandBarDedupe.comparableURL("https://YouTube.com") == "https://youtube.com")
        #expect(CommandBarDedupe.comparableURL("https://www.youtube.com/") == "https://youtube.com")
        #expect(CommandBarDedupe.comparableURL("https://www.youtube.com/watch?v=x") == "https://youtube.com/watch?v=x")
    }

    /// Arc 1.171: "semrush" completes to semrush.com/projects, "umami" to umami.kildahl.dk/dashboard.
    @Test func completionAddress() {
        #expect(CommandBarDedupe.completionAddress("https://www.semrush.com/projects/") == "semrush.com/projects")
        #expect(CommandBarDedupe.completionAddress("https://umami.kildahl.dk/dashboard") == "umami.kildahl.dk/dashboard")
        #expect(CommandBarDedupe.completionAddress("https://youtube.com") == "youtube.com")
    }

    /// YouTube pages share titles, so they also match by host and title.
    @Test func keys() {
        #expect(CommandBarDedupe.keys(id: "hist:x", url: "https://www.youtube.com/?app=desktop", title: "YouTube")
                == ["https://youtube.com?app=desktop", "www.youtube.com|youtube"])
        #expect(CommandBarDedupe.keys(id: "hist:y", url: "https://example.com/a/", title: "A") == ["https://example.com/a"])
        #expect(CommandBarDedupe.keys(id: "cmd:settings", url: nil, title: "Settings") == ["cmd:settings"])
    }

    /// X, 1 Nov 2026: "YouTube" history (many visits) outscored the pinned YouTube tab and took
    /// its row; Return then opened a new tab. The tab keeps the row, at the history's score.
    @Test func openTabWinsItsPage() {
        let tab = CommandBarDedupe.keys(id: "tab:1", url: "https://youtube.com", title: "YouTube")
        let history = CommandBarDedupe.keys(id: "hist:1", url: "https://www.youtube.com/", title: "YouTube")
        let rows = [Row(keys: history, score: 128, isOpenTab: false),
                    Row(keys: ["https://youtube.com/feed"], score: 72, isOpenTab: false),
                    Row(keys: tab, score: 100, isOpenTab: true)]
        let kept = CommandBarDedupe.kept(rows)
        #expect(kept.map(\.index) == [2, 1])
        #expect(kept.map(\.score) == [128, 72])
    }

    /// Arc 1.171 hid both address variants of the pinned Semrush tab's page and kept another page.
    @Test func addressVariantsFoldIntoTheTab() {
        func row(_ url: String, _ title: String, _ score: Double, tab: Bool = false) -> Row {
            Row(keys: CommandBarDedupe.keys(id: url, url: url, title: title), score: score, isOpenTab: tab)
        }
        let rows = [row("https://semrush.com/projects/", "Semrush nowww variant", 110),
                    row("https://www.semrush.com/projects", "Semrush noslash variant", 105),
                    row("https://www.semrush.com/analytics/", "Semrush analytics control", 90),
                    row("https://www.semrush.com/projects/", "Semrush", 100, tab: true)]
        #expect(CommandBarDedupe.kept(rows).map(\.index) == [3, 2])
    }

    /// Without an open tab the best row stays; of two open tabs, the better one.
    @Test func bestRowOtherwise() {
        let history = [Row(keys: ["a"], score: 60, isOpenTab: false), Row(keys: ["a"], score: 80, isOpenTab: false)]
        #expect(CommandBarDedupe.kept(history).map(\.index) == [1])
        let tabs = [Row(keys: ["a"], score: 90, isOpenTab: true), Row(keys: ["a"], score: 95, isOpenTab: true), Row(keys: ["a"], score: 99, isOpenTab: false)]
        #expect(CommandBarDedupe.kept(tabs).map(\.index) == [1])
        #expect(CommandBarDedupe.kept(tabs).map(\.score) == [99])
    }

    /// A row sharing one key with each of two others joins them into one page.
    @Test func sharedKeysChain() {
        let rows = [Row(keys: ["p1", "t"], score: 50, isOpenTab: false), Row(keys: ["p2"], score: 60, isOpenTab: true),
                    Row(keys: ["p2", "t"], score: 40, isOpenTab: false)]
        #expect(CommandBarDedupe.kept(rows).map(\.index) == [1])
    }

    /// Different pages all stay, best first; equal scores keep their order.
    @Test func distinctRowsStayInScoreOrder() {
        let rows = [Row(keys: ["a"], score: 50, isOpenTab: false), Row(keys: ["b"], score: 70, isOpenTab: true), Row(keys: ["c"], score: 50, isOpenTab: false)]
        #expect(CommandBarDedupe.kept(rows).map(\.index) == [1, 0, 2])
        #expect(CommandBarDedupe.kept([]).isEmpty)
    }
}
