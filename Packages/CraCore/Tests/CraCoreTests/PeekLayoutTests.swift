import CoreGraphics
import CraCore
import Testing

/// Arc's Peek as measured (docs/arc-reverse-engineering.md, "Peek and the copy toast's Share
/// button"): a 1728 × 1084 pt window, sidebar edge at 347, AX frames turned y-up.
struct PeekLayoutTests {
    static let window = CGSize(width: 1728, height: 1084)

    @Test func cardMatchesArc() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 347))
        // Arc: x 485…1590, 12 pt under the window's top, 12.5 above its bottom.
        #expect(card == CGRect(x: 485, y: 12, width: 1105, height: 1060))
    }

    @Test func buttonsMatchArc() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 347))
        let buttons = PeekLayout.buttons(beside: card)
        // Arc's tops, 19 / 63 / 106 pt under the window's top (y down).
        let topsFromWindowTop = buttons.map { Self.window.height - $0.maxY }
        #expect(buttons.allSatisfy { $0.minX == 1603 && $0.size == PeekLayout.buttonSize })
        #expect(zip(topsFromWindowTop, [19.0, 63, 106]).allSatisfy { abs($0 - $1) <= 0.5 })
        #expect(PeekLayout.column(beside: card) == CGRect(x: 1603, y: buttons[2].minY, width: 34, height: buttons[0].maxY - buttons[2].minY))
    }

    @Test func clicksNearTheEdgeResizeLikeArc() {
        // Arc 1.172.1, a 1100 × 760 pt window: 1–3 pt inside an edge resize and keep the Peek, 4 pt
        // in closes it.
        let window = CGRect(x: 100, y: 80, width: 1100, height: 760)
        let area = PeekLayout.dismissArea(covering: window)
        for d: CGFloat in [1, 2, 3 - 0.01] {
            for p in [CGPoint(x: window.maxX - d, y: window.midY), CGPoint(x: window.minX + d, y: window.midY),
                      CGPoint(x: window.midX, y: window.maxY - d), CGPoint(x: window.midX, y: window.minY + d)] {
                #expect(!area.contains(p), "\(d) pt in")
            }
        }
        for p in [CGPoint(x: window.maxX - 4, y: window.midY), CGPoint(x: window.minX + 4, y: window.midY),
                  CGPoint(x: window.midX, y: window.maxY - 4), CGPoint(x: window.midX, y: window.minY + 4)] {
            #expect(area.contains(p))
        }
        #expect(window.contains(area))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/242")) func aClickOnTheSidebarIsTheSidebars() {
        // Arc 1.172.1, 8 Nov: a click on another tab's row with a Peek over the page opens that tab
        // (the Peek waits on its own); only the page area closes the Peek.
        let window = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let area = PeekLayout.dismissArea(covering: window, contentMinX: 236)
        for x: CGFloat in [1, 6, 114, 235] { #expect(!area.contains(CGPoint(x: x, y: 600)), "sidebar at \(x)") }
        for x: CGFloat in [236, 300, 1724.99] { #expect(area.contains(CGPoint(x: x, y: 600)), "page at \(x)") }
        // The resize band stays out at the top, right and bottom.
        #expect(area.maxX == window.maxX - 3 && area.minY == window.minY + 3 && area.maxY == window.maxY - 3)
        // With the sidebar hidden the page fills the window, and so does the area.
        #expect(PeekLayout.dismissArea(covering: window, contentMinX: 0) == PeekLayout.dismissArea(covering: window))
        #expect(PeekLayout.dismissArea(covering: window, contentMinX: 0).minX == 3)
    }

    @Test func hiddenSidebarCentresOnTheWindow() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 0))
        #expect(card.midX == Self.window.width / 2)
        #expect(card.width == (Self.window.width * 0.8).rounded())
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func withoutALinkItGrowsFromTheArea() {
        // Arc from a link that covers the page (3 Nov): the card starts as the whole area.
        let area = PeekLayout.area(window: Self.window, contentMinX: 347)
        let card = PeekLayout.card(in: area)
        #expect(PeekLayout.opening(from: area, to: card, at: 0).frame == area)
        #expect(PeekLayout.opening(from: area, to: card, at: PeekLayout.openDuration).frame == card)
        #expect(PeekLayout.closing(from: card, to: area, at: PeekLayout.closeToAreaDuration, duration: PeekLayout.closeToAreaDuration).frame == area)
    }

    // MARK: Growing out of the link (Arc 1.171, small links, 60 fps, 6 Nov 2026, GitHub #204)

    static let card = PeekLayout.card(in: PeekLayout.area(window: window, contentMinX: 347))
    /// Link A of the run: x 407, 132 pt under the window's top, 68 × 31.
    static let link = CGRect(x: 407, y: 1084 - 132 - 31, width: 68, height: 31)

    @Test func curvesRunFromZeroToOne() {
        for c in [PeekLayout.Curve.easeOut, .easeOutCubic, .close] {
            #expect(c(0) == 0 && c(1) == 1 && c(-1) == 0 && c(2) == 1)
            #expect(c(0.25) < c(0.5) && c(0.5) < c(0.75))
        }
        // The ease-out cubic's own value, 1 − (1 − u)³, within a hair.
        #expect(abs(PeekLayout.Curve.easeOutCubic(0.5) - 0.875) < 0.02)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func opensFromTheLinkAndLandsOnTheCard() {
        let start = PeekLayout.opening(from: Self.link, to: Self.card, at: 0)
        #expect(start.frame == Self.link)
        #expect(start.sourceOpacity == 1 && start.buttonsOpacity == 0)
        let end = PeekLayout.opening(from: Self.link, to: Self.card, at: PeekLayout.openDuration)
        #expect(end.frame == Self.card)
        #expect(end.sourceOpacity == 0 && end.buttonsOpacity == 1)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func heightLagsWidthAsInArc() {
        // Arc, run A: when the width was 60.3 % of the way, the height was 47.9 %.
        var t = 0.0
        while PeekLayout.opening(from: Self.link, to: Self.card, at: t).frame.width < Self.link.width + 0.603 * (Self.card.width - Self.link.width) { t += 0.0005 }
        let f = PeekLayout.opening(from: Self.link, to: Self.card, at: t).frame
        let q = (f.height - Self.link.height) / (Self.card.height - Self.link.height)
        #expect(abs(q - 0.479) < 0.05)
        // The centre goes with the width.
        let p = (f.midX - Self.link.midX) / (Self.card.midX - Self.link.midX)
        #expect(abs(p - 0.603) < 0.01)
        // The link's picture was mostly gone by then (Arc: 0.065).
        #expect(PeekLayout.opening(from: Self.link, to: Self.card, at: t).sourceOpacity < 0.12)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func closesBackIntoTheLink() {
        let start = PeekLayout.closing(from: Self.card, to: Self.link, at: 0)
        #expect(start.frame == Self.card && start.sourceOpacity == 0 && start.buttonsOpacity == 1)
        let end = PeekLayout.closing(from: Self.card, to: Self.link, at: PeekLayout.closeScaleDuration)
        #expect(end.frame == Self.link && end.buttonsOpacity == 0)
        // Arc, run B: the link picture at about a third when the frame was 80 % of the way.
        var t = 0.0
        while PeekLayout.closing(from: Self.card, to: Self.link, at: t).frame.width > Self.card.width - 0.8 * (Self.card.width - Self.link.width) { t += 0.0005 }
        let a = PeekLayout.closing(from: Self.card, to: Self.link, at: t).sourceOpacity
        #expect(a > 0.15 && a < 0.5)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func pageScalesWithTheWidthFromTheTopLeft() {
        let frame = PeekLayout.frame(from: Self.link, to: Self.card, p: 0.6, q: 0.48)
        let c = PeekLayout.content(in: frame, card: Self.card)
        #expect(abs(c.width - frame.width) < 0.001)
        #expect(abs(c.maxY - frame.height) < 0.001 && c.minX == 0)
        #expect(abs(c.height / Self.card.height - frame.width / Self.card.width) < 0.001)
        #expect(PeekLayout.content(in: Self.card, card: Self.card) == CGRect(origin: .zero, size: Self.card.size))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func columnRidesTheCorner() {
        let column = PeekLayout.column(beside: Self.card)
        #expect(PeekLayout.column(column, card: Self.card, frame: Self.card) == column)
        let half = CGRect(x: 600, y: 300, width: Self.card.width / 2, height: 400)
        let c = PeekLayout.column(column, card: Self.card, frame: half)
        #expect(abs(c.width - column.width / 2) < 0.001)
        #expect(abs(half.maxY - c.maxY - PeekLayout.buttonTop) < 0.5)
        #expect(abs(c.minX - half.maxX - PeekLayout.buttonGap / 2) < 0.001)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/204")) func linkFractionsMapOntoThePage() {
        let page = CGRect(x: 347, y: 0, width: 1371, height: 1032)
        // Run A's link: 60, 90, 68 × 31 CSS px in a 1371 × 1032 view.
        let f = CGRect(x: 60.0 / 1371, y: 90.0 / 1032, width: 68.0 / 1371, height: 31.0 / 1032)
        let r = PeekLayout.source(fraction: f, in: page)!
        #expect(abs(r.minX - 407) < 0.001 && abs(r.maxY - (1032 - 90)) < 0.001 && abs(r.width - 68) < 0.001)
        // Off the page, empty or not a number: no source.
        #expect(PeekLayout.source(fraction: CGRect(x: 2, y: 0, width: 0.1, height: 0.1), in: page) == nil)
        #expect(PeekLayout.source(fraction: CGRect(x: 0, y: 0, width: 0, height: 0.1), in: page) == nil)
        #expect(PeekLayout.source(fraction: CGRect(x: .nan, y: 0, width: 0.1, height: 0.1), in: page) == nil)
        // Partly scrolled out: the part on the page.
        #expect(PeekLayout.source(fraction: CGRect(x: 0.5, y: -0.02, width: 0.1, height: 0.05), in: page)?.maxY == page.maxY)
    }

    @Test func scriptAnswersParse() {
        #expect(PeekLayout.fraction(fromScript: ["x": 0.1, "y": 0.2, "width": 0.05, "height": 0.03]) == CGRect(x: 0.1, y: 0.2, width: 0.05, height: 0.03))
        #expect(PeekLayout.fraction(fromScript: ["x": "0.1", "y": 0.2, "width": 0.05, "height": 0.03]) == nil)
        #expect(!PeekLayout.sourceScript(pointer: nil).contains("nan"))
        #expect(PeekLayout.sourceScript(pointer: CGPoint(x: 0.25, y: 0.5)).contains("0.25 * vv.width"))
    }
}
