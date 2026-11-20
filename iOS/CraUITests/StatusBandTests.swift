import XCTest

/// The band behind the status bar over a page (#657).
final class StatusBandTests: BrowserTestCase {
    /// The screen's colour a few points from the top, left of the clock: the band, not the page.
    private func topColour() -> (r: Int, g: Int, b: Int) {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        let x = Int(Double(cg.width) * 0.08), y = Int(Double(cg.height) * 0.006)
        let i = y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
        // Simulator screenshots are BGRA.
        let first = Int(bytes[i]), third = Int(bytes[i + 2])
        let bgra = cg.bitmapInfo.contains(.byteOrder32Little)
        return (bgra ? third : first, Int(bytes[i + 1]), bgra ? first : third)
    }

    private func near(_ c: (r: Int, g: Int, b: Int), _ hex: Int, _ what: String) {
        let want = (r: hex >> 16 & 0xff, g: hex >> 8 & 0xff, b: hex & 0xff)
        XCTAssertLessThanOrEqual(max(abs(c.r - want.r), abs(c.g - want.g), abs(c.b - want.b)), 6, "\(what): \(c)")
    }

    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    // promise: #657
    /// Arc Search puts a solid band in the page's colour behind the status bar, so the time stays
    /// readable while the page's text scrolls under it: the page's theme-color, else its background.
    /// Before, the page's text ran up under a see-through status bar.
    func testTheStatusBarSitsOnThePagesColour() {
        launch(["-CraOpenURL", base + "/themed", "-CraSearch", "NO"])
        waitForPage("Themed")
        sleep(1)
        near(topColour(), 0x7F6BAB, "the theme-color, at rest")
        keep("themed band")
        // Scrolled, the page's text passes under the band, which stays.
        app.webViews.firstMatch.swipeUp()
        sleep(1)
        near(topColour(), 0x7F6BAB, "the theme-color, scrolled")
        keep("themed band, scrolled")

        launch(["-CraOpenURL", base + "/dark-page", "-CraSearch", "NO"])
        waitForPage("Dark Page")
        sleep(1)
        near(topColour(), 0x123456, "the page's own background, with no theme-color")
        keep("dark page band")
    }
}
