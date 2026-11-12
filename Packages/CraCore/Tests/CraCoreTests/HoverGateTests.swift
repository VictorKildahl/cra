import CoreGraphics
import CraCore
import Testing

struct HoverGateTests {
    /// GitHub #382: ⌘T under a resting pointer selected the row under it, and Return opened that
    /// instead of the top row. Hover waits until the pointer moves from where it was when the bar
    /// opened, and again each time the rows change under it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/382"))
    func stillPointerIsNotHover() {
        var gate = HoverGate()
        let rest = CGPoint(x: 400, y: 300)
        func hover(_ p: CGPoint) -> Bool { gate.isHover(pointerAt: p) }
        gate.listChanged(pointerAt: rest)
        #expect(!hover(rest), "the bar ordered in under the pointer")
        #expect(!hover(rest), "the panel grew under it")
        #expect(hover(CGPoint(x: 400.5, y: 300)), "the pointer moved")
        #expect(hover(rest), "moving: back where it was is hover too")

        gate.listChanged(pointerAt: rest)
        #expect(!hover(rest), "rows changed under the still pointer")
        #expect(hover(CGPoint(x: 390, y: 310)))
    }

    @Test func noListYetIsHover() {
        var gate = HoverGate()
        let hover = gate.isHover(pointerAt: .zero)
        #expect(hover)
    }
}
