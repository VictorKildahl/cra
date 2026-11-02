import CraCore
import Testing

struct ToolbarColorTests {
    @Test(arguments: [
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
