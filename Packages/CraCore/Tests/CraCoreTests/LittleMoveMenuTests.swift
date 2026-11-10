import CoreGraphics
import CraCore
import Testing

/// The Little Window's "Open in" menu, measured on Arc 1.172.1 (#331).
struct LittleMoveMenuTests {
    let window = CGRect(x: 100, y: 200, width: 1400, height: 900)

    /// 46 pt rows under a 46 pt header (Arc 1.168's were 54 pt), the whole list while it fits.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func rowsAre46PointsTall() {
        #expect(LittleMoveMenu.rowHeight == 46)
        #expect(LittleMoveMenu.headerHeight == 46)
        #expect(LittleMoveMenu.listHeight(rows: 2) == 92)
        #expect(LittleMoveMenu.listHeight(rows: 7) == 322)
    }

    /// Past 350 pt the list scrolls instead of dropping spaces (Cra used to show the first six).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func longListsScroll() {
        #expect(LittleMoveMenu.listHeight(rows: 8) == 350)
        #expect(LittleMoveMenu.listHeight(rows: 30) == 350)
        // Down to the tenth of ten: the last row's bottom meets the list's.
        let o = LittleMoveMenu.scrollOffset(showing: 9, from: 0, rows: 10)
        #expect(o == CGFloat(10 * 46 - 350))
        // Back up to the first: the top again.
        #expect(LittleMoveMenu.scrollOffset(showing: 0, from: o, rows: 10) == 0)
        // A row already in view doesn't move the list.
        #expect(LittleMoveMenu.scrollOffset(showing: 3, from: 0, rows: 10) == 0)
        #expect(LittleMoveMenu.scrollOffset(showing: 4, from: 0, rows: 5) == 0)
    }

    /// Nothing matches the filter: "No results" in 64 pt.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func noResults() {
        #expect(LittleMoveMenu.listHeight(rows: 0) == 64)
        #expect(LittleMoveMenu.frame(rows: 0, in: window).height == 110)
    }

    /// 244 pt wide, 4 pt below the window's top and 4 pt in from its right edge (Cra had it 240 pt,
    /// flush with the top, 8 pt in).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func hangsFromTheWindowsTopRightCorner() {
        let f = LittleMoveMenu.frame(rows: 10, in: window)
        #expect(f.width == 244)
        #expect(f.maxX == window.maxX - 4)
        #expect(f.maxY == window.maxY - 4)
        #expect(f.height == 396)
        #expect(LittleMoveMenu.frame(rows: 2, in: window).height == 138)
    }

    /// The space "Open in" names leads the list, the rest keep the sidebar's order.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func theTargetSpaceComesFirst() {
        #expect(LittleMoveMenu.order(["Victor", "Work", "Alpha", "Bravo"], target: "Work") == ["Work", "Victor", "Alpha", "Bravo"])
        #expect(LittleMoveMenu.order(["Victor", "Work"], target: "Victor") == ["Victor", "Work"])
        #expect(LittleMoveMenu.order(["Victor", "Work"], target: "Gone") == ["Victor", "Work"])
    }

    /// With one space the menu has nowhere to send the page, so there's no ⌄.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/331"))
    func oneSpaceHasNoChevron() {
        #expect(!LittleMoveMenu.showsChevron(spaces: 1))
        #expect(LittleMoveMenu.showsChevron(spaces: 2))
    }
}
