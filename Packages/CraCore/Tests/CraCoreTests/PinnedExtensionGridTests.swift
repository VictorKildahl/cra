import CoreGraphics
import CraCore
import Testing

/// Arc 1.171's pinned extension grid in the sidebar, as measured live on 4 Nov 2026 (AX frames,
/// URL field in the sidebar; docs/arc-reverse-engineering.md, "Pinned extensions with the
/// toolbar hidden"). Widths are the sidebar's; the grid is 16 pt narrower.
struct PinnedExtensionGridTests {
    /// Eleven pins: 4 + 4 + 3 at 200 pt, 6 + 5 from 240 pt; five at 200 pt in one row.
    @Test(arguments: [
        (200, 11, 4, 3, 40.0), (240, 11, 6, 2, 30.67), (300, 11, 6, 2, 40.67), (347, 11, 6, 2, 48.5),
        (200, 5, 5, 1, 30.4), (300, 7, 7, 1, 33.71),
    ] as [(Int, Int, Int, Int, Double)])
    func columnsMatchArc(sidebarWidth: Int, count: Int, columns: Int, rows: Int, cellWidth: Double) {
        let grid = PinnedExtensionGrid(count: count, width: CGFloat(sidebarWidth - 16))
        #expect(grid.columns == columns)
        #expect(grid.rows == rows)
        #expect(abs(Double(grid.cellWidth) - cellWidth) < 0.01)
    }

    /// Arc's AX frames at 240 pt (sidebar-relative, from the grid's top-left 8 pt in): x 8, 46,
    /// 85, 124, 162, 201; rows 36 pt apart; cells 28 pt tall.
    @Test func framesMatchArc() {
        let grid = PinnedExtensionGrid(count: 11, width: 224)
        let xs = (0..<6).map { Int(8 + grid.frame(at: $0).minX) }
        #expect(xs == [8, 46, 85, 124, 162, 201])
        #expect(grid.frame(at: 6) == CGRect(x: 0, y: 36, width: grid.cellWidth, height: 28))
        #expect(grid.height == 64)
        // The favorites start 8 pt under the last row (Arc: grid 123–187, tiles from 195).
        #expect(grid.favoritesOffset == 72)
    }

    /// Field (sidebar − 16) less 28 pt a pin: Arc kept them in the URL field with 124 pt or more
    /// left and moved them to the grid with 117 or less (live, 4 Nov 2026, github.com).
    @Test(arguments: [
        (240, 3, true), (252, 4, true), (262, 4, true), (300, 5, true), (347, 7, true),
        (240, 4, false), (245, 4, false), (200, 5, false), (270, 7, false), (300, 7, false), (320, 7, false),
        (347, 8, false), (240, 11, false), (347, 11, false),
    ] as [(Int, Int, Bool)])
    func fieldOrGridMatchesArc(sidebarWidth: Int, pins: Int, inField: Bool) {
        #expect(PinnedExtensionGrid.fitsInURLField(count: pins, fieldWidth: CGFloat(sidebarWidth - 16)) == inField)
    }

    @Test func nothingPinnedTakesNoRoom() {
        let grid = PinnedExtensionGrid(count: 0, width: 224)
        #expect(grid.rows == 0 && grid.height == 0 && grid.favoritesOffset == 0)
    }
}
