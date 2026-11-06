import CraCore
import Testing

struct FaviconKeyTests {
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
        #expect(tab.faviconKey == "example.org")
    }
}
