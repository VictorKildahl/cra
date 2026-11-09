import CraCore
import Testing

/// A drag of the sidebar's edge against Arc's, step by step as the offline Arc read it (issue #287).
struct SidebarResizeTests {
    private func trace(from start: Double, through widths: [Double], speed: Double = 10) -> [SidebarResize.Outcome] {
        var r = SidebarResize(startWidth: start)
        return widths.map { r.update(translation: $0 - start, speed: speed) }
    }

    /// Slowly down from 260 in 2 pt steps: free to 242, 228 from 240 to 216, free again at 214.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func snapsTo228OnTheWayDown() {
        let widths: [Double] = [258, 244, 242, 240, 230, 228, 220, 216, 214, 200]
        #expect(trace(from: 260, through: widths) ==
                [258, 244, 242, 228, 228, 228, 228, 228, 214, 200].map { .width($0) })
    }

    /// Slowly up from 200 in 1 pt steps: no early pull, then 228 from 228 to 241, free at 242.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func snapsOnceItReaches228OnTheWayUp() {
        let widths: [Double] = [201, 214, 215, 227, 228, 229, 241, 242, 250]
        #expect(trace(from: 200, through: widths) ==
                [201, 214, 215, 227, 228, 228, 228, 242, 250].map { .width($0) })
    }

    /// A quick drag to 220 stays 220.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func aFastDragDoesNotSnap() {
        #expect(trace(from: 260, through: [240, 220], speed: 400) == [.width(240), .width(220)])
    }

    /// Down past 164 it holds 164; under 82 the sidebar hides, and back over 82 it is 164 again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func hidesUnder82AndComesBack() {
        let widths: [Double] = [170, 150, 84, 82, 81, 60, 61, 81, 85, 149]
        #expect(trace(from: 200, through: widths) ==
                [.width(170), .width(164), .width(164), .width(164), .hidden, .hidden, .hidden, .hidden, .width(164), .width(164)])
    }

    /// The edge stays with the pointer: back out from the clamp, the width follows at once.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func widthIsStartPlusDrag() {
        #expect(trace(from: 300, through: [100, 290, 520]) == [.width(164), .width(290), .width(500)])
    }
}
