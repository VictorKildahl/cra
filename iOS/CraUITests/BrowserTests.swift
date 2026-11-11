import XCTest

/// The app driven by real taps in the simulator. Pages are `data:` addresses, so nothing here
/// needs the network. `scripts/ios.sh test` runs these and saves the screenshots they attach.
class BrowserTestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches on an empty data folder.
    func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-CraDataDir", "fresh"] + arguments
        app.launch()
    }

    /// A page with `title` as its heading. No spaces in the address (typed text with a space is
    /// a search, not an address), so attributes are separated with slashes.
    static func page(_ title: String, color: String = "white") -> String {
        "data:text/html,<meta/name=viewport/content=width=device-width><title>\(title)</title>"
            + "<body/bgcolor=\(color)><h1/style=font-family:-apple-system;padding:24px>\(title)</h1>"
    }

    func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func waitForPage(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.webViews.staticTexts[title].waitForExistence(timeout: 20), "page \(title) never showed", file: file, line: line)
    }
}

final class SearchTests: BrowserTestCase {
    /// Arc Search comes up ready to type: the search field has the keyboard on a first launch.
    func testLaunchesReadyToType() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(field.placeholderValue, "Search...")
        keep("launch")
    }

    /// Typing shows the typed text as the first row, and Go opens it in a new tab.
    func testTypingAnAddressAndGoOpensThePage() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("example")
        XCTAssertTrue(app.staticTexts["example"].waitForExistence(timeout: 5))
        keep("typed")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        field.typeText(Self.page("First") + "\n")
        waitForPage("First")
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        keep("page")
    }

    /// The pill opens search over a page, and a tap above the sheet puts it away again.
    func testThePillOpensSearchAndATapAboveClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        keep("search-over-page")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
}

final class TabSwitcherTests: BrowserTestCase {
    private func openTwoTabs() {
        launch(["-CraOpenURL", Self.page("First", color: "%23ffe9d6"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.page("Second", color: "%23d6ecff") + "\n")
        waitForPage("Second")
    }

    /// The tab stack opens the row of cards, newest in focus; a tap on the older card opens it.
    func testTheRowShowsEveryTabAndATapOpensOne() {
        openTwoTabs()
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bar-archive"].exists)
        XCTAssertTrue(app.buttons["bar-settings"].exists)
        sleep(1)
        keep("tab-row")
        // The older card is tucked behind the newest: only its left edge can be tapped.
        app.buttons["tab-card-0"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        waitForPage("First")
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
    }

    /// Throwing a card upwards closes its tab; the last one gone leaves the search sheet.
    func testThrowingACardUpClosesItsTab() {
        openTwoTabs()
        app.buttons["bar-tabs"].tap()
        let newest = app.buttons["tab-card-1"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        sleep(1)
        newest.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-card-1"].waitForExistence(timeout: 2))
        keep("tab-row-after-close")
        app.buttons["tab-card-0"].swipeUp(velocity: .fast)
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }
}

final class PageMenuTests: BrowserTestCase {
    /// The up arrow opens the menu on the page's site, with Arc Search's tiles and rows.
    func testTheMenuShowsThePageAndItsControls() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.staticTexts["menu-host"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["menu-host"].label, "example.com")
        for tile in ["reader", "copyLink", "share"] { XCTAssertTrue(app.buttons["menu-tile-\(tile)"].exists, tile) }
        for row in ["findOnPage", "requestDesktopSite", "translate", "siteSettings"] { XCTAssertTrue(app.buttons["menu-row-\(row)"].exists, row) }
        XCTAssertFalse(app.buttons["menu-back"].isEnabled)
        sleep(1)
        keep("page-menu")
        // Zooming shows the percentage, and a tap on it goes back to the page's own size.
        app.buttons["menu-zoom-in"].tap()
        XCTAssertEqual(app.buttons["menu-zoom-value"].label, "110%")
        app.buttons["menu-zoom-value"].tap()
        XCTAssertFalse(app.buttons["menu-zoom-value"].exists)
        // A tap on the dimmed page puts the menu away.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertFalse(app.staticTexts["menu-host"].waitForExistence(timeout: 2))
    }

    /// Copy Link acts and puts the menu away. (That trackers are left out is CleanURL's test.)
    func testCopyLinkPutsTheMenuAway() {
        launch(["-CraOpenURL", Self.page("First") + "?utm_source=test", "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-copyLink"].waitForExistence(timeout: 5))
        app.buttons["menu-tile-copyLink"].tap()
        XCTAssertFalse(app.staticTexts["menu-host"].waitForExistence(timeout: 2))
    }
}

final class SettingsTests: BrowserTestCase {
    /// Site Settings opens from the page menu on the page's site, and a switch flipped there is
    /// still flipped when the sheet is opened again.
    func testSiteSettingsKeepsASitesChoice() {
        launch(["-CraOpenURL", "https://example.com/", "-CraSearch", "NO"])
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 10))
        app.buttons["bar-menu"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        XCTAssertTrue(app.staticTexts["EXAMPLE.COM SETTINGS"].waitForExistence(timeout: 5))
        let ads = app.switches["setting-block-ads"]
        XCTAssertEqual(ads.value as? String, "1")
        sleep(1)
        keep("site-settings")
        ads.switches.firstMatch.tap()
        XCTAssertEqual(ads.value as? String, "0")
        app.buttons["Done"].tap()
        app.buttons["menu-row-siteSettings"].tap()
        XCTAssertTrue(app.switches["setting-block-ads"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["setting-block-ads"].value as? String, "0")
        // App Settings is one step further, with the global options behind their own row.
        XCTAssertTrue(app.buttons["setting-app-settings"].waitForExistence(timeout: 5))
        app.buttons["setting-app-settings"].tap()
        XCTAssertTrue(app.buttons["setting-global-site-settings"].waitForExistence(timeout: 5))
        sleep(1)
        keep("app-settings")
        app.buttons["setting-global-site-settings"].tap()
        XCTAssertTrue(app.switches["setting-block-ads"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["setting-block-ads"].value as? String, "1", "the site's choice leaves the global one alone")
    }

    /// A tab thrown out of the row is in the Archive, and a tap there brings it back.
    func testAnArchivedTabComesBackFromTheArchive() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        app.textFields["search-field"].typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["tab-card-1"].swipeUp(velocity: .fast)
        XCTAssertFalse(app.buttons["tab-card-1"].waitForExistence(timeout: 2))
        app.buttons["bar-settings"].tap()
        XCTAssertTrue(app.buttons["settings-archive"].waitForExistence(timeout: 5))
        app.buttons["settings-archive"].tap()
        let row = app.buttons["archive-row-Second"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TODAY"].exists)
        sleep(1)
        keep("archive")
        row.tap()
        waitForPage("Second")
    }
}
