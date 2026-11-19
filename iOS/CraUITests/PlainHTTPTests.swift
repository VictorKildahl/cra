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

    /// GitHub #568, follow-up: iOS 26.5's WebKit commits an empty about:blank for an address it
    /// refuses, and the error page came after it, so Back from the error page has to skip that
    /// blank and land on the page before. The address is typed into the tab: a link to it does
    /// nothing at all (WebKit drops it in the page before the app hears of it).
    // promise: #568
    func testBackFromARefusedAddressReturnsToThePageBefore() {
        let base = ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765"
        launch(["-CraOpenURL", base + "/before-refused", "-CraSearch", "NO"])
        waitForPage("Before Refused")
        app.buttons["bar-menu"].tap()
        let host = app.staticTexts["menu-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("http://127.0.0.1:1/\n")
        waitForPage("This page couldn’t load")
        // Reload tries the address again and the error page comes back in its place, not after it.
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-reload"].waitForExistence(timeout: 5))
        app.buttons["menu-reload"].tap()
        XCTAssertFalse(host.waitForExistence(timeout: 2))
        waitForPage("This page couldn’t load")
        app.buttons["bar-menu"].tap()
        let back = app.buttons["menu-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isEnabled, "nothing to go back to")
        back.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertFalse(host.waitForExistence(timeout: 2))
        waitForPage("Before Refused")
        XCTAssertFalse(app.webViews.staticTexts["This page couldn’t load"].exists)
        // One Back is the whole way: the page before is the first in the tab.
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(back.isEnabled, "a blank page or a second error page sits between")
        keep("refused-back")
    }
}
