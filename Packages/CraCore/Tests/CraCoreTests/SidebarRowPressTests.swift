import CraCore
import Foundation
import Testing

/// Arc's sidebar rows and Favorites tiles push in while pressed; folders don't.
struct SidebarRowPressTests {
    @Test func tabsSplitsNewTabAndFavoritesPushIn() {
        #expect(SidebarRowPress.pushesIn(.tab, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.split, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.newTab, clickCount: 1))
        #expect(SidebarRowPress.pushesIn(.favorite, clickCount: 1))
        #expect(!SidebarRowPress.pushesIn(.other, clickCount: 1))
    }

    /// A double-click's second press doesn't dip a tab or split again; New Tab and a tile have no such check.
    @Test func secondPressOfADoubleClick() {
        #expect(!SidebarRowPress.pushesIn(.tab, clickCount: 2))
        #expect(!SidebarRowPress.pushesIn(.split, clickCount: 2))
        #expect(SidebarRowPress.pushesIn(.newTab, clickCount: 2))
        #expect(SidebarRowPress.pushesIn(.favorite, clickCount: 2))
        #expect(!SidebarRowPress.pushesIn(.other, clickCount: 2))
    }

    /// A tile pushes in further than a row.
    @Test func depth() {
        #expect(SidebarRowPress.scale(.tab) == 0.992)
        #expect(SidebarRowPress.scale(.newTab) == 0.992)
        #expect(SidebarRowPress.scale(.favorite) == 0.99)
    }

    /// Arc's spring for damping ratio 0.5, response 0.2 s (mass 1).
    @Test func arcsSpring() {
        #expect(abs(SidebarRowPress.stiffness - 986.96) < 0.01)
        #expect(abs(SidebarRowPress.damping - 31.416) < 0.001)
    }
}
