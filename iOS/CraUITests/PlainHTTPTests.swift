import XCTest

/// Plain-http pages, and pages that fail to load. `scripts/ios.sh test` starts
/// `iOS/Tests/popup_server.py` on loopback and passes its address as CRA_POPUP_TEST_BASE_URL; run by
/// hand, start it yourself (port 18765). No external site is involved.
final class PlainHTTPTests: BrowserTestCase {
    /// The fixture by a domain name. App Transport Security lets IP addresses and a bare
    /// `localhost` through, so only a dotted name shows what happens to a real http:// site;
    /// `cra.localhost` resolves to the loopback without the network.
    private var plainPage: String {
        let base = ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
        return base.replacingOccurrences(of: "127.0.0.1", with: "cra.localhost") + "/plain"
    }

    /// GitHub #568: every http:// address opened as a blank white page. The app had no
    /// NSAppTransportSecurity entry, so iOS refused each plain-http load in the web view (error
    /// -1022), and nothing said so. Arc Search, Safari and Cra for Mac open them.
    // promise: #568
    func testAPlainHTTPPageLoads() {
        launch(["-CraOpenURL", plainPage, "-CraSearch", "NO"])
        waitForPage("Plain HTTP Fixture")
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.label, "Plain HTTP Fixture", "the tab holds the page, not a blank one")
        keep("plain-http")
    }

    /// GitHub #568: a page that can't load said nothing; only a certificate error had a message.
    /// Now the tab says it couldn't load, and why (here nothing listens on port 4; WebKit refuses port 1 itself).
    // promise: #568
    func testAPageThatCantLoadSaysSo() {
        launch(["-CraOpenURL", "http://127.0.0.1:4/", "-CraSearch", "NO"])
        waitForPage("This page couldn’t load")
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "127.0.0.1: ")).firstMatch.exists,
                      "the error names the host and the reason")
        keep("load-failed")
    }

    /// GitHub #568, follow-up: an address WebKit refuses itself still opened as a blank white
    /// page. Port 1 is on WebKit's restricted list; iOS 26.5's WebKit answers it with an empty
    /// about:blank, a newer one with WebKitErrorDomain 103, and both must say so.
    // promise: #568
    func testAnAddressWebKitRefusesSaysSo() {
        launch(["-CraOpenURL", "http://127.0.0.1:1/", "-CraSearch", "NO"])
        waitForPage("This page couldn’t load")
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "127.0.0.1: ")).firstMatch.exists,
                      "the error names the host and the reason")
        keep("load-refused")
    }
}
