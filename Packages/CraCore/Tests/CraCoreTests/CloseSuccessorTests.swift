import CraCore
import Testing

/// The tab shown after a close (Arc 1.171, GitHub #105). The cases are the runs on Arc.
struct CloseSuccessorTests {
    // Today, top to bottom; S is pinned.
    let today = ["C", "B", "A", "D"]

    func next(_ closing: String, previous: String?, loaded: Set<String>, list: [String]? = nil) -> String? {
        CloseSuccessor.next(closing: closing, previous: previous, hasPage: loaded.contains, list: list ?? today)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/105"))
    func backToTheTabShownBeforeWhileItHasAPage() {
        // A opened from S in the background, reached from D: back to D, not to S.
        #expect(next("A", previous: "D", loaded: ["S", "D", "A"]) == "D")
        // A pinned tab goes back the same way.
        #expect(next("S", previous: "P2", loaded: ["S", "P2"], list: []) == "P2")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/105"))
    func aPreviousTabWithoutAPageDoesNotCount() {
        // Closed (a pinned tab's ⌘W) or not loaded since launch: the neighbour above instead.
        #expect(next("D", previous: "S", loaded: ["D"]) == "A")
        #expect(next("B", previous: "D", loaded: ["B"]) == "C")
        // A pinned tab hands over to nothing, even with other pages loaded.
        #expect(next("P2", previous: "S", loaded: ["P2", "C"], list: []) == nil)
        #expect(next("S", previous: nil, loaded: ["S"], list: []) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/105"))
    func theNeighbourAboveThenBelow() {
        #expect(next("B", previous: nil, loaded: []) == "C")
        #expect(next("C", previous: "B", loaded: ["C"]) == "B")
        #expect(next("C", previous: nil, loaded: []) == "B")
        #expect(next("D", previous: nil, loaded: []) == "A")
        // The last tab: nothing (Arc doesn't load a pinned tab instead).
        #expect(next("C", previous: nil, loaded: [], list: ["C"]) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/105"))
    func aPinnedSplitHandsOverToNothing() {
        #expect(CloseSuccessor.afterPinned(closing: "PS", isSplit: true, previous: "D", hasPage: { _ in true }) == nil)
        #expect(CloseSuccessor.afterPinned(closing: "F1", isSplit: false, previous: "D", hasPage: { _ in true }) == "D")
        #expect(CloseSuccessor.afterPinned(closing: "F1", isSplit: false, previous: "D", hasPage: { _ in false }) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/105"))
    func theClosingTabIsNeverItsOwnSuccessor() {
        #expect(next("A", previous: "A", loaded: ["A"]) == "B")
    }

    /// ⌘W on a Favorite only deselects it, its page left running, as in Arc 1.173.1 (#740: a test page's load time
    /// and counter carried on, and the server saw no second load). A pinned tab still unloads back to its pinned page.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/740"))
    func closingAFavoriteKeepsItsPage() {
        #expect(CloseSuccessor.pinnedClose(isFavorite: true) == .deselectKeepingPage)
        #expect(CloseSuccessor.pinnedClose(isFavorite: false) == .unloadToPinnedPage)
    }

    /// Close Tab in a Favorite's right-click menu closes it, as in Arc 1.173.1: its page is let go, and a click on the
    /// Favorite loads it again. Only ⌘W keeps the page running (#740). Before, the menu's Close Tab did what ⌘W does,
    /// so nothing let a Favorite's page go, and on a Favorite loaded in the background it did nothing at all.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/740"))
    func closeTabInAFavoritesMenuLetsItsPageGo() {
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, fromItsMenu: true) == .unloadToPinnedPage, "its menu's Close Tab unloads it")
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, fromItsMenu: false) == .deselectKeepingPage, "⌘W still keeps it (#740)")
        #expect(CloseSuccessor.pinnedClose(isFavorite: false, fromItsMenu: true) == .unloadToPinnedPage)
    }

    /// ⌘W on a Favorite playing sound closes it, as in Arc 1.174.2: a test video's page got `pagehide` on ⌘W and a click
    /// on the Favorite loaded it afresh, while a page without sound ran on (#740). 0.1.56 kept every Favorite's page, so a
    /// YouTube video played on after ⌘W (#803).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/803"))
    func closingAFavoritePlayingSoundLetsItsPageGo() {
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, audible: true) == .unloadToPinnedPage, "a video stops")
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, audible: false) == .deselectKeepingPage, "a silent page runs on (#740)")
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, fromItsMenu: true, audible: true) == .unloadToPinnedPage)
        #expect(CloseSuccessor.pinnedClose(isFavorite: false, audible: true) == .unloadToPinnedPage)
    }

    /// ⌘W on a silent Favorite away from its pinned page takes it back there, as in Arc 1.174.2: the pinned page loaded in
    /// the background at the moment of ⌘W, and a click on the Favorite showed that same load. 0.1.56 left it on the page
    /// it had moved to, so CRM tools pinned as Favorites no longer went back to their pinned page (#804).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/804"))
    func closingAFavoriteAwayFromItsPageTakesItBack() {
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, awayFromPinnedPage: true) == .deselectGoingHome)
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, awayFromPinnedPage: false) == .deselectKeepingPage, "on its page it runs on (#740)")
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, audible: true, awayFromPinnedPage: true) == .unloadToPinnedPage, "sound still closes it (#803)")
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, fromItsMenu: true, awayFromPinnedPage: true) == .unloadToPinnedPage)
        #expect(CloseSuccessor.pinnedClose(isFavorite: false, awayFromPinnedPage: true) == .unloadToPinnedPage)
    }
}
