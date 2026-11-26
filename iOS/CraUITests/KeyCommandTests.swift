import XCTest

/// A hardware keyboard (`MobileKeyCommands`): ⌘T and ⌘L open the search sheet. XCTest never
/// delivers Escape to the app in the simulator (it reaches neither `pressesBegan` nor a key
/// command), so Escape closing the sheet is in docs/release-checklist.md.
final class KeyCommandTests: BrowserTestCase {
    /// Over a page, ⌘T opens the empty sheet, and what is typed opens in a new tab.
    func testCommandTSearchesForANewTab() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        let field = app.textFields["search-field"]
        XCTAssertFalse(field.exists)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘T opens the search sheet")
        XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "a new search starts empty")
        keep("command-t")
        app.typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-1"].waitForExistence(timeout: 5), "it opened in a new tab")
    }

    /// ⌘L opens the sheet on the page's address, also with the page itself in focus; what is
    /// typed loads in the same tab.
    func testCommandLEditsTheAddress() {
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO"])
        waitForPage("First")
        app.webViews.staticTexts["First"].tap()
        // WebKit takes a single tap only once its double-tap window has passed: a ⌘L sooner
        // opens the sheet, and then the page takes the keyboard back from the field.
        sleep(1)
        let field = app.textFields["search-field"]
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘L opens the search sheet")
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("data:text/html,") && value.contains("First"), "the page's address is in the field: \(value)")
        keep("command-l")
        // Selected, so what is typed replaces it.
        field.typeText(Self.page("Second") + "\n")
        waitForPage("Second")
        app.buttons["bar-tabs"].tap()
        XCTAssertTrue(app.buttons["tab-card-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-card-1"].exists, "it loaded in the same tab")
    }

    /// On the empty home there is no page and nothing in focus: ⌘L still opens the search.
    func testCommandLSearchesOnTheEmptyHome() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.otherElements["search-dismiss"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘L opens the search sheet")
        XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "with no page there is no address")
    }
}
