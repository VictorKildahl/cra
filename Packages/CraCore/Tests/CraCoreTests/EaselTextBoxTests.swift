import CraCore
import Testing

struct EaselTextBoxTests {
    /// GitHub #580: a text longer than the 240 pt box was cut off ("…hover over" lost "over"), and
    /// Return or ⇧Return ended the typing instead of starting a line. The box widens with the text up
    /// to 560 pt, then wraps and grows down; Return and ⇧Return start a new line.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func longTextWidensThenWrapsAndReturnStartsALine() {
        let start = Easel.Rect(x: 100, y: 200, width: 240, height: 27)
        // A line of 400 pt fits on one line in a wider box.
        let wide = Easel.fittedText(start, longestLine: 400, size: 18) { _ in 26 }
        #expect(wide == Easel.Rect(x: 100, y: 200, width: 408, height: 27))
        // A line of 900 pt wraps at 560 pt, and the box is as tall as the wrapped lines.
        let wrapped = Easel.fittedText(start, longestLine: 900, size: 18) { width in width == 560 ? 52 : 26 }
        #expect(wrapped == Easel.Rect(x: 100, y: 200, width: 560, height: 52))
        #expect(EaselTextKey(command: "insertNewline:") == .newline)
        #expect(EaselTextKey(command: "insertLineBreak:") == .newline)
        #expect(EaselTextKey(command: "insertNewlineIgnoringFieldEditor:") == .newline)
    }

    /// Escape ends the typing; other commands are the text field's.
    @Test func escapeFinishesTyping() {
        #expect(EaselTextKey(command: "cancelOperation:") == .finish)
        #expect(EaselTextKey(command: "insertTab:") == .pass)
        #expect(EaselTextKey(command: "moveLeft:") == .pass)
    }

    /// An empty or short text keeps a new box's 240 pt and one line at its size.
    @Test func shortTextKeepsOneLineOfTheNewBox() {
        #expect(Easel.textWidth(longestLine: 0) == 240)
        #expect(Easel.textWidth(longestLine: 120) == 240)
        #expect(Easel.textHeight(wrappedHeight: 0, size: 18) == 27)
        #expect(Easel.textHeight(wrappedHeight: 10, size: 40) == 58)
        #expect(Easel.textHeight(wrappedHeight: 120.2, size: 18) == 121)
    }
}
