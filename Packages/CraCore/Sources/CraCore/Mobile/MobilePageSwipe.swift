import CoreGraphics
import Foundation

/// How a swipe across the page looks while it goes and once it is let go (`MobileSwipe.navigation` decides where it
/// goes). Measured frame by frame on Arc Search screen recordings from an iPhone (430 × 932 pt, Nov 2026): Back slides
/// the page off the one it goes back to, and Back on a tab's first page shrinks the page into a card while the tab
/// before it comes out of the tab button beside it. A swipe along the bar to the tab beside goes the same way, as the
/// tab closing does towards the older tab and as the closed tab coming back does towards the newer.
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
        /// Along the bar to the right: the tab before this one in the row, out of the tab button.
        case olderTab
        /// Along the bar to the left: the tab after this one in the row, coming in beside the page from the right.
        case newerTab
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
        reveal == .forward || reveal == .reopeningTab || reveal == .newerTab
    }

    /// Whether the swipe takes the page into a card beside the tab it leads to: a tab closing or the closed tab coming
    /// back, or the tab beside along the bar.
    public static func showsCards(_ reveal: Reveal) -> Bool {
        reveal != .back && reveal != .forward
    }

    /// Whether the tab the swipe leads to comes out of the tab button (the tab shown once this one closes, or the
    /// older tab along the bar), or in beside the page from the right.
    public static func comesOutOfTabButton(_ reveal: Reveal) -> Bool {
        reveal == .closingTab || reveal == .olderTab
    }

    /// Whether the swipe is along the bar, to the tab beside: it walks the row, closing and reopening nothing.
    public static func alongBar(_ reveal: Reveal) -> Bool {
        reveal == .olderTab || reveal == .newerTab
    }

    /// Whether the magnet ticks as it lets go: not along the bar, where the swipe is the bar's own and quiet (asked
    /// for on Nov 28).
    public static func ticks(_ reveal: Reveal) -> Bool { !alongBar(reveal) }

    /// Where a swipe that leads to `wanted` the way the finger now is goes, having started `way` in this gesture: once
    /// it has started a swipe to another tab (closing, reopening, or along the bar) it keeps to that, so turning back
    /// can't close a tab just brought back, or bring back the one just closing (asked for on Nov 28). Turned back past
    /// where it started, its page drags its feet (`dragsFeet`) and its cards go back in.
    public static func leads(_ wanted: Reveal?, after way: Reveal?) -> Reveal? {
        guard let way, showsCards(way) else { return wanted }
        return way
    }

    /// How long the picture of a tab a swipe brings takes to fade off its live page: as a card picked in the tab row
    /// does (`MobileTabCarousel.pictureFade`), `pictureFadeSlower` times as long (asked for on Nov 28).
    public static func pictureFade(_ growth: MobileTabCarousel.Growth) -> TimeInterval {
        MobileTabCarousel.pictureFade(growth, handOver: MobileTabCarousel.liveCover) * pictureFadeSlower
    }

    public static let pictureFadeSlower: TimeInterval = 1.5

    /// How far a page goes with the finger where the swipe leads nowhere: it drags its feet.
    public static let dragsFeet: CGFloat = 0.25

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
    /// (Nov 27, finger not shown) were not held: from their first moving frame the cards came out. Cra holds them as it
    /// holds a slow one, the page held back before the cards come out however fast the finger (asked for on Nov 28).
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
        /// Whether it has let the page go: letting go goes where the swipe leads from here.
        public private(set) var letGo = false
        /// Whether the page is still held back: not yet let go, or held again.
        public var holds: Bool { !letGo }
        /// How far the page is behind the finger, and how fast that is changing while it springs to its new
        /// distance after letting go or taking hold again.
        public private(set) var lag: CGFloat = 0
        private var lagSpeed: CGFloat = 0
        private var springing = false

        public init(deadZone: CGFloat = 0, share: CGFloat, letGoAt: CGFloat, catchUp: MobileMotion.Spring, gap: CGFloat = 0) {
            self.deadZone = deadZone
            self.share = share
            self.letGoAt = letGoAt
            self.catchUp = catchUp
            self.gap = gap
        }

        /// How far the finger has come when the held page reaches `letGoAt`.
        public var letGoFinger: CGFloat { deadZone + letGoAt / max(share, 0.01) }

        /// Where the held page is with the finger `finger` along.
        public func held(_ finger: CGFloat) -> CGFloat { max(0, finger - deadZone) * share }

        /// `dt` seconds on, with the finger `distance` along the way the swipe leads (less than nothing is back past
        /// where it started): how far the page has come, and whether the magnet let go on this step.
        public mutating func step(distance: CGFloat, dt: Double) -> (page: CGFloat, letGoNow: Bool) {
            let finger = max(0, distance)
            var letGoNow = false
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

    /// How far a tab's page comes, held, before the magnet lets it go: Arc Search's let go at 21 pt, the finger 185 pt
    /// in; Cra's lets go sooner, with the finger about 100 pt in, now that every swipe is held first (asked for on
    /// Nov 28).
    public static let tabLetGoAt: CGFloat = 10.4

    /// Along the bar the magnet lets go sooner, with the finger about 60 pt in: switching tabs closes nothing (asked
    /// for on Nov 28).
    public static let barLetGoAt: CGFloat = 5.46

    /// The magnet for each swipe, held whatever the finger's speed: Back and Forward as Arc Search's Back, a swipe to
    /// another tab as its tab closing, held longer, and let go sooner along the bar.
    public static func magnet(for reveal: Reveal) -> Magnet {
        guard showsCards(reveal) else {
            return Magnet(share: 0.28, letGoAt: 21, catchUp: MobileMotion.Spring(response: 0.16, dampingRatio: 1))
        }
        return Magnet(deadZone: 16, share: 0.124, letGoAt: alongBar(reveal) ? barLetGoAt : tabLetGoAt,
                      catchUp: MobileMotion.Spring(response: 0.26, dampingRatio: 1), gap: 30)
    }

    /// Whether letting go goes where the swipe leads, with the finger moving at `velocity` points a second towards
    /// it: once the magnet has let the page go, unless the finger is flicking it back; short of that, only a flick
    /// onwards.
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

    /// As the magnet stops holding the page, the page shrinks into a card and the tab before it comes out of the tab
    /// button into one the same size beside it: one critically damped spring on its own clock, not the finger's
    /// travel. Arc Search's was 99 % there 13 frames in (0.26 s response, fitted within 0.01). Held again, both go
    /// back on the same spring from wherever they are, so a finger going back and forth takes them out and in.
    public static let cardSpring = MobileMotion.Spring(response: 0.26, dampingRatio: 1)

    /// The tab's card coming out overshoots its place a little and settles back; it goes back in, and the page in and
    /// out, without (Arc Search's tab came out on `cardSpring`; the overshoot was asked for on Nov 28).
    public static let tabCardOut = MobileMotion.Spring(response: 0.35, dampingRatio: 0.85)

    /// How far into a card a page or the tab is, 0 to 1 (past 1 overshooting), stepped once a frame: `outSpring` on
    /// the way out, `inSpring` on the way back.
    public struct Cards: Equatable, Sendable {
        public let outSpring: MobileMotion.Spring
        public let inSpring: MobileMotion.Spring
        public private(set) var progress: CGFloat = 0
        private var speed: Double = 0

        public init(out: MobileMotion.Spring = cardSpring, in back: MobileMotion.Spring = cardSpring) {
            outSpring = out
            inSpring = back
        }

        /// The page's: in and out on `cardSpring`.
        public static var page: Cards { Cards() }
        /// The tab's: out of the tab button with a little overshoot, back in on `cardSpring`; a tab coming in beside
        /// the page goes as the page does.
        public static func tab(for reveal: Reveal) -> Cards { comesOutOfTabButton(reveal) ? Cards(out: tabCardOut) : page }

        /// `dt` seconds on, heading out into cards when `out`, back to the page otherwise.
        public mutating func step(out: Bool, dt: Double) -> CGFloat {
            let target: Double = out ? 1 : 0
            let next = (out ? outSpring : inSpring).step(offset: Double(progress) - target, velocity: speed, after: dt)
            let x = next.offset
            speed = next.velocity
            if abs(x) < 0.001, abs(speed) < 0.01 {
                progress = CGFloat(target)
                speed = 0
            } else {
                progress = CGFloat(target + x)
            }
            return progress
        }
    }

    /// The cards: `cardInset` from the screen's sides, from the top of the screen's safe area (under the status bar)
    /// down to `cardInset` above the bar, the page in them scaled to their width with its strip under the status bar
    /// squashed away, rounded `cardCornerRadius`, and `cardGap` apart, their tops level. Arc Search's were 390 × 777 at
    /// y 59 on a 430 pt screen with its safe area's top at 59 and its bar's top at 856.
    public static let cardInset: CGFloat = 20
    public static let cardCornerRadius: CGFloat = 20
    public static let cardGap: CGFloat = 20

    /// How much the page is shrunk in its card.
    public static func cardScale(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return max(0, width - 2 * cardInset) / width
    }

    /// The page's card in its place, on a screen whose safe area starts `band` down and whose bar starts at `barTop`.
    public static func cardFrame(width: CGFloat, band: CGFloat, barTop: CGFloat) -> CGRect {
        CGRect(x: cardInset, y: band, width: width * cardScale(width: width), height: max(0, barTop - cardInset - band))
    }

    /// The page on screen on its way into its card: its centre on screen, its size before scaling, its scale and its
    /// rounding as seen, and how high the strip under the status bar is in it, before scaling.
    public struct LeavingPage: Equatable, Sendable {
        public var center: CGPoint
        public var size: CGSize
        public var scale: CGFloat
        public var cornerRadius: CGFloat
        public var band: CGFloat
    }

    /// Where the page on screen is, `progress` of the way into its card, the finger `translation` across, on a screen
    /// `height` high with the status bar's strip `band` high at its top and its corners rounded `displayCorner`. It
    /// follows the finger one to one. Held, before the cards come out, it is the whole screen, rounded as the display
    /// is, so the page slides as it is. As they come out it shrinks into its card, rounded as the card: the strip
    /// squashes to nothing, and the page under it, shrunk as the card is, is cut off at the card's bottom. Arc Search's
    /// page was a card at once, strip and all; Cra's waits for the cards and leaves the strip behind (asked for on
    /// Nov 28).
    public static func leavingPage(progress: CGFloat, translation: CGFloat, width: CGFloat, height: CGFloat, band: CGFloat,
                                   barTop: CGFloat, displayCorner: CGFloat) -> LeavingPage {
        let p = min(1, max(0, progress))
        let card = cardFrame(width: width, band: band, barTop: barTop)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let scale = mix(1, cardScale(width: width))
        let strip = band * (1 - p)
        let size = CGSize(width: width, height: strip + mix(height - band, card.height / cardScale(width: width)))
        let bottom = mix(height, card.maxY)
        return LeavingPage(center: CGPoint(x: width / 2 + translation, y: bottom - size.height * scale / 2), size: size,
                           scale: scale, cornerRadius: mix(displayCorner, cardCornerRadius), band: strip)
    }

    /// The arriving tab's card: its centre, size, lean and rounding, and how much of its strip under the status bar
    /// shows, 1 (all of it, as on screen) to 0 (squashed away).
    public struct Card: Equatable, Sendable {
        public var center: CGPoint
        public var size: CGSize
        public var angle: CGFloat
        public var cornerRadius: CGFloat
        public var strip: CGFloat
    }

    /// How far the tab's card bows out to the left on its way up, at its widest half way.
    public static let tabCardArc: CGFloat = 32

    /// The tab before this one coming out of the tab button's front card (`button`, leaning `tilt`, rounded
    /// `buttonCorner`), `progress` of the way (a little past 1 as it overshoots), beside the page whose card is centred
    /// at `leavingCenterX`. It rises straight away and moves out to the left later (its sideways way on the square of
    /// the progress), bowing `tabCardArc` further left on the way, so it flies up off the button in an arc and out to
    /// its place, the page's card width and `cardGap` to the page's left, its lean letting go and its strip squashing
    /// away as it comes, as the page's does. Made the page once let go, its strip comes back as it grows to the screen.
    public static func arrivingCard(progress: CGFloat, from button: CGRect, tilt: CGFloat, buttonCorner: CGFloat,
                                    leavingCenterX: CGFloat, width: CGFloat, band: CGFloat, barTop: CGFloat) -> Card {
        let p = max(0, progress), q = min(1, p)
        let card = cardFrame(width: width, band: band, barTop: barTop)
        let targetX = leavingCenterX - (card.width + cardGap)
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        return Card(center: CGPoint(x: mix(button.midX, targetX, p * p) - tabCardArc * sin(.pi * q),
                                    y: mix(button.midY, card.midY, p)),
                    size: CGSize(width: mix(button.width, card.width, p), height: mix(button.height, card.height, p)),
                    angle: tilt * (1 - q), cornerRadius: mix(buttonCorner, cardCornerRadius, q), strip: 1 - q)
    }

    /// The closed tab coming back, or the newer tab along the bar, beside the page `leaving` on its way into its card, on a screen whose safe area
    /// starts `band` down: the page's own width, `cardGap` to its right, from the safe area's top down to the page's
    /// bottom, its strip under the status bar squashed away all the while, so it only grows back over the status bar
    /// as the tab becomes the page; no lean, arc or overshoot (asked for on Nov 28; Arc Search's came in as Forward
    /// does).
    public static func cardBeside(_ leaving: LeavingPage, band: CGFloat) -> Card {
        let width = leaving.size.width * leaving.scale
        let bottom = leaving.center.y + leaving.size.height * leaving.scale / 2
        let height = max(0, bottom - band)
        return Card(center: CGPoint(x: leaving.center.x + width + cardGap, y: band + height / 2),
                    size: CGSize(width: width, height: height), angle: 0, cornerRadius: leaving.cornerRadius, strip: 0)
    }

    /// Whether the tab's card comes out over the bar: lifted off the button while the bar is there; with the bar
    /// slid away (`barCollapse` 0 there to 1 gone) more than half way, it sweeps out from behind it, and back in.
    public static func tabCardOverBar(barCollapse: CGFloat) -> Bool { barCollapse < 0.5 }

    /// How far out the tab's card from behind a slid-away bar is before it is wholly there: out of sight while it is
    /// still where the button was, it fades in quickly as it leaves, and out as it goes back.
    public static let tabCardFadeIn: CGFloat = 0.12

    /// How opaque the tab's card is `progress` of the way out: always wholly there over the bar.
    public static func tabCardAlpha(progress: CGFloat, overBar: Bool) -> CGFloat {
        overBar ? 1 : min(1, max(0, progress) / tabCardFadeIn)
    }

    /// Let go, the page's card springs off to the right, shrinking a little further, and the arriving card grows to
    /// fill the screen: Arc Search's took 0.28 s and 0.24 s, the page's card down to 0.888 within four frames.
    public static let cardLeaveScale: CGFloat = 0.888
    public static let cardLeave = MobileMotion.Spring(response: 0.28, dampingRatio: 1)
    public static let cardArrive = MobileMotion.Spring(response: 0.24, dampingRatio: 1)

    /// Where the page's card goes once let go, centred at this x: off the right edge as the tab it leads to comes out
    /// of the tab button, off the left as one comes in from the right.
    public static func leavingCardGoneX(width: CGFloat, reveal: Reveal) -> CGFloat {
        let half = width * cardScale(width: width) / 2
        return arrivesOnTop(reveal) ? -half : width + half
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
