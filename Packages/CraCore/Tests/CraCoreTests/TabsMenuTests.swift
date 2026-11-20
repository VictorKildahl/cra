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

    /// Arc 1.173.1's Tabs menu, read over Accessibility (19 Nov 2026): three groups, with "Open in
    /// <space>" in the first while a Little Window or Peek is in front.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func arcSections() {
        #expect(TabsMenu.sections == [
            ["newTab", "pinTab", "promoteLittleWindow", "newFolder"],
            ["nextTab", "previousTab", "revealTab"],
            ["clearToday", "resetSpaceTabs"],
        ])
    }

    /// Cra's actions Arc keeps out of its Tabs menu stay as hidden rows: their shortcuts, Settings ▸
    /// Shortcuts and the command bar keep working, and Arc has no Go to Tab rows at all.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func extrasStayAsHiddenRows() {
        #expect(TabsMenu.hidden == ["recentTab", "favoriteTab", "renameTab", "duplicateTab", "resetTab", "muteTab",
                                    "item1", "item2", "item3", "item4", "item5", "item6", "item7", "item8", "item9"])
        #expect(Set(TabsMenu.hidden).isDisjoint(with: TabsMenu.sections.joined()))
    }

    @Test func headIsTheFirstSection() {
        #expect(TabsMenu.sections.first == TabsMenu.head)
    }

    @Test func shortcutsNameIsArcs() {
        // Arc's name with Cra's "Little Window" for "Little Arc", as in Show Little Window "Open In" Menu.
        #expect(TabsMenu.openInName == "Open Little Window or Peek in…")
    }
}

/// The Tabs menu's rows are enabled only when choosing them would do something, and a dimmed row's
/// shortcut does nothing either (GitHub #622). Arc leaves some of them enabled with nothing to act on.
struct TabsMenuStateTests {
    typealias F = TabsMenu.Facts

    /// Rows that act on a tab, a space's tabs or Today, keyed by action.
    static let acting = ["pinTab", "nextTab", "previousTab", "revealTab", "clearToday", "resetSpaceTabs"]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func anEmptySpaceOffersOnlyNewTabAndNewFolder() {
        let empty = F()
        for id in Self.acting { #expect(!TabsMenu.state(of: id, empty).enabled, "\(id)") }
        #expect(TabsMenu.state(of: "newTab", empty).enabled)
        #expect(TabsMenu.state(of: "newFolder", empty).enabled)
        #expect(TabsMenu.state(of: "pinTab", empty).title == "Pin Tab")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func pinTabSaysWhatItDoes() {
        #expect(TabsMenu.state(of: "pinTab", F(selection: .today, tabs: 1)) == .init(enabled: true, title: "Pin Tab"))
        #expect(TabsMenu.state(of: "pinTab", F(selection: .pinned, tabs: 1)) == .init(enabled: true, title: "Unpin Tab"))
        // ⌘D on a Favorite takes it out of Favorites, as it already did.
        #expect(TabsMenu.state(of: "pinTab", F(selection: .favorite, tabs: 1)) == .init(enabled: true, title: "Unpin Tab"))
        #expect(!TabsMenu.state(of: "pinTab", F(selection: .today, tabs: 1, window: .blank)).enabled)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func nextAndPreviousNeedAnotherTab() {
        for id in ["nextTab", "previousTab"] {
            #expect(!TabsMenu.state(of: id, F(tabs: 0)).enabled)
            #expect(TabsMenu.state(of: id, F(tabs: 1)).enabled, "one tab, not selected: it goes there")
            #expect(!TabsMenu.state(of: id, F(selection: .pinned, tabs: 1)).enabled, "the only tab, already selected")
            #expect(TabsMenu.state(of: id, F(selection: .today, tabs: 2)).enabled)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func revealNeedsASelectedTab() {
        #expect(!TabsMenu.state(of: "revealTab", F(tabs: 3)).enabled)
        for s in [F.Selection.today, .pinned, .favorite] {
            #expect(TabsMenu.state(of: "revealTab", F(selection: s, tabs: 1)).enabled)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func clearTodayAndResetNeedSomethingToDo() {
        #expect(!TabsMenu.state(of: "clearToday", F(selection: .today, tabs: 2)).enabled, "only protected Today tabs")
        #expect(TabsMenu.state(of: "clearToday", F(selection: .today, tabs: 2, clearableToday: true)).enabled)
        #expect(!TabsMenu.state(of: "resetSpaceTabs", F(selection: .pinned, tabs: 1)).enabled, "pinned tabs at home")
        #expect(TabsMenu.state(of: "resetSpaceTabs", F(selection: .pinned, tabs: 1, resettablePinned: true)).enabled)
        for w in [F.Window.blank, .incognito] {
            #expect(!TabsMenu.state(of: "resetSpaceTabs", F(tabs: 1, resettablePinned: true, window: w)).enabled)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func newFolderEverywhereButABlankWindow() {
        #expect(TabsMenu.state(of: "newFolder", F(window: .incognito)).enabled)
        #expect(!TabsMenu.state(of: "newFolder", F(window: .blank)).enabled)
    }

    /// A Little Window or Peek in front takes these keys and does nothing with them.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func aLittleWindowInFrontDimsTheTabRows() {
        let busy = F(selection: .pinned, tabs: 3, clearableToday: true, resettablePinned: true, littleWindowInFront: true)
        for id in Self.acting { #expect(!TabsMenu.state(of: id, busy).enabled, "\(id)") }
        #expect(TabsMenu.state(of: "newTab", busy).enabled)
        // New Folder isn't one of them: it still makes a folder in the browser window's space.
        #expect(TabsMenu.state(of: "newFolder", busy).enabled)
    }

    /// The Create a Space page covers the space it was opened from: nothing acts on that space behind it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/622"))
    func theCreateASpacePageDimsWhatWouldActBehindIt() {
        let making = F(tabs: 2, clearableToday: true, resettablePinned: true, makingSpace: true)
        for id in Self.acting + ["newFolder"] { #expect(!TabsMenu.state(of: id, making).enabled, "\(id)") }
        #expect(TabsMenu.state(of: "newTab", making).enabled)
    }

    /// Rows the rule doesn't decide (the hidden extras, Open in <space>) are left as they were.
    @Test func otherRowsAreNotDecidedHere() {
        #expect(TabsMenu.state(of: "duplicateTab", F()).enabled)
        #expect(TabsMenu.state(of: "duplicateTab", F()).title == nil)
        #expect(!TabsMenu.decides("duplicateTab"))
        #expect(TabsMenu.decides("clearToday"))
    }
}
