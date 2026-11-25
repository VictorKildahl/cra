import CoreGraphics
import Foundation

/// How a swipe across the page looks while it goes and once it is let go (`MobileSwipe.navigation` decides where it
/// goes). Measured frame by frame on Arc Search screen recordings from an iPhone (430 × 932 pt, Nov 2026): Back slides
/// the page off the one it goes back to, and Back on a tab's first page shrinks the page into a card while the tab
/// before it comes out of the tab button beside it.
public enum MobilePageSwipe {
    /// What shows beside the page during the swipe.
    public enum Reveal: Equatable, Sendable {
        /// Back in the tab's history: the page it goes back to, underneath.
        case back
        /// Forward in the tab's history: the next page, coming in over this one from the right.
        case forward
        /// Back on the tab's first page: the tab shown once this one closes, out of the tab button.
        case closingTab
        /// Forward right after that: the tab that closed, coming back in from the right.
        case reopeningTab
    }

    public static func reveal(for navigation: MobileSwipe.Navigation) -> Reveal? {
        switch navigation {
        case .back: return .back
        case .forward: return .forward
        case .archiveTab: return .closingTab
        case .reopenTab: return .reopeningTab
        case .none: return nil
        }
    }

    /// Whether the page that arrives comes in over the one on screen (Forward), or the one on screen leaves over it
    /// (Back): the page further on is always the one on top. Arc Search's Forward was not recorded; it mirrors Back
    /// as UIKit's navigation does.
    public static func arrivesOnTop(_ reveal: Reveal) -> Bool {
        reveal == .forward || reveal == .reopeningTab
    }

    // MARK: Back and Forward

    /// The page underneath moves at a third of the top page's speed, from a third of the screen off to the left:
    /// Arc Search's under page sat at -(430 - x) / 3 within 2 pt all the way. It is not scaled, dimmed or rounded.
    public static let parallax: CGFloat = 1.0 / 3

    /// How far across the page on top has come: the left edge of whichever page is on top, 0 (it covers the screen)
    /// to `width` (gone). For Back the page on screen is on top and follows the finger right; for Forward the page
    /// that arrives is on top and comes in from the right edge with the finger.
    public static func topEdge(translation: CGFloat, width: CGFloat, reveal: Reveal) -> CGFloat {
        let edge = arrivesOnTop(reveal) ? width + min(0, translation) : max(0, translation)
        return min(width, max(0, edge))
    }

    /// Where the page underneath sits while the top page's left edge is at `edge`.
    public static func underOffset(edge: CGFloat, width: CGFloat) -> CGFloat {
        -parallax * (width - edge)
    }

    /// The shadow the top page casts on the one underneath, along its left edge: how dark it is (black's opacity)
    /// at each distance from the edge, in points. Arc Search's page underneath read 0.76 of its brightness 1 pt from
    /// the edge, 0.85 at 4, 0.91 at 8, 0.95 at 12 and 0.98 at 16.
    public static let shadow: [(distance: CGFloat, opacity: CGFloat)] = [(0, 0.25), (4, 0.15), (8, 0.09), (12, 0.05), (16, 0.02), (20, 0)]
    public static var shadowWidth: CGFloat { shadow.last?.distance ?? 0 }

    /// Let go, both pages settle on one critically damped spring from the finger's speed: Arc Search's top page
    /// closed 30 % of its remaining way every frame and was home in 0.23 s, without overshooting.
    public static let settle = MobileMotion.Spring(response: 0.21, dampingRatio: 1)

    /// The spring's starting speed as UIKit takes it, a share of the distance still to go a second: the finger's
    /// `velocity` (points a second) on the way from `from` to `to`. Never backwards, and never a jolt.
    public static func initialVelocity(velocity: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let distance = to - from
        guard abs(distance) > 1 else { return 0 }
        return min(40, max(0, velocity / distance))
    }

    // MARK: Back on the tab's first page

    /// As the swipe starts, the page shrinks into a card and the tab before it comes out of the tab button into one
    /// the same size beside it: one timed critically damped spring from the moment the swipe is recognised, not the
    /// finger's travel. Arc Search's was 99 % there 13 frames in (0.26 s response, fitted within 0.01).
    public static let cardSpring = MobileMotion.Spring(response: 0.26, dampingRatio: 1)

    /// How far into cards both pages are `time` seconds after the swipe started, 0 to 1.
    public static func cardProgress(after time: Double) -> CGFloat {
        guard time > 0 else { return 0 }
        return min(1, max(0, CGFloat(1 - cardSpring.remaining(after: time))))
    }

    /// The cards: `cardInset` from the screen's sides, their bottom `cardInset` above the bar, the page above the bar
    /// scaled to fit, rounded `cardCornerRadius`, and `cardGap` apart. Arc Search's were 390 × 777 at y 59 on a
    /// 430 pt screen with its bar's top at 856.
    public static let cardInset: CGFloat = 20
    public static let cardCornerRadius: CGFloat = 20
    public static let cardGap: CGFloat = 20

