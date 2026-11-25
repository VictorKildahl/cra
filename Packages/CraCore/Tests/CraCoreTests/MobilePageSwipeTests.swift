import CoreGraphics
import CraCore
import Foundation
import Testing

/// The swipe across the page, as measured on Arc Search's recordings (430 × 932 pt, its bar's top at 856).
struct MobilePageSwipeTests {
    private let width: CGFloat = 430, barTop: CGFloat = 856

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

    /// Arc Search's cards: 390 × 777 at (20, 59), from a page whose bar starts at 856.
    @Test func bothPagesShrinkIntoArcSearchsCards() {
        let card = MobilePageSwipe.cardFrame(width: width, barTop: barTop)
        #expect(abs(card.minX - 20) < 0.01)
        #expect(abs(card.width - 390) < 0.01)
        #expect(abs(card.height - 776.4) < 0.1)
        #expect(abs(card.minY - 59.6) < 0.1)
        #expect(abs(card.maxY - (barTop - 20)) < 0.01)
        #expect(abs(MobilePageSwipe.cardScale(width: width) - 0.907) < 0.001)
    }

    /// The cards' own clock, not the finger's travel: Arc Search's measured .09, .33, .59, .77, .89 at frames 1, 3, 5,
    /// 7, 9 after the swipe started, and .98 by frame 12.
    @Test func theCardsComeOnTheirOwnClock() {
        let measured: [(frame: Double, progress: CGFloat)] = [(1, 0.09), (3, 0.33), (5, 0.59), (7, 0.77), (9, 0.89)]
        for (frame, progress) in measured {
            #expect(abs(MobilePageSwipe.cardProgress(after: frame / 60) - progress) < 0.04, "frame \(frame)")
        }
        #expect(MobilePageSwipe.cardProgress(after: 13.0 / 60) > 0.95)
        #expect(MobilePageSwipe.cardProgress(after: 0) == 0)
        #expect(MobilePageSwipe.cardProgress(after: -1) == 0)
        #expect(MobilePageSwipe.cardProgress(after: 5) == 1)
    }

    /// The page follows the finger one to one and shrinks about its centre into its card's place.
    @Test func thePageFollowsTheFingerIntoItsCard() {
        let start = MobilePageSwipe.leavingPage(progress: 0, translation: 0, width: width, barTop: barTop)
        #expect(start.center == CGPoint(x: 215, y: 428))
        #expect(start.scale == 1)
        let done = MobilePageSwipe.leavingPage(progress: 1, translation: 100, width: width, barTop: barTop)
        let card = MobilePageSwipe.cardFrame(width: width, barTop: barTop)
        #expect(done.center.x == 315)
        #expect(abs(done.center.y - card.midY) < 0.01)
        #expect(abs(done.scale - MobilePageSwipe.cardScale(width: width)) < 0.0001)
        // Arc Search's centre came down from 428 to 447.5.
        #expect(abs(done.center.y - 447.8) < 0.5)
    }

    /// The tab before it lifts off the button's front card, leaning as it does there, flies up first and out to the
    /// left after, and ends a card's width and 20 pt to the left of the page's card, straight.
    @Test func theTabBeforeItComesOutOfTheTabButton() {
        let button = CGRect(x: 32, y: 869, width: 26.5, height: 30)
        let tilt: CGFloat = 8 * .pi / 180
        func card(_ progress: CGFloat, page: CGFloat = 215) -> MobilePageSwipe.Card {
            MobilePageSwipe.arrivingCard(progress: progress, from: button, tilt: tilt, buttonCorner: 5,
                                         leavingCenterX: page, width: width, barTop: barTop)
        }
        let lifted = card(0)
        #expect(lifted.center == CGPoint(x: button.midX, y: button.midY))
        #expect(lifted.size == button.size)
        #expect(lifted.angle == tilt)
        #expect(lifted.cornerRadius == 5)

        let out = card(1, page: 315)
        let place = MobilePageSwipe.cardFrame(width: width, barTop: barTop)
        #expect(abs(out.center.x - (315 - 410)) < 0.01, "a card's width and 20 pt to the left of the page's card")
        #expect(abs(out.center.y - place.midY) < 0.01)
        #expect(abs(out.size.width - place.width) < 0.01 && abs(out.size.height - place.height) < 0.01)
        #expect(out.angle == 0)
        #expect(out.cornerRadius == MobilePageSwipe.cardCornerRadius)

        // Half way it has risen half the way but gone only a quarter of the way out: up first, then out.
        let half = card(0.5)
        #expect(abs(half.center.y - (button.midY + (place.midY - button.midY) / 2)) < 0.01)
        #expect(abs(half.center.x - (button.midX + ((215 - 410) - button.midX) / 4)) < 0.01)
        #expect(abs(half.angle - tilt / 2) < 0.0001)
    }

    /// Let go, the page's card leaves off the right edge, whole.
    @Test func thePagesCardLeavesOffTheRightEdge() {
        let gone = MobilePageSwipe.leavingCardGoneX(width: width)
        #expect(abs(gone - (430 + 195)) < 0.01)
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

    /// The page Back went to goes back where it was left, under the app's own inset at its top, within the document:
    /// at its top it sits a status bar down, as it was, not under the status bar where WebKit put it.
    @Test func thePageGoesBackWhereItWasLeft() {
        func offset(_ top: CGFloat, content: CGFloat = 3000) -> CGFloat {
            MobilePageSwipe.restoredOffset(scrollTop: top, insetTop: 59, insetBottom: 76, contentHeight: content, viewHeight: 932)
        }
        #expect(offset(0) == -59)
        #expect(offset(400) == 341)
        // No further than the document's end, with the bar's inset under it...
        #expect(offset(5000) == CGFloat(2144))
        // ...and a page shorter than the screen stays at its top.
        #expect(offset(300, content: 500) == -59)
        #expect(offset(-20) == -59)
    }
}
