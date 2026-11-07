import CraCore
import Foundation
import Testing

/// Arc's Easel model (Arc 1.172.1): what the toolbar's tools make, hit-testing and the saved file.
struct EaselTests {
    @Test func aNewEaselIsArcs() {
        let e = Easel()
        #expect(e.title == "Untitled Easel" && e.items.isEmpty)
        #expect(Easel.Tool.allCases.map(\.rawValue) == ["pointer", "image", "text", "ellipse", "rectangle", "arrow", "freehand"])
    }

    @Test func dragsDrawShapesWhicheverWayTheyGo() {
        let r = Easel.Item.drawn(.rectangle, from: .init(200, 150), to: .init(100, 50))
        #expect(r?.kind == .rectangle && r?.frame == .init(x: 100, y: 50, width: 100, height: 100))
        let a = Easel.Item.drawn(.arrow, from: .init(10, 10), to: .init(60, 30))
        #expect(a?.kind == .arrow(from: .init(10, 10), to: .init(60, 30)))
        #expect(Easel.Item.drawn(.pointer, from: .init(0, 0), to: .init(5, 5)) == nil)
    }

    @Test func thePointerPicksTheTopmostItem() {
        var e = Easel()
        let low = Easel.Item(kind: .rectangle, frame: .init(x: 0, y: 0, width: 100, height: 100))
        let high = Easel.Item(kind: .ellipse, frame: .init(x: 50, y: 50, width: 100, height: 100))
        e.items = [low, high]
        #expect(e.item(at: .init(75, 75))?.id == high.id)
        #expect(e.item(at: .init(10, 10))?.id == low.id)
        #expect(e.item(at: .init(400, 400)) == nil)
    }

    @Test func movingCarriesArrowsAndStrokes() {
        let stroke = Easel.freehand([.init(0, 0), .init(10, 20), .init(30, 5)])!
        #expect(stroke.frame == .init(x: 0, y: 0, width: 30, height: 20))
        let moved = stroke.moved(by: .init(5, 5))
        #expect(moved.kind == .freehand([.init(5, 5), .init(15, 25), .init(35, 10)]) && moved.frame.x == 5)
    }

    @Test func survivesASave() throws {
        var e = Easel(title: "Moodboard")
        e.items = [Easel.Item(kind: .text("Hello", size: 22), frame: .init(x: 1, y: 2, width: 3, height: 4), color: "#FF0000"),
                   Easel.Item(kind: .image(file: "a.png"), frame: .init(x: 0, y: 0, width: 10, height: 10))]
        #expect(try JSONDecoder().decode(Easel.self, from: JSONEncoder().encode(e)) == e)
    }

    @Test func itsTabHoldsItsAddress() {
        let e = Easel()
        #expect(Easel.id(fromURL: e.url) == e.id)
        #expect(Easel.id(fromURL: "https://example.com/") == nil && Easel.id(fromURL: "easel://nope") == nil)
    }
}
