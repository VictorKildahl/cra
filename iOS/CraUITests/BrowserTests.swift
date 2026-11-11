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

final class BlockingTests: BrowserTestCase {
    /// A page that loads Google Analytics' script and puts what became of it in its title. With
    /// the blockers on the script is stopped at once and the menu counts it; with Block Trackers
    /// off for the page the request is let through and nothing is counted. The tab's card is
    /// asked for the title: web content changed by script does not reach the test's view of the
    /// page.
    func testAListedScriptIsStoppedAndCountedUntilItsBlockerIsSwitchedOff() {
        let page = "data:text/html,<meta name=viewport content='width=device-width'><title>waiting</title><h1>Blocking</h1>"
            + "<script src='https://www.google-analytics.com/analytics.js' onload=\"document.title='script-loaded'\" onerror=\"document.title='script-stopped'\"></script>"
        launch(["-CraOpenURL", page, "-CraSearch", "NO"])
        waitForPage("Blocking")
        app.buttons["bar-menu"].tap()
        let count = app.staticTexts["menu-blocked-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "Scrubbed 1 ad or tracker")
        keep("blocked-count")
        // The page has no site of its own, so its Site Settings are the global ones.
        app.buttons["menu-row-siteSettings"].tap()
        let trackers = app.switches["setting-block-trackers"]
        XCTAssertTrue(trackers.waitForExistence(timeout: 5))
        trackers.switches.firstMatch.tap()
        XCTAssertEqual(trackers.value as? String, "0")
        app.buttons["Done"].tap()
        app.buttons["menu-reload"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(6)
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.staticTexts["menu-host"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["menu-blocked-count"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Let through, the request is the network's business: it loads, or is still on its way on
        // a slow or filtered network. Stopped by a rule it would have failed at once.
        XCTAssertNotEqual(card.label, "script-stopped")
    }
}

final class GestureTests: BrowserTestCase {
    private func drag(fromX: CGFloat, toX: CGFloat, y: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func openSecondTab() {
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.page("Second") + "\n")
        waitForPage("Second")
    }

    /// The title of the tab on screen: opens the tab row, reads the focused card (the selected
    /// tab) and goes back into it.
    private func shownTabTitle() -> String {
        app.buttons["bar-tabs"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        // The focused card is the one whose left edge is 83 pt in.
        let focused = cards.allElementsBoundByIndex.first { abs($0.frame.minX - 83) < 3 }
        let title = focused?.label ?? ""
        focused?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(1)
        return title
    }

    /// A swipe along the bottom bar goes to the neighbouring tab: right for the older one, left
    /// for the newer.
    func testSwipingTheBarMovesBetweenTabs() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openSecondTab()
        drag(fromX: 0.3, toX: 0.9, y: 0.95)
        sleep(1)
        XCTAssertEqual(shownTabTitle(), "First")
        drag(fromX: 0.8, toX: 0.2, y: 0.95)
        sleep(1)
        XCTAssertEqual(shownTabTitle(), "Second")
    }

    /// A swipe right across a tab's first page archives the tab and shows the one before it; the
    /// swipe back left reopens it.
    func testSwipingBackOnAFirstPageArchivesTheTabAndTheOppositeSwipeReopensIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openSecondTab()
        drag(fromX: 0.3, toX: 0.95, y: 0.5)
        sleep(1)
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-card-0"].label, "First")
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "the swiped tab left the row")
        app.buttons["tab-card-0"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(1)
        drag(fromX: 0.8, toX: 0.1, y: 0.5)
        sleep(1)
        XCTAssertEqual(shownTabTitle(), "Second")
    }

    /// Dragging the search sheet down puts it away when there is a page behind it.
    func testDraggingTheSearchSheetDownClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }
}

final class ReadingTests: BrowserTestCase {
    static let article: String = {
        let paragraphs = [
            "Pizza is a dish of Italian origin made of a flattened base of leavened dough topped with tomato and cheese.",
            "The dough rests for a day so that it stretches without tearing and bakes with large bubbles at its edge.",
            "A wood fired oven reaches four hundred degrees and bakes a pizza in about ninety seconds.",
            "Naples protects the recipe of its pizza with rules about flour, tomatoes and the size of the base.",
        ]
        let body = paragraphs.map { "<p>\($0)</p>" }.joined()
        return "data:text/html,<meta name=viewport content='width=device-width'><title>About Pizza</title>"
            + "<nav>Menu Home Shop</nav><article><h1>About Pizza</h1>\(body)</article><footer>Copyright</footer>"
    }()

    /// The Summarize tile shrinks the page into its card and shows the summary with its credit;
    /// the close button brings the page back.
    func testSummarizeShowsTheSummaryAndClosesBackToThePage() {
        launch(["-CraOpenURL", Self.article, "-CraSearch", "NO", "-CraFakeModel", "YES"])
        waitForPage("About Pizza")
        app.buttons["bar-menu"].tap()
        XCTAssertTrue(app.buttons["menu-tile-summarize"].waitForExistence(timeout: 5))
        app.buttons["menu-tile-summarize"].tap()
        let overview = app.staticTexts["summary-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        // The canned model answers with the article's own opening lines: its heading, then its sentences.
        XCTAssertEqual(overview.label, "About Pizza.")
        XCTAssertTrue(app.staticTexts["Summarized for you by Cra"].exists)
        XCTAssertTrue(app.staticTexts["Point 1"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pizza is a dish of Italian origin'")).firstMatch.exists)
        sleep(1)
        keep("summary")
        app.buttons["summary-close"].tap()
        XCTAssertTrue(app.buttons["bar-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["summary-overview"].waitForExistence(timeout: 1))
    }

    /// Reader shows the article without the page's navigation and footer, and the tile closes it again.
    func testReaderShowsTheArticleAlone() {
        launch(["-CraOpenURL", Self.article, "-CraSearch", "NO"])
        waitForPage("About Pizza")
        XCTAssertTrue(app.webViews.staticTexts["Copyright"].exists)
        app.buttons["bar-menu"].tap()
        app.buttons["menu-tile-reader"].tap()
        let reader = app.webViews["reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(reader.staticTexts["About Pizza"].waitForExistence(timeout: 5))
        XCTAssertFalse(reader.staticTexts["Copyright"].exists)
        XCTAssertFalse(reader.staticTexts["Menu Home Shop"].exists)
        sleep(1)
        keep("reader")
        app.buttons["bar-menu"].tap()
        app.buttons["menu-tile-reader"].tap()
        XCTAssertFalse(app.webViews["reader"].waitForExistence(timeout: 2))
    }
}
