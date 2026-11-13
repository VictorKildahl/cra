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
}
