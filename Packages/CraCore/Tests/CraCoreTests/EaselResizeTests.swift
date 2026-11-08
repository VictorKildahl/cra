import CraCore
import Foundation
import Testing

/// Pictures on an Easel resize from their corners and keep their proportions, as in Arc.
struct EaselResizeTests {
    static let r = Easel.Rect(x: 100, y: 100, width: 200, height: 100)

    @Test func cornersAreGrabbedNearTheOutline() {
        #expect(Easel.corner(of: Self.r, at: .init(296, 196)) == .bottomRight)
        #expect(Easel.corner(of: Self.r, at: .init(104, 95)) == .topLeft)
        #expect(Easel.corner(of: Self.r, at: .init(200, 150)) == nil)
    }

    @Test func aPictureKeepsItsProportions() {
        let out = Easel.resized(Self.r, corner: .bottomRight, to: .init(500, 160), keepRatio: true)
        #expect(out == Easel.Rect(x: 100, y: 100, width: 400, height: 200))
        // Dragging the top-left corner keeps the bottom-right one where it was.
        let tl = Easel.resized(Self.r, corner: .topLeft, to: .init(200, 150), keepRatio: true)
        #expect(tl == Easel.Rect(x: 200, y: 150, width: 100, height: 50))
    }

    @Test func aShapeFollowsThePointer() {
        let out = Easel.resized(Self.r, corner: .topRight, to: .init(250, 50), keepRatio: false)
        #expect(out == Easel.Rect(x: 100, y: 50, width: 150, height: 150))
    }

    @Test func nothingShrinksAway() {
        let out = Easel.resized(Self.r, corner: .bottomRight, to: .init(0, 0), keepRatio: true)
        #expect(out.height == Easel.minimumSide && out.width == Easel.minimumSide * 2)
        #expect(out.x == 100 && out.y == 100)
    }

    @Test func onlyPicturesAndShapesResize() {
        #expect(Easel.resizes(.image(file: "a.png")))
        #expect(Easel.resizes(.rectangle))
        #expect(!Easel.resizes(.text("x", size: 18)))
        #expect(!Easel.resizes(.freehand([])))
    }
}
