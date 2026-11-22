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

    @Test func picturesShapesAndTextResize() {
        #expect(Easel.resizes(.image(file: "a.png")))
        #expect(Easel.resizes(.rectangle))
        #expect(Easel.resizes(.ellipse))
        #expect(Easel.resizes(.text("x", size: 18)))
        #expect(!Easel.resizes(.arrow(from: .init(0, 0), to: .init(10, 10))))
        #expect(!Easel.resizes(.freehand([])))
    }

    @Test func sideHandlesAreGrabbedNearEdgeMidpoints() {
        #expect(Easel.corner(of: Self.r, at: .init(200, 102)) == .top)
        #expect(Easel.corner(of: Self.r, at: .init(200, 198)) == .bottom)
        #expect(Easel.corner(of: Self.r, at: .init(103, 150)) == .left)
        #expect(Easel.corner(of: Self.r, at: .init(297, 150)) == .right)
    }

    @Test func aShapeResizesFromEdges() {
        let top = Easel.resized(Self.r, corner: .top, to: .init(200, 80), keepRatio: false)
        #expect(top == Easel.Rect(x: 100, y: 80, width: 200, height: 120))

        let bottom = Easel.resized(Self.r, corner: .bottom, to: .init(200, 250), keepRatio: false)
        #expect(bottom == Easel.Rect(x: 100, y: 100, width: 200, height: 150))

        let left = Easel.resized(Self.r, corner: .left, to: .init(80, 150), keepRatio: false)
        #expect(left == Easel.Rect(x: 80, y: 100, width: 220, height: 100))

        let right = Easel.resized(Self.r, corner: .right, to: .init(350, 150), keepRatio: false)
        #expect(right == Easel.Rect(x: 100, y: 100, width: 250, height: 100))
    }

    @Test func edgeResizingDoesNotShrinkBelowMinimum() {
        let top = Easel.resized(Self.r, corner: .top, to: .init(200, 300), keepRatio: false)
        #expect(top.height == Easel.minimumSide && top.y == 200 - Easel.minimumSide)

        let right = Easel.resized(Self.r, corner: .right, to: .init(50, 150), keepRatio: false)
        #expect(right.width == Easel.minimumSide && right.x == 100)
    }

    @Test func handlesAppropriateForKind() {
        #expect(Easel.handles(for: .rectangle).count == 8)
        #expect(Easel.handles(for: .ellipse).count == 8)
        #expect(Easel.handles(for: .text("x", size: 18)).count == 8)
        #expect(Easel.handles(for: .image(file: "a.png")) == [.topLeft, .topRight, .bottomLeft, .bottomRight])
    }

    @Test func textBoxResizesHorizontally() {
        let (rx, rw) = Easel.resizedText(Self.r, corner: .right, to: .init(350, 150))
        #expect(rx == 100 && rw == 250)

        let (lx, lw) = Easel.resizedText(Self.r, corner: .left, to: .init(80, 150))
        #expect(lx == 80 && lw == 220)

        // Corners also resize horizontally, anchoring the opposite edge
        let (brX, brW) = Easel.resizedText(Self.r, corner: .bottomRight, to: .init(400, 250))
        #expect(brX == 100 && brW == 300)

        let (tlX, tlW) = Easel.resizedText(Self.r, corner: .topLeft, to: .init(50, 50))
        #expect(tlX == 50 && tlW == 250)
    }

    @Test func textEdgeGrabsAlongEntireEdge() {
        let textKind = Easel.Item.Kind.text("Hello", size: 18)
        // High on the right edge
        #expect(Easel.corner(of: Self.r, at: .init(300, 120), kind: textKind) == .right)
        // Low on the right edge
        #expect(Easel.corner(of: Self.r, at: .init(300, 180), kind: textKind) == .right)
        // High on the left edge
        #expect(Easel.corner(of: Self.r, at: .init(100, 120), kind: textKind) == .left)
        // Top and bottom edges also grab for text
        #expect(Easel.corner(of: Self.r, at: .init(200, 100), kind: textKind) == .top)
        #expect(Easel.corner(of: Self.r, at: .init(200, 200), kind: textKind) == .bottom)
        // Center of text box returns nil
        #expect(Easel.corner(of: Self.r, at: .init(200, 150), kind: textKind) == nil)
    }
}
