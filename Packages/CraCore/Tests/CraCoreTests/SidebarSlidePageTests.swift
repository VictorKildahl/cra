import CoreGraphics
import CraCore
import Testing

struct SidebarSlidePageTests {
    @Test func aPageThatStaysPutHasNoDrift() {
        var slide = SidebarSlidePage()
        #expect(slide.isEmpty)
        for _ in 0..<5 { slide.record(CGRect(x: 10, y: 10, width: 1380, height: 800)) }
        #expect(!slide.isEmpty)
        #expect(slide.drift == 0)
    }

    @Test func aPageThatRidesItsCardDriftsBySidebarWidth() {
        var slide = SidebarSlidePage()
        for x in [260.0, 152, 80, 37, 17, 10] { slide.record(CGRect(x: x, y: 10, width: 1380, height: 800)) }
        #expect(slide.drift == 250)
        #expect(slide.samples == 6)
    }

    @Test func theCardsRightEdgeStaysPut() {
        let from = CGRect(x: 260, y: 10, width: 1130, height: 800), to = CGRect(x: 10, y: 10, width: 1380, height: 800)
        #expect(SidebarSlidePage.frame(from: from, to: to, progress: 0) == from)
        #expect(SidebarSlidePage.frame(from: from, to: to, progress: 1) == to)
        for p in [0.25, 0.43, 0.72, 0.97] {
            let f = SidebarSlidePage.frame(from: from, to: to, progress: p)
            #expect(abs(f.maxX - 1390) < 1e-9)
            #expect(f.minX < from.minX && f.minX > to.minX)
        }
    }

    /// Full screen, 10 Nov: a sample taken before the slide's first layout was drawn still showed the
    /// page where it was before ⌘S, and the readout called that 328 pt of movement.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/317"))
    func thePictureFromBeforeTheSlideIsNotMovement() {
        var slide = SidebarSlidePage()
        slide.record(CGRect(x: 328, y: 10, width: 1582, height: 1060), drawn: false)
        #expect(slide.isEmpty)
        for _ in 0..<5 { slide.record(CGRect(x: 0, y: 0, width: 1920, height: 1080), drawn: true) }
        slide.record(CGRect(x: 0, y: 0, width: 1920, height: 1080), drawn: false)
        #expect(slide.drift == 0)
        #expect(slide.samples == 6)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/317"))
    func onceDrawnEverySampleCounts() {
        var slide = SidebarSlidePage()
        slide.record(CGRect(x: 10, y: 0, width: 100, height: 10), drawn: true)
        slide.record(CGRect(x: 60, y: 0, width: 100, height: 10), drawn: false)
        #expect(slide.drift == 50)
    }

    @Test func eitherEdgeMovingCounts() {
        var slide = SidebarSlidePage()
        slide.record(CGRect(x: 10, y: 0, width: 100, height: 10))
        slide.record(CGRect(x: 10, y: 0, width: 130, height: 10))
        #expect(slide.drift == 30)
    }
}
