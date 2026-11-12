import CraCore
import Testing

/// Arc's ⌘O row: Tabs ▸ "Open in <space>" after Pin Tab, only while a Little Arc or Peek is in
/// front; "Open Little Arc or Peek in…" in Settings ▸ Shortcuts (Arc 1.172.2, 11 Nov 2026).
struct TabsMenuTests {
    @Test func openInFollowsPinTab() {
        #expect(TabsMenu.head == ["newTab", "pinTab", "promoteLittleWindow", "newFolder"])
    }

    @Test func openInNamesTheSpace() {
        #expect(TabsMenu.openInTitle(space: "Victor") == "Open in Victor")
    }

    @Test(arguments: [true, false])
    func openInShowsOnlyForALittleWindow(front: Bool) {
        #expect(TabsMenu.showsOpenIn(littleWindowWithPage: front) == front)
    }

    @Test func shortcutsNameIsArcs() {
        // Arc's name with Cra's "Little Window" for "Little Arc", as in Show Little Window "Open In" Menu.
        #expect(TabsMenu.openInName == "Open Little Window or Peek in…")
    }
}
