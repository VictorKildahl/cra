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
