import XCTest

/// The site icon above each card in the tab switcher.
final class TabSwitcherIconTests: BrowserTestCase {
    private var base: String { ProcessInfo.processInfo.environment["CRA_POPUP_TEST_BASE_URL"] ?? "http://127.0.0.1:18765" }

    /// Every card's icon was a rounded square: the page's touch icon, an app icon most sites list
    /// first and largest, was fetched first, and the header clipped whatever it showed to a
    /// rounded square. The fixture names a blue square touch icon, then its own icon, a red
    /// triangle on see-through. The card shows the triangle: red up to its sharp top-left
    /// corner, the row's background where the triangle is see-through.
    func testATabCardShowsTheSitesOwnIconInItsOwnShape() throws {
        launch(["-CraOpenURL", base + "/icon-shapes", "-CraSearch", "NO"])
        waitForPage("Icon Shapes")
        // The icon is fetched once the page has loaded; the row reads it when it opens.
        sleep(3)
        app.buttons["bar-tabs"].tap()
        let card = app.buttons["tab-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        sleep(1)
        keep("icon-shapes")
        guard let shot = capture()?.image else {
            throw XCTSkip("XCTest screen capture is blank on this display; the pixel check cannot judge Cra here")
        }
        // MobileTabCarousel's header: an 18 pt icon, 18 pt in from the card's left edge and
        // 8.5 pt above it; the card in focus is at scale 1.
        let icon = CGRect(x: card.frame.minX + 18, y: card.frame.minY - 8.5 - 18, width: 18, height: 18)
        let topLeft = colour(shot, at: CGPoint(x: icon.minX + 1, y: icon.minY + 1))
        let inside = colour(shot, at: CGPoint(x: icon.minX + 5, y: icon.minY + 5))
        let bottomRight = colour(shot, at: CGPoint(x: icon.maxX - 1.5, y: icon.maxY - 1.5))
        XCTAssertTrue(isRed(inside), "the site's own icon, not its touch icon: \(inside)")
        XCTAssertTrue(isRed(topLeft), "the icon's sharp corner isn't rounded off: \(topLeft)")
        XCTAssertFalse(isRed(bottomRight) || isBlue(bottomRight), "the see-through half shows the row: \(bottomRight)")
    }

    private func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 170 && c.g < 100 && c.b < 100 }
    private func isBlue(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.b > 170 && c.r < 100 }

    /// The screenshot's colour at a point on the screen.
    private func colour(_ image: UIImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0) }
        let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
        let i = y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
        // Simulator screenshots are BGRA.
        let first = Int(bytes[i]), third = Int(bytes[i + 2])
        let bgra = cg.bitmapInfo.contains(.byteOrder32Little)
        return (bgra ? third : first, Int(bytes[i + 1]), bgra ? first : third)
    }
}
