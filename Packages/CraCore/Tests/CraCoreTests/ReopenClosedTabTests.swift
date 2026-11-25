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

    // MARK: Only this Space (#601, not in Arc)

    /// The issue's steps: Tab 1 closed in Space A, then Tab 2 in Space B, then ⇧⌘T back in Space A.
    /// Arc (and Cra by default) switches to Space B for Tab 2; with Only this Space it's Tab 1.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/601")) func onlyThisSpaceReopensTheTabClosedHere() {
        let tab1 = UUID(), tab2 = UUID()
        let archived = [
            ReopenClosedTab.ArchivedTab(id: tab2, archivedAt: Date(timeIntervalSince1970: 200)),
            ReopenClosedTab.ArchivedTab(id: tab1, archivedAt: Date(timeIntervalSince1970: 100)),
        ]
        let arc = ReopenClosedTab.next(closedPinned: [], closedPeek: nil, archived: archived)
        #expect(arc?.restoration == .archived(tab2), "by default, the tab closed last in any Space, as in Arc")

        let here = ReopenClosedTab.next(closedPinned: [], closedPeek: nil, archived: archived, isInCurrentSpace: { $0 == tab1 })
        #expect(here?.restoration == .archived(tab1))
    }

    /// A pinned tab closed in another Space stays on the stack for when you go back there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/601")) func onlyThisSpaceKeepsOtherSpacesPinnedTabs() {
        let here = UUID(), there = UUID()
        let stack = [
            ReopenClosedTab.ClosedPinnedTab(id: there, url: "https://example.com/there", closedAt: Date(timeIntervalSince1970: 300)),
            ReopenClosedTab.ClosedPinnedTab(id: here, url: "https://example.com/here", closedAt: Date(timeIntervalSince1970: 200)),
        ]
        let decision = ReopenClosedTab.next(
            closedPinned: stack, closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: there, archivedAt: Date(timeIntervalSince1970: 250))],
            isInCurrentSpace: { $0 == here }
        )
        #expect(decision?.restoration == .pinned(id: here, url: "https://example.com/here", title: nil, paneStates: []))
        #expect(decision?.remainingPinned.map(\.id) == [there])
    }

    /// A Peek closed over a tab in another Space, or with no tab, isn't this Space's.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/601")) func onlyThisSpaceSkipsAnotherSpacesPeek() {
        let here = UUID(), there = UUID()
        let peek = ReopenClosedTab.ClosedPeek(url: "https://example.com/peek", tabID: there, closedAt: Date(timeIntervalSince1970: 300))
        let decision = ReopenClosedTab.next(
            closedPinned: [], closedPeek: peek,
            archived: [ReopenClosedTab.ArchivedTab(id: here, archivedAt: Date(timeIntervalSince1970: 100))],
            isInCurrentSpace: { $0 == here }
        )
        #expect(decision?.restoration == .archived(here))
        #expect(decision?.remainingPeek == peek, "the Peek is still there for its own Space")

        let loose = ReopenClosedTab.ClosedPeek(url: "https://example.com/peek", tabID: nil, closedAt: Date(timeIntervalSince1970: 300))
        #expect(ReopenClosedTab.next(closedPinned: [], closedPeek: loose, archived: [], isInCurrentSpace: { _ in true }) == nil)
    }

    /// Nothing closed in this Space: ⇧⌘T does nothing rather than leave the Space.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/601")) func onlyThisSpaceWithNothingClosedHereStays() {
        let there = UUID()
        let decision = ReopenClosedTab.next(
            closedPinned: [ReopenClosedTab.ClosedPinnedTab(id: there, closedAt: Date())],
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: UUID(), archivedAt: Date())],
            isInCurrentSpace: { _ in false }
        )
        #expect(decision == nil)
    }

    /// Settings ▸ Tabs ▸ "Reopen tabs from this Space only": off by default (Arc), and kept.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/601")) func onlyThisSpaceSettingIsOffByDefaultAndSaved() throws {
        let older = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!older.reopenClosedTabCurrentSpaceOnly)
        var on = AppSettings()
        on.reopenClosedTabCurrentSpaceOnly = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).reopenClosedTabCurrentSpaceOnly)
    }
    // #806: ⌘Z right after Remove Favorite puts the favorite back. A space's own favorite is archived
    // in the same moment, so the tie goes to the favorite, not to the archive (which reopens in Pinned).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/806")) func undoBringsBackTheFavoriteRemovedLast() {
        let fav = UUID(), older = UUID()
        let at = Date(timeIntervalSince1970: 200)
        let decision = ReopenClosedTab.next(
            closedPinned: [],
            closedPeek: nil,
            archived: [ReopenClosedTab.ArchivedTab(id: fav, archivedAt: at), ReopenClosedTab.ArchivedTab(id: older, archivedAt: Date(timeIntervalSince1970: 100))],
            removedFavorite: ReopenClosedTab.RemovedFavorite(id: fav, removedAt: at)
        )
        #expect(decision?.restoration == .favorite(fav))
        #expect(ReopenClosedTab.next(closedPinned: [], closedPeek: nil, archived: [],
                                     removedFavorite: .init(id: fav, removedAt: at))?.restoration == .favorite(fav),
                "a shared favorite leaves nothing in the archive and still comes back")
    }

    // #806: Arc's undo is a stack: what was closed after the removal comes back first, then the favorite.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/806")) func undoReopensWhatClosedAfterTheRemovalFirst() {
        let fav = UUID(), tab = UUID(), pinned = UUID()
        let removal = ReopenClosedTab.RemovedFavorite(id: fav, removedAt: Date(timeIntervalSince1970: 100))
        let later = Date(timeIntervalSince1970: 200)
        #expect(ReopenClosedTab.next(closedPinned: [], closedPeek: nil, archived: [.init(id: tab, archivedAt: later)],
                                     removedFavorite: removal)?.restoration == .archived(tab))
        #expect(ReopenClosedTab.next(closedPinned: [.init(id: pinned, closedAt: later)], closedPeek: nil, archived: [],
                                     removedFavorite: removal)?.restoration == .pinned(id: pinned, url: nil, title: nil, paneStates: []))
        #expect(ReopenClosedTab.next(closedPinned: [], closedPeek: .init(url: "https://a.example", tabID: nil, closedAt: later), archived: [],
                                     removedFavorite: removal)?.restoration == .peek(url: "https://a.example", tabID: nil))
        #expect(ReopenClosedTab.next(closedPinned: [], closedPeek: nil, archived: [.init(id: tab, archivedAt: Date(timeIntervalSince1970: 50))],
                                     removedFavorite: removal)?.restoration == .favorite(fav), "an older close waits")
    }

}
