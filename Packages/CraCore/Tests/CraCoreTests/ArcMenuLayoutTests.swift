import CraCore
import Testing

/// Arc's menu geometry: the sidebar + menu (Arc 1.172.1, live, 9 Nov 2026) and the back and forward
/// list (a 2x capture, 13 Nov 2026, GitHub #416).
struct ArcMenuLayoutTests {
    /// New Space, New Folder | New Easel, New Boost | New Split, New Tab: rows 194×40 at y 8, 48 | 105,
    /// 145 | 202, 242, separators at y 96 and 193, a 290 pt fill with the tail under it.
    @Test func thePlusMenuKeepsArcsMeasuredRows() {
        let plus = ArcMenuLayout(groups: [2, 2, 2], tail: .bottom)
        #expect(plus.rowTops == [8, 48, 105, 145, 202, 242])
        #expect(plus.separatorTops == [96, 193])
        #expect(plus.fillHeight == 290)
        #expect(plus.height == 296)
        #expect(plus.fillTop == 0)
    }

    /// Three history entries make a 136 pt fill (272 px in Arc's 2x capture), the tail above it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/416"))
    func theHistoryListIsOneGroupUnderItsTail() {
        let list = ArcMenuLayout(groups: [3], tail: .top)
        #expect(list.rowTops == [8, 48, 88])
        #expect(list.separatorTops.isEmpty)
        #expect(list.fillHeight == 136)
        #expect(list.fillTop == 6)
        #expect(list.height == 142)
    }
}
