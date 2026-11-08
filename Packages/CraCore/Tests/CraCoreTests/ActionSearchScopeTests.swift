import CraCore
import Testing

/// The command bar's Actions scope (#195, Arc's typeTravel): which actions it lists and in what order.
struct ActionSearchScopeTests {
    typealias C = ActionSearchScope.Candidate<String>

    /// New Tab… and Open Command Bar would only reopen the bar; everything else is listed.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195"), arguments: [("newTab", false), ("editURL", false), ("archiveTab", true), ("toggleSidebar", true)])
    func barOpenersAreLeftOut(id: String, listed: Bool) {
        #expect(ActionSearchScope.lists(actionID: id) == listed)
    }

    /// Nothing typed: every action, the most used first, the others in menu order.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func nothingTypedListsByUseThenMenuOrder() {
        let actions = [
            C(id: "new-tab", score: 0, uses: 0),
            C(id: "archive", score: 0, uses: 4),
            C(id: "reload", score: 0, uses: 0),
            C(id: "sidebar", score: 9, uses: 1),
        ]
        #expect(ActionSearchScope.rank(actions, typed: false) == ["archive", "sidebar", "new-tab", "reload"])
    }

    /// Typed: actions the text doesn't name drop out, the best name leads, use breaks ties.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func typedRanksByMatchThenUse() {
        let actions = [
            C(id: "unrelated", score: 0, uses: 10),
            C(id: "add-top-split", score: 68, uses: 0),
            C(id: "add-split-view", score: 68, uses: 2),
            C(id: "split-prefix", score: 80, uses: 0),
        ]
        #expect(ActionSearchScope.rank(actions, typed: true) == ["split-prefix", "add-split-view", "add-top-split"])
    }

    /// Use counts are capped: a much-used action can't outrank one the text names better by far.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func useCannotBuryABetterName() {
        let actions = [C(id: "habit", score: 50, uses: 500), C(id: "named", score: 80, uses: 0)]
        #expect(ActionSearchScope.rank(actions, typed: true) == ["named", "habit"])
    }
}
