import CoreGraphics
import CraCore
import Testing

/// Arc's favorites grid as measured (docs/arc-reverse-engineering.md, "Favorites grid columns
/// and Peek"). Arc's widths are the sidebar's; the grid is 16 pt narrower (8 pt each side).
struct FavoritesLayoutTests {
    /// Arc 1.170, 29 Oct: four favorites, sidebar width → columns and the tile width Arc's AX
    /// frames report (whole points; nil where it wasn't written down).
    @Test(arguments: [
        (347, 4, 76), (300, 4, nil), (260, 4, 55), (230, 4, 47),
        (227, 2, 101), (225, 2, 100), (220, 2, 98), (212, 2, 94), (205, 2, 90), (200, 2, 88),
        (170, 2, 73), (140, 2, 58), (100, 1, 84),
    ] as [(Int, Int, Int?)])
    func fourFavoritesMatchArc(sidebarWidth: Int, columns: Int, tileWidth: Int?) {
        let grid = FavoritesLayout(count: 4, width: CGFloat(sidebarWidth - 16))
        #expect(grid.columns == columns)
        if let tileWidth { #expect(Int(grid.tileWidth) == tileWidth) }
    }

    /// Arc 1.171, 31 Oct: 1–9 favorites at five sidebar widths. The widest grid keeps tiles at
    /// least 47 pt (4 at 347 and 230, 3 at 200, 2 at 140, 1 at 100), then takes the fewest
    /// columns that need no more rows: 5 → 3 + 2, 6 → 3 × 2, 7 → 4 + 3, 9 → 3 × 3, 4 at 200 → 2 × 2.
    @Test(arguments: [
        (347, [1, 2, 3, 4, 3, 3, 4, 4, 3]),
        (230, [1, 2, 3, 4, 3, 3, 4, 4, 3]),
        (200, [1, 2, 3, 2, 3, 3, 3, 3, 3]),
        (140, [1, 2, 2, 2, 2, 2, 2, 2, 2]),
        (100, [1, 1, 1, 1, 1, 1, 1, 1, 1]),
    ])
    func columnsByCountMatchArc(sidebarWidth: Int, columnsByCount: [Int]) {
        for (i, expected) in columnsByCount.enumerated() {
            let grid = FavoritesLayout(count: i + 1, width: CGFloat(sidebarWidth - 16))
            #expect(grid.columns == expected, "\(i + 1) favorites at \(sidebarWidth) pt")
        }
    }

    @Test func tilesSitOnHalfPoints() {
        // Arc at 347 pt: 84.75 → 85, 254.25 → 254.5. Widths are not rounded.
        let grid = FavoritesLayout(count: 4, width: 331)
        #expect(grid.frame(at: 1).minX == 85)
        #expect(grid.frame(at: 3).minX == 254.5)
        #expect(grid.frame(at: 3).width == 76.75)
    }

    @Test func shortLastRowKeepsTileWidthFromTheLeft() {
        let grid = FavoritesLayout(count: 5, width: 331)
        #expect(grid.columns == 3 && grid.rows == 2)
        #expect(grid.frame(at: 3).minX == 0 && grid.frame(at: 3).minY == 55)
        #expect(grid.frame(at: 4).minX == grid.frame(at: 1).minX)
        #expect(grid.frame(at: 4).width == grid.frame(at: 0).width)
    }

    @Test func heightCountsRowsAndGaps() {
        #expect(FavoritesLayout(count: 0, width: 331).gridHeight == 0)
        #expect(FavoritesLayout(count: 0, width: 331).rows == 0)
        #expect(FavoritesLayout(count: 4, width: 331).gridHeight == 47)
        #expect(FavoritesLayout(count: 9, width: 331).gridHeight == 157, "3 rows of 47 and 2 gaps of 8")
    }

    /// #176: the slot under the pointer, across rows, with gaps going to the nearer tile.
    @Test func slotUnderThePointer() {
        let grid = FavoritesLayout(count: 5, width: 331)  // 3 + 2, tiles 105 wide, 55 pt row pitch
        #expect(grid.slot(at: CGPoint(x: 10, y: 10)) == 0)
        #expect(grid.slot(at: CGPoint(x: 120, y: 10)) == 1)
        #expect(grid.slot(at: CGPoint(x: 110, y: 10)) == 1, "a gap's right half goes to the tile after it")
        #expect(grid.slot(at: CGPoint(x: 108, y: 10)) == 0, "its left half to the tile before")
        #expect(grid.slot(at: CGPoint(x: 330, y: 10)) == 2)
        #expect(grid.slot(at: CGPoint(x: 10, y: 60)) == 3)
        #expect(grid.slot(at: CGPoint(x: 120, y: 60)) == 4)
        #expect(grid.slot(at: CGPoint(x: 300, y: 60)) == 4, "past the short last row: the last slot")
        #expect(grid.slot(at: CGPoint(x: -20, y: -20)) == 0)
        #expect(grid.slot(at: CGPoint(x: 400, y: 400)) == 4)
        #expect(FavoritesLayout(count: 0, width: 331).slot(at: .zero) == 0)
    }

    @Test func tilesMoveAlongPastTheOpenSlot() {
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: nil) } == [0, 1, 2, 3])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 0) } == [1, 2, 3, 4])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 2) } == [0, 1, 3, 4])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 4) } == [0, 1, 2, 3])
    }
}
