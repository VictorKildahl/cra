import CraCore
import Foundation
import Testing

/// Arc's "Clear unselected Today tabs": the selected tab and tabs playing sound stay.
struct TodayClearTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    var rows: [TodayClear.Row] {
        [.init(id: a, tabs: [a]), .init(id: b, tabs: [b]), .init(id: UUID(), tabs: [c, d]), .init(id: e, tabs: [e])]
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/406"))
    func selectedAndPlayingTabsStay() {
        #expect(TodayClear.archived(rows, selected: [e], playing: [b]) == [a, c, d])
    }

    /// A split stays whole when one of its panes is selected or playing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/406"))
    func splitStaysWhole() {
        #expect(TodayClear.archived(rows, selected: [d], playing: []) == [a, b, e])
        #expect(TodayClear.archived(rows, selected: [], playing: [c]) == [a, b, e])
    }

    @Test func nothingSelectedOrPlayingClearsAll() {
        #expect(TodayClear.archived(rows, selected: [], playing: []) == [a, b, c, d, e])
    }

    /// The Tabs menu's Clear Today asks only whether Clear would take anything (GitHub #622): the
    /// same answer as `archived`, from the first row it would take. An empty row (a folder with
    /// no tabs) takes nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func archivesAnyAgreesWithArchived() {
        let empty = TodayClear.Row(id: UUID(), tabs: [])
        let cases: [([TodayClear.Row], Set<UUID>, Set<UUID>)] = [
            (rows, [], []), (rows, [a, b, e], [c]), (rows, [a, b], [d, e]), (rows, [a], []),
            ([], [], []), ([empty], [], []), ([empty, .init(id: a, tabs: [a])], [a], []),
            ([empty, .init(id: a, tabs: [a])], [], []),
        ]
        for (rows, selected, playing) in cases {
            #expect(TodayClear.archivesAny(rows, selected: selected, playing: playing)
                    == !TodayClear.archived(rows, selected: selected, playing: playing).isEmpty)
        }
        #expect(!TodayClear.archivesAny(rows, selected: [a, b, c, e], playing: []), "every row keeps a tab")
        #expect(TodayClear.archivesAny(rows, selected: [a, b, c], playing: []), "the last row is idle")
    }
}
