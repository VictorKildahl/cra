import CraCore
import CoreGraphics
import Testing

struct FolderPreviewRowsTests {
    /// The shown part of a scrolling preview: six rows and a bit (320 pt less the search field).
    let height: CGFloat = 271

    @Test func thePointerHoversTheRowItIsOn() {
        #expect(FolderPreviewRows.row(atY: 2, offset: 0, height: height, count: 10) == nil)
        #expect(FolderPreviewRows.row(atY: 4, offset: 0, height: height, count: 10) == 0)
        #expect(FolderPreviewRows.row(atY: 48.9, offset: 0, height: height, count: 10) == 0)
        #expect(FolderPreviewRows.row(atY: 49, offset: 0, height: height, count: 10) == 1)
        #expect(FolderPreviewRows.row(atY: 120, offset: 0, height: height, count: 10) == 2)
    }

    /// The list scrolls under a pointer that stays put: the row now under it is the hovered one,
    /// and only that one (#544).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/544"))
    func aScrollMovesTheHoverToTheRowNowUnderThePointer() {
        let still: CGFloat = 120
        #expect(FolderPreviewRows.row(atY: still, offset: 0, height: height, count: 10) == 2)
        #expect(FolderPreviewRows.row(atY: still, offset: 3 * FolderPreviewRows.rowPitch, height: height, count: 10) == 5)
        #expect(FolderPreviewRows.row(atY: still, offset: 100, height: height, count: 10) == 4)
    }

    @Test func nothingIsHoveredPastTheRowsOrOffTheList() {
        // Four rows end at 184 pt; the panel is taller than that only while filtering keeps it.
        #expect(FolderPreviewRows.row(atY: 190, offset: 0, height: height, count: 4) == nil)
        #expect(FolderPreviewRows.row(atY: -1, offset: 90, height: height, count: 10) == nil)
        #expect(FolderPreviewRows.row(atY: height, offset: 0, height: height, count: 10) == nil)
        #expect(FolderPreviewRows.row(atY: 10, offset: 0, height: height, count: 0) == nil)
    }
}
