import CraCore
import Testing

/// The Library is Arc's 417 pt whatever the tab sidebar's width (issue #302).
struct LibraryWidthTests {
    /// The report's 218 pt sidebar gave a 288 pt Library and a 175 pt list. Arc's list keeps
    /// 304 pt beside the rail at any tab sidebar width.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/302"))
    func libraryIsArcsWidth() {
        #expect(LibraryWidth.sidebar(window: 1728) == 417)
        #expect(LibraryWidth.sidebar(window: 1728) - LibraryWidth.rail == 304)
    }

    /// The Spaces page still widens to fit its cards, leaving the page 56 pt.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/302"))
    func spacesPageFitsItsCards() {
        #expect(LibraryWidth.sidebar(spacesCards: 300, window: 1728) == 417)
        #expect(LibraryWidth.sidebar(spacesCards: 900, window: 1728) == 900)
        #expect(LibraryWidth.sidebar(spacesCards: 2000, window: 1728) == 1672)
        #expect(LibraryWidth.sidebar(spacesCards: 2000, window: 400) == 417)
    }

    /// Arc's narrowest window is 926 pt, so its page always keeps 926 − 417 = 509 pt beside the
    /// Library. Cra's window goes down to 640 pt, where a fixed 417 pt Library left the page
    /// 223 pt (franvz9 on #302): below 926 the Library gives way, down to 320 pt.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/302"))
    func narrowWindowKeepsThePage() {
        #expect(LibraryWidth.sidebar(window: 926) == 417)
        #expect(LibraryWidth.sidebar(window: 900) == 391)
        #expect(900 - LibraryWidth.sidebar(window: 900) == LibraryWidth.pageMinimum)
        #expect(LibraryWidth.sidebar(window: 640) == LibraryWidth.minimum)
        #expect(640 - LibraryWidth.sidebar(window: 640) == 320)
    }
}
