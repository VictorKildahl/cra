import CraCore
import Testing

/// Arc's ⌘T keeps five rows in view and more behind them (#805, the reporter's recording of Arc):
/// ↓ past the fifth row scrolls the list one row, past the last row the selection goes back to the
/// top. Cra listed five rows and no more, so the rest of the history matching the text was out of reach.
struct CommandBarRowWindowTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/805")) func theBarHoldsMoreRowsThanItShows() {
        // Arc's fifteen (the reporter's recording), five of them in view.
        #expect(CommandBarRowWindow.maxSuggestions == 15)
        #expect(CommandBarRowWindow.visibleRows == 5)
        #expect(CommandBarRowWindow.shown(count: 10, banner: false) == 5)
        #expect(CommandBarRowWindow.shown(count: 3, banner: false) == 3)
        // The banner takes the last place in view, not a row of the list.
        #expect(CommandBarRowWindow.shown(count: 10, banner: true) == 4)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/805")) func theArrowsScrollOneRowAtATime() {
        var first = 0
        var seen: [Int] = []
        for selected in 0..<10 {
            first = CommandBarRowWindow.first(selected: selected, count: 10, shown: 5, previous: first)
            seen.append(first)
        }
        // Rows 0–4 in view while the selection is on them, then one row more per ↓.
        #expect(seen == [0, 0, 0, 0, 0, 1, 2, 3, 4, 5])
        // ↑ from the bottom: the list stays until the selection reaches its top row.
        first = CommandBarRowWindow.first(selected: 8, count: 10, shown: 5, previous: 5)
        #expect(first == 5)
        first = CommandBarRowWindow.first(selected: 4, count: 10, shown: 5, previous: 5)
        #expect(first == 4)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/805")) func aWrapBringsThatEndIntoView() {
        // ↓ on the last row selects the first: back to the top.
        #expect(CommandBarRowWindow.first(selected: 0, count: 10, shown: 5, previous: 5) == 0)
        // ↑ on the first row selects the last: the bottom five.
        #expect(CommandBarRowWindow.first(selected: 9, count: 10, shown: 5, previous: 0) == 5)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/805")) func aShorterListStaysAtTheTop() {
        #expect(CommandBarRowWindow.first(selected: 3, count: 4, shown: 5, previous: 2) == 0)
        // A new, shorter list after typing: never past its end.
        #expect(CommandBarRowWindow.first(selected: 0, count: 6, shown: 5, previous: 5) == 0)
        #expect(CommandBarRowWindow.first(selected: 5, count: 6, shown: 5, previous: 5) == 1)
    }
}
