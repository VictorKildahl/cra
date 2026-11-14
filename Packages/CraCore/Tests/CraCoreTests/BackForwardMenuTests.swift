import CoreGraphics
import CraCore
import Testing

/// Right-click Back or Forward (GitHub #416): the rows come from DevTools' Page.getNavigationHistory,
/// the geometry from Arc 1.172.1's menu (a 2x capture in the issue).
struct BackForwardMenuTests {
    /// Five pages, the third one showing: a.com, b.com, (c.com), d.com, e.com.
    static let history = """
    {"currentIndex":2,"entries":[
      {"id":11,"url":"https://a.com/","title":"A","userTypedURL":"","transitionType":"typed"},
      {"id":12,"url":"https://b.com/page","title":"","userTypedURL":"","transitionType":"link"},
      {"id":13,"url":"https://c.com/","title":"C","userTypedURL":"","transitionType":"link"},
      {"id":14,"url":"https://d.com/","title":"  D  ","userTypedURL":"","transitionType":"link"},
      {"id":15,"url":"https://e.com/","title":"E","userTypedURL":"","transitionType":"link"}]}
    """

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func backListsThePagesBehindNearestFirst() {
        let rows = BackForwardMenu.rows(history: Self.history, direction: .back)
        #expect(rows.map(\.entryID) == [12, 11])
        #expect(rows.map(\.title) == ["b.com/page", "A"], "a page without a title shows its address")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func forwardListsThePagesAheadNearestFirst() {
        let rows = BackForwardMenu.rows(history: Self.history, direction: .forward)
        #expect(rows.map(\.entryID) == [14, 15])
        #expect(rows.map(\.title) == ["D", "E"])
        #expect(rows.first?.url == "https://d.com/")
    }

    @Test func nothingBehindTheFirstPageOrAheadOfTheLast() {
        let only = #"{"currentIndex":0,"entries":[{"id":1,"url":"https://a.com/","title":"A"}]}"#
        #expect(BackForwardMenu.rows(history: only, direction: .back).isEmpty)
        #expect(BackForwardMenu.rows(history: only, direction: .forward).isEmpty)
    }

    @Test(arguments: ["", "{}", "not json", #"{"currentIndex":5,"entries":[]}"#, #"{"currentIndex":-1,"entries":[{"id":1,"url":"x"}]}"#])
    func aBrokenReplyGivesNoRows(_ reply: String) {
        #expect(BackForwardMenu.rows(history: reply, direction: .back).isEmpty)
        #expect(BackForwardMenu.rows(history: reply, direction: .forward).isEmpty)
    }

    @Test func entriesWithoutAnIdOrAddressAreLeftOut() {
        let rows = BackForwardMenu.rows(entries: [
            .init(entryID: 1, title: "A", url: "https://a.com/"),
            .init(entryID: -1, title: "No id", url: "https://b.com/"),
            .init(entryID: 3, title: "No address", url: ""),
            .init(entryID: 4, title: "Here", url: "https://d.com/"),
        ], currentIndex: 3, direction: .back)
        #expect(rows.map(\.entryID) == [1])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func atMostTwelveRowsAsInChromium() {
        let entries = (0..<30).map { BackForwardMenu.Row(entryID: $0, title: "P\($0)", url: "https://p\($0).com/") }
        let back = BackForwardMenu.rows(entries: entries, currentIndex: 29, direction: .back)
        #expect(back.count == 12 && back.first?.entryID == 28 && back.last?.entryID == 17)
        let forward = BackForwardMenu.rows(entries: entries, currentIndex: 0, direction: .forward)
        #expect(forward.count == 12 && forward.first?.entryID == 1 && forward.last?.entryID == 12)
    }

    @Test(arguments: [("https://example.com/", "example.com"), ("http://example.com/a/", "example.com/a/"),
                      ("https://x.com/p?q=1", "x.com/p?q=1"), ("file:///tmp/a.html", "file:///tmp/a.html")])
    func addressesDropTheirScheme(_ url: String, _ shown: String) {
        #expect(BackForwardMenu.displayURL(url) == shown)
    }

    typealias L = BackForwardMenu.Layout

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func threeRowsMakeArcs136PointFill() {
        #expect(L.fillHeight(rows: 3) == 136)
        #expect(L.size(rows: 1) == CGSize(width: 232, height: 74), "Arc's window for one row, 6 pt of shadow all round")
        #expect(L.size(rows: 3) == CGSize(width: 232, height: 154))
        #expect(L.fillRect(rows: 3) == CGRect(x: 6, y: 12, width: 220, height: 136), "under the 7 pt tail, a point of overlap")
        #expect(L.rowRect(0) == CGRect(x: 14, y: 20, width: 204, height: 40))
        #expect(L.rowRect(2).maxY == L.fillRect(rows: 3).maxY - 8, "8 pt under the last row")
        #expect(L.faviconRect(1) == CGRect(x: 22, y: 72, width: 16, height: 16))
        #expect(L.titleWidth == 160)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func theMenuHangsCentredUnderTheButton() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let button = CGRect(x: 300, y: 860, width: 32, height: 32)
        let p = L.placement(button: button, screen: screen, rows: 1)
        // Arc, live: a 32 pt ← at 269 pt gave its 232 × 74 pt window at 169 pt, the fill at 175.
        #expect(p.frame == CGRect(x: 200, y: 860 - 10 + 6 - 74, width: 232, height: 74))
        #expect(p.frame.minX + L.margin + L.width / 2 == button.midX, "the fill is centred under the button")
        #expect(p.frame.maxY - L.margin == button.minY - 10, "the tail's tip 10 pt under the button")
        #expect(p.tailX == 116, "the tail points at the button's centre")
    }

    @Test func aButtonNearTheScreenEdgeKeepsTheMenuOnScreenAndTheTailOnTheButton() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let left = L.placement(button: CGRect(x: 60, y: 860, width: 32, height: 32), screen: screen, rows: 2)
        #expect(left.frame.minX + L.margin == 4 && left.tailX == 72 + L.margin)
        let corner = L.placement(button: CGRect(x: 0, y: 860, width: 10, height: 32), screen: screen, rows: 2)
        #expect(corner.tailX == 18 + L.margin, "never on the fill's rounded corner")
        let right = L.placement(button: CGRect(x: 1490, y: 860, width: 20, height: 32), screen: screen, rows: 2)
        #expect(right.frame.maxX - L.margin == 1508 && right.tailX == 202 + L.margin)
        let low = L.placement(button: CGRect(x: 600, y: 30, width: 32, height: 32), screen: screen, rows: 12)
        #expect(low.frame.minY + L.margin == 4, "a long menu near the bottom stays on the screen")
    }
}
