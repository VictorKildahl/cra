import XCTest

/// The search sheet moved by hand, as in Arc Search: pulled up out of the pill, dragged down by
/// any part of it.
final class SearchPullTests: BrowserTestCase {
    private func pillPoint() -> XCUICoordinate {
        app.buttons["bar-search"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// The number after `key` in a `-CraTraceNewTabDrawer` trace ("rise 52 field 0.00 ...").
    private func traceNumber(_ key: String, in trace: String) -> Double? {
        let parts = trace.split(separator: " ")
        guard let at = parts.firstIndex(of: Substring(key)), at + 1 < parts.endIndex else { return nil }
        return Double(parts[at + 1])
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

    /// The new tab drawer is the bar grown upward: the material takes the drawer's colour at once,
    /// the side buttons ride the top edge and let go, and the plus stays a plus until the finger
    /// lifts. The drag's last frame is kept for the test after the drawer has sunk back.
    func testPullingTheNewTabDrawerKeepsThePlusUntilRelease() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceNewTabDrawer", "YES"])
        waitForPage("First")
        let trace = app.descendants(matching: .any)["new-tab-drawer-drag-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 5))
        let pill = pillPoint()
        pill.press(forDuration: 0.05, thenDragTo: pill.withOffset(CGVector(dx: 0, dy: -50)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        let value = trace.value as? String ?? ""
        XCTAssertTrue(value.contains("field 0.00"), "the plus has not become the field yet: \(value)")
        XCTAssertTrue(value.contains("material 1.00"), "the drawer's colour came in at once: \(value)")
        XCTAssertTrue(value.contains("tabs off"), "the tabs button let go as the bar rose: \(value)")
        XCTAssertFalse(value.contains("list 0.00"), "the pinned rows fade in with the drawer: \(value)")
        let rise = traceNumber("rise", in: value) ?? 0
        XCTAssertGreaterThan(rise, 35, "the bar rose with the finger: \(value)")
        XCTAssertLessThan(rise, 65, "the bar rose with the finger: \(value)")
    }

    /// Tapped, the drawer opens and the plus becomes the field: the side buttons are gone and the
    /// drawer's colour is over the bar's material.
    func testTappingThePillOpensTheNewTabDrawer() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceNewTabDrawer", "YES"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let trace = app.descendants(matching: .any)["new-tab-drawer-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 5))
        let value = trace.value as? String ?? ""
        XCTAssertTrue(value.contains("field 1.00"), "the plus became the field: \(value)")
        XCTAssertTrue(value.contains("material 1.00"), "the drawer's colour stayed: \(value)")
        XCTAssertTrue(value.contains("list 1.00"), "the pinned rows are in with the drawer: \(value)")
        XCTAssertTrue(value.contains("tabs off"), "the side buttons left: \(value)")
        let rise = traceNumber("rise", in: value) ?? 0
        XCTAssertGreaterThan(rise, 200, "the drawer is open, its top edge well above the bar: \(value)")
        keep("new tab drawer over a light page")
    }

    /// A tap above the open drawer puts it back into the bar: the field and keyboard go, and the
    /// tabs and menu buttons are back and take touches.
    func testTappingAboveTheNewTabDrawerPutsItBackIntoTheBar() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let field = app.textFields["search-field"]
        let window = app.windows.firstMatch
        let point = CGPoint(x: window.frame.midX, y: field.frame.minY - 60)
        XCTAssertLessThanOrEqual(point.y, field.frame.minY - 40, "the tap lands above the drawer")
        XCTAssertTrue(window.frame.contains(point), "the tap lands inside the window")
        let above = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - window.frame.minX, dy: point.y - window.frame.minY))
        above.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the drawer closed")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        waitForBarOnScreen()
        XCTAssertTrue(app.buttons["bar-tabs"].isHittable, "the tabs button is back")
        XCTAssertTrue(app.buttons["bar-menu"].isHittable, "the menu button is back")
        waitForPage("First")
    }

    /// From an incognito tab, the word beside the mask comes in with the field and its buttons,
    /// not before: pulled up with the plus still a plus, it is not there yet. It used to show at
    /// once, over the closed pill.
    func testTheIncognitoWordWaitsForTheField() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceNewTabDrawer", "YES"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["search-incognito"].tap()
        waitForValue("On", of: app.buttons["search-incognito"])
        field.typeText(Self.page("Secret") + "\n")
        waitForPage("Secret")
        let trace = app.descendants(matching: .any)["new-tab-drawer-drag-trace"]
        let pill = pillPoint()
        pill.press(forDuration: 0.05, thenDragTo: pill.withOffset(CGVector(dx: 0, dy: -50)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        let value = trace.value as? String ?? ""
        XCTAssertTrue(value.contains("field 0.00"), "the plus has not become the field yet: \(value)")
        XCTAssertTrue(value.contains("word 0.00"), "the word waits for the field: \(value)")
    }

    /// Opened from the tab row and closed again, the drawer leaves the bar as the row has it, with
    /// no material of its own. It used to keep the drawer's slab.
    func testClosingTheDrawerOverTheTabRowLeavesTheBarFloating() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceNewTabDrawer", "YES"])
        waitForPage("First")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the drawer closed")
        XCTAssertTrue(app.buttons["tab-card-0"].exists, "the tab row is still up")
        sleep(1)
        let value = app.descendants(matching: .any)["new-tab-drawer-trace"].value as? String ?? ""
        XCTAssertTrue(value.contains("base 0.00"), "the bar has no material over the tab row: \(value)")
    }

    /// Dragging the open drawer down keeps its colour until the finger lifts; the bar's own
    /// material stays behind it, so the background never goes transparent.
    func testDraggingTheOpenDrawerDownKeepsTheBarMaterialBehindIt() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraTraceNewTabDrawer", "YES"])
        waitForPage("First")
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let trace = app.descendants(matching: .any)["new-tab-drawer-drag-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 3.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 200)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let value = trace.value as? String ?? ""
        XCTAssertTrue(value.contains("base 1.00"), "the bar's material stayed behind the drawer: \(value)")
        XCTAssertTrue(value.contains("material 1.00"), "the drawer kept its colour until the finger lifted: \(value)")
        XCTAssertTrue(value.contains("field 1.00"), "the address bar stayed open until the finger lifted: \(value)")
    }
}
