import CoreGraphics
import CraCore
import Foundation
import Testing

/// The swipe across the page, as measured on Arc Search's recordings (430 × 932 pt, its bar's top at 856).
struct MobilePageSwipeTests {
    private let width: CGFloat = 430, height: CGFloat = 932, band: CGFloat = 59, barTop: CGFloat = 856

    @Test func eachWayLeadsSomewhereShowsWhatItLeadsTo() {
        #expect(MobilePageSwipe.reveal(for: .back) == .back)
        #expect(MobilePageSwipe.reveal(for: .forward) == .forward)
        #expect(MobilePageSwipe.reveal(for: .archiveTab) == .closingTab)
        #expect(MobilePageSwipe.reveal(for: .reopenTab) == .reopeningTab)
        #expect(MobilePageSwipe.reveal(for: .none) == nil)
        // The page further on is the one on top: it leaves to the right going Back, comes in from the right going
        // Forward.
        #expect(!MobilePageSwipe.arrivesOnTop(.back))
        #expect(!MobilePageSwipe.arrivesOnTop(.closingTab))
        #expect(MobilePageSwipe.arrivesOnTop(.forward))
        #expect(MobilePageSwipe.arrivesOnTop(.reopeningTab))
    }

    /// Back: the page follows the finger right; Forward: the next page comes in from the right edge with it. Neither
    /// goes past its ends.
    @Test func theTopPagesEdgeFollowsTheFinger() {
        #expect(MobilePageSwipe.topEdge(translation: 120, width: width, reveal: .back) == 120)
        #expect(MobilePageSwipe.topEdge(translation: -30, width: width, reveal: .back) == 0)
        #expect(MobilePageSwipe.topEdge(translation: 900, width: width, reveal: .back) == width)
        #expect(MobilePageSwipe.topEdge(translation: -120, width: width, reveal: .forward) == 310)
        #expect(MobilePageSwipe.topEdge(translation: 40, width: width, reveal: .forward) == width)
        #expect(MobilePageSwipe.topEdge(translation: -900, width: width, reveal: .forward) == 0)
    }

    /// Arc Search's page underneath sat at -(430 - x) / 3 within 2 pt: -124 with the page at 53, -108 at 101.
    @Test func thePageUnderneathMovesAtAThirdOfTheSpeed() {
        #expect(abs(MobilePageSwipe.underOffset(edge: 53, width: width) - -125.7) < 0.1)
        #expect(abs(MobilePageSwipe.underOffset(edge: 101, width: width) - -109.7) < 0.1)
        #expect(abs(MobilePageSwipe.underOffset(edge: 0, width: width) - -143.3) < 0.1)
        #expect(MobilePageSwipe.underOffset(edge: width, width: width) == 0)
    }

    /// The shadow is darkest at the page's edge and gone 20 pt out, as Arc Search's page underneath read.
    @Test func theShadowFadesOutFromThePagesEdge() {
        let opacities = MobilePageSwipe.shadow.map(\.opacity)
        #expect(opacities.first == 0.25)
        #expect(opacities.last == 0)
        #expect(zip(opacities, opacities.dropFirst()).allSatisfy { $0 > $1 })
        #expect(MobilePageSwipe.shadowWidth == 20)
    }

    /// Let go, the spring starts at the finger's speed as a share of the way still to go, never backwards.
    @Test func theSpringStartsAtTheFingersSpeed() {
        #expect(MobilePageSwipe.initialVelocity(velocity: 3000, from: 130, to: 430) == 10)
        #expect(MobilePageSwipe.initialVelocity(velocity: -1500, from: 280, to: 0) == CGFloat(1500.0 / 280))
        #expect(MobilePageSwipe.initialVelocity(velocity: -800, from: 130, to: 430) == 0)
        #expect(MobilePageSwipe.initialVelocity(velocity: 900_000, from: 130, to: 430) == 40)
        #expect(MobilePageSwipe.initialVelocity(velocity: 900, from: 430, to: 430) == 0)
        // Arc Search's top page closed about 30 % of its way each frame and was home in 0.23 s.
        #expect(MobilePageSwipe.settle.remaining(after: 0.23) < 0.01)
        #expect(MobilePageSwipe.settle.dampingRatio == 1)
    }

