import CraCore
import Foundation
import Testing

struct FaviconKeyTests {
    @Test func tabKeysAreIndependentAndStable() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let key = FaviconKey.key(site: "gitlab.com", tabID: first)
        #expect(key == "gitlab.com#tab-00000000-0000-0000-0000-000000000001")
        #expect(key != FaviconKey.key(site: "gitlab.com", tabID: second))
        #expect(key != FaviconKey.key(site: "example.org", tabID: first))
        #expect(FaviconKey.siteKey(of: key) == "gitlab.com")
        #expect(FaviconKey.key(after: key, goingTo: "https://gitlab.com/projects/pr1") == key)
        #expect(FaviconKey.key(after: key, goingTo: "https://example.org/") == "example.org")
    }

    @Test(arguments: [
        ("https://Mail.Example.com/inbox?x=1", "mail.example.com" as String?),
        ("http://localhost:3000/", "localhost"),
        ("https://www.example.com/", "www.example.com"),
        ("notes", nil),
        ("about:blank", nil),
        ("file:///tmp/a.html", nil),
    ])
    func keyIsTheLowercasedHost(url: String, key: String?) {
        #expect(FaviconKey.key(for: url) == key)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/211"))
    func tabsOnOneHostKeepTheirOwnIcons() throws {
        let rds = try #require(FaviconKey.key(for: "https://console.aws.amazon.com/rds/home", iconURL: "https://a.b/rds.ico"))
        let eks = try #require(FaviconKey.key(for: "https://console.aws.amazon.com/eks/home", iconURL: "https://a.b/eks.ico"))
        let app1 = try #require(FaviconKey.key(for: "http://localhost:3000/", iconURL: "http://localhost:3000/favicon.ico"))
        let app2 = try #require(FaviconKey.key(for: "http://localhost:5173/", iconURL: "http://localhost:5173/favicon.ico"))
        #expect(rds != eks && app1 != app2)
        #expect(FaviconKey.siteKey(of: rds) == "console.aws.amazon.com" && FaviconKey.siteKey(of: app1) == "localhost")
        // The key names a file on disk: it must not change between launches.
        #expect(FaviconKey.key(site: "localhost", iconURL: "http://localhost:3000/favicon.ico") == app1)
        #expect(FaviconKey.key(site: "localhost", iconURL: "") == "localhost")
        #expect(FaviconKey.siteKey(of: "custom-abc") == "custom-abc")
    }

    @Test func aNavigationKeepsTheIconOnTheSameHost() {
        let own = FaviconKey.key(site: "localhost", iconURL: "http://localhost:3000/favicon.ico")
        #expect(FaviconKey.key(after: own, goingTo: "http://localhost:3000/settings") == own)
        #expect(FaviconKey.key(after: own, goingTo: "https://example.org/") == "example.org")
        #expect(FaviconKey.key(after: nil, goingTo: "https://example.org/") == "example.org")
        #expect(FaviconKey.key(after: own, goingTo: "about:blank") == own)
    }

    @Test func backToThePinnedPageKeepsItsIconOnTheSameHost() {
        var tab = TabData(url: "https://example.org/home")
        tab.url = "https://other.net/page"
        tab.faviconKey = FaviconKey.key(site: "other.net", iconURL: "https://other.net/i.png")
        tab.returnHome()
        // The home's section, which falls back to its host (#909).
        #expect(tab.faviconKey == "example.org/home")
    }
}

/// One host, many apps (#909): docs.google.com serves Docs, Sheets and Slides, and an address serves
/// a different app on each port. A tab that hasn't got its own icon yet falls back to its part of the
/// host, never to whichever app on the host loaded last.
struct FaviconSectionTests {
    /// The keys a favicon cache that holds `stored` would draw `key` from: the first one found down
    /// its fallback chain, as FaviconCache reads.
    private func drawn(_ key: String?, stored: [String: String]) -> String? {
        key.flatMap { FaviconKey.chain(of: $0).lazy.compactMap { stored[$0] }.first }
    }

