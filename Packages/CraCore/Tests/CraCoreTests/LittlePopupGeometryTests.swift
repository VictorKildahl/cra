import CoreGraphics
import CraCore
import Testing

/// Where the Little Window's "Open in" menu sits and how tall it is (#331). Numbers are Arc
/// 1.172.1's, from window captures on 10 Nov 2026 and its disassembly (docs/arc-reverse-engineering.md).
struct LittlePopupGeometryTests {
    let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    /// 244 pt wide, a 46 pt header and 46 pt rows (Arc 1.168 had 54 pt ones).
    @Test func isTheHeaderAndOneRowPerSpace() {
        #expect(LittlePopupGeometry.width == 244)
        #expect(LittlePopupGeometry.height(rows: 1) == 92)
        #expect(LittlePopupGeometry.height(rows: 3) == 184)
        #expect(LittlePopupGeometry.height(rows: 7) == 368)
    }

    /// The list is `min(rows × 46, 350)` tall: past seven rows and a bit it scrolls, whatever the count.
    @Test func theListScrollsPastThreeHundredAndFifty() {
        #expect(LittlePopupGeometry.listHeight(rows: 7) == 322)
        #expect(LittlePopupGeometry.listHeight(rows: 8) == 350)
        #expect(LittlePopupGeometry.listHeight(rows: 200) == 350)
        #expect(LittlePopupGeometry.height(rows: 200) == 396)
    }

    /// A search that matches nothing shows "No results" in a row's height, not an empty gap.
    @Test func noResultsTakeOneRow() {
        #expect(LittlePopupGeometry.listHeight(rows: 0) == 46)
        #expect(LittlePopupGeometry.height(rows: 0) == 92)
    }

    /// It starts 4 pt under the window's top edge and ends 4.5 pt short of its right one; AppKit's
    /// y runs upwards, so the menu's origin is its height below the top.
    @Test func hangsFromTheWindowsTopRightCorner() {
        let frame = LittlePopupGeometry.frame(inWindow: window, rows: 3)
        #expect(frame == CGRect(x: 651.5, y: 512, width: 244, height: 184))
        #expect(frame.maxX == window.maxX - 4.5)
        #expect(frame.maxY == window.maxY - 4)
    }

    @Test func followsTheWindowWhereverItIs() {
        let moved = window.offsetBy(dx: -300, dy: 250)
        let a = LittlePopupGeometry.frame(inWindow: window, rows: 2)
        let b = LittlePopupGeometry.frame(inWindow: moved, rows: 2)
        #expect(b == a.offsetBy(dx: -300, dy: 250))
    }
}