    /// Arc Search's cards: 390 × 777 at (20, 59), from a page whose safe area starts at 59 and whose bar starts at 856:
    /// their tops on the safe area's.
    @Test func bothPagesShrinkIntoArcSearchsCards() {
        let card = MobilePageSwipe.cardFrame(width: width, band: band, barTop: barTop)
        #expect(abs(card.minX - 20) < 0.01)
        #expect(abs(card.width - 390) < 0.01)
        #expect(abs(card.height - 777) < 0.01)
        #expect(card.minY == band)
        #expect(abs(card.maxY - (barTop - 20)) < 0.01)
        #expect(abs(MobilePageSwipe.cardScale(width: width) - 0.907) < 0.001)
    }

    /// The cards' own clock, not the finger's travel: Arc Search's measured .09, .33, .59, .77, .89 at frames 1, 3, 5,
    /// 7, 9 after the swipe started, and .98 by frame 12.
    @Test func theCardsComeOnTheirOwnClock() {
        let measured: [Int: CGFloat] = [1: 0.09, 3: 0.33, 5: 0.59, 7: 0.77, 9: 0.89]
        var cards = MobilePageSwipe.Cards()
        #expect(cards.step(out: false, dt: 1) == 0, "held, they stay in")
        for frame in 1...300 {
            let progress = cards.step(out: true, dt: 1.0 / 60)
            if let arc = measured[frame] { #expect(abs(progress - arc) < 0.04, "frame \(frame)") }
            if frame == 13 { #expect(progress > 0.95) }
        }
        #expect(cards.progress == 1)
    }

    /// The tab's card comes out with a slight overshoot and settles on its place; going back in it doesn't overshoot
    /// into the button, and the page beside it never overshoots.
    @Test func theTabsCardOvershootsALittleOnTheWayOut() {
        var tab = MobilePageSwipe.Cards.tab(for: .closingTab), page = MobilePageSwipe.Cards.page
        var furthest: CGFloat = 0, pageFurthest: CGFloat = 0
        for _ in 0..<120 {
            furthest = max(furthest, tab.step(out: true, dt: 1.0 / 120))
            pageFurthest = max(pageFurthest, page.step(out: true, dt: 1.0 / 120))
        }
        #expect(furthest > 1.002 && furthest < 1.015, "a slight overshoot: \(furthest)")
        #expect(pageFurthest == 1)
        #expect(tab.progress == 1, "settled on its place")
        var lowest: CGFloat = 1
        for _ in 0..<240 { lowest = min(lowest, tab.step(out: false, dt: 1.0 / 120)) }
        #expect(lowest == 0, "back into the button without going past it")
    }

    /// The spring stepped a frame at a time lands where the whole step would, and an under-damped one overshoots as
    /// its damping says.
    @Test func aSpringSteppedFrameByFrameIsTheSpring() {
        for spring in [MobilePageSwipe.cardSpring, MobilePageSwipe.tabCardOut] {
            let whole = spring.step(offset: -1, velocity: 0, after: 0.2)
            var state = (offset: -1.0, velocity: 0.0)
            for _ in 0..<24 { state = spring.step(offset: state.offset, velocity: state.velocity, after: 0.2 / 24) }
            #expect(abs(state.offset - whole.offset) < 1e-9 && abs(state.velocity - whole.velocity) < 1e-9)
        }
        #expect(abs(MobilePageSwipe.cardSpring.step(offset: 1, velocity: 0, after: 0.1).offset
            - MobilePageSwipe.cardSpring.remaining(after: 0.1)) < 1e-12)
        let spring = MobilePageSwipe.tabCardOut
        var state = (offset: -1.0, velocity: 0.0), peak = -1.0
        for _ in 0..<600 {
            state = spring.step(offset: state.offset, velocity: state.velocity, after: 1.0 / 600)
            peak = max(peak, state.offset)
        }
        #expect(abs(peak - spring.overshoot) < 0.001)
    }

