import CraCore
import Foundation
import Testing

struct EaselCanvasExtentTests {
    let home = Easel.home(width: 1000)
    let view = Easel.Rect(x: 0, y: 0, width: 1000, height: 700)

    /// GitHub #580: "It should be an endless canvas to put ideas on board, but it isn't." The canvas was
    /// the window's width and 2436 pt tall, so a board ran out at the bottom and the right. Now there is
    /// always a whole view's room past the home sheet, the items and what is in view, on every side.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func thereIsAlwaysRoomOnEverySide() {
        let e = Easel.extent(home: home, items: [], visible: view)
        #expect(e == .init(x: -1000, y: -700, width: 3000, height: 2436 + 1400))
        // Scrolled to the bottom right corner of that: there is a view's room further on again.
        let corner = Easel.Rect(x: e.x + e.width - 1000, y: e.y + e.height - 700, width: 1000, height: 700)
        let further = Easel.extent(home: home, items: [], visible: corner, keeping: e)
        #expect(further.x + further.width == corner.x + corner.width + 1000)
        #expect(further.y + further.height == corner.y + corner.height + 700)
        // And up and to the left.
        let topLeft = Easel.Rect(x: e.x, y: e.y, width: 1000, height: 700)
        let back = Easel.extent(home: home, items: [], visible: topLeft, keeping: e)
        #expect(back.x == e.x - 1000 && back.y == e.y - 700)
    }

    /// GitHub #580: items anywhere, far below Arc's 2436 pt or left of the home sheet, are on the canvas
    /// with room past them; zoomed out (a bigger view) the room grows with it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func itemsAnywhereAreOnTheCanvas() {
        let far = Easel.Rect(x: -5000, y: 9000, width: 200, height: 200)
        let e = Easel.extent(home: home, items: [far], visible: view)
        #expect(e.x == -6000 && e.y + e.height == 9200 + 700)
        let zoomedOut = Easel.Rect(x: -2000, y: -1400, width: 5000, height: 3500)
        let wide = Easel.extent(home: home, items: [], visible: zoomedOut)
        #expect(wide.x == -7000 && wide.y == -4900)
        // An item from a damaged file or another app's pasteboard, past the canvas's reach or not a
        // number, doesn't stretch it.
        let plain = Easel.extent(home: home, items: [], visible: view)
        let wild = [Easel.Rect(x: 1e300, y: 0, width: 10, height: 10), .init(x: .nan, y: 0, width: 10, height: 10),
                    .init(x: 0, y: -.infinity, width: 10, height: 10), .init(x: 0, y: 0, width: 2e6, height: 10)]
        #expect(Easel.extent(home: home, items: wild, visible: view) == plain)
    }

    /// GitHub #580: while a scroll or drag goes on the canvas only grows; once it ends it shrinks back
    /// round the home sheet, the items and the view, and lands on whole points.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func growsWhileScrollingAndShrinksAfter() {
        let big = Easel.Rect(x: -20000, y: -20000, width: 50000, height: 50000)
        #expect(Easel.extent(home: home, items: [], visible: view, keeping: big) == big)
        #expect(Easel.extent(home: home, items: [], visible: view) == .init(x: -1000, y: -700, width: 3000, height: 3836))
        let odd = Easel.extent(home: home, items: [.init(x: 10.4, y: 3000.6, width: 5, height: 5)], visible: view)
        #expect(odd.x == odd.x.rounded() && odd.y + odd.height == (3005.6 + 700).rounded(.up))
    }

    /// GitHub #580: View ▸ Zoom In and Out step the canvas as they step a page (1.2× a step, ⌘0 back to
    /// actual size), between a tenth and four times.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/580"))
    func zoomStepsLikeAPage() {
        #expect(Easel.magnification(zoomLevel: 0) == 1)
        #expect(abs(Easel.magnification(zoomLevel: 1) - 1.2) < 1e-9)
        #expect(Easel.magnification(zoomLevel: -40) == 0.1)
        #expect(Easel.magnification(zoomLevel: 40) == 4)
        #expect(abs(Easel.zoomLevel(magnification: 1.2 * 1.2) - 2) < 1e-9)
    }
}
