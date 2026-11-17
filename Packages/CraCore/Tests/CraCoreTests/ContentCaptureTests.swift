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

    // MARK: Choosing the element (Arc's score, and ⌥ for the one right under the pointer, #451)

    /// One row of the picker script's stack: CSS size for the score, device pixels for the rect (1x here).
    static func el(_ tag: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, inline: Bool = false, shadow: Bool = false) -> [String: Any] {
        ["tag": tag, "inline": inline, "shadow": shadow, "w": w, "h": h, "x": x, "y": y, "width": w, "height": h]
    }

    /// YouTube's home page, 1383 × 1064 CSS px (16 Nov 2026), the pointer on a video's title line:
    /// the elements under it, topmost first, as `document.elementsFromPoint` gave them.
    static let youTubeTitle: [String: Any] = ["view": ["w": 1383.0, "h": 1064.0], "stack": [
        el("A", 678, 347, 263, 20, inline: true),
        el("H3", 678, 347, 263, 20),
        el("DIV", 678, 347, 263, 44),
        el("YT-LOCKUP-METADATA-VIEW-MODEL", 634, 347, 354, 44),
        el("DIV", 634, 136, 354, 255),
        el("YT-LOCKUP-VIEW-MODEL", 634, 136, 354, 255),
        el("DIV", 634, 136, 354, 331),
        el("YTD-RICH-ITEM-RENDERER", 634, 136, 354, 331),
        el("DIV", 256, 112, 1111, 4829),
        el("YTD-APP", 0, 0, 1383, 4957),
        el("HTML", 0, 0, 1383, 0),
    ]]

    @Test func arcPicksTheCardAroundATitle() throws {
        // Arc's score: the line is under 100 px tall (and the link inline), so the card wins; the
        // first of equal scores, the topmost, as Arc's stable sort keeps it.
        let stack = try #require(ContentCapture.pickerStack(from: Self.youTubeTitle))
        let chosen = try #require(ContentCapture.choose(in: stack, deeper: false))
        #expect(chosen.rect == CGRect(x: 634, y: 136, width: 354, height: 331))
        #expect(chosen.tag == "DIV")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/451"))
    func optionPicksTheTitleLineItself() throws {
        let stack = try #require(ContentCapture.pickerStack(from: Self.youTubeTitle))
        let chosen = try #require(ContentCapture.choose(in: stack, deeper: true))
        #expect(chosen.tag == "A")
        #expect(chosen.rect == CGRect(x: 678, y: 347, width: 263, height: 20))
    }

    @Test func arcPicksTheThumbnailImage() throws {
        let stack = try #require(ContentCapture.pickerStack(from: ["view": ["w": 1383.0, "h": 1064.0], "stack": [
            Self.el("IMG", 634, 136, 354, 199), Self.el("DIV", 634, 136, 354, 199),
            Self.el("DIV", 634, 136, 354, 331), Self.el("DIV", 256, 112, 1111, 4829),
        ]]))
        #expect(ContentCapture.choose(in: stack, deeper: false)?.tag == "IMG")
        #expect(ContentCapture.choose(in: stack, deeper: true)?.tag == "IMG")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/451"))
    func optionSkipsSpecksAndThePageButNotShadowRoots() throws {
        let stack = try #require(ContentCapture.pickerStack(from: ["view": ["w": 1000.0, "h": 700.0], "stack": [
            Self.el("SPAN", 10, 10, 40, 6, shadow: true),      // a hairline: too thin to capture
            Self.el("BUTTON", 10, 8, 40, 24, shadow: true),    // inside an open shadow root
            Self.el("SHREDDIT-POST", 0, 0, 600, 400),          // its host
            Self.el("BODY", 0, 0, 1000, 2000),                 // the page itself
        ]]))
        #expect(ContentCapture.choose(in: stack, deeper: true)?.tag == "BUTTON")
        // Arc's score never looks inside a shadow root.
        #expect(ContentCapture.choose(in: stack, deeper: false)?.tag == "SHREDDIT-POST")
        // Over the page alone neither finds anything; the page then only takes drags.
        let bare = try #require(ContentCapture.pickerStack(from: ["view": ["w": 1000.0, "h": 700.0], "stack": [Self.el("BODY", 0, 0, 1000, 2000)]]))
        #expect(ContentCapture.choose(in: bare, deeper: true) == nil)
        #expect(ContentCapture.choose(in: bare, deeper: false) == nil)
    }

    @Test func pickerStackRejectsWhatItCannotRead() {
        #expect(ContentCapture.pickerStack(from: [:]) == nil)
        #expect(ContentCapture.pickerStack(from: ["view": ["w": 0, "h": 700], "stack": []] as [String: Any]) == nil)
        // A row missing its numbers is left out, not the whole stack; JSON numbers arrive as NSNumber.
        let json = try? JSONSerialization.jsonObject(with: Data(#"{"view":{"w":800,"h":600},"stack":[{"tag":"P"},{"tag":"DIV","inline":false,"shadow":false,"w":200,"h":150,"x":2,"y":4,"width":400,"height":300}]}"#.utf8)) as? [String: Any]
        let stack = ContentCapture.pickerStack(from: json ?? [:])
        #expect(stack?.elements.count == 1)
        #expect(stack?.elements.first?.rect == CGRect(x: 2, y: 4, width: 400, height: 300))
        #expect(stack?.elements.first?.size == CGSize(width: 200, height: 150))
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

    @Test func capturedImageMovesToTheMiddleWithTheMenuBesideIt() {
        // Arc 1.172's Little Arc: a 1688 × 963 pt page, a 160 × 100 pt image, the 273 pt menu.
        let page = CGRect(x: 0, y: 0, width: 1688, height: 963)
        let l = ContentCapture.liftedLayout(image: CGSize(width: 160, height: 100), menu: CGSize(width: 273, height: 300), in: page)
        #expect(l.image == CGRect(x: 627.5, y: 431.5, width: 160, height: 100))
        // Ring 623.5…791.5, the menu 10 pt on, level with the ring's top.
        #expect(l.menu == CGRect(x: 801.5, y: 427.5, width: 273, height: 300))
    }

    @Test func capturedImageTooBigShrinksAndTheMenuFindsRoom() {
        let l = ContentCapture.liftedLayout(image: CGSize(width: 2000, height: 1000), menu: CGSize(width: 273, height: 300), in: Self.page)
        // Fits inside the ring and margins, aspect kept.
        #expect(l.image.width == 976 && l.image.height == 488)
        #expect(Self.page.contains(ContentCapture.lensFrame(around: l.image)))
        // No room beside it: menuFrame's place, inside the page.
        #expect(Self.page.insetBy(dx: ContentCapture.menuMargin, dy: ContentCapture.menuMargin).contains(l.menu))
    }

    @Test func imageScriptLooksForTheImageUnderThePoint() {
        let js = ContentCapture.imageRectScript(x: 120, y: 80)
        #expect(js.contains("elementsFromPoint(px, py)"))
        #expect(js.contains("120.0 / dpr / k"))
        #expect(js.contains("'IMG'"))
    }
}
