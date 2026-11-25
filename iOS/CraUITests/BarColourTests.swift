import XCTest

/// The bottom bar's background follows the page's top, the way the status bar's text does.
final class BarColourTests: BrowserTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // shortcut: only the iPhone Duo simulator is known here; the pixel check needs a screen capture.
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
            throw XCTSkip("XCTest screen capture is blank on this display (iPhone Duo inner screen); the pixel check cannot judge Cra here")
        }
    }

    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    /// The bar's slab left of the pill, above the home indicator.
    private func barColour() -> (r: Int, g: Int, b: Int) {
        screenColour(x: 0.25, y: 0.94)
    }

    private func luminance(_ c: (r: Int, g: Int, b: Int)) -> Double {
        (0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b)) / 255
    }

    /// A dark page in the app's light appearance gets a dark bar, and a light page in the app's
    /// dark appearance a light one: the page decides, not the app.
    func testTheBarsBackgroundFollowsThePagesTop() {
        launch(["-CraOpenURL", base + "/dark-page", "-CraSearch", "NO", "-CraAppearance", "light"])
        waitForPage("Dark Page")
        sleep(1)
        XCTAssertLessThan(luminance(barColour()), 0.35, "the bar over a dark page is dark: \(barColour())")
        keep("dark page, light app")

        launch(["-CraOpenURL", base + "/plain", "-CraSearch", "NO", "-CraAppearance", "dark"])
        waitForPage("Plain HTTP Fixture")
        sleep(1)
        XCTAssertGreaterThan(luminance(barColour()), 0.65, "the bar over a light page is light: \(barColour())")
        keep("light page, dark app")
    }

    /// Picking a tab takes the bar to that tab's colour while its card is still growing back, not
    /// once the row is gone: the tab's picture gives the colour before its page loads.
    func testPickingATabTakesTheBarItsColourAtOnce() {
        launch(["-CraOpenURL", base + "/plain", "-CraSearch", "NO", "-CraAppearance", "dark"])
        waitForPage("Plain HTTP Fixture")
        XCTAssertGreaterThan(luminance(barColour()), 0.65, "the light page's bar is light")

        // A second tab, dark.
        app.buttons["bar-search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(base + "/dark-page\n")
        waitForPage("Dark Page")
        sleep(1)
        XCTAssertLessThan(luminance(barColour()), 0.35, "the dark page's bar is dark")

        // Back to the light tab: the bar takes its colour as the card grows out of the row.
        app.buttons["bar-tabs"].tap()
        let lightCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Plain HTTP Fixture'")).firstMatch
        XCTAssertTrue(lightCard.waitForExistence(timeout: 5))
        lightCard.tap()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertGreaterThan(luminance(barColour()), 0.65,
                             "the bar took the light tab's colour while the row closed")
        keep("tab picked")
        waitForPage("Plain HTTP Fixture")
    }
}
