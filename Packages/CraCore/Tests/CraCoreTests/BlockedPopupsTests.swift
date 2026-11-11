import CraCore
import Testing

/// The pop-ups Chromium blocked on a page and the button that opens them. A shared folder's
/// Open All opened one tab in Cra and lost the rest without a word (GitHub #357).
struct BlockedPopupsTests {
    /// Open All on crabrowser.app/folder: one click may open one tab, Chromium blocks the other
    /// three, and every one of them can be opened from the button.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/357"))
    func blockedPopupsWaitToBeOpened() {
        var popups = BlockedPopups()
        #expect(popups.waiting.isEmpty)
        popups.update(ids: [0, 1, 2], urls: ["https://a.example/", "https://b.example/x", "https://c.example/"])
        #expect(popups.waiting.map(\.url) == ["https://a.example/", "https://b.example/x", "https://c.example/"])

        #expect(popups.open(1).map(\.url) == ["https://b.example/x"])
        #expect(popups.waiting.map(\.id) == [0, 2])
        // Chromium still lists the one Cra opened; it stays hidden.
        popups.update(ids: [0, 1, 2], urls: ["https://a.example/", "https://b.example/x", "https://c.example/"])
        #expect(popups.waiting.map(\.id) == [0, 2])

        #expect(popups.open(nil).map(\.id) == [0, 2])
        #expect(popups.waiting.isEmpty)
        #expect(popups.open(nil).isEmpty)
    }

    /// The page navigated: Chromium clears its list, and a later block starts the button again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/357"))
    func navigationClearsTheList() {
        var popups = BlockedPopups()
        popups.update(ids: [0, 1], urls: ["https://a.example/", "https://b.example/"])
        _ = popups.open(0)
        popups.update(ids: [], urls: [])
        #expect(popups.waiting.isEmpty)
        #expect(popups.opened.isEmpty)
        popups.update(ids: [2], urls: ["https://c.example/"])
        #expect(popups.waiting.map(\.id) == [2])
    }

    /// The folder page asks for every tab on the first click, then opens the next one per click: a
    /// tab it opened itself goes off the button, and an address asked for twice is listed once.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/357"))
    func pageOpeningATabTakesItOffTheList() {
        var popups = BlockedPopups()
        popups.update(ids: [0, 1, 2], urls: ["https://b.example/", "https://c.example/", "https://d.example/"])
        let first = popups.markOpened(url: "https://b.example/")
        let again = popups.markOpened(url: "https://b.example/")
        let other = popups.markOpened(url: "https://elsewhere.example/")
        #expect(first && !again && !other)
        #expect(popups.waiting.map(\.url) == ["https://c.example/", "https://d.example/"])
        // The page asked for c and d again; Chromium lists them twice.
        popups.update(ids: [0, 1, 2, 3, 4], urls: ["https://b.example/", "https://c.example/", "https://d.example/",
                                                   "https://c.example/", "https://d.example/"])
        #expect(popups.waiting.map(\.id) == [1, 2])
        // Opening c opens it once and takes both of its entries off.
        let c = popups.open(1)
        #expect(c.map(\.url) == ["https://c.example/"])
        #expect(popups.waiting.map(\.url) == ["https://d.example/"])
        let rest = popups.open(nil)
        #expect(rest.map(\.url) == ["https://d.example/"])
        #expect(popups.waiting.isEmpty)
    }

    @Test func mismatchedListsPairByIndex() {
        var popups = BlockedPopups()
        popups.update(ids: [4, 5, 6], urls: ["https://a.example/"])
        #expect(popups.waiting == [.init(id: 4, url: "https://a.example/")])
    }

    @Test func menuWords() {
        #expect(BlockedPopups.buttonTitle(count: 1) == "Pop-up Blocked")
        #expect(BlockedPopups.buttonTitle(count: 3) == "Pop-ups Blocked")
        #expect(BlockedPopups.heading(count: 1) == "1 Pop-up Blocked on This Page")
        #expect(BlockedPopups.heading(count: 3) == "3 Pop-ups Blocked on This Page")
        #expect(BlockedPopups.openAllTitle(count: 3) == "Open All 3 Pop-ups")
        #expect(BlockedPopups.menuTitle(url: "https://www.example.com/") == "example.com")
        #expect(BlockedPopups.menuTitle(url: "https://example.com/a/") == "example.com/a/")
        #expect(BlockedPopups.menuTitle(url: "about:blank") == "about:blank")
        let long = "https://example.com/" + String(repeating: "x", count: 80)
        #expect(BlockedPopups.menuTitle(url: long).count == 60)
        #expect(BlockedPopups.menuTitle(url: long).hasSuffix("…"))
    }

    /// Chrome's setting is per site, for web pages only.
    @Test func allowsWebSitesOnly() {
        #expect(BlockedPopups.allowTitle(pageURL: "https://www.crabrowser.app/folder#abc") == "Always Allow Pop-ups from crabrowser.app")
        #expect(BlockedPopups.allowTitle(pageURL: "http://localhost:3000/") == "Always Allow Pop-ups from localhost")
        #expect(BlockedPopups.allowTitle(pageURL: "file:///Users/me/page.html") == nil)
        #expect(BlockedPopups.allowTitle(pageURL: "cra://settings") == nil)
    }
}
