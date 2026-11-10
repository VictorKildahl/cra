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
}
