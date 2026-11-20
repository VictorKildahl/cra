import XCTest

/// Sideways drags and pinches on a page: what scrolls, what zooms, and what goes Back.
final class PageGestureTests: BrowserTestCase {
    /// A page with a carousel under its heading: a 300 pt high strip whose content is 2000 px wide,
    /// with words at its start and far along it.
    static let carousel = page("Wide")
        + "<div/style=overflow-x:auto;height:300px><div/style=width:2000px;height:300px;position:relative;background:linear-gradient(90deg,gold,teal)>"
        + "<p/style=position:absolute;left:20px;font-size:30px>Start</p><p/style=position:absolute;left:600px;font-size:30px>Further</p>"
        + "</div></div>"

    /// A quick drag, or with `settle` a slow one held at its end, so the page doesn't coast on.
    private func drag(fromX: CGFloat, toX: CGFloat, y: CGFloat, settle: Bool = false) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: settle ? .slow : .fast, thenHoldForDuration: settle ? 0.4 : 0)
        sleep(1)
    }

    private func openTab(_ address: String, title: String) {
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(address + "\n")
        waitForPage(title)
    }

    /// The tabs in the row, by title.
    private func rowTitles() -> [String] {
        // Scrolling may have put the bar away: a tap on the bottom edge brings it back (#509).
        if !app.buttons["bar-tabs"].isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995)).tap()
            waitForBarOnScreen()
        }
        app.buttons["bar-tabs"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        return cards.allElementsBoundByIndex.map(\.label)
    }

    // promise: #627
    /// A carousel scrolls under a sideways drag both ways. Before, the drag went to Back: on a
    /// tab's first page that put the tab in the archive.
    func testACarouselScrollsSidewaysInsteadOfGoingBack() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab(Self.carousel, title: "Wide")
        let further = app.webViews.staticTexts["Further"]
        XCTAssertTrue(further.waitForExistence(timeout: 5))
        let before = further.frame.minX

        // Along the carousel, which is under the heading.
        let y = (app.webViews.staticTexts["Start"].frame.midY) / app.frame.height
        drag(fromX: 0.85, toX: 0.15, y: y)
        let scrolled = further.frame.minX
        XCTAssertLessThan(scrolled, before - 100, "the carousel scrolled with the drag")
        keep("carousel scrolled")

        drag(fromX: 0.15, toX: 0.85, y: y)
        XCTAssertTrue(app.webViews.staticTexts["Wide"].exists, "the drag back scrolled the carousel; it didn't go Back")
        XCTAssertGreaterThan(further.frame.minX, scrolled + 100, "and the carousel came back")
        XCTAssertEqual(rowTitles(), ["First", "Wide"], "the tab is still in the row")
    }

    // promise: #627
    // promise: #628
    /// Pinched open, the page zooms; a sideways drag then moves around the zoomed page, and only
    /// at its left end does a drag right go Back.
    func testAZoomedPageScrollsSidewaysAndItsEndGoesBack() {
        // A desktop-width page tiled with words, so some word is on screen wherever the pinch lands.
        let rows = (0..<11).map { row in "<tr>" + (0..<5).map { "<td>W\(row * 5 + $0)</td>" }.joined() + "</tr>" }.joined()
        let zoomedPage = Self.page("Zoomed") + "<table/style=width:100%;font-size:40px;line-height:200px>\(rows)</table>"
        launch(["-CraOpenURL", zoomedPage, "-CraSearch", "NO"])
        waitForPage("Zoomed")
        openTab(Self.page("First"), title: "First")
        // Back to the zoomed page's tab, the older one, along the bar.
        drag(fromX: 0.3, toX: 0.9, y: 0.95)
        waitForPage("Zoomed")
        let probe = app.webViews.staticTexts["W27"]
        let normal = probe.frame.width

        app.webViews.firstMatch.pinch(withScale: 3, velocity: 4)
        sleep(1)
        keep("zoomed")
        // A word well inside the screen, which a short drag either way keeps on it.
        let words = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'W'")).allElementsBoundByIndex
        guard let word = words.first(where: { (90...300).contains($0.frame.minX) && $0.frame.maxX < app.frame.width
                                               && (150...600).contains($0.frame.midY) }) else {
            return XCTFail("no word inside the screen after the pinch")
        }
        XCTAssertGreaterThan(word.frame.width, normal * 1.5, "the pinch zoomed the page")

        // Zoomed in, a drag left moves the page along (Forward has nowhere to go: before #627
        // the page only dragged its feet)...
        let zoomedX = word.frame.minX
        drag(fromX: 0.6, toX: 0.4, y: 0.5, settle: true)
        let along = word.frame.minX
        XCTAssertLessThan(along, zoomedX - 40, "the page moved with the finger")
        keep("moved along")
        // ...and a drag right brings it back instead of going Back.
        drag(fromX: 0.4, toX: 0.6, y: 0.5, settle: true)
        XCTAssertTrue(app.webViews.staticTexts["Zoomed"].exists, "the drag moved around the page; it didn't go Back")
        XCTAssertGreaterThan(word.frame.minX, along + 40, "and back the other way")
        XCTAssertEqual(rowTitles(), ["Zoomed", "First"])
        app.buttons["tab-card-0"].tap()
        XCTAssertTrue(app.buttons["bar-tabs"].waitForExistence(timeout: 5))
        sleep(1)

        // Dragged right until the page's left end is on screen, the next drag right goes Back,
        // which on a tab's first page archives the tab.
        for _ in 0..<5 { drag(fromX: 0.2, toX: 0.9, y: 0.5) }
        XCTAssertEqual(rowTitles(), ["First"], "past the page's left end, the drag went Back")
    }
}
