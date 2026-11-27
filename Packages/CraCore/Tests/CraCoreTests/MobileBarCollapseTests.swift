import CoreGraphics
import CraCore
import Testing

/// The bottom bar moves with the finger that scrolls a page, and letting go picks the end the last
/// travel pointed at. Site Settings ▸ Collapse Bottom Bar decides per site whether it moves at
/// all.
struct MobileBarCollapseTests {
    /// The bar starts moving with the finger's first point.
    @Test func theBarFollowsTheFingerFromItsFirstPoint() {
        var bar = MobileBarCollapse()
        var moved = bar.dragged(by: 1, collapses: true, scrolls: true)
        #expect(moved)
        #expect(bar.progress == 1 / MobileBarCollapse.travel)
        moved = bar.dragged(by: 20, collapses: true, scrolls: true)
        #expect(moved)
        #expect(bar.progress == 21 / MobileBarCollapse.travel)
        moved = bar.dragged(by: 0, collapses: true, scrolls: true)
        #expect(!moved)
    }

    /// The bar moves exactly as far as the finger, both ways: a drag as long as the bar's own
    /// height takes it the whole way, and every point of drag is a point of the bar.
    @Test func theBarMovesAsFarAsTheFinger() {
        var bar = MobileBarCollapse()
        for drag in [1, 7.5, 13] as [CGFloat] {
            let before = bar.progress
            bar.dragged(by: drag, collapses: true, scrolls: true)
            #expect(abs((bar.progress - before) * MobileBarCollapse.travel - drag) < 0.001, "closing: \(drag) pt")
        }
        // A turn first crosses the dead zone; past it, every point back is a point of the bar.
        bar.dragged(by: -(MobileBarCollapse.deadZone + 10), collapses: true, scrolls: true)
        #expect(abs(bar.progress * MobileBarCollapse.travel - 11.5) < 0.001, "opening moves it as far back")
        bar.reveal()
        bar.dragged(by: MobileBarCollapse.travel - 0.5, collapses: true, scrolls: true)
        #expect(!bar.isClosed, "just short of the bar's height leaves it just short")
        bar.dragged(by: 0.5, collapses: true, scrolls: true)
        #expect(bar.isClosed, "the bar's own height of drag closes it")
    }

    /// Scrolling down hides the bar from the finger's first point; scrolling up brings it back
    /// only once the finger has gone the dead zone (20 points here), and then point for point.
    @Test func closingStartsAtOnceAndOpeningWaitsTheDeadZone() {
        var moved = false
        #expect(MobileBarCollapse.deadZone > 0, "the bar has a dead zone of its own")
        var bar = MobileBarCollapse(deadZone: 20)
        bar.touchBegan()
        moved = bar.dragged(by: 1, collapses: true, scrolls: true)
        #expect(moved, "closing starts at once")
        bar.settle(atClosed: true)

        bar.touchBegan()
        moved = bar.dragged(by: -19, collapses: true, scrolls: true)
        #expect(!moved, "inside the dead zone nothing moves")
        moved = bar.dragged(by: -1, collapses: true, scrolls: true)
        #expect(!moved, "its edge is still nothing")
        #expect(bar.isClosed)
        moved = bar.dragged(by: -4, collapses: true, scrolls: true)
        #expect(moved)
        #expect(abs((1 - bar.progress) * MobileBarCollapse.travel - 4) < 0.001, "past it, the bar follows the finger")
    }

    /// A turn in the middle of a drag waits the dead zone (20 points here) too, either way: a wobble back inside
    /// it moves nothing, and carrying on the way the bar was going moves it at once again.
    @Test func aTurnWaitsTheDeadZone() {
        var moved = false
        var bar = MobileBarCollapse(deadZone: 20)
        bar.touchBegan()
        bar.dragged(by: 30, collapses: true, scrolls: true)
        let place = bar.progress
        moved = bar.dragged(by: -15, collapses: true, scrolls: true)
        #expect(!moved, "a turn inside the dead zone")
        #expect(bar.progress == place)
        moved = bar.dragged(by: 2, collapses: true, scrolls: true)
        #expect(moved, "on the way it was going: at once")
        #expect(abs(bar.progress - (place + 2 / MobileBarCollapse.travel)) < 0.0001)
        let before = bar.progress
        moved = bar.dragged(by: -20, collapses: true, scrolls: true)
        #expect(!moved, "a fresh turn starts its dead zone again")
        bar.dragged(by: -5, collapses: true, scrolls: true)
        #expect(abs(bar.progress - (before - 5 / MobileBarCollapse.travel)) < 0.0001, "then the bar comes back")
        // And turning to close again waits as long.
        let opening = bar.progress
        moved = bar.dragged(by: 20, collapses: true, scrolls: true)
        #expect(!moved)
        bar.dragged(by: 3, collapses: true, scrolls: true)
        #expect(abs(bar.progress - (opening + 3 / MobileBarCollapse.travel)) < 0.0001)
    }

