import CraCore
import Foundation
import Testing

/// Add Split View, then an open tab picked in the command bar (GitHub #645).
struct SplitPanePickTests {
    static let left = UUID(), empty = UUID(), other = UUID()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/645"))
    func anOpenTabTakesTheEmptyPanesPlace() {
        #expect(SplitPanePick.of(picked: Self.other, emptyPane: Self.empty, panes: [Self.left, Self.empty], sameProfile: true)
            == .join(replacing: Self.empty))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/645"))
    func aTabAlreadyInTheSplitIsSelectedAndTheEmptyPaneGoes() {
        #expect(SplitPanePick.of(picked: Self.left, emptyPane: Self.empty, panes: [Self.left, Self.empty], sameProfile: true)
            == .selectPane(dropping: Self.empty))
    }

    @Test func withoutAnEmptyPaneTheBarSwitchesAsBefore() {
        // ⌘T's "Switch to Tab" row.
        #expect(SplitPanePick.of(picked: Self.other, emptyPane: nil, panes: [Self.left], sameProfile: true) == .switchTo)
    }

    @Test func aTabFromAnotherProfileIsSwitchedTo() {
        // Its page can't move into this profile's space.
        #expect(SplitPanePick.of(picked: Self.other, emptyPane: Self.empty, panes: [Self.left, Self.empty], sameProfile: false) == .switchTo)
    }
}
