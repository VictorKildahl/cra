import XCTest

/// Root starts `python3 iOS/Tests/popup_server.py` on loopback before running this class.
/// Only synthetic form/cookie values are used; no model, clipboard or external site is involved.
final class PopupTests: BrowserTestCase {
    private var source: String {
        (ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765") + "/source"
    }

    private func openSource() {
        launch(["-CraOpenURL", source, "-CraSearch", "NO"])
        waitForPage("Popup Source")
    }

    private func postAndClose(returningTo title: String, mode: String) {
        let post = app.webViews.buttons["Post to popup"]
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()
        waitForPage("POST preserved")
        XCTAssertTrue(app.webViews.staticTexts["Body: order=synthetic-123&mode=\(mode)"].exists, "full POST body survived")
        XCTAssertTrue(app.webViews.staticTexts["Source cookie shared"].exists, "popup uses the source's website data store")
        XCTAssertTrue(app.webViews.staticTexts["Opener available"].exists, "related view keeps the opted-in opener")
        // WebKit sometimes reports a visible related-view button as not hittable to XCTest.
        app.webViews.buttons["Reply and close"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForPage(title)
        XCTAssertTrue(app.webViews.staticTexts["Popup reply received"].waitForExistence(timeout: 10), "source receives postMessage and survives window.close")
    }

    func testPostBodyRelatedSessionAndCloseReturnToNormalSource() {
        openSource()
        postAndClose(returningTo: "Popup Source", mode: "normal")
        // A second popup also works: its script handler setup did not replace the opener's.
        postAndClose(returningTo: "Popup Source", mode: "normal")
    }

    func testBlankPopupReturnsAWindowHandleAndKeepsItsOpener() {
        openSource()
        app.webViews.buttons["Open blank popup"].tap()
        waitForPage("Blank Popup")
        XCTAssertTrue(app.webViews.staticTexts["Opener handle preserved"].exists)
        // WebKit sometimes reports a visible related-view button as not hittable to XCTest.
        app.webViews.buttons["Reply and close"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForPage("Popup Source")
        XCTAssertTrue(app.webViews.staticTexts["Popup reply received"].waitForExistence(timeout: 10))
    }

    func testPrivatePopupSharesOnlyItsPrivateSourceAndClosesBackToIt() {
        openSource()
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["search-incognito"].tap()
        field.typeText(source + "?private=1\n")
        waitForPage("Private Popup Source")
        XCTAssertTrue(app.webViews.staticTexts["Normal cookie absent"].exists, "incognito source is isolated from normal browsing")
        postAndClose(returningTo: "Private Popup Source", mode: "private")
        app.buttons["bar-tabs"].tap()
        let normal = app.buttons["tab-card-0"]
        XCTAssertTrue(normal.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "neither private popup nor its retained source appears in the row")
        normal.tap()
        waitForPage("Popup Source")
    }
}
