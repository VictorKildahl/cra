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
        XCTAssertGreaterThanOrEqual(app.frame.maxX - off.maxX, 16 + 13, "the field ends 16 pt from the screen; the glyph 13.5 pt before that")
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

    /// The clear button's cross is cut out of its disc: at the cross's middle the field shows, as
    /// it does just left of the disc, while the disc itself takes the ink. It used to be painted in
    /// white, which no longer matched the field.
    func testTheClearButtonsCrossIsCutOut() {
        // Dark, where a cross painted white would stand out from the field.
        launch(["-CraAppearance", "dark"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("ovens")
        let clear = app.buttons["search-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        sleep(1)
        let middle = CGPoint(x: clear.frame.midX, y: clear.frame.midY)
        // Inside the disc, clear of the cross: 6 pt left of the middle, on its centre line.
        let disc = CGPoint(x: middle.x - 6, y: middle.y)
        // The field, between the typed text's end and the disc's left edge.
        let beside = CGPoint(x: middle.x - 15, y: middle.y)
        XCTAssertLessThan(abs(contrast(middle, beside)), 12, "the field shows through the cross")
        XCTAssertGreaterThan(abs(contrast(disc, beside)), 15, "the disc takes the ink")
        keep("clear button")
    }

    /// Typing swaps the mic and the incognito toggle for the clear button; clearing brings both
    /// back and the clear button goes.
    func testTypingSwapsTheMicAndMaskForTheClearButton() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let mic = app.buttons["search-voice"], mask = app.buttons["search-incognito"], clear = app.buttons["search-clear"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        XCTAssertTrue(mask.exists)
        field.typeText("ovens")
        XCTAssertTrue(clear.waitForExistence(timeout: 2), "the clear button comes in")
        XCTAssertTrue(mic.waitForNonExistence(timeout: 2), "the mic goes")
        XCTAssertTrue(mask.waitForNonExistence(timeout: 2), "the incognito toggle goes")
        clear.tap()
        XCTAssertTrue(mic.waitForExistence(timeout: 2), "the mic is back")
        XCTAssertTrue(mask.waitForExistence(timeout: 2), "the incognito toggle is back")
        XCTAssertTrue(clear.waitForNonExistence(timeout: 2), "the clear button goes")
    }

    /// In incognito, typing swaps only the mask for the clear button: the word stays beside it,
    /// and the typed text stops short of the word.
    func testTheIncognitoWordStaysWhileTyping() {
        launch()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["search-incognito"].tap()
        waitForValue("On", of: app.buttons["search-incognito"])
        field.typeText("a long query that runs on and on")
        XCTAssertTrue(app.buttons["search-clear"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["search-incognito"].waitForNonExistence(timeout: 2))
        let word = app.staticTexts["Incognito"]
        XCTAssertTrue(word.exists, "the word stays while there is text")
        XCTAssertLessThanOrEqual(field.frame.maxX, word.frame.minX, "the text stops short of the word")
        keep("incognito word with text")
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
