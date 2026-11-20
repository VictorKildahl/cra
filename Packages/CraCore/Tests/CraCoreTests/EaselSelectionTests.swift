import CraCore
import Foundation
import Testing

struct EaselSelectionTests {
    let a = Easel.Item(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
    let b = Easel.Item(kind: .ellipse, frame: .init(x: 300, y: 100, width: 100, height: 100))
    let c = Easel.Item(kind: .arrow(from: .init(500, 150), to: .init(600, 150)), frame: .init(x: 500, y: 150, width: 100, height: 0))
    let d = Easel.Item(kind: .text("Note", size: 18), frame: .init(x: 100, y: 400, width: 240, height: 27))
    var easel: Easel { Easel(items: [a, b, c, d]) }

    /// GitHub #580: the canvas picked one item at a time. ⌘- or ⇧-click now adds an item to the picks
    /// or takes it out, as Finder does; a plain click on a picked item keeps the group (so it can be
    /// dragged), and a plain click elsewhere picks that item alone or, on empty canvas, nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func commandOrShiftClickAddsAndRemoves() {
        #expect(Easel.picked([], click: a.id, extend: false) == [a.id])
        #expect(Easel.picked([a.id], click: b.id, extend: true) == [a.id, b.id])
        #expect(Easel.picked([a.id, b.id], click: a.id, extend: true) == [b.id])
        #expect(Easel.picked([a.id, b.id], click: nil, extend: true) == [a.id, b.id])
        #expect(Easel.picked([a.id, b.id], click: b.id, extend: false) == [a.id, b.id])
        #expect(Easel.picked([a.id, b.id], click: c.id, extend: false) == [c.id])
        #expect(Easel.picked([a.id, b.id], click: nil, extend: false) == [])
    }

    /// GitHub #580: "let me drag and select multiple items, just like anything else on the Mac". A drag
    /// from empty canvas draws a box that picks every item it touches, a flat arrow included; with ⌘ or
    /// ⇧ held, the items it touches flip in the picks from before the drag, as in Finder.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func dragBoxPicksEveryItemItTouches() {
        let band = Easel.Rect(from: .init(550, 50), to: .init(150, 160))
        #expect(easel.touching(band) == [a.id, b.id, c.id])
        #expect(easel.touching(Easel.Rect(from: .init(220, 220), to: .init(280, 380))).isEmpty)
        #expect(easel.touching(Easel.Rect(from: .init(90, 390), to: .init(110, 410))) == [d.id])
        #expect(Easel.picked([d.id], band: [a.id, b.id], extend: false) == [a.id, b.id])
        #expect(Easel.picked([a.id, d.id], band: [a.id, b.id], extend: true) == [d.id, b.id])
    }

    /// GitHub #580: picked items move together, by the same amount, and snap as one box onto the edges
    /// of the items that stay (Use Alignment Guides).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func pickedItemsMoveTogetherAndSnapAsOne() {
        let moved = easel.moving([a.id, c.id], by: .init(10, 40), snap: false)
        #expect(moved.easel.items[0].frame == .init(x: 110, y: 140, width: 100, height: 100))
        #expect(moved.easel.items[2].kind == .arrow(from: .init(510, 190), to: .init(610, 190)))
        #expect(moved.easel.items[1] == b && moved.easel.items[3] == d)
        #expect(moved.guides.isEmpty)
        // The group's box (a to c, y 100–200) dragged 197 pt down ends 3 pt above d's top (400): the
        // box lands on it, and both items move the 200 pt with it.
        let snapped = easel.moving([a.id, c.id], by: .init(0, 197), snap: true)
        #expect(snapped.easel.items[0].frame == .init(x: 100, y: 300, width: 100, height: 100))
        #expect(snapped.easel.items[2].kind == .arrow(from: .init(500, 350), to: .init(600, 350)))
        #expect(snapped.guides.contains { $0.axis == .horizontal && $0.position == 400 })
        #expect(Easel.bounds(of: [a.frame, c.frame]) == .init(x: 100, y: 100, width: 500, height: 100))
        #expect(Easel.bounds(of: []) == nil)
    }

    /// GitHub #580: Bring to Front and Send to Back move every picked item, keeping their order among
    /// themselves; the menu rows grey out when the group is already there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func groupLayersTogether() {
        var e = easel
        e.bringToFront([b.id, a.id])
        #expect(e.items.map(\.id) == [c.id, d.id, a.id, b.id])
        #expect(e.isFront([a.id, b.id]) && !e.isFront([a.id, c.id]))
        e.sendToBack([d.id, b.id])
        #expect(e.items.map(\.id) == [d.id, b.id, c.id, a.id])
        #expect(e.isBack([b.id, d.id]) && !e.isBack([a.id]))
    }
}
