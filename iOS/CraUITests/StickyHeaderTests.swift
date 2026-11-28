import XCTest

/// The page's content starts below the status band, so a sticky header never slides under it.
final class StickyHeaderTests: BrowserTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // shortcut: only the iPhone Duo simulator is known here; revisit for other non-top status bars.
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
            throw XCTSkip("The status bar is a right-hand column or a top-right cluster, the top safe area is 0, and whether the band belongs there is an open product question (duo research, finding 8)")
        }
    }

    func testAStickyHeaderStaysBelowTheStatusBand() {
        let rows = String(repeating: "<p>Row</p>", count: 80)
        // Spaces, not slashes, between attributes: -CraOpenURL percent-encodes the address, and WebKit decodes it
        // once, so this arrives as written. `<meta/name=viewport/...>` named no viewport (an unquoted value runs on
        // past "/"), and the page laid out 980 px wide at 0.41 zoom, where the sticky header pinned above the view.
        let page = "data:text/html,<meta name=viewport content=width=device-width>"
            + "<body style=margin:0>"
            + "<div style=position:sticky;top:0;background:red;height:80px;z-index:10><p>STICKY</p></div>"
            + rows
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        let header = app.webViews.staticTexts["STICKY"]
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        app.webViews.firstMatch.swipeUp()
        sleep(1)
        XCTAssertTrue(header.exists, "the sticky header is still on screen")
        // Under the band it would sit in the top strip; the smallest safe area plus the
        // paragraph's margin still clears this.
        XCTAssertGreaterThan(header.frame.minY, 30, "the sticky header is under the band: \(header.frame)")
        keep("sticky header")
    }
}
