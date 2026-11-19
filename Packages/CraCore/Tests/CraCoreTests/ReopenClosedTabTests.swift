import CraCore
import Foundation
import Testing

struct ReopenClosedTabTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/566")) func reopenClosedPinnedTabWhenNoArchivedTabs() {
        let p1 = UUID()
        let now = Date()
        let closedPinned = [ReopenClosedTab.ClosedPinnedTab(id: p1, url: "https://youtube.com/watch?v=abc", title: "Video", closedAt: now)]

        let decision = ReopenClosedTab.next(
            closedPinned: closedPinned,
            closedPeek: nil,
            archived: []
        )

        #expect(decision?.restoration == .pinned(id: p1, url: "https://youtube.com/watch?v=abc", title: "Video", paneStates: []))
        #expect(decision?.remainingPinned.isEmpty == true)
        #expect(decision?.remainingPeek == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/566")) func reopensMostRecentBetweenPinnedAndArchived() {
        let p1 = UUID()
        let t1 = UUID()
        let t1Date = Date(timeIntervalSince1970: 100)
        let p1Date = Date(timeIntervalSince1970: 200)

        // Pinned tab was closed more recently than archived tab
        let decision1 = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: p1, url: "https://youtube.com/watch?v=123", title: "Video 123", closedAt: p1Date)],
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: t1, archivedAt: t1Date)]
        )
        #expect(decision1?.restoration == .pinned(id: p1, url: "https://youtube.com/watch?v=123", title: "Video 123", paneStates: []))
        #expect(decision1?.remainingPinned.isEmpty == true)

        // Next restoration brings back the archived tab
        let decision2 = ReopenClosedTab.next(
            closedPinned: decision1!.remainingPinned,
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: t1, archivedAt: t1Date)]
        )
        #expect(decision2?.restoration == .archived(t1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/566")) func reopensArchivedTabWhenNewerThanPinned() {
        let p1 = UUID()
        let t1 = UUID()
        let p1Date = Date(timeIntervalSince1970: 100)
        let t1Date = Date(timeIntervalSince1970: 200)

        let decision1 = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: p1, closedAt: p1Date)],
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: t1, archivedAt: t1Date)]
        )
        #expect(decision1?.restoration == .archived(t1))
        #expect(decision1?.remainingPinned.count == 1)

        // After archived tab is restored, next restoration brings back pinned tab
        let decision2 = ReopenClosedTab.next(
            closedPinned: decision1!.remainingPinned,
            closedPeek: nil,
            archived: []
        )
        #expect(decision2?.restoration == .pinned(id: p1, url: nil, title: nil, paneStates: []))
    }

    @Test func reopensMostRecentBetweenPeekPinnedAndArchived() {
        let p1 = UUID()
        let t1 = UUID()
        let peekURL = "https://example.com/peek"
        let p1Date = Date(timeIntervalSince1970: 100)
        let t1Date = Date(timeIntervalSince1970: 200)
        let peekDate = Date(timeIntervalSince1970: 300)

        let peek = ReopenClosedTab.ClosedPeek(url: peekURL, tabID: nil, closedAt: peekDate)
        let decision = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: p1, closedAt: p1Date)],
            closedPeek: peek,
            archived: [ReopenClosedTab.ArchivedTab(id: t1, archivedAt: t1Date)]
        )
        #expect(decision?.restoration == .peek(url: peekURL, tabID: nil))
        #expect(decision?.remainingPeek == nil)
        #expect(decision?.remainingPinned.count == 1)
    }

    @Test func skipsAlreadySelectedPinnedTab() {
        let p1 = UUID()
        let t1 = UUID()
        let p1Date = Date(timeIntervalSince1970: 200)
        let t1Date = Date(timeIntervalSince1970: 100)

        // p1 is the most recent closed pinned tab, but it is currently already selected
        let decision = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: p1, closedAt: p1Date)],
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: t1, archivedAt: t1Date)],
            isTabSelected: { $0 == p1 }
        )
        #expect(decision?.restoration == .archived(t1))
        #expect(decision?.remainingPinned.isEmpty == true)
    }

    @Test func skipsUnavailablePinnedTab() {
        let p1 = UUID()
        let p2 = UUID()
        let p1Date = Date(timeIntervalSince1970: 200)
        let p2Date = Date(timeIntervalSince1970: 100)

        // p1 was deleted / removed from sidebar
        let decision = ReopenClosedTab.next(
            closedPinned: [
                ReopenClosedTab.ClosedPinnedTab(id: p1, closedAt: p1Date),
                ReopenClosedTab.ClosedPinnedTab(id: p2, url: "https://example.com", title: "Example", closedAt: p2Date)
            ],
            closedPeek: nil,
            archived: [],
            isPinnedTabAvailable: { $0 == p2 }
        )
        #expect(decision?.restoration == .pinned(id: p2, url: "https://example.com", title: "Example", paneStates: []))
        #expect(decision?.remainingPinned.isEmpty == true)
    }

    @Test func restoresPinnedSplitPaneStates() {
        let p1 = UUID()
        let p2 = UUID()
        let splitID = UUID()
        let now = Date()

        let panes = [
            ReopenClosedTab.PaneState(id: p1, url: "https://example.com/left", title: "Left"),
            ReopenClosedTab.PaneState(id: p2, url: "https://example.com/right", title: "Right")
        ]

        let decision = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: splitID, url: "https://example.com/left", title: "Left", paneStates: panes, closedAt: now)],
            closedPeek: nil,
            archived: []
        )

        #expect(decision?.restoration == .pinned(id: splitID, url: "https://example.com/left", title: "Left", paneStates: panes))
    }

    @Test func emptyHistoryReturnsNil() {
        let decision = ReopenClosedTab.next(
            closedPinned: [],
            closedPeek: nil,
            archived: []
        )
        #expect(decision == nil)
    }
}
