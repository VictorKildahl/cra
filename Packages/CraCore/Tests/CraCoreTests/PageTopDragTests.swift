import CraCore
import Testing

/// Arc 1.172.2, measured with real drags on 11 Nov 2026 (#363): the band reaches 60 pt down from the top
/// of the pane card, its bar included. Toolbar hidden, a drag 59 pt into the page moved the window and
/// 60 pt didn't; under the 32 pt toolbar 27 pt did and 28 pt didn't.
struct PageTopDragTests {
    @Test(arguments: [(0.0, true), (59.0, true), (59.9, true), (60.0, false), (61.0, false), (-1.0, false)])
    func theBandIsArcs60PointsWithNoBar(depth: Double, holds: Bool) {
        #expect(PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: depth, clickCount: 1, modifiers: false) == holds)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/363"),
          arguments: [(32.0, 27.0, true), (32.0, 27.9, true), (32.0, 28.0, false), (32.0, 30.0, false),
                      (40.0, 19.9, true), (40.0, 20.0, false), (60.0, 0.0, false), (70.0, 0.0, false)])
    func underABarTheBandIsWhatIsLeftOf60Points(bar: Double, depth: Double, holds: Bool) {
        #expect(PageTopDrag.holds(enabled: true, barHeight: bar, depthIntoPage: depth, clickCount: 1, modifiers: false) == holds)
    }

    @Test func onlyPlainSingleClicksWithTheSettingOn() {
        #expect(!PageTopDrag.holds(enabled: false, barHeight: 0, depthIntoPage: 10, clickCount: 1, modifiers: false))
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 10, clickCount: 2, modifiers: false), "double-clicks go straight to the page")
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 10, clickCount: 1, modifiers: true), "⌘-click opens links as always")
    }

    @Test(arguments: [(-1.0, false), (0.0, false), (13.9, false), (14.0, false), (14.1, true), (30.0, true)])
    func theRight14PointsStayWithThePage(distance: Double, holds: Bool) {
        #expect(PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 20,
                                  clickCount: 1, modifiers: false, distanceFromRight: distance) == holds)
    }

    /// A press on an inactive Cra, or the one that made it active, can't go by the cursor: it is the one
    /// Cra left behind. Found with real drags on #335: such a drag moved the window only every other time.
    @Test(arguments: [(false, 0.0, 10.0, false), (true, 10.02, 10.0, false), (true, 9.95, 10.0, false),
                      (true, 9.8, 10.0, true), (true, 0.0, 10.0, true)])
    func theCursorCountsOnlyOnceCraHasBeenActive(active: Bool, becameActiveAt: Double, pressedAt: Double, counts: Bool) {
        #expect(PageTopDrag.cursorIsCurrent(appActive: active, becameActiveAt: becameActiveAt, pressedAt: pressedAt) == counts)
    }

    /// Edge to edge with no bar above the page (#685): nothing stands in for the title bar but the page's top, so a double
    /// click in its top 10 pt (the margin edge to edge takes away) zooms the window as the strip above the card does with
    /// the margin. Further down it stays the page's: a site's buttons show the arrow too.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/685"),
          arguments: [(0.0, true), (5.0, true), (9.9, true), (10.0, false), (30.0, false), (-1.0, false)])
    func edgeToEdgeADoubleClickInTheBandZooms(depth: Double, zooms: Bool) {
        #expect(PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 0, depthIntoPage: depth,
                                  clickCount: 2, modifiers: false) == zooms)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/685"))
    func onlyAPlainDoubleClickEdgeToEdgeWithNoBar() {
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: false, barHeight: 0, depthIntoPage: 5, clickCount: 2, modifiers: false),
                "with the margin, the strip above the card takes it")
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 32, depthIntoPage: 5, clickCount: 2, modifiers: false),
                "the toolbar above the page takes it")
        #expect(!PageTopDrag.zooms(enabled: false, fillsWindow: true, barHeight: 0, depthIntoPage: 5, clickCount: 2, modifiers: false),
                "no window dragging from the page's top, no zoom from it either")
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 0, depthIntoPage: 5, clickCount: 1, modifiers: false))
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 0, depthIntoPage: 5, clickCount: 3, modifiers: false))
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 0, depthIntoPage: 5, clickCount: 2, modifiers: true))
        #expect(!PageTopDrag.zooms(enabled: true, fillsWindow: true, barHeight: 0, depthIntoPage: 5, clickCount: 2, modifiers: false,
                                   distanceFromRight: 10), "the scrollbar's strip stays with the page")
    }
}
