import CoreGraphics
import Foundation

/// The iPhone app's springs, fitted to Arc Search's footage (30 frames a second, docs/ios.md).
public enum MobileMotion {
    /// A cubic ease-out over `t` from 0 to 1: it leaves quickly and settles softly. The bottom
    /// bar's snap, the pull's ring and a closing tab's drop share it.
    public static func easeOut(_ t: CGFloat) -> CGFloat {
        let t = min(1, max(0, t))
        return 1 - pow(1 - t, 3)
    }

    /// How long the bottom bar takes to walk to an end once the finger lets go.
    public static let barSnap: Double = 0.25

    /// Which of a view's overlapping moves is the latest. Each move takes a ticket, and a delayed
    /// step of a move (its end, a staggered second half) only lands while its ticket is still the
    /// current one: toggled back quickly, an older move's end must not cut the newer one short.
    public struct Ticket: Equatable, Sendable {
        public private(set) var current = 0

        public init() {}

        /// Starts a move, leaving every earlier ticket stale.
        public mutating func next() -> Int {
            current += 1
            return current
        }

        public func isCurrent(_ ticket: Int) -> Bool { ticket == current }
    }

    /// A spring by how long one period would take and how damped it is; 1 is critically damped
    /// (no overshoot).
    public struct Spring: Equatable, Sendable {
        public var response: Double
        public var dampingRatio: Double

        public init(response: Double, dampingRatio: Double) {
            self.response = response
            self.dampingRatio = dampingRatio
        }

        /// For a unit mass.
        public var stiffness: Double { pow(2 * .pi / response, 2) }
        public var damping: Double { 4 * .pi * dampingRatio / response }

        /// How far past its rest the spring goes before it settles, as a share of the move: 0 when
        /// critically damped or more.
        public var overshoot: Double {
            guard dampingRatio < 1 else { return 0 }
            return exp(-.pi * dampingRatio / (1 - dampingRatio * dampingRatio).squareRoot())
        }

        /// How far from rest the spring still is after `time`, as a share of where it began
        /// (released at rest). Only for a critically damped spring.
        public func remaining(after time: Double) -> Double {
            let omega = 2 * .pi / response
            return (1 + omega * time) * exp(-omega * time)
        }

        /// Where something let go `offset` from its rest at `velocity` is after `time`, still as
        /// an offset from rest. Only for a critically damped spring: it carries on the way it was
        /// going, turns once and eases home, never rocking back and forth.
        public func offset(from offset: Double, velocity: Double, after time: Double) -> Double {
            let omega = 2 * .pi / response
            return (offset + (velocity + omega * offset) * time) * exp(-omega * time)
        }
    }

    /// The tab row settling as it opens out of the page. Fitted to Arc Search's row settling
    /// (2024 footage, 30 fps): the card's distance to its place shrinks to 0.54 of itself every
    /// frame, a critically damped spring with a 0.34 s response. Let go after a drag, the row
    /// keeps the finger's speed instead (`MobileTabCarousel.Settle`).
    public static let tabRowSettle = Spring(response: 0.34, dampingRatio: 1)
    /// A card growing into its page: there within five frames.
    public static let tabOpen = Spring(response: 0.26, dampingRatio: 1)
    /// A button at the field's end coming in as the field fills or empties, or the mic as
    /// incognito goes off: a quick scale up with a clear overshoot.
    public static let accessoryEnter = Spring(response: 0.27, dampingRatio: 0.6)
    /// The flick's arriving tab, let go, on its way into the page. Each axis of its place is on
    /// its own fully damped spring that starts at the hand's own speed, so a tab thrown sideways
    /// carries on sideways on one smooth arc before it comes in; its lean lets go on a spring of
    /// its own; and it grows to 101 % of the page and settles back. One clock drives all three.
    public struct FlickLanding: Equatable, Sendable {
        public var from: CGPoint
        public var to: CGPoint
        /// Points a second, as the hand threw it (`flickLaunch`).
        public var velocity: CGPoint
        public var angle: CGFloat
        /// Radians a second, as it was swinging when let go.
        public var spin: CGFloat
        public var scale: CGFloat

        public init(from: CGPoint, to: CGPoint, velocity: CGPoint, angle: CGFloat, spin: CGFloat, scale: CGFloat) {
            self.from = from
            self.to = to
            self.velocity = velocity
            self.angle = angle
            self.spin = spin
            self.scale = scale
        }

