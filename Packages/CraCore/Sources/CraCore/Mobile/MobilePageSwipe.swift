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

    // MARK: The magnet

    /// Arc Search holds the page as a swipe across it starts: past a dead zone the page moves at a share of the
    /// finger's travel until it has come `letGoAt` points, then lets go with a tick and catches up with the finger on
    /// a critically damped spring, a gap behind it, following it from there. Measured on six of its swipes and two
    /// more with AssistiveTouch showing the finger: the page let go at 20–22 pt of its own travel whatever the
    /// finger's speed. Closing a tab it holds hard: still for the finger's first 16 pt, then at 0.124 of its travel, so
    /// the finger is 185 pt in as it lets go; it catches up in 0.26 s to 30 pt behind the finger. Going Back it holds
    /// at 0.28 of the finger's travel and caught up in about 0.16 s (the finger not seen yet). Let go while held, the
    /// swipe goes nowhere; once let go, it goes. Taken back under `holdAgainShare` of the finger's way to letting go,
    /// the magnet holds the page again (Arc Search's was not seen).
    ///
    /// Those closing swipes were slow, about 80 pt a second from mid-page. Arc Search's quick ones on a tab's first page
    /// (Nov 27, finger not shown) were not held: from their first moving frame the cards came out and the page followed
    /// on the catch-up spring, 3, 7.5, 12.5 and 17.5 pt in its first four frames, too fast for a page held at an eighth.
    /// Let go there, the page's card 60 to 95 pt along, they went back, as the finger short of where the slow swipes let
    /// go says (`quickSpeed`).
    public static let holdAgainShare: CGFloat = 0.6

    /// The magnet's hold on the page through one swipe, stepped once a frame.
    public struct Magnet: Equatable, Sendable {
        /// How far the finger goes before the page moves at all, the page's share of the finger's travel from there
        /// while held, how far the page comes before it lets go, the spring it catches up on, and how far behind the
        /// finger it then stays.
        public let deadZone: CGFloat
        public let share: CGFloat
        public let letGoAt: CGFloat
        public let catchUp: MobileMotion.Spring
        public let gap: CGFloat
        /// A finger past the dead zone faster than this (points a second) takes the hold off: the page follows it from
        /// there as if let go, though letting go still only goes past `letGoFinger`. Nil: held whatever the speed.
        public let quickSpeed: CGFloat?
        /// Whether it has let the page go: letting go goes where the swipe leads from here.
        public private(set) var letGo = false
        /// Whether a quick finger took the hold off.
        public private(set) var quick = false
        /// Whether the page is still held back.
        public var holds: Bool { !letGo && !quick }
        /// How far the page is behind the finger, and how fast that is changing while it springs to its new
        /// distance after letting go or taking hold again.
        public private(set) var lag: CGFloat = 0
        private var lagSpeed: CGFloat = 0
        private var springing = false

        public init(deadZone: CGFloat = 0, share: CGFloat, letGoAt: CGFloat, catchUp: MobileMotion.Spring, gap: CGFloat = 0,
                    quickSpeed: CGFloat? = nil) {
            self.deadZone = deadZone
            self.share = share
            self.letGoAt = letGoAt
            self.catchUp = catchUp
            self.gap = gap
            self.quickSpeed = quickSpeed
        }

        /// How far the finger has come when the held page reaches `letGoAt`.
        public var letGoFinger: CGFloat { deadZone + letGoAt / max(share, 0.01) }

        /// Where the held page is with the finger `finger` along.
        public func held(_ finger: CGFloat) -> CGFloat { max(0, finger - deadZone) * share }

        /// `dt` seconds on, with the finger `distance` along the way the swipe leads (less than nothing is back past
        /// where it started) and moving at `speed` points a second that way: how far the page has come, and whether
        /// the magnet let go on this step.
        public mutating func step(distance: CGFloat, dt: Double, speed: CGFloat = 0) -> (page: CGFloat, letGoNow: Bool) {
            let finger = max(0, distance)
            var letGoNow = false
            if holds, let quickSpeed, finger > deadZone, speed >= quickSpeed {
                quick = true
                springing = true
            }
            if !letGo, finger >= letGoFinger - 0.001 {
                letGo = true
                letGoNow = true
                springing = true
            } else if letGo, finger < letGoFinger * holdAgainShare {
                letGo = false
                springing = true
            }
            let target = holds ? finger - held(finger) : gap
            if springing {
                // A critically damped spring of the lag towards where it belongs, worked out exactly for the step.
                let omega = 2 * Double.pi / catchUp.response, t = max(0, dt)
                let x0 = Double(lag - target), v0 = Double(lagSpeed)
                let e = exp(-omega * t)
                lag = target + CGFloat((x0 + (v0 + omega * x0) * t) * e)
                lagSpeed = CGFloat((v0 - omega * (v0 + omega * x0) * t) * e)
                if abs(lag - target) < 0.25, abs(lagSpeed) < 5 { springing = false }
            }
            if !springing {
                lag = target
                lagSpeed = 0
            }
            return (max(0, finger - lag), letGoNow)
        }
    }

    /// How fast a finger closing a tab goes for the page not to be held: Arc Search held its slow swipes, about 80 pt a
    /// second, and not its quick ones, which had the page 17.5 pt along four frames in, the finger over 1000 pt a second.
    /// Somewhere between; Arc Search's own figure was not seen.
    public static let quickSpeed: CGFloat = 300

    /// The magnet for each swipe: Back and Forward as Arc Search's Back, held whatever the finger's speed, a tab
    /// closing or coming back as its tab closing.
    public static func magnet(for reveal: Reveal) -> Magnet {
        switch reveal {
        case .back, .forward:
            return Magnet(share: 0.28, letGoAt: 21, catchUp: MobileMotion.Spring(response: 0.16, dampingRatio: 1))
        case .closingTab, .reopeningTab:
            return Magnet(deadZone: 16, share: 0.124, letGoAt: 21, catchUp: MobileMotion.Spring(response: 0.26, dampingRatio: 1),
                          gap: 30, quickSpeed: quickSpeed)
        }
    }

    /// Whether letting go goes where the swipe leads, with the finger moving at `velocity` points a second towards
    /// it: once the magnet has let the page go, unless the finger is flicking it back; short of that, a quick finger's
    /// page following it or not, only a flick onwards.
    public static func commits(letGo: Bool, velocity: CGFloat, distance: CGFloat) -> Bool {
        if letGo { return velocity > -MobileSwipe.flickVelocity }
        return distance > MobileSwipe.flickDistance && velocity > MobileSwipe.flickVelocity
    }

    /// A finger that stood still for this long before lifting is let go, not flicked: a pan's speed is the speed of its
    /// last move, which a finger held still doesn't replace.
    public static let stillBeforeLifting: TimeInterval = 0.1

    /// The finger's speed as it lifts, `velocity` as the pan last measured it, `stillFor` seconds after it last moved.
    public static func liftVelocity(_ velocity: CGFloat, stillFor: TimeInterval) -> CGFloat {
        stillFor >= stillBeforeLifting ? 0 : velocity
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

    /// Let go, the page's card springs off to the right, shrinking a little further, and the arriving card grows to
    /// fill the screen: Arc Search's took 0.28 s and 0.24 s, the page's card down to 0.888 within four frames.
    public static let cardLeaveScale: CGFloat = 0.888
    public static let cardLeave = MobileMotion.Spring(response: 0.28, dampingRatio: 1)
    public static let cardArrive = MobileMotion.Spring(response: 0.24, dampingRatio: 1)

    /// Where the page's card goes once let go: off the right edge, centred at this x.
    public static func leavingCardGoneX(width: CGFloat) -> CGFloat {
        width + width * cardScale(width: width) / 2
    }

    /// Let go short of closing, the cards go back the way they came, on the spring they came out on: the tab's card down
    /// the screen's edge into the tab button, the page's card back to the whole page. How far back they are `time`
    /// seconds after letting go, from where they were (0) to before the swipe (1), and whether they are home. Arc Search's
    /// page card came back .20, .47, .69, .83 and .93 of the way at frames 2, 4, 6, 8 and 10, and its tab card with it,
    /// down the way it had come up.
    public static func cardsReturn(after time: Double) -> (share: CGFloat, home: Bool) {
        let remaining = cardSpring.remaining(after: max(0, time))
        return (CGFloat(1 - remaining), remaining < 0.003)
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
