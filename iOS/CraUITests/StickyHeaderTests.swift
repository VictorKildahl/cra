import XCTest

/// The page's content starts below the status band, so a sticky header never slides under it.
final class StickyHeaderTests: BrowserTestCase {
    func testAStickyHeaderStaysBelowTheStatusBand() {
        let rows = String(repeating: "<p>Row</p>", count: 80)
        let page = "data:text/html,<meta/name=viewport/content=width=device-width>"
            + "<body/style=margin:0>"
            + "<div/style=position:sticky;top:0;background:%23ff0000;height:80px;z-index:10><p>STICKY</p></div>"
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
