import XCTest

/// The tab row's order: least to most recently picked, as in Arc Search.
final class TabOrderTests: BrowserTestCase {
    private func openTab(_ title: String) {
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(Self.page(title) + "\n")
        waitForPage(title)
    }

    /// The tabs in the row, by title, read with the row open.
    private func rowTitles() -> [String] {
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        return cards.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }.map(\.label)
    }

    private func swipeAlongTheBarToTheOlderTab() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
    }

    private func swipeAlongTheBarToTheNewerTab() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.95)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
    }

    private func flickUpFromTheTabButton() {
        let start = app.buttons["bar-tabs"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
    }

    /// A flick begun while the one before it is still settling must not leave that one's page
    /// card frozen over the screen: the bar stays reachable and the page answers.
    func testAFlickStartedWhileAnotherSettlesLeavesNoCardOverThePage() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        waitForPage("Second")
        let start = app.buttons["bar-tabs"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
        for _ in 0..<2 {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(app.buttons["bar-search"].waitForExistence(timeout: 5))
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5),
                      "a page card left over the screen would swallow the tap")
    }

    // promise: #647
    /// A tab picked from the row moves to its newest end, the right.
    func testAPickedTabMovesToTheEndOfTheRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        openTab("Third")
        app.buttons["bar-tabs"].tap()
        XCTAssertEqual(rowTitles(), ["First", "Second", "Third"])
        // An older card is tucked behind the next one: only its left edge can be tapped.
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-card-' AND label == 'Second'")).firstMatch
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        waitForPage("Second")
        sleep(1)
        app.buttons["bar-tabs"].tap()
        XCTAssertEqual(rowTitles(), ["First", "Third", "Second"])
        keep("picked tab at the end")
    }

    // promise: #647
    /// A flick up on the tab button picks the tab looked at last; it moves to the row's newest
    /// end like a card picked in the row.
    func testAFlickUpOnTheTabButtonMovesItsTabToTheEndOfTheRow() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        openTab("Third")
        swipeAlongTheBarToTheOlderTab()
        waitForPage("Second")
        flickUpFromTheTabButton()
        waitForPage("Third")
        flickUpFromTheTabButton()
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertEqual(rowTitles(), ["First", "Third", "Second"])
    }

    /// A swipe along the bar walks the row without picking: the tab button's stack keeps the tab
    /// last picked on top, so a flick up goes back to it, not to the tab swiped past.
    func testSwipingAlongTheBarLeavesTheTabStackAlone() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        openTab("Third")
        swipeAlongTheBarToTheOlderTab()
        waitForPage("Second")
        swipeAlongTheBarToTheOlderTab()
        waitForPage("First")
        flickUpFromTheTabButton()
        waitForPage("Third")
        // The tab flicked from comes next: the second flick returns to it.
        flickUpFromTheTabButton()
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertEqual(rowTitles(), ["Second", "Third", "First"])
    }

    /// A flick along the bar quick enough to have gone its way before the swipe began, the swipe
    /// seeing nothing moved, still goes to the tab beside: it takes its whole way from where it
    /// touched down, at once as it lifts. Before, it went nowhere (1 in 6 of the bar's UI tests).
    func testAQuickFlickAlongTheBarStillGoesToTheTabBeside() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)),
                    withVelocity: XCUIGestureVelocity(rawValue: 20000), thenHoldForDuration: 0)
        waitForPage("First")
    }

    /// Along the bar the tabs go in the row's order, as the tab switcher shows them, both ways:
    /// back from the newest, then forward again to the tab next in the row, not to the one last
    /// looked at.
    func testSwipingAlongTheBarGoesInTheRowsOrder() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        openTab("Second")
        openTab("Third")
        openTab("Fourth")
        swipeAlongTheBarToTheOlderTab()
        waitForPage("Third")
        swipeAlongTheBarToTheOlderTab()
        waitForPage("Second")
        swipeAlongTheBarToTheNewerTab()
        waitForPage("Third")
        swipeAlongTheBarToTheNewerTab()
        waitForPage("Fourth")
        app.buttons["bar-tabs"].tap()
        XCTAssertEqual(rowTitles(), ["First", "Second", "Third", "Fourth"])
    }

    // promise: #647
    /// A popup from a tab further back, swiped away on its first page, hands the screen back to
    /// that tab instead of the row's last one. The source tab is reached along the bar, which
    /// keeps the row's order, so the popup's opener stays at the front of the row.
    func testSwipingAPopupAwayReturnsToItsOpener() {
        let source = (ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765") + "/source"
        launch(["-CraOpenURL", source, "-CraSearch", "NO"])
        waitForPage("Popup Source")
        openTab("Second")
        openTab("Third")
        swipeAlongTheBarToTheOlderTab()
        swipeAlongTheBarToTheOlderTab()
        waitForPage("Popup Source")

        let open = app.webViews.buttons["Open blank popup"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        waitForPage("Blank Popup")
        // Back on the popup's first page puts it in the archive.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        waitForPage("Popup Source")
        keep("back on the opener")
    }
}
