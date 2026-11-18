import CoreGraphics
import CraCore
import Testing

/// The split card's panes in the tab switcher (#554), against Arc 1.172's measured card.
struct SwitcherSplitLayoutTests {
    let thumb = CGSize(width: 158, height: 105)

    /// Arc's 50/50 split on its 158×105 thumbnail: panes 4 pt in, 4 pt apart, 97 pt tall, and
    /// 73 and 72.5 pt wide (146 and 145 px at 2×).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/554"))
    func anEvenSplitMatchesArc() {
        let f = SwitcherSplitLayout.paneFrames(in: thumb, widths: [0.5, 0.5])
        #expect(f.count == 2)
        #expect(f[0] == CGRect(x: 4, y: 4, width: 73, height: 97))
        #expect(f[1].minX == 81 && f[1].maxX == 154 && f[1].height == 97)
        #expect(f[1].minX - f[0].maxX == 4)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/554"))
    func widthsFollowThePanesShares() {
        let f = SwitcherSplitLayout.paneFrames(in: thumb, widths: [0.75, 0.25])
        #expect(f[0].width > 2.5 * f[1].width && f[0].width < 3.5 * f[1].width)
        #expect(f.last?.maxX == 154, "the last pane ends 4 pt from the frame's edge")
        let three = SwitcherSplitLayout.paneFrames(in: thumb, widths: [1, 1, 1])
        #expect(three.count == 3 && three.last?.maxX == 154)
        #expect(zip(three, three.dropFirst()).allSatisfy { $1.minX - $0.maxX == 4 })
        #expect(three.allSatisfy { ($0.minX * 2).rounded() == $0.minX * 2 }, "on half points")
    }

    @Test func aspectIsThePanesShape() {
        let a = SwitcherSplitLayout.paneAspect(in: thumb, widths: [0.5, 0.5], pane: 0)
        #expect(a == CGFloat(73) / CGFloat(97))
        #expect(SwitcherSplitLayout.paneAspect(in: thumb, widths: [0.5, 0.5], pane: 2) == nil)
        #expect(SwitcherSplitLayout.paneFrames(in: thumb, widths: [0, 0]).count == 2, "zero shares split evenly")
    }
}
