import CraCore
import Foundation
import Testing

/// Arc's Blank Window: a window whose sidebar is its own, in no space list (Arc 1.172, #220).
struct BlankWindowTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/220"))
    func aBlankWindowsSpaceIsThisWindowAndBelongsToIt() {
        let window = UUID()
        let (space, containers) = BlankWindow.space(window: window, at: date)
        #expect(space.title == "This Window")
        #expect(space.emoji.isEmpty && space.symbol == nil)
        #expect(space.standaloneWindowID == window)
        #expect(space.profileID == nil)  // the normal Default profile, not incognito
        #expect(containers.map(\.id) == [space.favoritesContainerID, space.pinnedContainerID, space.todayContainerID])
        #expect(containers.map(\.container) == [.favorites(spaceID: space.id), .pinned(spaceID: space.id), .today(spaceID: space.id)])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/220"))
    func noSpaceListShowsABlankWindowsSpace() {
        let a = BlankWindow.space(window: UUID(), at: date, id: UUID()).space
        var b = a; b.id = UUID(); b.standaloneWindowID = nil
        var c = a; c.id = UUID(); c.standaloneWindowID = nil
        // Saved with the blank space in the order (an older Cra appended it): it comes out again.
        #expect(BlankWindow.spaceOrder(saved: [c.id, a.id, b.id], spaces: [a, b, c]) == [c.id, b.id])
        // A space the order missed is appended; one the order names that is gone is dropped.
        #expect(BlankWindow.spaceOrder(saved: [b.id, UUID()], spaces: [a, b, c]) == [b.id, c.id])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/220"))
    func aBlankSpaceWithoutItsWindowGoes() {
        let w1 = UUID(), w2 = UUID()
        let kept = BlankWindow.space(window: w1, at: date).space
        let lost = BlankWindow.space(window: w2, at: date).space
        let shown = BlankWindow.space(window: w2, at: date).space  // another space claims w2's window
        var normal = kept; normal.id = UUID(); normal.standaloneWindowID = nil
        let windows = [WindowSession(id: w1, focusedSpaceID: kept.id), WindowSession(id: w2, focusedSpaceID: shown.id),
                       WindowSession(focusedSpaceID: normal.id)]
        #expect(BlankWindow.orphans(spaces: [kept, lost, shown, normal], windows: windows) == [lost.id])
        #expect(BlankWindow.orphans(spaces: [kept, normal], windows: []) == [kept.id])
    }

    /// sidebar.json with a Blank Window's space: it loads and saves with its window id, outside
    /// spaceOrder (CLAUDE.md rule 4).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/220"))
    func sidebarWithABlankWindowLoadsAsRecorded() throws {
        let (loaded, recorded) = try ModelFixtureTests.load("sidebar-blank-window.json", as: SidebarDocument.self)
        #expect(loaded == recorded)
        #expect(try ModelFixtureTests.roundTrips(loaded))
        #expect(loaded.spaces.map(\.standaloneWindowID) == [nil, UUID(uuidString: "D0000000-0000-0000-0000-000000000002")])
        #expect(BlankWindow.spaceOrder(saved: loaded.spaceOrder, spaces: loaded.spaces) == [loaded.spaces[0].id])
    }
}
