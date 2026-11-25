import XCTest

/// The page's view runs on under the bar while WebKit lays its content out clear of it (iOS 26's
/// obscured content insets): the bar's material has the page behind it, and a sticky bottom edge
/// sits on the bar's top rather than under it.
final class PageUnderBarTests: BrowserTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) else {
            throw XCTSkip("a page runs under the bar only with iOS 26's obscured content insets")
        }
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
            throw XCTSkip("XCTest screen capture is blank on this display (iPhone Duo inner screen); the pixel check cannot judge Cra here")
        }
    }

    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    private func luminance(_ c: (r: Int, g: Int, b: Int)) -> Double {
        (0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b)) / 255
    }

    /// The bar's top edge, from the pill's frame (the controls' centre is 31.5 pt below the bar's
    /// top and the pill is 39 pt tall) or, with the bar closed, from the strip that brings it back.
    private var barTop: CGFloat {
        let pill = app.buttons["bar-search"]
        if pill.exists { return pill.frame.minY - 12 }
        return app.buttons["bar-reveal"].frame.minY
    }

    /// A page titled `title` with a sticky footer button of its own.
    private static func stickyPage(_ title: String) -> String {
        "data:text/html,<meta/name=viewport/content=width=device-width><title>\(title)</title>"
            + "<body/style=margin:0><h1>\(title)</h1><div/style=height:3000px></div>"
            + "<button/style=display:block;width:100vw;height:44px;font-size:20px;position:sticky;bottom:0>Footer</button>"
    }

    /// The web view reaches the safe area's edge, 42 pt under the bar's top, not just to its top.
    func testThePagesViewRunsUnderTheBar() {
        launch(["-CraOpenURL", Self.stickyPage("Under"), "-CraSearch", "NO"])
        waitForPage("Under")
        let web = app.webViews.firstMatch
        XCTAssertGreaterThan(web.frame.maxY, barTop + 30,
                             "the page runs under the bar: \(web.frame) vs bar top \(barTop)")
        XCTAssertLessThan(web.frame.maxY, app.windows.firstMatch.frame.maxY,
                          "the page stops at the safe area's edge: \(web.frame)")
        keep("page under the bar")
    }

    /// A sticky bottom: 0 sits on the bar's top on a page laid out above it, not under the bar.
    func testAStickyFooterSitsOnTheBarsTop() {
        launch(["-CraOpenURL", Self.stickyPage("Sticky"), "-CraSearch", "NO"])
        waitForPage("Sticky")
        let footer = app.webViews.buttons["Footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.frame.maxY, barTop, accuracy: 4,
                       "the sticky footer sits on the bar's top: \(footer.frame) vs \(barTop)")
        keep("sticky footer")
    }

    /// The page's last line can still be brought above the bar: the covered area under it is
    /// scroll room, not content that is lost.
    func testTheLastOfAPageScrollsClearOfTheBar() {
        launch(["-CraOpenURL", "data:text/html,<meta/name=viewport/content=width=device-width><title>End</title>"
                + "<body/style=margin:0><h1>End</h1><div/style=height:3000px></div><h2>Last line</h2>", "-CraSearch", "NO"])
        waitForPage("End")
        let web = app.webViews.firstMatch
        let last = app.webViews.staticTexts["Last line"]
        for _ in 0..<6 where !last.isHittable { web.swipeUp() }
        sleep(1)
        XCTAssertTrue(last.isHittable, "the last line can be reached: \(last.frame)")
        XCTAssertLessThanOrEqual(last.frame.maxY, barTop + 2, "the last line stays clear of the bar")
        keep("last line clear")
    }

    /// The bar's material takes the page's colour behind it: red through the glass over a red
    /// page, blue over a blue one.
    func testTheBarsMaterialTakesThePagesColour() {
        launch(["-CraOpenURL", Self.colouredPage("Red", "red"), "-CraSearch", "NO"])
        waitForPage("Red")
        sleep(1)
        let red = screenColour(x: 0.25, y: 0.94)
        XCTAssertGreaterThan(red.r, red.b + 15, "the bar over a red page is red: \(red)")
        keep("red through the glass")

        launch(["-CraOpenURL", Self.colouredPage("Blue", "blue"), "-CraSearch", "NO"])
        waitForPage("Blue")
        sleep(1)
        let blue = screenColour(x: 0.25, y: 0.94)
        XCTAssertGreaterThan(blue.b, blue.r + 15, "the bar over a blue page is blue: \(blue)")
        keep("blue through the glass")
    }

    /// The bar takes the colour under it, not the page's top: over a white page bottom with a
    /// black top band, the bar is light while the status band keeps the black.
    func testTheBarTakesTheColourBelowItNotThePagesTop() {
        launch(["-CraOpenURL", base + "/two-tones", "-CraSearch", "NO", "-CraAppearance", "light"])
        waitForPage("Two Tones")
        sleep(1)
        let bar = screenColour(x: 0.25, y: 0.94)
        XCTAssertGreaterThan(luminance(bar), 0.6, "the bar is light over the white page below it: \(bar)")
        let band = screenColour(x: 0.08, y: 0.006)
        XCTAssertLessThan(luminance(band), 0.1, "the status band keeps the page's black top: \(band)")
        keep("bottom colour, not top")
    }

    private static func colouredPage(_ title: String, _ colour: String) -> String {
        "data:text/html,<meta/name=viewport/content=width=device-width><title>\(title)</title>"
            + "<body/style=margin:0;background:\(colour);height:100vh><h1>\(title)</h1>"
    }
}