        public struct Frame: Equatable, Sendable {
            public var center: CGPoint
            public var angle: CGFloat
            public var scale: CGFloat
            /// How far it has grown from where it was let go to the page's size, 0 to 1.
            public var grown: CGFloat
            public var done: Bool
        }

        public func frame(after time: Double) -> Frame {
            let travel = MobileMotion.flickTravel, turn = MobileMotion.flickTurn
            let x = travel.offset(from: Double(from.x - to.x), velocity: Double(velocity.x), after: time)
            let y = travel.offset(from: Double(from.y - to.y), velocity: Double(velocity.y), after: time)
            let a = turn.offset(from: Double(angle), velocity: Double(spin), after: time)
            let done = time >= 2 || (time >= MobileMotion.flickGrow && abs(x) < 0.5 && abs(y) < 0.5 && abs(a) < 0.002)
            if done { return Frame(center: to, angle: 0, scale: 1, grown: 1, done: true) }
            let size = MobileMotion.flickGrowth(from: scale, after: time)
            let grown = scale < 1 ? min(1, max(0, (size - scale) / (1 - scale))) : 1
            return Frame(center: CGPoint(x: to.x + CGFloat(x), y: to.y + CGFloat(y)), angle: CGFloat(a),
                         scale: size, grown: grown, done: false)
        }

        /// The whole landing, worked out before it starts: a frame every `step` seconds up to and
        /// including the one where it lands, so it can be handed to the render server and play
        /// whatever the app is busy with meanwhile.
        public func frames(every step: Double = 1.0 / 120) -> [Frame] {
            var frames: [Frame] = []
            var time = 0.0
            repeat {
                frames.append(frame(after: time))
                time += step
            } while frames.last?.done == false
            return frames
        }
    }

    /// The landing's place and its lean, each fully damped; and how long it
    /// takes to grow into the page.
    public static let flickTravel = Spring(response: 0.4, dampingRatio: 1)
    public static let flickTurn = Spring(response: 0.4, dampingRatio: 1)
    public static let flickGrow: TimeInterval = 0.5

    /// The arriving tab's size `time` into its landing: out of the hand at `start`, growing
    /// evenly through the middle rather than all at once, easing into 101 % of the page three
    /// quarters of the way, then settling on it. One rise and one gentle fall, no wobble.
    public static func flickGrowth(from start: CGFloat, after time: Double) -> CGFloat {
        let peak: CGFloat = 1.01, peakAt = 0.75
        let u = min(1, max(0, time / flickGrow))
        if u < peakAt {
            // Half an even S, half an ease-out: some speed straight away, most of the growth in
            // the middle, still at the top.
            let k = CGFloat(u / peakAt)
            let rise = (k * k * (3 - 2 * k) + (1 - (1 - k) * (1 - k))) / 2
            return start + (peak - start) * rise
        }
        let k = CGFloat((u - peakAt) / (1 - peakAt))
        return peak + (1 - peak) * k * k * (3 - 2 * k)
    }

    /// How much more a sideways throw counts than an upward one: the hand moves the tab up
    /// anyway, so it is the sideways part that shows the flick.
    public static let flickSidewaysGain: CGFloat = 1.8

    /// The speed the arriving tab leaves the hand at, in points a second: the hand's own, its
    /// sideways part counting more, no faster than a hard flick, and always rising a little;
    /// straight up when the hand was still.
    public static func flickLaunch(velocity: CGPoint) -> CGPoint {
        let thrown = abs(velocity.x) + abs(velocity.y) > 1 ? velocity : CGPoint(x: 0, y: -600)
        let limit: CGFloat = 4000
        let sideways = thrown.x * flickSidewaysGain
        return CGPoint(x: max(-limit * flickSidewaysGain, min(limit * flickSidewaysGain, sideways)),
                       y: max(-limit, min(-100, thrown.y)))
    }

