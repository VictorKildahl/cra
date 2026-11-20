import CoreGraphics
import CraCore
import Testing

/// The edge strip after a hide the pointer didn't make (GitHub #635).
struct FloatingSidebarStillPointerTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/635"))
    func aPointMovedEitherWayCounts() {
        let p = CGPoint(x: 4, y: 400)
        #expect(!FloatingSidebarStillPointer.moved(from: p, to: p))
        #expect(!FloatingSidebarStillPointer.moved(from: p, to: CGPoint(x: 4.5, y: 400.9)))
        #expect(FloatingSidebarStillPointer.moved(from: p, to: CGPoint(x: 5, y: 400)))
        #expect(FloatingSidebarStillPointer.moved(from: p, to: CGPoint(x: 4, y: 398)))
    }
}
