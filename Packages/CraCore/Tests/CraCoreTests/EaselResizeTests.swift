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

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func picturesShapesAndTextResize() {
        #expect(Easel.resizes(.image(file: "a.png")))
        #expect(Easel.resizes(.rectangle))
        #expect(Easel.resizes(.ellipse))
        #expect(Easel.resizes(.text("x", size: 18)))
        #expect(!Easel.resizes(.arrow(from: .init(0, 0), to: .init(10, 10))))
        #expect(!Easel.resizes(.freehand([])))
    }

    /// Arc 1.174.1 (22 Nov 2026): four corner dots on whatever resizes, none on the edges.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func onlyTheCornersHaveDots() {
        let corners: [Easel.Corner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for kind: Easel.Item.Kind in [.rectangle, .ellipse, .text("x", size: 18), .image(file: "a.png")] {
            #expect(Easel.handles(for: kind) == corners)
        }
        #expect(Easel.handles(for: .arrow(from: .init(0, 0), to: .init(10, 10))).isEmpty)
    }

    /// Arc's ExtendedDragArea: a shape's or a text box's edge resizes from anywhere along it, right up to the
    /// corners (which win where they meet); a picture's edges don't, nor a press inside.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func edgesGrabAlongTheirWholeLength() {
        for kind: Easel.Item.Kind in [.rectangle, .ellipse, .text("x", size: 18)] {
            #expect(Easel.corner(of: Self.r, at: .init(300, 112), kind: kind) == .right)
            #expect(Easel.corner(of: Self.r, at: .init(302, 188), kind: kind) == .right)
            #expect(Easel.corner(of: Self.r, at: .init(98, 120), kind: kind) == .left)
            #expect(Easel.corner(of: Self.r, at: .init(115, 101), kind: kind) == .top)
            #expect(Easel.corner(of: Self.r, at: .init(285, 199), kind: kind) == .bottom)
            #expect(Easel.corner(of: Self.r, at: .init(299, 101), kind: kind) == .topRight)
            #expect(Easel.corner(of: Self.r, at: .init(200, 150), kind: kind) == nil)
        }
        #expect(Easel.corner(of: Self.r, at: .init(300, 150), kind: .image(file: "a.png")) == nil)
        #expect(Easel.corner(of: Self.r, at: .init(300, 150)) == nil)
    }

    /// Arc: the right edge dragged 100 pt widened the rectangle 100 pt, its height and left edge unchanged.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func aShapeResizesFromAnEdge() {
        #expect(Easel.resized(Self.r, corner: .right, to: .init(400, 150)) == Easel.Rect(x: 100, y: 100, width: 300, height: 100))
        #expect(Easel.resized(Self.r, corner: .left, to: .init(80, 150)) == Easel.Rect(x: 80, y: 100, width: 220, height: 100))
        #expect(Easel.resized(Self.r, corner: .top, to: .init(200, 80)) == Easel.Rect(x: 100, y: 80, width: 200, height: 120))
        #expect(Easel.resized(Self.r, corner: .bottom, to: .init(200, 250)) == Easel.Rect(x: 100, y: 100, width: 200, height: 150))
        let flat = Easel.resized(Self.r, corner: .top, to: .init(200, 300))
        #expect(flat.height == Easel.minimumSide && flat.y == 200 - Easel.minimumSide)
    }

    /// Arc: a text box's corner or left/right edge sets its width with the other side fixed (the text reflows); its
    /// top and bottom edges move nothing, as its height is its text's.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func aTextBoxTakesItsWidthFromADrag() {
        #expect(Easel.resizedText(Self.r, corner: .right, to: .init(350, 150))! == (100, 250))
        #expect(Easel.resizedText(Self.r, corner: .bottomRight, to: .init(450, 400))! == (100, 350))
        #expect(Easel.resizedText(Self.r, corner: .left, to: .init(0, 150))! == (0, 300))
        #expect(Easel.resizedText(Self.r, corner: .topLeft, to: .init(150, 0))! == (150, 150))
        #expect(Easel.resizedText(Self.r, corner: .bottom, to: .init(200, 400)) == nil)
        #expect(Easel.resizedText(Self.r, corner: .top, to: .init(200, 0)) == nil)
        // Never narrower than a short word.
        #expect(Easel.resizedText(Self.r, corner: .right, to: .init(90, 150))!.width == Easel.textPadding + 40)
    }

    /// The width a drag set stays as the text changes and after the easel is reopened (it's saved with the item);
    /// a box nobody resized fits its longest line (#580).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/680"))
    func aDraggedWidthStays() throws {
        var item = Easel.Item(kind: .text("Hello", size: 18), frame: .init(x: 0, y: 0, width: 300, height: 30))
        #expect(Easel.textBoxWidth(item, longestLine: 400) == Easel.textWidth(longestLine: 400))
        item.fixedWidth = true
        #expect(Easel.textBoxWidth(item, longestLine: 400) == 300)
        let reopened = try JSONDecoder().decode(Easel.Item.self, from: JSONEncoder().encode(item))
        #expect(reopened.fixedWidth == true && Easel.textBoxWidth(reopened, longestLine: 10) == 300)
        // A box saved before #680 has no fixedWidth, and nothing is written for one that has none.
        var plain = item
        plain.fixedWidth = nil
        #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("fixedWidth"))
    }
}
