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

    // promise: #656
    /// A page nudged by less than 100 pt opens at its top, not where the nudge left it.
    func testASmallScrollComesBackAtTheTop() {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        app.launchArguments = ["-CraDataDir", data.path, "-CraOpenURL", base + "/long-article", "-CraSearch", "NO"]
        app.launch()
        waitForPage("Long Article")
        let heading = app.webViews.staticTexts["Long Article"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let top = heading.frame.minY
        let start = app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -40)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertLessThan(heading.frame.minY, top - 10, "the page moved a little, under the 100 pt threshold")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app.launchArguments = ["-CraDataDir", data.path, "-CraSearch", "NO"]
        app.launch()
        let restored = app.webViews.staticTexts["Long Article"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertEqual(restored.frame.minY, top, accuracy: 5, "under 100 pt opens at the top")
        keep("small scroll back at the top")
    }
}
