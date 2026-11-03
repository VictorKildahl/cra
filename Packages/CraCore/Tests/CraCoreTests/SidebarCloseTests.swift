import CraCore
import Testing

/// GitHub #139: Arc 1.171's close buttons, as recorded in an offline Arc.
struct SidebarCloseTests {
    @Test func tabRows() {
        let open = SidebarClose.tab(pinned: true, current: true, navigatedAway: false, peeked: false)
        #expect(open.minus && open.help == "Close and Keep Pinned (⌘W)")
        let away = SidebarClose.tab(pinned: true, current: false, navigatedAway: true, peeked: false)
        #expect(away.minus && away.help == "Close and Keep Pinned", "away from its page, in the background")
        let peeked = SidebarClose.tab(pinned: true, current: false, navigatedAway: false, peeked: true)
        #expect(peeked.minus, "shown under a closed folder")
        let resting = SidebarClose.tab(pinned: true, current: false, navigatedAway: false, peeked: false)
        #expect(!resting.minus && resting.help == "Archive this tab", "loaded or not, on its own page")
        #expect(SidebarClose.tab(pinned: false, current: true, navigatedAway: false, peeked: false).help == "Archive this tab (⌘W)")
        #expect(SidebarClose.tab(pinned: false, current: false, navigatedAway: true, peeked: true).help == "Archive this tab")
    }

    @Test func splitRows() {
        #expect(SidebarClose.split(pinned: true, current: true) == .row(.init(action: .keep, help: "Close this item (⌘W)")))
        #expect(SidebarClose.split(pinned: true, current: false) == .row(.init(action: .archive, help: "Archive this item")))
        #expect(SidebarClose.split(pinned: false, current: false) == .row(.init(action: .archive, help: "Archive this item")))
        #expect(SidebarClose.split(pinned: false, current: true) == .perPane(.init(action: .archive, help: "Archive this item")))
    }

    @Test func commandW() {
        #expect(SidebarClose.commandW(anyToday: true) == .archive)
        #expect(SidebarClose.commandW(anyToday: false) == .keep)
    }
}
