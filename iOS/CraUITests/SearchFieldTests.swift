import XCTest

/// The search field's own controls.
final class SearchFieldTests: BrowserTestCase {
    // promise: #654
    /// The incognito glyph has the same room to the field's right end off as on: off, it sat
    /// against the rim.
    func testTheIncognitoGlyphStaysPutWhenSwitchedOn() {
        launch()
        let toggle = app.buttons["search-incognito"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        sleep(1)
        let off = toggle.frame
        keep("incognito off")
        toggle.tap()
        waitForValue("On", of: toggle)
        sleep(1)
        let on = toggle.frame
        keep("incognito on")
        // The glyph is drawn at the toggle's right edge in both states.
        XCTAssertEqual(off.maxX, on.maxX, accuracy: 1, "the glyph moved: off \(off), on \(on)")
        XCTAssertGreaterThanOrEqual(app.frame.maxX - off.maxX, 16 + 16, "the field ends 16 pt from the screen; the glyph 16.5 pt before that")
    }

    /// Off, the mask is two hollow eggs with a pupil in each; on, the eggs fill in. A point inside
    /// the left egg, clear of its pupil and rim, shows the field around it off and takes the ink on.
    func testTheIncognitoMaskIsHollowUntilItIsOn() {
        launch()
        let toggle = app.buttons["search-incognito"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        sleep(1)
        // The glyph sits at the toggle's right edge; the left egg's centre is 7 pt into its
        // 28 pt width. The sample is up and to the right of the lower-left pupil, inside the rim;
        // 9.5 pt below the centre is the field's fill, past the bottom of the glyph.
        let centre = CGPoint(x: toggle.frame.maxX - 28 + 7, y: toggle.frame.midY)
        let sample = CGPoint(x: centre.x + 1.5, y: centre.y - 3.5)
        let field = CGPoint(x: centre.x, y: centre.y + 9.5)
        XCTAssertLessThan(abs(contrast(sample, field)), 12, "off, the egg is hollow and the field shows through it")
        toggle.tap()
        waitForValue("On", of: toggle)
        sleep(1)
        XCTAssertGreaterThan(abs(contrast(sample, field)), 15, "on, the egg fills in with the ink")
        toggle.tap()
        waitForValue("Off", of: toggle)
        sleep(1)
        XCTAssertLessThan(abs(contrast(sample, field)), 12, "off again, the lids lift and the field shows through")
    }

    /// How far apart two points of the screen are in brightness, in one screenshot.
    private func contrast(_ first: CGPoint, _ second: CGPoint) -> Int {
        func sample(_ point: CGPoint) -> Int {
            let colour = screenColour(x: (point.x - app.frame.minX) / app.frame.width,
                                      y: (point.y - app.frame.minY) / app.frame.height)
            return (colour.r + colour.g + colour.b) / 3
        }
        return sample(first) - sample(second)
    }
}
