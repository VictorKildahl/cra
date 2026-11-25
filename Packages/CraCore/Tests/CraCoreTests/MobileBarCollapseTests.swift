import CoreGraphics
import CraCore
import Testing

/// The bottom bar trails the finger that scrolls a page, and letting go picks the end the last
/// travel pointed at. Site Settings ▸ Collapse Bottom Bar decides per site whether it moves at
/// all.
struct MobileBarCollapseTests {
    /// The bar starts moving with the finger's first point and trails it at the drag's rate.
    @Test func theBarFollowsTheFingerFromItsFirstPoint() {
        var bar = MobileBarCollapse()
        var moved = bar.dragged(by: 1, collapses: true, scrolls: true)
        #expect(moved)
        #expect(bar.progress == 1 / MobileBarCollapse.fingerTravel)
        moved = bar.dragged(by: 20, collapses: true, scrolls: true)
        #expect(moved)
        #expect(bar.progress == 21 / MobileBarCollapse.fingerTravel)
        moved = bar.dragged(by: 0, collapses: true, scrolls: true)
        #expect(!moved)
    }

    /// The bar moves a little slower than the finger: a drag as long as the bar's own height
    /// leaves it part of the way, and closing it takes half again that much drag.
    @Test func theDragGoesFurtherThanTheBarMoves() {
        var bar = MobileBarCollapse()
        bar.dragged(by: MobileBarCollapse.travel, collapses: true, scrolls: true)
        #expect(bar.progress > 0 && bar.progress < 1, "the bar arrived before the finger")
        bar.dragged(by: MobileBarCollapse.fingerTravel - MobileBarCollapse.travel, collapses: true, scrolls: true)
        #expect(bar.isClosed)
    }

    /// A turn takes the bar back at once: the drag has no dead zone before it.
    @Test func aTurnTakesTheBarBackAtOnce() {
        var bar = MobileBarCollapse()
        bar.dragged(by: 20, collapses: true, scrolls: true)
        let place = bar.progress
        let moved = bar.dragged(by: -4, collapses: true, scrolls: true)
        #expect(moved)
        #expect(bar.progress == place - 4 / MobileBarCollapse.fingerTravel)
    }

    /// Letting go picks the end the last travel pointed at, however far the bar got.
    @Test func lettingGoPicksTheEndTheFingerTravelledTowards() {
        var bar = MobileBarCollapse()
        bar.dragged(by: 20, collapses: true, scrolls: true)
        #expect(bar.progress > 0 && bar.progress < 1)
        let target = bar.released()
        #expect(target == true)
        bar.settle(atClosed: true)
        #expect(bar.isClosed)

        bar = MobileBarCollapse()
        bar.dragged(by: 30, collapses: true, scrolls: true)
        bar.dragged(by: -10, collapses: true, scrolls: true)
        let open = bar.released()
        #expect(open == false)
        bar.settle(atClosed: false)
        #expect(bar.isOpen)
    }

    /// Letting go of a bar that is already at an end leaves it there.
    @Test func lettingGoAtAnEndChangesNothing() {
        var bar = MobileBarCollapse()
        bar.dragged(by: MobileBarCollapse.fingerTravel, collapses: true, scrolls: true)
        #expect(bar.isClosed)
        let target = bar.released()
        #expect(target == nil)

        bar = MobileBarCollapse()
        bar.dragged(by: -MobileBarCollapse.fingerTravel, collapses: true, scrolls: true)
        #expect(bar.isOpen)
        let open = bar.released()
        #expect(open == nil)
    }

    /// A page that fits the screen has nothing to scroll, so its bar cannot be put away; one
    /// that was away comes back.
    @Test func aPageThatFitsTheScreenKeepsItsBar() {
        var bar = MobileBarCollapse()
        var moved = bar.dragged(by: 80, collapses: true, scrolls: false)
        #expect(!moved && bar.isOpen)
        bar.settle(atClosed: true)
        moved = bar.dragged(by: 80, collapses: true, scrolls: false)
        #expect(moved && bar.isOpen, "a bar that was away comes back")
    }

    /// A page is scrollable only when it is taller than its screen, with room to spare.
    @Test func aPageOnlyScrollsWhenItIsTallerThanItsScreen() {
        #expect(!MobileBarCollapse.scrolls(contentHeight: 700, pageHeight: 700))
        #expect(!MobileBarCollapse.scrolls(contentHeight: 699, pageHeight: 700))
        #expect(MobileBarCollapse.scrolls(contentHeight: 701, pageHeight: 700))
    }

    /// A page whose content shrinks until it fits brings a bar that was away back; one that
    /// still scrolls leaves it where it is.
    @Test func aShrinkingPageBringsTheBarBack() {
        var bar = MobileBarCollapse()
        bar.dragged(by: 80, collapses: true, scrolls: true)
        bar.settle(atClosed: true)
        #expect(!bar.contentChanged(scrolls: true))
        #expect(bar.contentChanged(scrolls: false))
        bar.settle(atClosed: false)
        #expect(!bar.contentChanged(scrolls: false), "there is nothing to bring back")
    }

    /// The bar stops at its ends; dragging further points moves nothing.
    @Test func theBarStopsAtItsEnds() {
        var bar = MobileBarCollapse()
        bar.dragged(by: 500, collapses: true, scrolls: true)
        #expect(bar.progress == 1)
        bar.dragged(by: -500, collapses: true, scrolls: true)
        #expect(bar.progress == 0)
    }

    /// With Collapse Bottom Bar off the bar never leaves, however far the page scrolls; one
    /// drag after the switch goes off brings back a bar that was away.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/505"))
    func withTheSwitchOffTheBarNeverCollapses() {
        var bar = MobileBarCollapse()
        for _ in 0..<50 {
            let moved = bar.dragged(by: 80, collapses: false, scrolls: true)
            #expect(!moved && bar.isOpen)
        }
        bar.dragged(by: 80, collapses: true, scrolls: true)
        bar.settle(atClosed: true)
        #expect(bar.isClosed)
        let moved = bar.dragged(by: -4, collapses: false, scrolls: true)
        #expect(moved && bar.isOpen)
    }

    /// A link from a site that collapses the bar to one whose switch is off: the bar that was
    /// away comes back with the new page, before any scrolling. On a site that collapses it
    /// stays as it was.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/505"))
    func aSiteWithTheSwitchOffShowsTheBarItArrivesWithout() {
        var bar = MobileBarCollapse()
        bar.dragged(by: 80, collapses: true, scrolls: true)
        bar.settle(atClosed: true)
        var comesBack = bar.pageChanged(collapses: true)
        #expect(!comesBack && bar.isClosed)
        comesBack = bar.pageChanged(collapses: false)
        #expect(comesBack)
        bar.settle(atClosed: false)
        #expect(bar.isOpen)
        comesBack = bar.pageChanged(collapses: false)
        #expect(!comesBack)
    }

    /// A tap on the strip under the page, the tab row or another tab brings the bar back at
    /// once, and it starts from open again.
    @Test func revealBringsTheBarBack() {
        var bar = MobileBarCollapse()
        var moved = bar.reveal()
        #expect(!moved)
        bar.dragged(by: 80, collapses: true, scrolls: true)
        bar.settle(atClosed: true)
        moved = bar.reveal()
        #expect(moved && bar.isOpen)
        moved = bar.dragged(by: 1, collapses: true, scrolls: true)
        #expect(moved)
        #expect(!bar.isOpen)
    }
}
