import CraCore
import Foundation
import Testing

/// The right-click list on Back and Forward, as Arc's BackForwardList (GitHub #416).
struct BackForwardMenuTests {
    /// a → b → c → d, on c.
    private let menu = BackForwardMenu(entries: [
        .init(id: 11, url: "https://example.com/a", title: "Example A"),
        .init(id: 12, url: "https://example.com/b", title: "Example B"),
        .init(id: 13, url: "https://example.com/c", title: "Example C"),
        .init(id: 14, url: "https://example.com/d", title: "Example D"),
    ], currentIndex: 2)

    /// Back lists the pages behind, the one Back goes to first, as in Arc's capture.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func backListsThePagesBehindNearestFirst() {
        #expect(menu.rows(.back).map(\.title) == ["Example B", "Example A"])
        #expect(menu.rows(.back).map(\.entryID) == [12, 11])
    }

    /// Forward lists the pages ahead, and never the current one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func forwardListsThePagesAheadNearestFirst() {
        #expect(menu.rows(.forward) == [.init(entryID: 14, title: "Example D", url: "https://example.com/d")])
    }

    /// At either end there is nothing to list.
    @Test func theEndsListNothing() {
        let first = BackForwardMenu(entries: menu.entries, currentIndex: 0)
        let last = BackForwardMenu(entries: menu.entries, currentIndex: 3)
        #expect(first.rows(.back).isEmpty)
        #expect(last.rows(.forward).isEmpty)
        #expect(BackForwardMenu(entries: [], currentIndex: 0).rows(.back).isEmpty)
        #expect(BackForwardMenu(entries: menu.entries, currentIndex: 9).rows(.back).isEmpty)
    }

    /// A page without a title shows its address, as Chromium's menu does.
    @Test func anUntitledPageShowsItsAddress() {
        let m = BackForwardMenu(entries: [.init(id: 1, url: "https://example.com/a", title: "  "),
                                          .init(id: 2, url: "https://example.com/b", title: "B")], currentIndex: 1)
        #expect(m.rows(.back).map(\.title) == ["https://example.com/a"])
    }

    /// A long history lists the nearest 12 entries, Chromium's cap.
    @Test func aLongHistoryListsTheNearestTwelve() {
        let entries = (0..<30).map { BackForwardMenu.Entry(id: $0, url: "https://example.com/\($0)", title: "\($0)") }
        let m = BackForwardMenu(entries: entries, currentIndex: 20)
        #expect(m.rows(.back).map(\.entryID) == Array((8...19).reversed()))
        #expect(m.rows(.forward).map(\.entryID) == Array(21...29))
    }

    /// Chromium's answer to Page.getNavigationHistory, extra fields and all.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func readsPageGetNavigationHistory() throws {
        let json = #"""
        {"currentIndex":1,"entries":[
          {"id":3,"url":"https://a.test/","userTypedURL":"https://a.test/","title":"A","transitionType":"typed"},
          {"id":7,"url":"https://b.test/","userTypedURL":"https://b.test/","title":"B","transitionType":"link"}]}
        """#
        let m = try #require(BackForwardMenu(navigationHistory: Data(json.utf8)))
        #expect(m.currentIndex == 1)
        #expect(m.rows(.back) == [.init(entryID: 3, title: "A", url: "https://a.test/")])
    }

    /// An error, or a current index outside the list, is no menu rather than a wrong one.
    @Test func aBrokenAnswerIsNoMenu() {
        #expect(BackForwardMenu(navigationHistory: Data("{}".utf8)) == nil)
        #expect(BackForwardMenu(navigationHistory: Data("not json".utf8)) == nil)
        #expect(BackForwardMenu(navigationHistory: Data(#"{"currentIndex":2,"entries":[{"id":1,"url":"u","title":"t"}]}"#.utf8)) == nil)
    }
}
