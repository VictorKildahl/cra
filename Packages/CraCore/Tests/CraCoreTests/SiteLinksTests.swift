import CraCore
import Testing

/// Visits from the app's buttons showed up as "Direct / None" on the site's analytics.
struct SiteLinksTests {
    @Test func tagsSiteLinksWithTheButton() {
        #expect(SiteLinks.tagged("https://crabrowser.app/release-notes", from: .whatsNew)
            == "https://crabrowser.app/release-notes?utm_source=cra-app&utm_campaign=whats-new")
        #expect(SiteLinks.tagged("https://www.crabrowser.app/help", from: .helpMenu)
            == "https://www.crabrowser.app/help?utm_source=cra-app&utm_campaign=help-menu")
    }

    @Test func keepsOtherParametersAndTheFragment() {
        #expect(SiteLinks.tagged("https://crabrowser.app/help/protected-media?x=1#spotify", from: .protectedMedia)
            == "https://crabrowser.app/help/protected-media?x=1&utm_source=cra-app&utm_campaign=protected-media#spotify")
    }

    @Test func replacesATagAlreadyThere() {
        #expect(SiteLinks.tagged("https://crabrowser.app/?utm_campaign=old&utm_source=x", from: .helpMenu)
            == "https://crabrowser.app/?utm_source=cra-app&utm_campaign=help-menu")
    }

    @Test(arguments: ["https://github.com/VictorKildahl/cra/issues", "http://crabrowser.app/help",
                      "https://crabrowser.app.evil.example/", "https://evilcrabrowser.app/", "not a url"])
    func leavesEverythingElseAlone(url: String) {
        #expect(SiteLinks.tagged(url, from: .helpMenu) == url)
    }
}
