import CoreGraphics
import CraCore
import Foundation
import Testing

/// Split pane layout and Arc's View ▸ Expand Current Split, measured on Arc 1.172.2 (11 Nov 2026) in a
/// window 1728 pt wide with the sidebar hidden: the panes share a 1708 pt content area, 10 pt apart.
struct SplitPaneLayoutTests {
    let a = UUID(), b = UUID(), c = UUID()

    func lengths(_ ids: [UUID], factors: [UUID: CGFloat], width: CGFloat = 1708, orientation: SplitOrientation = .horizontal) -> [CGFloat] {
        let size = orientation == .horizontal ? CGSize(width: width, height: 1032) : CGSize(width: 1708, height: width)
        let layout = SplitPaneLayout(panes: ids.map { .init(id: $0, factor: factors[$0] ?? 0) }, orientation: orientation, containerSize: size)
        let frames = layout.compute().frames
        return ids.map { orientation == .horizontal ? frames[$0]!.width : frames[$0]!.height }
    }

    @Test func equalPanesShareTheContent() {
        // Arc: two 849 pt panes.
        #expect(lengths([a, b], factors: [a: 0.5, b: 0.5]) == [849, 849])
    }

    @Test func expandGivesTheOtherPanesTheMinimumAndTheFocusedOneTheRest() {
        // Arc: the focused right pane 1478 pt, the left one 220 pt.
        let f = SplitPaneLayout.expanding(b, in: [a, b])
        #expect(f == [a: 0, b: 1])
        #expect(lengths([a, b], factors: f) == [220, 1478])
        // Three panes: 220 + 1248 + 220, whichever is focused.
        #expect(lengths([a, b, c], factors: SplitPaneLayout.expanding(b, in: [a, b, c])) == [220, 1248, 220])
        #expect(lengths([a, b, c], factors: SplitPaneLayout.expanding(c, in: [a, b, c])) == [220, 220, 1248])
    }

    @Test func expandingAgainChangesNothingAndAnotherPaneSwaps() {
        // Arc keeps one menu title and no toggle: a second Expand leaves the panes where they are.
        let once = SplitPaneLayout.expanding(b, in: [a, b])
        #expect(SplitPaneLayout.expanding(b, in: [a, b]) == once)
        // Expanding the small pane makes it the big one.
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b])) == [1478, 220])
    }

    @Test func anExpandedSplitKeepsTheMinimumWhenTheWindowNarrows() {
        // Arc at a 1200 pt window: the focused pane 950, the other still 220 (not its share of the width).
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b]), width: 1180) == [950, 220])
    }

    @Test func expandInAVerticalSplitCountsTheDividerBelowAPaneInItsMinimum() {
        // Arc, stacked in a 1064 pt high content area with the middle pane focused: 210 | 614 | 220.
        // A pane above a divider keeps 220 with it, the bottom pane 220 of its own.
        let three = SplitPaneLayout.expanding(b, in: [a, b, c])
        #expect(lengths([a, b, c], factors: three, width: 1064, orientation: .vertical) == [210, 614, 220])
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b]), width: 1064, orientation: .vertical) == [834, 220])
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(b, in: [a, b]), width: 1064, orientation: .vertical) == [210, 844])
    }

    @Test func storedFactorsOfAnExpandedSplitSurviveNormalizing() {
        // sidebar.json keeps 1 and 0, as Arc's itemWidthFactors do; the layout applies the minimum.
        let n = SplitPaneLayout.normalizedFactors(ids: [a, b, c], stored: [a: 0, b: 1, c: 0])
        #expect(n == [a: 0, b: 1, c: 0])
    }

    @Test func aDividerDragFromAnExpandedSplitStartsWhereThePanesAre() {
        // Dragging the divider 30 pt right from 220 | 1478 gives 250 | 1448, not a jump.
        let layout = SplitPaneLayout(panes: [.init(id: a, factor: 0), .init(id: b, factor: 1)], orientation: .horizontal,
                                     containerSize: CGSize(width: 1708, height: 1032))
        let dragged = layout.dragging(dividerAfter: 0, by: 30).factors
        #expect(lengths([a, b], factors: dragged) == [250, 1448])
        // Dragging it left stops at the minimum.
        let left = layout.dragging(dividerAfter: 0, by: -100).factors
        #expect(lengths([a, b], factors: left) == [220, 1478])
    }

    @Test func aPaneWithNoRoomForTheMinimumGetsAnEqualShare() {
        // Four panes in 700 pt: each gets 167.5 pt, below Arc's 220 minimum.
        let ids = [a, b, c, UUID()]
        let f = SplitPaneLayout.expanding(a, in: ids)
        #expect(lengths(ids, factors: f, width: 700).allSatisfy { abs($0 - 167.5) <= 0.5 })
    }
}
