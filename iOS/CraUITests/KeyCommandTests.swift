import XCTest

/// A hardware keyboard (`MobileKeyCommands`): ⌘T and ⌘L open the search sheet. XCTest never
/// delivers Escape to the app in the simulator (it reaches neither `pressesBegan` nor a key
/// command), so Escape closing the sheet is in docs/release-checklist.md.
final class KeyCommandTests: BrowserTestCase {
    /// Over a page, with nothing in focus, ⌘T opens the empty sheet, and what is typed opens in a
    /// new tab.
    func testCommandTSearchesForANewTab() throws {
        try skipBeforeIOS27()
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
    func testCommandLEditsTheAddress() throws {
        try skipBeforeIOS27()
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
    func testCommandLSearchesOnTheEmptyHome() throws {
        try skipBeforeIOS27()
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.otherElements["search-dismiss"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘L opens the search sheet")
        XCTAssertEqual(field.value as? String ?? "", field.placeholderValue ?? "", "with no page there is no address")
    }

    /// A summary covers the browser, so ⌘T and ⌘L open nothing under it; closed, ⌘T searches again.
    func testNothingOpensUnderASummary() throws {
        try skipBeforeIOS27()
        launch(["-CraOpenURL", Self.page("First"), "-CraSearch", "NO", "-CraFakeModel", "YES", "-CraSummarize", "YES"])
        let close = app.buttons["summary-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        let field = app.textFields["search-field"]
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("l", modifierFlags: .command)
        XCTAssertFalse(field.waitForExistence(timeout: 2), "no search opens under the summary")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "with the summary closed, ⌘T searches")
    }

    /// On iOS 26.5, XCTest's `typeKey` loses ⌘ more often than not: the letter reaches the app alone,
    /// with no ⌘ press before it, with or without the page in focus. So these run from iOS 27. A
    /// hardware keyboard's ⌘ does reach the browser on 26.5, with or without focus: checked with
    /// HID events sent the way Simulator.app's keyboard sends them (PR #867), and a line in
    /// docs/release-checklist.md.
    private func skipBeforeIOS27() throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
                      "XCTest drops ⌘ from typeKey before iOS 27")
    }
}
