import XCTest

/// A tab's page opens where it was after the app was closed (#656).
final class PageRestoreTests: BrowserTestCase {
    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    // promise: #656
    /// Arc Search reopens a long article scrolled where it was after a force quit. Cra loaded the page
    /// again from its top.
    func testAScrolledPageOpensWhereItWasAfterTheAppIsClosed() {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        app.launchArguments = ["-CraDataDir", data.path, "-CraOpenURL", base + "/long-article", "-CraSearch", "NO"]
        app.launch()
        waitForPage("Long Article")
        let heading = app.webViews.staticTexts["Long Article"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        for _ in 0..<4 { app.webViews.firstMatch.swipeUp() }
        sleep(2)
        XCTAssertFalse(heading.isHittable, "scrolled past the heading")
        keep("scrolled down")

        // To the background, where iOS may end the app, then ended.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app.launchArguments = ["-CraDataDir", data.path, "-CraSearch", "NO"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Paragraph 60 of a long article, with enough words to take a few lines on a phone."]
            .waitForExistence(timeout: 10) || heading.waitForExistence(timeout: 1), "the page is back")
        sleep(2)
        XCTAssertFalse(app.webViews.staticTexts["Long Article"].isHittable, "it opens where it was, not at the top")
        keep("reopened where it was")
    }
}
