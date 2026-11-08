import CraCore
import Testing

struct ToolbarColorTests {
    /// A tab's toolbar colour: its page's report, else the colour the tab saved, else white, so a page
    /// coming back never flashes a white bar it didn't have (#84).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/84"), arguments: [
        // The page's own report wins over what the tab remembers.
        ("#602040", "#205060", "#602040" as String?),
        // Not reported yet (no live page, or a page still loading): the remembered colour.
        ("", "#205060", "#205060"),
        (nil, "#205060", "#205060"),
        ("none", "#205060", "#205060"),
        // Nothing known: white, never the canvas.
        ("", nil, nil),
        (nil, nil, nil),
        (nil, "", nil),
        ("rgb(1, 2, 3)", "#12345", nil),
    ] as [(String?, String?, String?)])
    func reportedThenRememberedThenWhite(reported: String?, remembered: String?, bar: String?) {
        #expect(ToolbarColor.hex(reported: reported, remembered: remembered) == bar)
    }
}
