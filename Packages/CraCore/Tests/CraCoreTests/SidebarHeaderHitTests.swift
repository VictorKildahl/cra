import CraCore
import Testing

/// The sidebar header's buttons with the toolbar hidden (GitHub #818): Arc draws ← → ↻ as 32 pt boxes 2 pt apart, and
/// the pointer between two of them was over neither, so a click there did nothing.
struct SidebarHeaderHitTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/818"))
    func neighbouringButtonsLeaveNoDeadSpace() {
        for width in [212.0, 213, 214, 240, 328, 400] {
            let spans = SidebarHeaderLayout.hitSpans(width: width, afterLights: 79)
            // ← → ↻ meet; the toggle meets ← where the sidebar is just wide enough for both, as Arc keeps it 2 pt clear.
            for (a, b) in zip(spans.dropFirst(), spans.dropFirst(2)) { #expect(a.upperBound >= b.lowerBound, "width \(width)") }
            if SidebarHeaderLayout.toggleX(width: width, afterLights: 79) < 79 { #expect(spans[0].upperBound >= spans[1].lowerBound, "width \(width)") }
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/818"))
    func theDrawnBoxesStayArcs() {
        // Only the clicks reach further: the boxes stay 32 pt, 2 pt apart, 6 pt from the edge (#287).
        #expect(SidebarHeaderLayout.navButtons(width: 328).map(\.x) == [222, 256, 290])
        #expect(SidebarHeaderLayout.hitOutset == 1)
        #expect(SidebarHeaderLayout.hitSpans(width: 328, afterLights: 79)[1] == 221...255)
        #expect(SidebarHeaderLayout.hitSpans(width: 328, afterLights: 79)[2] == 255...289)
    }
}
