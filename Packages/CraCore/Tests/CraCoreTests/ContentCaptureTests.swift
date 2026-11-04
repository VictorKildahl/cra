import CoreGraphics
import CraCore
import Foundation
import Testing

struct ContentCaptureTests {
    static let page = CGRect(x: 0, y: 0, width: 1000, height: 700)

    @Test func smallMovesAreClicks() {
        #expect(!ContentCapture.isDrag(from: .zero, to: CGPoint(x: 2, y: 3)))
        #expect(ContentCapture.isDrag(from: .zero, to: CGPoint(x: 3, y: 3)))
        #expect(ContentCapture.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 4)))
    }

    @Test func selectionNormalisesAndStaysOnThePage() {
        #expect(ContentCapture.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: Self.page)
                == CGRect(x: 100, y: 50, width: 200, height: 150))
        // Dragged out past the page's bottom-right corner.
        #expect(ContentCapture.selection(from: CGPoint(x: 900, y: 600), to: CGPoint(x: 1200, y: 900), in: Self.page)
                == CGRect(x: 900, y: 600, width: 100, height: 100))
        #expect(ContentCapture.selection(from: CGPoint(x: -50, y: -50), to: CGPoint(x: -10, y: -10), in: Self.page) == .zero)
    }

    @Test func tinySelectionsCaptureNothing() {
        #expect(!ContentCapture.isCapturable(CGRect(x: 0, y: 0, width: 200, height: 7)))
        #expect(!ContentCapture.isCapturable(.zero))
        #expect(ContentCapture.isCapturable(CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    @Test func pixelRectScalesToTheScreenshot() {
        let px = ContentCapture.pixelRect(for: CGRect(x: 10.25, y: 20, width: 100, height: 50.5),
                                          pageSize: Self.page.size, imageSize: CGSize(width: 2000, height: 1400))
        #expect(px == CGRect(x: 20, y: 40, width: 201, height: 101))
        // Never outside the image.
        #expect(ContentCapture.pixelRect(for: CGRect(x: 950, y: 650, width: 100, height: 100),
                                         pageSize: Self.page.size, imageSize: CGSize(width: 2000, height: 1400))
                == CGRect(x: 1900, y: 1300, width: 100, height: 100))
        #expect(ContentCapture.pixelRect(for: .zero, pageSize: .zero, imageSize: CGSize(width: 10, height: 10)) == .zero)
    }

    @Test func pickerResultBecomesPoints() {
        // Device pixels on a 2x screen.
        let r = ContentCapture.elementRect(fromPicker: ["x": 100.0, "y": 60.0, "width": 400.0, "height": 300.0], scale: 2, pageBounds: Self.page)
        #expect(r == CGRect(x: 50, y: 30, width: 200, height: 150))
        // Partly scrolled off the top: only the visible part.
        let off = ContentCapture.elementRect(fromPicker: ["x": 0, "y": -100, "width": 200, "height": 300] as [String: Any], scale: 1, pageBounds: Self.page)
        #expect(off == CGRect(x: 0, y: 0, width: 200, height: 200))
        // JSON numbers arrive as NSNumber.
        let json = try? JSONSerialization.jsonObject(with: Data(#"{"x":2,"y":4,"width":20,"height":40}"#.utf8)) as? [String: Any]
        #expect(ContentCapture.elementRect(fromPicker: json ?? [:], scale: 2, pageBounds: Self.page) == CGRect(x: 1, y: 2, width: 10, height: 20))
    }

    @Test func pickerFindingNothingOrOffPageIsNil() {
        #expect(ContentCapture.elementRect(fromPicker: [:], scale: 2, pageBounds: Self.page) == nil)
        #expect(ContentCapture.elementRect(fromPicker: ["x": 0, "y": 0, "width": 0, "height": 10], scale: 2, pageBounds: Self.page) == nil)
        #expect(ContentCapture.elementRect(fromPicker: ["x": 5000, "y": 0, "width": 10, "height": 10], scale: 1, pageBounds: Self.page) == nil)
        #expect(ContentCapture.elementRect(fromPicker: ["x": 0, "y": 0, "width": 10, "height": 10], scale: 0, pageBounds: Self.page) == nil)
    }

    @Test func lensMatchesArc() {
        // Arc: the image at page (32, 224) 480 × 300 showed in colour from 30, its ring's outer edge 6 pt out.
        let clear = ContentCapture.clearArea(element: CGRect(x: 32, y: 224, width: 480, height: 300))
        #expect(clear == CGRect(x: 30, y: 222, width: 484, height: 304))
        #expect(ContentCapture.lensFrame(around: clear) == CGRect(x: 26, y: 218, width: 492, height: 312))
        // A dragged rectangle gets its ring right outside it (Arc: a drag ending at x 1080 had its ring to 1084).
        #expect(ContentCapture.lensFrame(around: CGRect(x: 800, y: 145, width: 280, height: 175)).maxX == 1084)
    }

    @Test func menuGoesRightOfTheCaptureLikeArc() {
        // Arc, 1371 × 848 pt page: a dragged rectangle (800, 145)–(1080, 320) put its 273 pt menu at
        // x 1088 (4.5 right of the ring), level with the ring's top at 141.
        let page = CGRect(x: 0, y: 0, width: 1371, height: 848)
        let lens = ContentCapture.lensFrame(around: CGRect(x: 800, y: 145, width: 280, height: 175))
        let menu = ContentCapture.menuFrame(size: CGSize(width: 273, height: 354), besideLens: lens, in: page)
        #expect(menu == CGRect(x: 1088.5, y: 141, width: 273, height: 354))
    }

    @Test func menuFallsBackLeftThenInside() {
        let size = CGSize(width: 200, height: 180)
        // No room right: left of the ring.
        let left = ContentCapture.menuFrame(size: size, besideLens: ContentCapture.lensFrame(around: CGRect(x: 700, y: 100, width: 250, height: 100)), in: Self.page)
        #expect(left.maxX == 700 - 4 - ContentCapture.menuGap)
        // A capture as wide as the page: inside its right edge.
        let inside = ContentCapture.menuFrame(size: size, besideLens: ContentCapture.lensFrame(around: CGRect(x: 0, y: 100, width: 1000, height: 100)), in: Self.page)
        #expect(inside.maxX == 1000 - ContentCapture.menuMargin)
        // Near the bottom: pulled up to stay on the page; near the top: pushed down.
        let low = ContentCapture.menuFrame(size: size, besideLens: ContentCapture.lensFrame(around: CGRect(x: 100, y: 650, width: 100, height: 40)), in: Self.page)
        #expect(low.maxY == 700 - ContentCapture.menuMargin)
        let high = ContentCapture.menuFrame(size: size, besideLens: ContentCapture.lensFrame(around: CGRect(x: 100, y: 0, width: 100, height: 40)), in: Self.page)
        #expect(high.minY == ContentCapture.menuMargin)
    }

    @Test func pickerScriptCarriesThePoint() {
        let s = ContentCapture.pickerScript(x: 123.5, y: 456)
        #expect(s.contains("123.5 / dpr"))
        #expect(s.contains("456.0 / dpr"))
        #expect(s.contains("elementsFromPoint"))
    }
}