    /// Held again part of the way out, the cards turn and go back in on the same spring, and out again when the
    /// magnet lets go once more: a finger going back and forth takes them out and in.
    @Test func theCardsGoBackInWhenThePageIsHeldAgain() {
        var cards = MobilePageSwipe.Cards()
        for _ in 0..<6 { _ = cards.step(out: true, dt: 1.0 / 60) }
        let out = cards.progress
        #expect(out > 0.4 && out < 0.9)
        // Still on its way out for a moment as it turns, then only ever back.
        var last = cards.step(out: false, dt: 1.0 / 60)
        #expect(last < 1)
        var turned = false
        for _ in 0..<120 {
            let progress = cards.step(out: false, dt: 1.0 / 60)
            if progress < last { turned = true }
            if turned { #expect(progress <= last + 0.0001) }
            last = progress
        }
        #expect(cards.progress == 0, "back to the page")
        for _ in 0..<120 { _ = cards.step(out: true, dt: 1.0 / 60) }
        #expect(cards.progress == 1, "and out again")
    }

    /// Held, the page is the whole screen sliding with the finger, rounded as the display is; as the cards come out it
    /// shrinks into a card above the bar, its status bar strip squashed to nothing while the page under it keeps its
    /// height, cut down to the bar.
    @Test func thePageFollowsTheFingerIntoItsCard() {
        func place(_ progress: CGFloat, _ translation: CGFloat) -> MobilePageSwipe.LeavingPage {
            MobilePageSwipe.leavingPage(progress: progress, translation: translation, width: width, height: height,
                                        band: band, barTop: barTop, displayCorner: 55)
        }
        let start = place(0, 40)
        #expect(start.center == CGPoint(x: 255, y: 466))
        #expect(start.size == CGSize(width: width, height: height))
        #expect(start.scale == 1)
        #expect(start.cornerRadius == 55)
        #expect(start.band == band)

        let done = place(1, 100)
        let card = MobilePageSwipe.cardFrame(width: width, band: band, barTop: barTop)
        let scale = MobilePageSwipe.cardScale(width: width)
        #expect(done.center.x == 315)
        #expect(done.band == 0, "the strip squashed to nothing")
        #expect(abs(done.scale - scale) < 0.0001)
        #expect(abs(done.size.height * done.scale - card.height) < 0.01, "the page under it, shrunk, cut off at the card's bottom")
        #expect(abs(done.center.y - done.size.height * done.scale / 2 - band) < 0.01, "its top on the safe area's")
        #expect(abs(done.center.y + done.size.height * done.scale / 2 - card.maxY) < 0.01, "its bottom on the card's")
        #expect(done.cornerRadius == MobilePageSwipe.cardCornerRadius)

        // Half way, the strip half squashed and the page under it half cut down.
        let half = place(0.5, 0)
        #expect(half.band == band / 2)
        #expect(abs(half.size.height - (band / 2 + (height - band + card.height / scale) / 2)) < 0.01)
        #expect(half.cornerRadius == (55 + MobilePageSwipe.cardCornerRadius) / 2)
    }

    /// The tab before it lifts off the button's front card, leaning as it does there, flies up first and out to the
    /// left after, and ends a card's width and 20 pt to the left of the page's card, straight.
    @Test func theTabBeforeItComesOutOfTheTabButton() {
        let button = CGRect(x: 32, y: 869, width: 26.5, height: 30)
        let tilt: CGFloat = 8 * .pi / 180
        func card(_ progress: CGFloat, page: CGFloat = 215) -> MobilePageSwipe.Card {
            MobilePageSwipe.arrivingCard(progress: progress, from: button, tilt: tilt, buttonCorner: 5,
                                         leavingCenterX: page, width: width, band: band, barTop: barTop)
        }
        let lifted = card(0)
        #expect(lifted.center == CGPoint(x: button.midX, y: button.midY))
        #expect(lifted.size == button.size)
        #expect(lifted.angle == tilt)
        #expect(lifted.cornerRadius == 5)
        #expect(lifted.strip == 1, "as the button shows it, strip and all")

        let out = card(1, page: 315)
        let place = MobilePageSwipe.cardFrame(width: width, band: band, barTop: barTop)
        #expect(abs(out.center.x - (315 - 410)) < 0.01, "a card's width and 20 pt to the left of the page's card")
        #expect(abs(out.center.y - place.midY) < 0.01)
        #expect(abs(out.size.width - place.width) < 0.01 && abs(out.size.height - place.height) < 0.01)
        #expect(out.angle == 0)
        #expect(out.cornerRadius == MobilePageSwipe.cardCornerRadius)
        #expect(out.strip == 0, "its strip squashed away, as the page's beside it")
        // Overshooting, it carries on past its place.
        let past = card(1.03)
        #expect(past.center.x < card(1).center.x && past.size.width > place.width)
        #expect(past.angle == 0 && past.strip == 0)
        // Over the bar while it is there, from behind it once it has mostly slid away.
        #expect(MobilePageSwipe.tabCardOverBar(barCollapse: 0))
        #expect(MobilePageSwipe.tabCardOverBar(barCollapse: 0.4))
        #expect(!MobilePageSwipe.tabCardOverBar(barCollapse: 0.6))
        #expect(!MobilePageSwipe.tabCardOverBar(barCollapse: 1))
        // From behind it, out of sight while still where the button was, and quickly in view as it leaves.
        #expect(MobilePageSwipe.tabCardAlpha(progress: 0, overBar: false) == 0)
        #expect(abs(MobilePageSwipe.tabCardAlpha(progress: 0.06, overBar: false) - 0.5) < 0.0001)
        #expect(MobilePageSwipe.tabCardAlpha(progress: 0.12, overBar: false) == 1)
        #expect(MobilePageSwipe.tabCardAlpha(progress: 1.03, overBar: false) == 1)
        #expect(MobilePageSwipe.tabCardAlpha(progress: 0, overBar: true) == 1)
        #expect(abs(out.center.y - out.size.height / 2 - band) < 0.01, "its top level with the page's card's")

        // Half way it has risen half the way but gone only a quarter of the way out, bowed out to the left besides: up
        // first in an arc, then out.
        let half = card(0.5)
        #expect(abs(half.center.y - (button.midY + (place.midY - button.midY) / 2)) < 0.01)
        #expect(abs(half.center.x - (button.midX + ((215 - 410) - button.midX) / 4 - MobilePageSwipe.tabCardArc)) < 0.01)
        #expect(abs(half.angle - tilt / 2) < 0.0001)
    }

    /// The closed tab comes back beside the page, to its right: the page's own size all the way, 20 pt from it, its
    /// strip squashing as the page's does, and with nothing of the tab button's lean, arc or overshoot.
    @Test func theClosedTabComesBackBesideThePageAtItsSize() {
        #expect(MobilePageSwipe.showsCards(.closingTab) && MobilePageSwipe.showsCards(.reopeningTab))
        #expect(!MobilePageSwipe.showsCards(.back) && !MobilePageSwipe.showsCards(.forward))
        for (progress, translation) in [(CGFloat(0), CGFloat(-40)), (0.5, -120), (1, -200)] {
            let page = MobilePageSwipe.leavingPage(progress: progress, translation: translation, width: width, height: height,
                                                   band: band, barTop: barTop, displayCorner: 55)
            let card = MobilePageSwipe.reopeningCard(beside: page, progress: progress)
            let pageWidth = page.size.width * page.scale
            #expect(abs(card.size.width - pageWidth) < 0.01 && abs(card.size.height - page.size.height * page.scale) < 0.01)
            #expect(abs((card.center.x - card.size.width / 2) - (page.center.x + pageWidth / 2) - 20) < 0.01, "20 pt to its right")
            #expect(card.center.y == page.center.y)
            #expect(card.angle == 0 && card.cornerRadius == page.cornerRadius && card.strip == 1 - progress)
        }
        // On the page's spring, without the tab button's overshoot.
        var cards = MobilePageSwipe.Cards.tab(for: .reopeningTab), furthest: CGFloat = 0
        for _ in 0..<120 { furthest = max(furthest, cards.step(out: true, dt: 1.0 / 120)) }
        #expect(furthest == 1)
    }

    /// Let go, the page's card leaves off the right edge, whole; bringing the closed tab back, off the left.
    @Test func thePagesCardLeavesOffTheRightEdge() {
        let gone = MobilePageSwipe.leavingCardGoneX(width: width)
        #expect(abs(gone - (430 + 195)) < 0.01)
        #expect(abs(MobilePageSwipe.leavingCardGoneX(width: width, reveal: .reopeningTab) + 195) < 0.01)
        #expect(MobilePageSwipe.cardLeave.remaining(after: 0.3) < 0.01)
        #expect(MobilePageSwipe.cardArrive.remaining(after: 0.26) < 0.01)
    }

    /// The arriving page's picture comes off once the pages have settled and the page has had time to show its paint;
    /// never before they settle, and at the longest hold whatever the page is doing.
    @Test func thePictureComesOffOnceThePageHasDrawn() {
        #expect(!MobilePageSwipe.liftsPicture(settled: false, sinceNavigated: 5, sinceDrawn: 5))
        #expect(!MobilePageSwipe.liftsPicture(settled: true, sinceNavigated: 0.3, sinceDrawn: nil))
        #expect(!MobilePageSwipe.liftsPicture(settled: true, sinceNavigated: 0.3, sinceDrawn: 0.05))
        #expect(MobilePageSwipe.liftsPicture(settled: true, sinceNavigated: 0.3, sinceDrawn: 0.1))
        #expect(MobilePageSwipe.liftsPicture(settled: true, sinceNavigated: 1.5, sinceDrawn: nil))
    }

    /// Arc Search's magnet going Back: the page holds back at 0.28 of the finger's way, lets go once (and only once)
    /// when it has come 21 pt, the finger 75 pt in, catches up within a few frames, and follows the finger from there.
    @Test func theMagnetHoldsThePageThenLetsGo() {
        var magnet = MobilePageSwipe.magnet(for: .back)
        #expect(abs(magnet.letGoFinger - 75) < 0.01)
        let frame = 1.0 / 60
        var lettings = 0
        // A finger moving 3 pt a frame.
        var finger: CGFloat = 0
        var page: CGFloat = 0
        while finger < 72 {
            finger += 3
            let step = magnet.step(distance: finger, dt: frame)
            page = step.page
            if step.letGoNow { lettings += 1 }
        }
        #expect(!magnet.letGo)
        #expect(abs(page - finger * 0.28) < 0.01, "held at 0.28")
        finger += 3
        let snap = magnet.step(distance: finger, dt: frame)
        #expect(snap.letGoNow)
        #expect(magnet.letGo)
        lettings += 1
        // Catching up: most of the 54 pt it was behind made up within four frames, with the finger in a quarter of a
        // second.
        var frames = 0
        while frames < 15 {
            finger += 3
            let step = magnet.step(distance: finger, dt: frame)
            page = step.page
            if step.letGoNow { lettings += 1 }
            frames += 1
            if frames == 3 { #expect(finger - page < 25, "most of the way made up in four frames") }
        }
        #expect(abs(finger - page) < 1, "with the finger after 16 frames")
        #expect(lettings == 1, "one tick")
    }

    /// Closing a tab, the magnet holds much harder, as Arc Search's with the finger shown: still for the finger's first
    /// 16 pt, then an eighth of its travel, letting go with the finger 185 pt in, and catching up to 30 pt behind it.
    @Test func closingATabHoldsHarder() {
        let closing = MobilePageSwipe.magnet(for: .closingTab)
        let back = MobilePageSwipe.magnet(for: .back)
        #expect(closing.held(16) == 0)
        #expect(abs(closing.held(100.6) - 10.49) < 0.01, "Arc Search's page was at 10.1 with the finger 99 pt in")
        #expect(abs(closing.letGoFinger - 185.4) < 0.1)
        #expect(closing.letGoAt == back.letGoAt)
        #expect(MobilePageSwipe.magnet(for: .reopeningTab) == closing)
        #expect(MobilePageSwipe.magnet(for: .forward) == back)
        var magnet = closing
        #expect(!magnet.step(distance: 180, dt: 1).letGoNow)
        #expect(magnet.step(distance: 190, dt: 1 / 60).letGoNow)
        var page: CGFloat = 0
        for _ in 0..<30 { page = magnet.step(distance: 200, dt: 1 / 60).page }
        #expect(abs(page - 170) < 1, "settled 30 pt behind the finger")
    }

    /// Arc Search's quick swipes on a tab's first page weren't held: the page was 17.5 pt along four frames in, where
    /// held it would have been at most 0.124 of the finger's way. The cards come out at once (`holds` is false), but
    /// letting go still only goes once the finger is past where a slow swipe lets go, with one tick there. Turned back,
    /// it is held again.
    @Test func aQuickFingerClosingATabIsNotHeld() {
        var magnet = MobilePageSwipe.magnet(for: .closingTab)
        #expect(magnet.quickSpeed == MobilePageSwipe.quickSpeed)
        // Within the dead zone, speed alone takes nothing off.
        _ = magnet.step(distance: 10, dt: 1 / 60, speed: 2000)
        #expect(magnet.holds)
        var finger: CGFloat = 10
        var page: CGFloat = 0
        var ticks = 0
        // A finger at 1200 pt a second, 20 pt a frame, out to 100 pt, then still.
        for frame in 1...40 {
            if finger < 100 { finger += 20 }
            let step = magnet.step(distance: finger, dt: 1 / 60, speed: frame < 5 ? 1200 : 0)
            page = step.page
            if step.letGoNow { ticks += 1 }
            if frame == 4 { #expect(page > magnet.held(finger) + 5, "not held: \(page)") }
        }
        #expect(!magnet.holds)
        #expect(magnet.quick)
        #expect(!magnet.letGo, "short of where letting go goes")
        #expect(abs(page - (finger - 30)) < 1, "following the finger, 30 pt behind")
        #expect(ticks == 0)
        #expect(!MobilePageSwipe.commits(letGo: magnet.letGo, velocity: 0, distance: finger))
        // On past where the magnet lets go: the tick, and letting go goes.
        #expect(magnet.step(distance: 200, dt: 1 / 60).letGoNow)
        #expect(magnet.letGo)
        // Taken back under where the magnet takes hold again, a quick finger's page is held again too, so the cards go
        // back in; on past where it lets go, it lets go again, with its tick.
        for _ in 0..<40 { page = magnet.step(distance: 90, dt: 1 / 60).page }
        #expect(!magnet.letGo)
        #expect(magnet.holds)
        #expect(abs(page - magnet.held(90)) < 1)
        #expect(magnet.step(distance: 200, dt: 1 / 60).letGoNow)
        // A quick finger only slowing down, short of the furthest it came, stays not held.
        var slowing = MobilePageSwipe.magnet(for: .closingTab)
        _ = slowing.step(distance: 60, dt: 1 / 60, speed: 1200)
        _ = slowing.step(distance: 100, dt: 1 / 60, speed: 600)
        _ = slowing.step(distance: 90, dt: 1 / 60, speed: -100)
        #expect(!slowing.holds, "10 pt back is not turning back")
        _ = slowing.step(distance: 75, dt: 1 / 60, speed: -100)
        #expect(slowing.holds, "25 pt back is")

        // A slow finger, as the swipes with the finger shown, stays held; Back is held whatever the speed.
        var slow = MobilePageSwipe.magnet(for: .closingTab)
        #expect(abs(slow.step(distance: 100, dt: 1, speed: 90).page - slow.held(100)) < 0.01)
        #expect(slow.holds)
        var back = MobilePageSwipe.magnet(for: .back)
        _ = back.step(distance: 40, dt: 1 / 60, speed: 3000)
        #expect(back.holds)
    }

    /// Let go short of closing, the cards go back the way they came out, on the same spring: Arc Search's page card came
    /// back .20, .47, .69, .83 and .93 of the way at frames 2, 4, 6, 8 and 10 after letting go.
    @Test func theCardsGoBackTheWayTheyCameOut() {
        let measured: [(frame: Double, share: CGFloat)] = [(2, 0.20), (4, 0.47), (6, 0.69), (8, 0.83), (10, 0.93)]
        for (frame, share) in measured {
            #expect(abs(MobilePageSwipe.cardsReturn(after: frame / 60).share - share) < 0.04, "frame \(frame)")
        }
        #expect(MobilePageSwipe.cardsReturn(after: 0).share == 0)
        #expect(MobilePageSwipe.cardsReturn(after: -1).share == 0)
        #expect(!MobilePageSwipe.cardsReturn(after: 0.2).home)
        #expect(MobilePageSwipe.cardsReturn(after: 0.4).home)
        #expect(MobilePageSwipe.cardsReturn(after: 0.4).share > 0.997)
    }

    /// Taken back under 60 % of the way, the magnet holds the page again; past the let-go distance again, it lets go
    /// again. A finger dragged back past where it started holds the page at its place.
    @Test func theMagnetHoldsAgainWhenTakenBack() {
        var magnet = MobilePageSwipe.magnet(for: .back)
        _ = magnet.step(distance: 100, dt: 1)
        #expect(magnet.letGo)
        _ = magnet.step(distance: 50, dt: 1)
        #expect(magnet.letGo, "still let go at two thirds of the way")
        let held = magnet.step(distance: 40, dt: 1)
        #expect(!magnet.letGo)
        #expect(abs(held.page - 40 * 0.28) < 0.01, "a second on, held again")
        #expect(magnet.step(distance: 80, dt: 1).letGoNow)
        var back = MobilePageSwipe.magnet(for: .back)
        #expect(back.step(distance: -40, dt: 1 / 60).page == 0)
    }

    /// Let go once the magnet has let go, the swipe goes, unless flicked back; held, only a flick onwards takes it.
    @Test func lettingGoGoesOnlyOnceTheMagnetHasLetGo() {
        #expect(MobilePageSwipe.commits(letGo: true, velocity: 0, distance: 70))
        #expect(MobilePageSwipe.commits(letGo: true, velocity: -300, distance: 70))
        #expect(!MobilePageSwipe.commits(letGo: true, velocity: -900, distance: 70))
        #expect(!MobilePageSwipe.commits(letGo: false, velocity: 0, distance: 50))
        #expect(MobilePageSwipe.commits(letGo: false, velocity: 900, distance: 40))
        #expect(!MobilePageSwipe.commits(letGo: false, velocity: 900, distance: 20))
    }

    /// A finger held still before it lifts isn't flicking, whatever speed its last move had: dragged quickly 100 pt into
    /// closing a tab and held, letting go puts the tab back. A finger still moving as it lifts keeps its speed.
    @Test func aFingerHeldStillBeforeLiftingIsNotAFlick() {
        let held = MobilePageSwipe.liftVelocity(900, stillFor: 0.5)
        #expect(held == 0)
        #expect(!MobilePageSwipe.commits(letGo: false, velocity: held, distance: 100))
        #expect(MobilePageSwipe.liftVelocity(900, stillFor: 0.02) == 900)
        #expect(MobilePageSwipe.liftVelocity(-700, stillFor: 0.05) == -700)
        #expect(MobilePageSwipe.liftVelocity(-700, stillFor: MobilePageSwipe.stillBeforeLifting) == 0)
    }
}