    /// How much the page is shrunk in its card.
    public static func cardScale(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return max(0, width - 2 * cardInset) / width
    }

    /// The page's card in its place, with the page above the bar (`barTop` high) in it.
    public static func cardFrame(width: CGFloat, barTop: CGFloat) -> CGRect {
        let scale = cardScale(width: width)
        let height = barTop * scale
        return CGRect(x: cardInset, y: barTop - cardInset - height, width: width * scale, height: height)
    }

    /// Where the page on screen is, `progress` of the way into its card, the finger `translation` across: it follows
    /// the finger one to one, shrinking about its centre, and comes down to the card's place.
    public static func leavingPage(progress: CGFloat, translation: CGFloat, width: CGFloat, barTop: CGFloat)
        -> (center: CGPoint, scale: CGFloat) {
        let p = min(1, max(0, progress))
        let card = cardFrame(width: width, barTop: barTop)
        let scale = 1 + (cardScale(width: width) - 1) * p
        return (CGPoint(x: width / 2 + translation, y: barTop / 2 + (card.midY - barTop / 2) * p), scale)
    }

    /// The arriving tab's card: its centre, size, lean and rounding.
    public struct Card: Equatable, Sendable {
        public var center: CGPoint
        public var size: CGSize
        public var angle: CGFloat
        public var cornerRadius: CGFloat
    }

    /// The tab before this one coming out of the tab button's front card (`button`, leaning `tilt`, rounded
    /// `buttonCorner`), `progress` of the way, beside the page whose card is centred at `leavingCenterX`. It rises
    /// straight away and moves out to the left later (its sideways way on the square of the progress), so it flies
    /// up off the button and then out to its place, the page's card width and `cardGap` to the page's left, its lean
    /// letting go as it comes.
    public static func arrivingCard(progress: CGFloat, from button: CGRect, tilt: CGFloat, buttonCorner: CGFloat,
                                    leavingCenterX: CGFloat, width: CGFloat, barTop: CGFloat) -> Card {
        let p = min(1, max(0, progress))
        let card = cardFrame(width: width, barTop: barTop)
        let targetX = leavingCenterX - (card.width + cardGap)
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        return Card(center: CGPoint(x: mix(button.midX, targetX, p * p), y: mix(button.midY, card.midY, p)),
                    size: CGSize(width: mix(button.width, card.width, p), height: mix(button.height, card.height, p)),
                    angle: tilt * (1 - p), cornerRadius: mix(buttonCorner, cardCornerRadius, p))
    }

    /// Let go, the page's card springs off to the right, still a card, and the arriving card grows to fill the
    /// screen: Arc Search's took 0.28 s and 0.24 s.
    public static let cardLeave = MobileMotion.Spring(response: 0.28, dampingRatio: 1)
    public static let cardArrive = MobileMotion.Spring(response: 0.24, dampingRatio: 1)

    /// Where the page's card goes once let go: off the right edge, centred at this x.
    public static func leavingCardGoneX(width: CGFloat) -> CGFloat {
        width + width * cardScale(width: width) / 2
    }

    /// Where the page Back or Forward went to belongs, as a scroll view offset: `scrollTop` down its document, as it
    /// was left, with the app's own `insetTop` above it, and no further than the document goes. WebKit puts such a page
    /// back without the insets the app sets itself, a status bar higher than its picture shows it.
    public static func restoredOffset(scrollTop: CGFloat, insetTop: CGFloat, insetBottom: CGFloat, contentHeight: CGFloat,
                                      viewHeight: CGFloat) -> CGFloat {
        let lowest = -insetTop
        let highest = max(lowest, contentHeight + insetBottom - viewHeight)
        return min(highest, max(lowest, scrollTop - insetTop))
    }

    // MARK: After letting go

    /// The arriving page's picture stays over the live page until that has drawn, and no longer than this: a page
    /// that takes its time is shown as it is. Arc Search showed its picture a frame or four past settling; its
    /// closing tab went black for a third of a second while its page loaded again.
    public static let longestHold: TimeInterval = 1.5
    /// How long the picture stays once the page says it has drawn, for that paint to reach the screen.
    public static let drawnSettle: TimeInterval = 0.1

    /// Whether the arriving page's picture comes off: `settled` once the pages are in place; `sinceNavigated` seconds
    /// since the page was asked for; `sinceDrawn` since it said it had drawn, nil while it hasn't.
    public static func liftsPicture(settled: Bool, sinceNavigated: TimeInterval, sinceDrawn: TimeInterval?) -> Bool {
        guard settled else { return false }
        if sinceNavigated >= longestHold { return true }
        guard let sinceDrawn else { return false }
        return sinceDrawn >= drawnSettle
    }
}