    /// What BrowserManager stores when a tab's page sends its icon: under every key of its chain.
    private func store(_ icon: String, tab: UUID, url: String, into stored: inout [String: String]) -> String {
        let key = FaviconKey.key(site: FaviconKey.sectionKey(for: url)!, tabID: tab)
        for k in FaviconKey.chain(of: key) { stored[k] = icon }
        return key
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/909"))
    func aPinnedSheetsTabDoesNotTakeTheIconOfDocsOpenedLater() throws {
        var stored: [String: String] = [:]
        // Pinned sheets.google.com redirects to docs.google.com and is closed before its icon comes.
        var sheets = TabData(url: "https://sheets.google.com/")
        sheets.url = "https://docs.google.com/spreadsheets?usp=direct_url"
        sheets.faviconKey = FaviconKey.key(after: sheets.faviconKey, goingTo: sheets.url)
        // A Sheets page seen once, then a Docs page on the same host.
        _ = store("sheets", tab: UUID(), url: "https://docs.google.com/spreadsheets/d/1/edit", into: &stored)
        let docs = store("docs", tab: UUID(), url: "https://docs.google.com/document/d/2/edit", into: &stored)
        #expect(drawn(sheets.faviconKey, stored: stored) == "sheets")
        #expect(drawn(docs, stored: stored) == "docs")
        // The command bar's row for a Sheets address too.
        #expect(drawn(FaviconKey.sectionKey(for: "https://docs.google.com/spreadsheets/d/3"), stored: stored) == "sheets")
        // Nothing for the section yet: the row has no icon of its own, and the queue asks for that part of the host.
        let slides = try #require(FaviconKey.sectionKey(for: "https://docs.google.com/presentation/d/4"))
        #expect(!FaviconKey.ownKeys(of: slides).contains { stored[$0] != nil })
        var queue = SiteIconQueue()
        queue.want(.init(url: "https://docs.google.com/presentation/d/4", iconKey: slides, incognito: false))
        let next = queue.next()
        let fetch = try #require(next)
        #expect(fetch.host == "docs.google.com/presentation" && fetch.origin.absoluteString == "https://docs.google.com/presentation")
    }

    /// A section's icon comes from the section's own page, even when its key had to change the segment.
    @Test(arguments: [
        ("https://docs.google.com/spreadsheets/d/1/edit?x#y", "https://docs.google.com/spreadsheets"),
        ("https://example.org/%23odd/page", "https://example.org/%23odd"),
        ("https://example.org/" + String(repeating: "a", count: 80) + "/b", "https://example.org/" + String(repeating: "a", count: 80)),
        ("https://user:pw@Example.org:8443/app", "https://example.org:8443/app"),
        ("https://example.org/", "https://example.org/"),
    ])
    func aSectionIsFetchedFromItsOwnPage(url: String, origin: String) throws {
        var queue = SiteIconQueue()
        queue.want(.init(url: url, iconKey: FaviconKey.sectionKey(for: url), incognito: false))
        let next = queue.next()
        let fetch = try #require(next)
        #expect(fetch.origin.absoluteString == origin)
        #expect(fetch.host == FaviconKey.sectionKey(for: url))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/909"))
    func appsOnOneAddressKeepTheirOwnIcons() {
        var stored: [String: String] = [:]
        let proxmox = store("proxmox", tab: UUID(), url: "https://192.168.8.2:8006/", into: &stored)
        _ = store("router", tab: UUID(), url: "http://192.168.8.2/", into: &stored)
        #expect(drawn(proxmox, stored: stored) == "proxmox")
        #expect(drawn(FaviconKey.sectionKey(for: "https://192.168.8.2:8006/#v1:0:18"), stored: stored) == "proxmox")
        #expect(drawn(FaviconKey.sectionKey(for: "http://192.168.8.2/admin"), stored: stored) == "router")
    }

    @Test(arguments: [
        ("https://Docs.Google.com/spreadsheets/d/1/edit?x#y", "docs.google.com/spreadsheets" as String?),
        ("https://example.org/", "example.org"),
        ("https://example.org", "example.org"),
        ("https://example.org:443/a", "example.org/a"),
        ("http://localhost:3000/settings/x", "localhost:3000/settings"),
        ("http://[::1]:8080/", "[::1]:8080"),
        ("https://a.com/%23odd", "a.com/_odd"),
        ("about:blank", nil),
        ("notes", nil),
    ])
    func theSectionIsTheHostItsPortAndTheFirstPathSegment(url: String, key: String?) {
        #expect(FaviconKey.sectionKey(for: url) == key)
    }

    @Test func aKeyFallsBackToItsSectionThenItsHost() {
        #expect(FaviconKey.chain(of: "docs.google.com/spreadsheets#tab-1") == ["docs.google.com/spreadsheets#tab-1", "docs.google.com/spreadsheets", "docs.google.com"])
        #expect(FaviconKey.chain(of: "localhost:3000/settings") == ["localhost:3000/settings", "localhost:3000", "localhost"])
        #expect(FaviconKey.chain(of: "[::1]:8080") == ["[::1]:8080", "[::1]", "::1"])
        #expect(FaviconKey.chain(of: "github.com#tab-1") == ["github.com#tab-1", "github.com"])
        #expect(FaviconKey.chain(of: "custom-abc") == ["custom-abc"])
        // A row's own icon stops short of the bare host, which every page on it overwrites; a host's own key is its own.
        #expect(FaviconKey.ownKeys(of: "docs.google.com/spreadsheets#tab-1") == ["docs.google.com/spreadsheets#tab-1", "docs.google.com/spreadsheets"])
        #expect(FaviconKey.ownKeys(of: "github.com") == ["github.com"])
        #expect(FaviconKey.hostKey(of: "localhost:3000/settings#tab-1") == "localhost")
    }
}
