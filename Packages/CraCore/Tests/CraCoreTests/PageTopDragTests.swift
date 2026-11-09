import CraCore
import Testing

/// Arc 1.172.1 (measured 7 Nov 2026): with the toolbar hidden, drags from the top 56 pt of a page move the window.
struct PageTopDragTests {
    @Test(arguments: [(0.0, true), (55.9, true), (56.0, false), (58.0, false), (-1.0, false)])
    func theBandIsArcs56Points(depth: Double, holds: Bool) {
        #expect(PageTopDrag.holds(enabled: true, barAbovePage: false, depthIntoPage: depth, clickCount: 1, modifiers: false) == holds)
    }

    @Test func onlyPlainSingleClicksWithNoBarAndTheSettingOn() {
        #expect(!PageTopDrag.holds(enabled: false, barAbovePage: false, depthIntoPage: 10, clickCount: 1, modifiers: false))
        #expect(!PageTopDrag.holds(enabled: true, barAbovePage: true, depthIntoPage: 10, clickCount: 1, modifiers: false))
        #expect(!PageTopDrag.holds(enabled: true, barAbovePage: false, depthIntoPage: 10, clickCount: 2, modifiers: false), "double-clicks go straight to the page")
        #expect(!PageTopDrag.holds(enabled: true, barAbovePage: false, depthIntoPage: 10, clickCount: 1, modifiers: true), "⌘-click opens links as always")
    }

    @Test func aDragIsMoreThanTheSlop() {
        #expect(!PageTopDrag.isDrag(dx: 2, dy: 2))
        #expect(PageTopDrag.isDrag(dx: 3, dy: 1))
    }
}