    /// A wobble inside the dead zone is not a turn: letting go still settles the way the bar was
    /// going.
    @Test func aWobbleDoesNotTurnTheRelease() {
        var bar = MobileBarCollapse()
        bar.touchBegan()
        bar.dragged(by: 20, collapses: true, scrolls: true)
        bar.dragged(by: -12, collapses: true, scrolls: true)
        #expect(bar.released() == true)
    }

    /// A new touch starts afresh: closing moves at once whichever way the last touch went, and
    /// opening waits the dead zone even if the last touch was opening.
    @Test func eachTouchStartsAfresh() {
        var moved = false
        var bar = MobileBarCollapse()
        bar.touchBegan()
        bar.dragged(by: 30, collapses: true, scrolls: true)
        bar.dragged(by: -25, collapses: true, scrolls: true)
        bar.touchBegan()
        let place = bar.progress
        moved = bar.dragged(by: 1, collapses: true, scrolls: true)
        #expect(moved, "closing at once")
        bar.touchBegan()
        moved = bar.dragged(by: -10, collapses: true, scrolls: true)
        #expect(!moved, "opening waits again")
        #expect(bar.progress == place + 1 / MobileBarCollapse.travel)
    }

    /// The dead zone is the bar's own setting: with none, a turn takes the bar back at once.
    @Test func theDeadZoneIsConfigurable() {
        var moved = false
        var bar = MobileBarCollapse(deadZone: 0)
        bar.touchBegan()
        bar.dragged(by: 20, collapses: true, scrolls: true)
        let place = bar.progress
        moved = bar.dragged(by: -4, collapses: true, scrolls: true)
        #expect(moved)
        #expect(abs(bar.progress - (place - 4 / MobileBarCollapse.travel)) < 0.0001)
        var wide = MobileBarCollapse(deadZone: 50)
        wide.touchBegan()
        wide.dragged(by: 30, collapses: true, scrolls: true)
        moved = wide.dragged(by: -49, collapses: true, scrolls: true)
        #expect(!moved)
    }

    /// A quick flick picks the end it points at even inside the dead zone: a 19 pt flick back up
    /// the page, which carries on scrolling, brings the bar back. A slow release inside the dead
    /// zone moves nothing, and a flick towards the end the bar is at changes nothing.
    @Test func aFlickPicksItsEndInsideTheDeadZone() {
        #expect(MobileBarCollapse.flickSpeed == 300)
        var bar = MobileBarCollapse(deadZone: 20)
        bar.settle(atClosed: true)
        bar.touchBegan()
        bar.dragged(by: -19, collapses: true, scrolls: true)
        #expect(bar.isClosed, "the drag stayed inside the dead zone")
        #expect(bar.flicked(velocity: -1200, collapses: true, scrolls: true) == false, "a quick flick up opens it")
        #expect(bar.flicked(velocity: -299, collapses: true, scrolls: true) == nil, "a slow release is not a flick")
        #expect(bar.flicked(velocity: 1200, collapses: true, scrolls: true) == nil, "it is already closed")

        bar.settle(atClosed: false)
        bar.touchBegan()
        #expect(bar.flicked(velocity: 800, collapses: true, scrolls: true) == true, "a quick flick down closes it")
        #expect(bar.flicked(velocity: -800, collapses: true, scrolls: true) == nil, "it is already open")
    }

