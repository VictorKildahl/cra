import CoreGraphics
import Foundation

/// The iPhone app's springs, fitted to Arc Search's footage (30 frames a second, docs/ios.md).
public enum MobileMotion {
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

        /// How far from rest the spring still is after `time`, as a share of where it began
        /// (released at rest). Only for a critically damped spring.
        public func remaining(after time: Double) -> Double {
            let omega = 2 * .pi / response
            return (1 + omega * time) * exp(-omega * time)
        }
    }

    /// The tab row settling when it is let go. In Arc Search the card's distance to its place
    /// shrinks to 0.54 of itself every frame: a critically damped spring with a 0.34 s response.
    public static let tabRowSettle = Spring(response: 0.34, dampingRatio: 1)
    /// A card growing into its page: there within five frames.
    public static let tabOpen = Spring(response: 0.26, dampingRatio: 1)
    /// The flick's arriving tab travelling into the page, carrying the hand's throw with it.
    /// Fully damped: one relaxed arc that slows to a stop, never rocking back and forth.
    public static let flickTabOpen = Spring(response: 0.4, dampingRatio: 1)
    /// The arriving tab's picture growing into the page, overshooting to 101 % of it on the way.
    public static let flickTabScale: TimeInterval = 0.3
    /// The arriving tab's picture letting go of its lean.
    public static let flickTabStraighten = Spring(response: 0.3, dampingRatio: 0.9)
    /// The arriving tab's own page growing to full size, slower than the way it travels.
    public static let flickTabLiveScale = Spring(response: 0.5, dampingRatio: 0.9)

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

    /// How hard the hand's throw counts, sideways and up: the arriving page as itself, and the
    /// picture that stands in for a tab with no page yet.
    public static let flickThrowGain = CGVector(dx: 1, dy: 1)
    public static let flickPictureThrowGain = CGVector(dx: 0.4, dy: 0.6)

    /// The arriving tab's first velocity, as shares of its way a second: the hand's throw times
    /// `gain`, always at least a little upwards, and straight up when the hand was still.
    public static func flickThrow(velocity: CGPoint, distance: CGFloat, gain: CGVector) -> CGVector {
        let thrown = abs(velocity.x) + abs(velocity.y) > 1 ? velocity : CGPoint(x: 0, y: -1200)
        let way = max(distance, 1)
        return CGVector(dx: thrown.x / way * gain.dx, dy: max(-thrown.y / way * gain.dy, 1))
    }

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