    /// The page card's flight into the tab button once a flick lets go, and how far through it
    /// the arriving tab goes under the bottom bar.
    public static let flickButtonFlight: TimeInterval = 0.3
    public static let flickUnderBarAt: Double = 0.4
    /// The tab in the hand turning from the button's little card into the screen's shape, and
    /// the page on screen dropping into its first card: each on its own clock, not the hand's.
    public static let flickReshape: TimeInterval = 0.12
    public static let flickDrop: TimeInterval = 0.17
    /// A hand that has not moved for this long is still: the card it holds hangs straight.
    public static let flickHandStill: TimeInterval = 0.2
    /// How long the arriving tab's picture stays over its page while the page draws.
    public static let flickHandoffHold: TimeInterval = 0.1
    /// A page swapped in this recently has not drawn yet: a picture of it would be black.
    public static let pageDrawDelay: TimeInterval = 0.15

    /// The page under a finger dragging the bar upwards: it shrinks towards its card as it rises.
    /// 0 is the whole page, 1 the card in the row; a 300 pt drag gets there.
    public static func switcherProgress(dragUp distance: CGFloat) -> CGFloat {
        min(1, max(0, distance / 300))
    }

    /// Whether letting go of that drag settles into the tab row: far enough, or flicked upwards.
    public static func opensSwitcher(dragUp distance: CGFloat, velocityUp: CGFloat) -> Bool {
        distance > 110 || (distance > 20 && velocityUp > 500)
    }

    /// How far the page card has shrunk on a flick up: straight with the hand, from where it was
    /// picked up to the top of the screen.
    public static func flickCardProgress(dragUp distance: CGFloat, startY: CGFloat) -> CGFloat {
        min(1, max(0, distance / max(startY, 1)))
    }

    /// The page card on a flick up is rounded at the device's own corners from its first frame,
    /// and comes back to square as it returns to the page.
    public static let flickCornerRadius: CGFloat = 44

    /// The card the page has shrunk into once the hand has reached the top of the screen: half
    /// the tab area's height, the screen's own shape — so the whole tab, its top colour and the
    /// page under the bar, is in it — 16 pt in from the left edge and 24 pt above the bottom bar.
    public static func flickCardFrame(in screen: CGRect, aboveBar barTop: CGFloat, safeTop: CGFloat,
                                      inset: CGFloat = 16, bottomInset: CGFloat = 24) -> CGRect {
        let height = max(0, (barTop - safeTop) * 0.5)
        let width = height * screen.width / screen.height
        return CGRect(x: screen.minX + inset, y: barTop - bottomInset - height, width: width, height: height)
    }

    /// The card the page is in as soon as a flick starts: the page scaled down with `inset` of
    /// padding from the screen's top and sides and above the bottom bar.
    public static func flickStartFrame(in screen: CGRect, aboveBar barTop: CGFloat,
                                       inset: CGFloat = 20) -> CGRect {
        CGRect(x: screen.minX + inset, y: inset,
               width: max(0, screen.width - inset * 2),
               height: max(0, barTop - inset * 2))
    }

    /// The tab button's front card leans this far: a card landing in it, or going back to it,
    /// lies the same way.
    public static let frontCardTilt = 8 * CGFloat.pi / 180

    /// How tall the tab being dragged up may become before its bottom would pass the screen's
    /// own bottom: the hand holds it just under halfway down, so a twentieth of it sits above
    /// the finger and the rest below.
    public static func flickCardLimit(fingerY: CGFloat, screenHeight: CGFloat) -> CGFloat {
        max(0, (screenHeight - fingerY) / 0.55)
    }

    /// The lean the hand's sideways speed asks of the card it holds: none while the hand is
    /// still, so the card hangs straight.
    public static func flickSwingTarget(velocityX: CGFloat) -> CGFloat {
        // Five degrees either way at most: the tab leans in the hand, it does not swing about.
        let limit = 5 * CGFloat.pi / 180
        return max(-limit, min(limit, velocityX / 3400))
    }

    /// One frame of the card hanging from the finger: a lightly damped spring towards the lean
    /// the hand asks for, so it rocks a few times and hangs straight again in a third of a
    /// second once the hand is still.
    public static func flickSwingStep(angle: CGFloat, speed: CGFloat, target: CGFloat,
                                      dt: Double) -> (angle: CGFloat, speed: CGFloat) {
        let stiffness: CGFloat = 420, damping: CGFloat = 30
        let next = speed + (stiffness * (target - angle) - damping * speed) * CGFloat(dt)
        return (angle + next * CGFloat(dt), next)
    }
}
