import CraCore
import Testing

/// The sidebar's width range is Arc's: 164–500 pt (issue #287).
struct SidebarWidthTests {
    /// A sidebar kept narrow in Arc (the report's is about 160 pt) gets as narrow in Cra:
    /// down to Arc's 164 pt, where Cra stopped at 220.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func goesAsNarrowAsArc() {
        #expect(SidebarWidth.clamped(164) == 164)
        #expect(SidebarWidth.clamped(200) == 200)
        #expect(SidebarWidth.clamped(163) == 164)
        #expect(SidebarWidth.clamped(0) == 164)
    }

    /// And no wider than Arc's 500 pt.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func stopsWhereArcStops() {
        #expect(SidebarWidth.clamped(500) == 500)
        #expect(SidebarWidth.clamped(501) == 500)
        #expect(SidebarWidth.clamped(328) == 328)
    }
}
