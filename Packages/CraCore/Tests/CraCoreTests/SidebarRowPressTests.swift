import CraCore
import Foundation
import Testing

struct SidebarRowPressTests {
    @Test func tabsSplitsNewTabAndFavoritesPushIn() {
        #expect(SidebarRowPress.pushesIn(.tab, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.split, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.newTab, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.favorite, clickCount: 1))
        #expect(!SidebarRowPress.pushesIn(.other, clickCount: 1))
    }

    @Test func secondPressOfADoubleClick() {
        #expect(!SidebarRowPress.pushesIn(.tab, clickCount: 2))
        #expect(!SidebarRowPress.pushesIn(.split, clickCount: 2))
        #expect(SidebarRowPress.pushesIn(.newTab, clickCount: 2))
        #expect(SidebarRowPress.pushesIn(.favorite, clickCount: 2))
        #expect(!SidebarRowPress.pushesIn(.other, clickCount: 2))
    }

    @Test func depth() {
        #expect(SidebarRowPress.scale(.tab) == 0.992)
        #expect(SidebarRowPress.scale(.newTab) == 0.992)
        #expect(SidebarRowPress.scale(.favorite) == 0.99)
    }

    @Test func arcsSpring() {
        #expect(abs(SidebarRowPress.stiffness - 986.96) < 0.01)
        #expect(abs(SidebarRowPress.damping - 31.416) < 0.001)
    }

    /// Arc switches a tab on the press (live Arc 1.173.1, 12 Nov 2026); picks and renames wait for the release.
    @Test func tabsSwitchOnThePress() {
        #expect(SidebarRowPress.selectsOnPress(.tab, clickCount: 1, modified: false))
        #expect(!SidebarRowPress.selectsOnPress(.tab, clickCount: 2, modified: false), "a double-click's second press renames on release")
        #expect(!SidebarRowPress.selectsOnPress(.tab, clickCount: 1, modified: true), "⌘ or ⇧ picks on release, as Arc's ⌘-press")
        #expect(!SidebarRowPress.selectsOnPress(.favorite, clickCount: 1, modified: false))
        #expect(!SidebarRowPress.selectsOnPress(.split, clickCount: 1, modified: false))
    }

    /// ⌥-click on another tab opens it in Split View with the open one, as in Arc (reported on X, 27 Nov 2026).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/922")) func optionClickOnAnotherTabSplitsIt() {
        func click(command: Bool = false, shift: Bool = false, option: Bool = false, count: Int = 1, open: Bool = false, canSplit: Bool = true) -> SidebarRowPress.TabClick {
            SidebarRowPress.tabClick(command: command, shift: shift, option: option, clickCount: count, isOpen: open, canSplit: canSplit)
        }
        #expect(click(option: true) == .openInSplit)
        #expect(click(option: true, open: true) == .select, "the open tab has nothing to split with")
        #expect(click(option: true, canSplit: false) == .select, "no open tab with a page in this space: a plain click")
        #expect(click(option: true, count: 2) == .rename)
        #expect(click(command: true, option: true) == .pick(range: false))
        #expect(click(shift: true) == .pick(range: true))
        #expect(click() == .select)
        #expect(click(count: 2) == .rename)
    }
}
