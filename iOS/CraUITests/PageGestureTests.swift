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
        // The rightmost fifth includes the closed Duo's status column; keep page drags clear.
        // shortcut: only the iPhone Duo simulator's model id is known; revisit for a real Duo or other side status bars.
        let window = app.windows.firstMatch
        let maxX: CGFloat = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"
            && window.frame.width < window.frame.height ? 0.8 : 0.99
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: min(maxX, max(0.01, fromX)), dy: min(0.99, max(0.01, y))))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: min(maxX, max(0.01, toX)), dy: min(0.99, max(0.01, y))))
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

    // MARK: What the swipe shows while it goes

    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    /// The lines of the last swipe's trace (`-CraTracePageSwipe YES`).
    private func swipeTrace() -> [String] {
        let trace = app.descendants(matching: .any)["page-swipe-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 2))
        return (trace.value as? String ?? "").split(separator: "\n").map(String.init)
    }

    /// The numbers on a trace line, after its words.
    private func numbers(_ line: String) -> [CGFloat] {
        line.split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
    }

    /// Arc Search shows the page Back goes to underneath while the finger drags the page away, moving at a third of
    /// its speed from a third of the screen off to the left. Before, nothing was under the page, and the page it went
    /// to faded in afterwards.
    func testSwipingBackShowsThePageItGoesBackToUnderneath() {
        launch(["-CraOpenURL", base + "/swipe-first", "-CraSearch", "NO", "-CraTracePageSwipe", "YES"])
        waitForPage("Swipe First")
        sleep(1)
        let heading = app.webViews.staticTexts["Swipe First"].frame.minY
        app.webViews.links["Next page"].tap()
        waitForPage("Swipe Second")
        sleep(1)
        drag(fromX: 0.3, toX: 0.8, y: 0.5, settle: true)
        waitForPage("Swipe First")
        let lines = swipeTrace()
        XCTAssertEqual(lines.first, "back picture kept", "the page it went back to was underneath as a picture: \(lines)")
        let width = app.windows.firstMatch.frame.width
        let moves = lines.filter { $0.hasPrefix("edge ") }.map(numbers)
        XCTAssertGreaterThan(moves.count, 5, "the pages followed the finger: \(lines)")
        // Mid-way, the page underneath is a third of the page's way still to go off to the left.
        guard let mid = moves.first(where: { $0[0] > width * 0.3 && $0[0] < width * 0.6 }) else {
            return XCTFail("no frame mid-way: \(lines)")
        }
        XCTAssertEqual(mid[1], -(width - mid[0]) / 3, accuracy: 1, "the page underneath moves at a third of the speed")
        // Arc Search's magnet: the page holds back at 0.28 of the finger's way until it has come 21 pt, the finger 75 pt
        // in, and lets go there with a tick.
        guard let held = moves.first(where: { $0[2] > 20 && $0[2] < 60 }) else { return XCTFail("no held frame: \(lines)") }
        XCTAssertEqual(held[0], held[2] * 0.28, accuracy: 2, "held, the page moves 0.28 of the finger's way")
        let letGo = lines.first { $0.hasPrefix("let go with the finger at ") }.map(numbers)?.first
        XCTAssertEqual(letGo ?? 0, 75, accuracy: 15, "the magnet let go with the finger about 75 pt in: \(lines)")
        XCTAssertTrue(lines.contains("went back"))
        sleep(2)
        XCTAssertTrue(swipeTrace().contains { $0.hasPrefix("lifted after ") }, "the picture came off once the page drew")
        // The page is back where it was, as its picture showed it, so nothing jumps as the picture gives way. (Before
        // the page began under the status band, WebKit put it back a status bar higher than that.)
        XCTAssertEqual(app.webViews.staticTexts["Swipe First"].frame.minY, heading, accuracy: 2,
                       "the page came back where it was left")
        keep("back")
    }

    /// Arc Search's Back on a tab's first page: the page shrinks into a card and the tab before it comes out of the
    /// tab button's front card into one beside it, 20 pt to its left; let go, the tab closes into the archive.
    func testSwipingBackOnAFirstPageBringsTheTabBeforeItOutOfTheTabButton() {
        launch(["-CraOpenURL", Self.page("First", color: "gold"), "-CraSearch", "NO", "-CraTracePageSwipe", "YES"])
        waitForPage("First")
        openTab(Self.page("Second"), title: "Second")
        sleep(1)
        let button = app.buttons["bar-tabs"].frame
        // Past where the magnet lets go of a closing tab, the finger 185 pt in.
        drag(fromX: 0.15, toX: 0.85, y: 0.5, settle: true)
        waitForPage("First")
        let lines = swipeTrace()
        XCTAssertEqual(lines.first, "closingTab picture kept", "the tab before it came out as its picture: \(lines)")
        let cards = lines.filter { $0.hasPrefix("page ") }.map(numbers)
        guard let first = cards.first, let last = cards.last, first.count == 6, last.count == 6 else {
            return XCTFail("no card frames: \(lines)")
        }
        // page, x, y, width, height, finger: small, on the tab button, at first...
        let center = CGPoint(x: first[1] + first[3] / 2, y: first[2] + first[4] / 2)
        XCTAssertTrue(button.insetBy(dx: -30, dy: -30).contains(center), "out of the tab button \(button): \(first)")
        XCTAssertLessThan(first[3], 120, "small at first: \(first)")
        // ...and by the end the page's card size, 20 pt in from the sides, with its right edge 20 pt left of the
        // page's card, whose left edge is the page's travel plus 20.
        let width = app.windows.firstMatch.frame.width
        XCTAssertEqual(last[3], width - 40, accuracy: 1.5, "the page's card size by the end: \(last)")
        XCTAssertEqual(last[1] + last[3], last[0], accuracy: 1.5, "beside the page's card: \(last)")
        XCTAssertTrue(lines.contains("went closingTab"))
        XCTAssertEqual(rowTitles(), ["First"], "the swiped tab went to the archive")
    }

    /// Let go while the magnet still holds the page, it settles back, the tab stays and nothing of the swipe stays on
    /// screen.
    func testASwipeLetGoEarlyPutsThePageBack() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTracePageSwipe", "YES"])
        waitForPage("First")
        openTab(Self.page("Second"), title: "Second")
        sleep(1)
        // From the edge, where a swipe always starts, held still well short of where the magnet lets go (the finger
        // 160 pt in), so it lets go with no speed. (From mid-page, XCUITest's drags of a sixth of the screen never started a swipe.)
        drag(fromX: 0.03, toX: 0.12, y: 0.5, settle: true)
        let lines = swipeTrace()
        XCTAssertEqual(lines.first, "closingTab picture kept")
        XCTAssertEqual(lines.last, "went nowhere", "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("let go") }, "the magnet still held the page: \(lines)")
        XCTAssertTrue(app.webViews.staticTexts["Second"].isHittable, "the page is back in place")
        XCTAssertEqual(rowTitles(), ["First", "Second"])
    }
}
