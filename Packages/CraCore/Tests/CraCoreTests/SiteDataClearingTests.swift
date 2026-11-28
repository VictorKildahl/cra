import Testing
@testable import CraCore

@Suite("Clearing a site's data")
struct SiteDataClearingTests {
    @Test("Clear Site Data clears everything the page's origin keeps, only that origin, and reloads past the cache",
          .bug("https://github.com/VictorKildahl/cra/issues/853"))
    func siteDataClearsTheWholeOriginOnly() {
        let plan = SiteDataClearing.plan(.siteData, address: "https://App.Example.com:8443/inbox?x=1#top")
        #expect(plan == .init(call: .init(method: "Storage.clearDataForOrigin",
                                          params: ["origin": "https://app.example.com:8443", "storageTypes": "all"]),
                              reload: .ignoringCache))
        // Another page of the same site names the same origin, a sibling subdomain doesn't.
        #expect(SiteDataClearing.origin(of: "https://app.example.com:8443/") == "https://app.example.com:8443")
        #expect(SiteDataClearing.origin(of: "https://www.example.com/") == "https://www.example.com")
    }

    @Test("Arc's two clearing commands keep what they did: this site's cookies, or the HTTP cache",
          .bug("https://github.com/VictorKildahl/cra/issues/853"))
    func cookiesAndCacheStayArcs() {
        #expect(SiteDataClearing.plan(.cookies, address: "http://127.0.0.1:8080/a") ==
                .init(call: .init(method: "Storage.clearDataForOrigin", params: ["origin": "http://127.0.0.1:8080", "storageTypes": "cookies"]),
                      reload: .normal))
        #expect(SiteDataClearing.plan(.cache, address: "https://example.com/") ==
                .init(call: .init(method: "Network.clearBrowserCache", params: [:]), reload: .normal))
    }

    @Test("A page without a site has nothing to clear", .bug("https://github.com/VictorKildahl/cra/issues/853"))
    func noSiteNoPlan() {
        for kind in SiteDataClearing.Kind.allCases {
            #expect(SiteDataClearing.plan(kind, address: "") == nil)
            #expect(SiteDataClearing.plan(kind, address: "about:blank") == nil)
        }
    }

    @Test("The site menu's … has Clear Site Data right after Arc's Clear Cache and Clear Cookies",
          .bug("https://github.com/VictorKildahl/cra/issues/853"))
    func siteMenuRow() {
        #expect(SiteMoreMenu.groups.first == [.clearCache, .clearCookies, .clearSiteData])
        #expect(SiteMoreMenu.groups.flatMap { $0 }.map(\.title) == ["Clear Cache", "Clear Cookies", "Clear Site Data",
                                                                    "Manage Boosts…", "New Boost…", "Manage Extensions…",
                                                                    "Add Extension…", "All Site Settings"])
    }
}
