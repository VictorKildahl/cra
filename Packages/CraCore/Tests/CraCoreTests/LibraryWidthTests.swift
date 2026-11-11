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

/// Arc 1.172.2 keeps the page's width beside the Library and moves it with the Library's right
/// edge, past the window's: Cra gave it what was left, 181 pt beside five spaces, where the site
/// laid itself out as a phone column (issue #340).
struct LibraryPageTests {
    /// kKr1Xx's numbers: a 1728 pt window and a 264 pt tab sidebar leave a 1454 pt card, and it
    /// stays 1454 pt beside the 1536 pt Spaces page and the 417 pt Archived Tabs page.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/340"))
    func pageKeepsItsWidth() {
        #expect(LibraryWidth.page(window: 1728, library: 1536, tabSidebar: 264, inset: 10) == 1454)
        #expect(LibraryWidth.page(window: 1728, library: 417, tabSidebar: 264, inset: 10) == 1454)
        // Edge to edge the card has no right inset to keep.
        #expect(LibraryWidth.page(window: 1728, library: 1536, tabSidebar: 264, inset: 0) == 1464)
    }

    /// The Library brought a hidden sidebar out: the page keeps the whole card's width.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/340"))
    func hiddenSidebarKeepsTheWholeCard() {
        #expect(LibraryWidth.page(window: 1728, library: 417, tabSidebar: nil, inset: 10) == 1708)
    }

    /// A tab sidebar wider than the Library: the page fills what the Library leaves, no gap.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/340"))
    func narrowerLibraryLeavesNoGap() {
        #expect(LibraryWidth.page(window: 1728, library: 417, tabSidebar: 450, inset: 10) == 1301)
    }
}
