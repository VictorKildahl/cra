import XCTest

/// The search sheet moved by hand, as in Arc Search: pulled up out of the pill, dragged down by
/// any part of it.
final class SearchPullTests: BrowserTestCase {
    private func pillPoint() -> XCUICoordinate {
        app.buttons["bar-search"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    // promise: #623
    /// A drag up from the pill brings the search sheet out under the finger and, let go, opens it
    /// ready to type. Before, it opened the tab row.
    func testDraggingUpFromThePillOpensSearch() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        pillPoint().press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                          withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the sheet opened with the keyboard")
        XCTAssertTrue(app.textFields["search-field"].exists)
        XCTAssertFalse(app.buttons["tab-card-0"].exists, "the tab row stayed shut")
        keep("pulled open")
    }

    // promise: #623
    /// Held halfway, the sheet stays where the finger is; let go a little way up, it sinks back
    /// into the pill.
    func testAShortPullFallsBackIntoThePill() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        let pill = pillPoint()
        pill.press(forDuration: 0.05, thenDragTo: pill.withOffset(CGVector(dx: 0, dy: -50)), withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(1)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "a short pull doesn't open search")
        XCTAssertFalse(app.buttons["tab-card-0"].exists)
        XCTAssertTrue(app.buttons["bar-search"].isHittable, "the pill is back")
    }

    // promise: #623
    /// The open sheet goes down with a drag that starts on its suggestions, not only on the field.
    /// With something typed the suggestions scroll, and before, they took the drag.
    func testDraggingTheSheetDownByItsSuggestionsClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraFakeSuggestions", "YES"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("cat")
        let row = app.descendants(matching: .any)["suggestion-2"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the made-up completions are listed")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 250)), withVelocity: .fast, thenHoldForDuration: 0)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 5)
        waitForBarOnScreen()
        keep("dragged down by a suggestion")
    }
}
