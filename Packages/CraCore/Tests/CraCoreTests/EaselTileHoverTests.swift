import CoreGraphics
import CraCore
import Testing

/// Arc's Library ▸ Easels tile under the pointer (Arc 1.173.1, recorded 17 Nov 2026).
struct EaselTileHoverTests {
    @Test func theTileGrowsAboutItsCentreAsArcsDoes() {
        // Arc's tile: 128.6 pt at rest, 136.3 pt under the pointer (257.2 and 272.6 px at 2x).
        let rest = CGRect(x: 143, y: 180, width: 128.6, height: 128.6)
        let over = EaselTileHover.frame(rest, hovering: true)
        #expect(abs(over.width - 136.3) < 0.25 && abs(over.height - 136.3) < 0.25)
        #expect(abs(over.midX - rest.midX) < 0.001 && abs(over.midY - rest.midY) < 0.001)
        #expect(EaselTileHover.frame(rest, hovering: false) == rest)
    }

    @Test func theListLeavesRoomForATopTileToGrow() {
        // A 132 pt tile reaches 3.96 pt past its frame: 4 pt, and one to spare.
        #expect(EaselTileHover.overhang(side: 132) == 5)
        let grown = EaselTileHover.frame(CGRect(x: 0, y: 0, width: 132, height: 132), hovering: true)
        #expect(-grown.minY <= EaselTileHover.overhang(side: 132))
    }

    @Test func itsBackingStandsOutTwiceAsMuch() {
        #expect(EaselTileHover.fill(hovering: true) == 2 * EaselTileHover.fill(hovering: false))
        #expect(EaselTileHover.scale(hovering: false) == 1 && EaselTileHover.scale(hovering: true) == 1.06)
        #expect(EaselTileHover.duration == 0.1)
    }
}
