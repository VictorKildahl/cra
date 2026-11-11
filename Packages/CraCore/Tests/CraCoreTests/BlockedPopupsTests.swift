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
