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
        XCTAssertEqual(toggle.value as? String, "On")
        sleep(1)
        let on = toggle.frame
        keep("incognito on")
        // The glyph is drawn at the toggle's right edge in both states.
        XCTAssertEqual(off.maxX, on.maxX, accuracy: 1, "the glyph moved: off \(off), on \(on)")
        XCTAssertGreaterThanOrEqual(app.frame.maxX - off.maxX, 16 + 18, "the field ends 16 pt from the screen; the glyph 18.5 pt before that")
    }
}
