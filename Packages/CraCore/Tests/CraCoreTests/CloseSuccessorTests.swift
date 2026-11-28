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

    /// #841 asked whether ⌘W leaving a Favorite open is meant to be: it is, as in Arc. ⌘W on a silent Favorite
    /// deselects it and leaves its page running, at its pinned page or taken back there;
    /// one playing sound and Close Tab in its own right-click menu let the page go; a pinned tab in the list unloads.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/841"))
    func commandWOnAFavoriteDeselectsItAsInArc() {
        #expect(CloseSuccessor.pinnedClose(isFavorite: true) == .deselectKeepingPage)
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, awayFromPinnedPage: true) == .deselectGoingHome)
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, audible: true) == .unloadToPinnedPage)
        #expect(CloseSuccessor.pinnedClose(isFavorite: true, fromItsMenu: true) == .unloadToPinnedPage)
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

    /// ⌘W on Favorites one after another (F1, F2, F3 opened in turn) went F3 → F2 → F3 → F2 in 0.1.58: since #740 a
    /// Favorite closed with ⌘W keeps its page, so it still counted as the tab shown before the next one. In Arc each ⌘W
    /// goes one further back through the Favorites visited before (Discord report, 26 Nov 2026).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/870"))
    func repeatedCmdWOnFavoritesWalksBackThroughTheOnesVisitedBefore() {
        var shown = ShownTabs<String>()
        shown.left("F1"); shown.left("F2")                // F1 → F2 → F3: F3 on screen
        var closed: Set<String> = []
        let loaded: Set<String> = ["F1", "F2", "F3"]
        func close(_ id: String) -> String? {
            closed.insert(id)
            let next = CloseSuccessor.afterDeselectedFavorite(closing: id, isSplit: false, shownBefore: shown.newestFirst) {
                CloseSuccessor.counts(hasPage: loaded.contains($0), closedWithCmdW: closed.contains($0))
            }
            if let next { shown.left(id); closed.remove(next) }
            return next
        }
        #expect(close("F3") == "F2")
        #expect(close("F2") == "F1", "not back to F3, closed with ⌘W a moment ago")
        #expect(close("F1") == nil, "every Favorite left was closed: nothing to go back to")
    }

    /// A Favorite closed with ⌘W is closed though its page runs on: no close goes back to it, Today tabs' included.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/870"))
    func aFavoriteClosedWithCmdWIsNotSomewhereToGoBackTo() {
        #expect(!CloseSuccessor.counts(hasPage: true, closedWithCmdW: true))
        #expect(CloseSuccessor.counts(hasPage: true, closedWithCmdW: false))
        #expect(!CloseSuccessor.counts(hasPage: false, closedWithCmdW: false))
        // F → A, back to F, ⌘W on F → A; closing A then hands over to its neighbour, not back to F.
        #expect(CloseSuccessor.next(closing: "A", previous: "F", hasPage: { CloseSuccessor.counts(hasPage: true, closedWithCmdW: $0 == "F") },
                                    list: today) == "B")
    }

    /// The walk skips what isn't open and stops at the newest tab that is: one without a page, one in another space (the
    /// caller leaves those out of `counts`) or one closed with ⌘W is passed over. A Favorite split still hands over to
    /// nothing, as a pinned split does (Arc 1.171).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/870"))
    func theWalkSkipsWhatIsNotOpen() {
        let before = ["F2", "T", "F1", "D"]
        #expect(CloseSuccessor.afterDeselectedFavorite(closing: "F3", isSplit: false, shownBefore: before) { $0 != "F2" } == "T")
        #expect(CloseSuccessor.afterDeselectedFavorite(closing: "F3", isSplit: false, shownBefore: before) { $0 == "D" } == "D")
        #expect(CloseSuccessor.afterDeselectedFavorite(closing: "F3", isSplit: false, shownBefore: ["F3", "F2"]) { _ in true } == "F2")
        #expect(CloseSuccessor.afterDeselectedFavorite(closing: "FS", isSplit: true, shownBefore: before) { _ in true } == nil)
    }

    /// The tabs a window showed, newest first: each appears once, at the place it was last left, and the list is capped.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/870"))
    func shownTabsKeepsEachTabOnceNewestFirst() {
        var shown = ShownTabs<Int>(limit: 3)
        for id in [1, 2, 3, 2, 4] { shown.left(id) }
        #expect(shown.newestFirst == [4, 2, 3])
        shown.replace(3, with: 9)
        #expect(shown.newestFirst == [4, 2, 9])
    }
}
