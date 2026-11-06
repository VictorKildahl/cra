import CraCore
import Testing

/// A collapsed pinned section keeps the pinned row you were last on in sight (Arc's
/// peekedPinnedSidebarItemID; X DM 6 Nov 2026).
struct PinnedPeekTests {
    let reddit = "reddit", mail = "mail", split = "split", pane = "pane"

    @Test func aFavoriteOrTodayTabKeepsTheLastPinnedRow() {
        #expect(PinnedPeek.showing(pinnedRow: nil, peek: reddit) == reddit)
        #expect(PinnedPeek.showing(pinnedRow: mail, peek: reddit) == mail)
        #expect(PinnedPeek.showing(pinnedRow: String?.none, peek: nil) == nil)
    }

    @Test func collapsingKeepsOnlyTheOpenTabsRow() {
        #expect(PinnedPeek.collapsing(openPinnedRow: reddit) == reddit)
        #expect(PinnedPeek.collapsing(openPinnedRow: String?.none) == nil)
    }

    @Test func closingTheTabOrAPaneOfItsSplitDropsIt() {
        #expect(PinnedPeek.closing(reddit, rowOfClosed: nil, peek: reddit) == nil)
        #expect(PinnedPeek.closing(pane, rowOfClosed: split, peek: split) == nil)
        #expect(PinnedPeek.closing(mail, rowOfClosed: nil, peek: reddit) == reddit)
        #expect(PinnedPeek.closing(mail, rowOfClosed: nil, peek: nil) == nil)
    }

    @Test func listsTheOpenAndPeekedRowsInSidebarOrderWhileStillPinned() {
        let rows = [mail, split, reddit]
        #expect(PinnedPeek.listed(open: reddit, peek: mail, pinnedRows: rows) == [mail, reddit])
        #expect(PinnedPeek.listed(open: reddit, peek: reddit, pinnedRows: rows) == [reddit])
        #expect(PinnedPeek.listed(open: nil, peek: "unpinned", pinnedRows: rows) == [])
        #expect(PinnedPeek.listed(open: String?.none, peek: nil, pinnedRows: rows) == [])
    }
}
