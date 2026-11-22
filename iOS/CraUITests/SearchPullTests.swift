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

    // promise: #655
    /// The open sheet, nothing typed, goes down with a drag that starts anywhere on it, below the field
    /// too, as Arc Search's does in the reporter's recording; before #623 only a drag on the field did.
    func testDraggingTheEmptySheetDownFromAnywhereClosesIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Well below the field, on the sheet: not the field itself.
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 3.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 250)), withVelocity: .fast, thenHoldForDuration: 0)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 5)
        waitForBarOnScreen()
        keep("empty sheet dragged down from below the field")
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

    // promise: #655
    /// The open sheet, keyboard up, dragged down slowly stays in sight under the finger all the way, as a pull out of the
    /// pill does, and sinks into the pill when let go. Before, it slid down under the keyboard, out of sight, and the
    /// keyboard only went once the finger lifted (the reporter's recording).
    func testTheOpenSheetDraggedDownStaysInSight() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceSheetDrag", "YES"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 3.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 320)), withVelocity: .slow, thenHoldForDuration: 0.3)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 5)
        waitForBarOnScreen()
        let trace = app.descendants(matching: .any)["sheet-drag-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 2))
        let value = trace.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("under the keyboard 0 of "), "the sheet stayed in sight: \(value)")
        XCTAssertGreaterThan(Int(value.split(separator: " ").last ?? "") ?? 0, 10, "the drag was followed frame by frame: \(value)")
    }
}