    /// A flick mid-way, against the way the bar was going, wins: it is the finger's last word.
    @Test func aFlickBackTurnsTheBar() {
        var bar = MobileBarCollapse()
        bar.touchBegan()
        bar.dragged(by: 30, collapses: true, scrolls: true)
        bar.dragged(by: -10, collapses: true, scrolls: true)
        #expect(bar.released() == true, "a slow release keeps closing")
        #expect(bar.flicked(velocity: -600, collapses: true, scrolls: true) == false, "a flick back opens it")
    }

    /// A flick never moves a bar that stays: a site with Collapse Bottom Bar off, or a page with
    /// nothing to scroll. The speed it takes is the bar's own setting.
    @Test func aFlickRespectsABarThatStays() {
        let bar = MobileBarCollapse()
        #expect(bar.flicked(velocity: 2000, collapses: false, scrolls: true) == nil)
        #expect(bar.flicked(velocity: 2000, collapses: true, scrolls: false) == nil)
        let eager = MobileBarCollapse(flickSpeed: 100)
        #expect(eager.flicked(velocity: 150, collapses: true, scrolls: true) == true)
        #expect(MobileBarCollapse().flicked(velocity: 150, collapses: true, scrolls: true) == nil)
    }

    /// Letting go: a flick picks its own end, a touch that moved the bar settles the way it was
    /// going, one that rode the bar without moving it settles by its heading, and a touch that
    /// had nothing to do with the bar leaves it (and a settle already playing) alone.
    @Test func theEndOfATouchPicksWhereTheBarSettles() {
        var bar = MobileBarCollapse()
        bar.touchBegan()
        #expect(!bar.movedThisTouch)
        #expect(bar.ended(velocity: 0, collapses: true, scrolls: true, following: false) == nil,
                "a touch that never moved the bar leaves it")
        bar.dragged(by: 10, collapses: true, scrolls: true)
        #expect(bar.movedThisTouch)
        #expect(bar.ended(velocity: 0, collapses: true, scrolls: true, following: true) == true,
                "a moved bar settles the way it was going")
        #expect(bar.ended(velocity: -2000, collapses: true, scrolls: true, following: true) == false,
                "a flick wins")

        bar.settle(atClosed: true)
        bar.touchBegan()
        #expect(!bar.movedThisTouch, "each touch starts unmoved")
        #expect(bar.heading)
        #expect(bar.ended(velocity: 0, collapses: true, scrolls: true, following: true) == true,
                "a ride that never moved it settles by its heading, even at that end")
        #expect(bar.ended(velocity: 0, collapses: true, scrolls: true, following: false) == nil)
    }

    /// A drag on a site with the switch off that brings a hidden bar back counts as moving it.
    @Test func aRevealByDragCountsAsMovingTheBar() {
        var bar = MobileBarCollapse()
        bar.settle(atClosed: true)
        bar.touchBegan()
        bar.dragged(by: 5, collapses: false, scrolls: true)
        #expect(bar.isOpen && bar.movedThisTouch)
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
        bar.dragged(by: -(MobileBarCollapse.deadZone + 10), collapses: true, scrolls: true)
        let open = bar.released()
        #expect(open == false)
        bar.settle(atClosed: false)
        #expect(bar.isOpen)
    }

    /// Letting go of a bar that is already at an end leaves it there.
    @Test func lettingGoAtAnEndChangesNothing() {
        var bar = MobileBarCollapse()
        bar.dragged(by: MobileBarCollapse.travel, collapses: true, scrolls: true)
        #expect(bar.isClosed)
        let target = bar.released()
        #expect(target == nil)

        bar = MobileBarCollapse()
        bar.dragged(by: -MobileBarCollapse.travel, collapses: true, scrolls: true)
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

    /// A page is worth hiding the bar for only when it runs more than 100 points past its screen;
    /// one with only a little to scroll keeps its bar.
    @Test func aPageWithOnlyALittleToScrollKeepsTheBar() {
        let threshold = MobileBarCollapse.minimumScrollable
        #expect(!MobileBarCollapse.scrolls(contentHeight: 699, pageHeight: 700))
        #expect(!MobileBarCollapse.scrolls(contentHeight: 700, pageHeight: 700))
        #expect(!MobileBarCollapse.scrolls(contentHeight: 700 + threshold, pageHeight: 700))
        #expect(MobileBarCollapse.scrolls(contentHeight: 700 + threshold + 1, pageHeight: 700))
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

    /// A page the bar never leaves ends at the bar's top, so a screen-sized app (Excel for the
    /// web's sheet tabs, sized with `100vh`) has its bottom above the bar rather than under it. A
    /// page that scrolls, one still loading, and any page while the bar is away or moving run on
    /// under it.
    @Test func aPageTheBarNeverLeavesEndsAtTheBarsTop() {
        var bar = MobileBarCollapse()
        #expect(!bar.pageRunsUnder(collapses: true, scrolls: false, loaded: true), "a loaded page with nothing to scroll")
        #expect(!bar.pageRunsUnder(collapses: false, scrolls: true, loaded: true), "Collapse Bottom Bar off")
        #expect(!bar.pageRunsUnder(collapses: false, scrolls: false, loaded: false), "Collapse Bottom Bar off, still loading")
        #expect(bar.pageRunsUnder(collapses: true, scrolls: true, loaded: true), "a page that scrolls")
        #expect(bar.pageRunsUnder(collapses: true, scrolls: false, loaded: false), "a page still loading")
        bar.dragged(by: 10, collapses: true, scrolls: true)
        #expect(!bar.isOpen)
        #expect(bar.pageRunsUnder(collapses: true, scrolls: false, loaded: true), "the bar on its way")
        bar.settle(atClosed: true)
        #expect(bar.pageRunsUnder(collapses: true, scrolls: false, loaded: true), "the bar away")
        bar.reveal()
        #expect(!bar.pageRunsUnder(collapses: true, scrolls: false, loaded: true), "back under an open bar")
    }

    /// The page's covered bottom is what lies between the bar's top and the safe area's edge,
    /// following the bar from its whole height open to nothing closed, so a sticky bottom stays
    /// on the bar's top all the way; it never leaves the range WebKit is given for `svh`/`lvh`.
    @Test func thePagesCoveredBottomFollowsTheBar() {
        let size = CGSize(width: 402, height: 874)
        let safe: CGFloat = 34
        let edge = size.height - safe
        let range = MobileBarCollapse.viewportInsets
        #expect(range.least == 0 && range.most == MobileBottomBar.height)
        var bar = MobileBarCollapse()
        var last = range.most
        for _ in 0..<50 {
            let top = MobileBottomBar.top(in: size, safeBottom: safe, progress: bar.progress, scale: 3)
            let covered = MobileBottomBar.covered(in: size, safeBottom: safe, progress: bar.progress, scale: 3)
            #expect(covered == edge - top, "the page's visible bottom is the bar's top")
            #expect(covered <= last && covered >= range.least && covered <= range.most)
            last = covered
            bar.dragged(by: 1, collapses: true, scrolls: true)
        }
        #expect(bar.isClosed && MobileBottomBar.covered(in: size, safeBottom: safe, progress: bar.progress, scale: 3) == 0)
        #expect(MobileBottomBar.covered(in: size, safeBottom: safe, progress: 0.5, scale: 3) == MobileBottomBar.height / 2)
    }

    /// The bar's top, and so the page's bottom, sits on the display's pixel grid as the bar
    /// moves: WebKit is not asked to move the page's viewport by a fraction of a pixel, and a
    /// step too small to show moves nothing.
    @Test func theBarsTopKeepsToThePixelGrid() {
        let size = CGSize(width: 402, height: 874)
        for scale in [2, 3] as [CGFloat] {
            for step in 0...100 {
                let progress = CGFloat(step) / 100
                let top = MobileBottomBar.top(in: size, safeBottom: 34, progress: progress, scale: scale)
                #expect(abs((top * scale).rounded() - top * scale) < 0.0001, "\(top) at @\(scale)x")
                let exact = MobileBottomBar.top(in: size, safeBottom: 34, progress: progress)
                #expect(abs(top - exact) <= 0.5 / scale + 0.0001, "within half a pixel of the bar's place")
            }
        }
        // A step of a tenth of a pixel leaves the bar where it was.
        let here = MobileBottomBar.top(in: size, safeBottom: 34, progress: 0.5, scale: 3)
        let nudged = MobileBottomBar.top(in: size, safeBottom: 34, progress: 0.5 + 0.1 / 3 / MobileBottomBar.height, scale: 3)
        #expect(here == nudged)
    }
}
