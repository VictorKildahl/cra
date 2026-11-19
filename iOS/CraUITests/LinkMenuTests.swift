import XCTest

/// A long press on a link (GitHub #572).
final class LinkMenuTests: BrowserTestCase {
    /// A data: address for a page titled `title`, written to sit inside another data: page as a
    /// link. The app escapes the outer address's `%` once more as it loads it (from a launch
    /// argument or the search field), so `%3C` here is `%3C` in the link and `<` in its page.
    private static func linkedPage(_ title: String) -> String {
        "data:text/html,%3Ctitle%3E\(title)%3C/title%3E%3Ch1%3E\(title)%3C/h1%3E"
    }

    // promise: #572
    /// Arc Search's link menu: "Open in Background Tab" puts the link's page in the tab row and
    /// leaves the page on screen.
    func testALinkOpensInABackgroundTab() {
        let page = "data:text/html,<meta name=viewport content=width=device-width><title>First</title>"
            + "<h1 style=font-family:-apple-system;padding:24px>First</h1>"
            + "<a href=\(Self.linkedPage("Later")) style=font-size:48px;padding:24px>Read later</a>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("First")
        let link = app.webViews.links["Read later"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let background = app.buttons["Open in Background Tab"]
        XCTAssertTrue(background.waitForExistence(timeout: 5), "the link menu offers Open in Background Tab")
        XCTAssertTrue(app.buttons["Open in New Tab"].exists)
        keep("link-menu")
        background.tap()
        XCTAssertFalse(background.waitForExistence(timeout: 2))
        XCTAssertTrue(app.webViews.staticTexts["First"].exists, "the page stays on screen")
        sleep(2)
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the background tab is in the row")
        XCTAssertEqual(card.label, "Later")
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        sleep(1)
        keep("tab-row-with-background-tab")
    }

    // promise: #572
    /// A private tab is the eyes in the search field away (Arc Search's incognito toggle), and a
    /// link on it opens privately too: no background row, and its new tab stays out of the row.
    func testAPrivateTabsLinksStayPrivate() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["search-incognito"].tap()
        XCTAssertTrue(app.staticTexts["incognito-note"].waitForExistence(timeout: 3))
        field.typeText("data:text/html,<title>Secret</title><h1><a/href=\(Self.linkedPage("Hidden"))>Secret</a></h1>\n")
        let link = app.webViews.links["Secret"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.press(forDuration: 1.5)
        let newTab = app.buttons["Open in New Tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open in Background Tab"].exists, "an incognito tab can't wait in the background")
        keep("incognito-link-menu")
        newTab.tap()
        waitForPage("Hidden")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "the link's tab is incognito too")
    }
}
