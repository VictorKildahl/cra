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
}
