import CraCore
import Foundation
import Testing

/// Which sites Cra asks for an icon in the background, and in what order: a sidebar tab, favorite or
/// command-bar row that shows a globe because no icon is stored.
struct SiteIconQueueTests {
    /// A sidebar tab on `url` that reads its icon under the site's key.
    private func tab(_ url: String, visible: Bool = true, incognito: Bool = false) -> SiteIconQueue.Row {
        .init(url: url, iconKey: FaviconKey.key(for: url), visible: visible, incognito: incognito)
    }

    private func drain(_ q: inout SiteIconQueue) -> [String] {
        var out: [String] = []
        while let f = q.next() { out.append(f.host) }
        return out
    }

    @Test func atMostThreeAreInFlight() {
        var q = SiteIconQueue()
        for host in ["a.com", "b.com", "c.com", "d.com"] { q.want(tab("https://\(host)/page")) }
        #expect(drain(&q) == ["a.com", "b.com", "c.com"])
        q.finished("b.com")
        #expect(q.next()?.host == "d.com")
        #expect(q.next() == nil)
    }

    @Test func aVisibleRowsSiteGoesBeforeAnEarlierMarginRow() {
        var q = SiteIconQueue(cap: 1)
        q.want(tab("https://margin.com/", visible: false))
        q.want(tab("https://shown.com/"))
        #expect(q.next()?.host == "shown.com")
        q.finished("shown.com")
        #expect(q.next()?.host == "margin.com")
    }

    @Test func aMarginSiteScrolledIntoViewMovesUp() {
        var q = SiteIconQueue(cap: 1)
        q.want(tab("https://first.com/", visible: false))
        q.want(tab("https://second.com/", visible: false))
        q.want(tab("https://second.com/other"))
        #expect(q.next()?.host == "second.com")
    }

    @Test func aSiteIsAskedOncePerSession() {
        var q = SiteIconQueue()
        q.want(tab("https://GitHub.com/a"))
        q.want(tab("http://github.com/b", visible: false))
        #expect(drain(&q) == ["github.com"])
        // Asked again while its fetch runs, and after it ended.
        let whileRunning = q.want(tab("https://github.com/c"))
        #expect(whileRunning)
        #expect(q.next() == nil)
        q.finished("github.com")
        let afterwards = q.want(tab("https://github.com/d"))
        #expect(!afterwards)
        #expect(q.next() == nil)
    }

    @Test func wantSaysWhetherTheSiteIsStillComing() {
        var q = SiteIconQueue()
        let first = q.want(tab("https://a.com/"))
        let again = q.want(tab("https://a.com/x", visible: false))
        let blank = q.want(.init(url: "about:blank", iconKey: "about", incognito: false))
        #expect(first && again && !blank)
    }

    @Test func onlyHttpAndHttpsAreAsked() {
        var q = SiteIconQueue()
        for url in ["file:///Users/me/a.html", "cra://settings", "about:blank", "data:text/html,hi", "chrome-extension://abc/p.html", "ftp://a.com/", "", "not a url"] {
            q.want(.init(url: url, iconKey: FaviconKey.key(for: url) ?? "x", incognito: false))
        }
        #expect(q.next() == nil)
    }

    @Test func anIncognitoSpaceNeverAsks() {
        var q = SiteIconQueue()
        let asked = q.want(tab("https://secret.com/", incognito: true))
        #expect(!asked)
        #expect(q.next() == nil)
        // Nor does it use up the site's one ask.
        q.want(tab("https://secret.com/"))
        #expect(q.next()?.host == "secret.com")
    }

    @Test func theOriginKeepsSchemeHostAndPort() {
        var q = SiteIconQueue()
        q.want(tab("http://127.0.0.1:8123/deep/page.html?q=1#top"))
        q.want(tab("https://user:pw@Example.com:8443/x"))
        let fetches = [q.next(), q.next()]
        #expect(fetches.map { $0?.origin.absoluteString } == ["http://127.0.0.1:8123/", "https://example.com:8443/"])
        #expect(fetches.map { $0?.host } == ["127.0.0.1", "example.com"])
    }

    @Test func commandBarRowsAskOnlyForSitesTheUserHasBeenTo() {
        var q = SiteIconQueue()
        let url = "https://news.example.com/a"
        let preset = q.want(.init(url: url, iconKey: "news.example.com", preset: true, incognito: false))
        #expect(!preset && q.next() == nil)
        let visited = q.want(.init(url: url, iconKey: "news.example.com", incognito: false))
        #expect(visited && q.next()?.host == "news.example.com")
    }

    @Test func onlyARowReadingTheSitesKeyAsks() {
        var q = SiteIconQueue()
        let url = "https://gitlab.com/group/project"
        for key in [nil, "custom-6f1c9a3e", "github.com", "github.com#tab-6f1c9a3e"] as [String?] {
            q.want(.init(url: url, iconKey: key, incognito: false))
        }
        #expect(q.next() == nil, "no key, a custom icon or another site's key never asks")
        q.want(.init(url: url, iconKey: FaviconKey.key(site: "gitlab.com", tabID: UUID()), incognito: false))
        #expect(q.next()?.host == "gitlab.com", "a tab's own key falls back to the site's")
    }
}
