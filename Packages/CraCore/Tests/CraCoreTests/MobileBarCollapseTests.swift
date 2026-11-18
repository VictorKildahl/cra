import CoreGraphics
import CraCore
import Testing

/// Site Settings ▸ Collapse Bottom Bar: on, scrolling down puts the bar away and scrolling up
/// brings it back; off, the bar stays on the page whatever it does.
struct MobileBarCollapseTests {
    /// 24 pt of scrolling down puts the bar away, 24 pt back up brings it back, and the top of
    /// the page always has it.
    @Test func scrollingDownPutsTheBarAwayAndScrollingUpBringsItBack() {
        var bar = MobileBarCollapse()
        var moved = bar.scrolled(by: 20, atTop: false, collapses: true)
        #expect(!moved && !bar.isHidden)
        moved = bar.scrolled(by: 10, atTop: false, collapses: true)
        #expect(moved && bar.isHidden)
        moved = bar.scrolled(by: -20, atTop: false, collapses: true)
        #expect(!moved && bar.isHidden)
        moved = bar.scrolled(by: -10, atTop: false, collapses: true)
        #expect(moved && !bar.isHidden)
        bar.scrolled(by: 100, atTop: false, collapses: true)
        moved = bar.scrolled(by: 1, atTop: true, collapses: true)
        #expect(moved && !bar.isHidden)
    }

    /// With Collapse Bottom Bar off the bar never leaves, however far the page scrolls; one
    /// scroll after the switch goes off brings back a bar that was away.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/505"))
    func withTheSwitchOffTheBarNeverCollapses() {
        var bar = MobileBarCollapse()
        for _ in 0..<50 {
            let moved = bar.scrolled(by: 80, atTop: false, collapses: false)
            #expect(!moved && !bar.isHidden)
        }
        bar.scrolled(by: 100, atTop: false, collapses: true)
        #expect(bar.isHidden)
        let moved = bar.scrolled(by: 5, atTop: false, collapses: false)
        #expect(moved && !bar.isHidden)
    }

    /// A link from a site that collapses the bar to one whose switch is off: the bar that was
    /// away comes back with the new page, before any scrolling. On a site that collapses it
    /// stays as it was.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/505"))
    func aSiteWithTheSwitchOffShowsTheBarItArrivesWithout() {
        var bar = MobileBarCollapse()
        bar.scrolled(by: 100, atTop: false, collapses: true)
        var moved = bar.pageChanged(collapses: true)
        #expect(!moved && bar.isHidden)
        moved = bar.pageChanged(collapses: false)
        #expect(moved && !bar.isHidden)
        moved = bar.pageChanged(collapses: false)
        #expect(!moved)
    }

    /// A tap under the page brings the bar back and starts the count again.
    @Test func revealBringsTheBarBack() {
        var bar = MobileBarCollapse()
        var moved = bar.reveal()
        #expect(!moved)
        bar.scrolled(by: 100, atTop: false, collapses: true)
        moved = bar.reveal()
        #expect(moved && !bar.isHidden)
        moved = bar.scrolled(by: 20, atTop: false, collapses: true)
        #expect(!moved && !bar.isHidden)
    }
}
