import CoreGraphics
import Foundation

/// Swiping into the Library: past the first space two fingers pull the Library in from the left,
/// in the Library they push it back out. Arc 1.171 has this gesture (docs/arc-reverse-engineering.md,
/// "Swiping into the Library"). Like Arc the sidebar widens with the reveal, from its own width to
/// the Library's, so it lands at the Library's width with no resize after; but where Arc's Library
/// follows the fingers at half speed, Cra's moves like a space swipe (Victor, 1 Nov 2026): the
/// Library is the page before the first space, its right edge 1:1 under the fingers, with the space
/// swipe's rubber band, release rule and spring.
/// The reveal is 0 on the space, 1 with the Library in, past 1 while it rubber-bands.
public enum LibrarySwipe {
    /// The space swipe's settle, which the Library's shares: Arc's PageSwipeController spring, critically damped
    /// at ω ≈ 30.6 rad/s (SwiftUI's response 0.205), within 1 % of its travel in about 0.2 s (docs/arc-reverse-
    /// engineering.md, "Swiping into the Library"). Cra settled on Dia's (perceptual duration 0.4 s), half as fast:
    /// in a side-by-side recording on #613 Arc's swipes settled in ~215 ms and Cra's took ~330 ms.
    public static let omega: CGFloat = 2 * .pi / CGFloat(response)
    /// The spring's response (SwiftUI's, a CASpringAnimation's perceptual duration): the window tint settles on it
    /// too, with the strip (it stayed on Dia's 0.4 s and trailed the sidebar after #613's first fix).
    public static let response: TimeInterval = 0.205
    /// A release faster than this (pages per second) goes its way whatever the position.
    public static let flickSpeed: CGFloat = 0.8

    /// The reveal for `travel` points of finger movement (+ toward the Library) from `start`, the
    /// Library being `width` wide; nil once it is past the space on a swipe that counts from the
    /// space, which then heads for the next space. A swipe counts from the page it began on, or
    /// for one that caught the Library sliding, from the page the slide was `toward`: like a space
    /// swipe, the release makes the page it lands on the current one, so a quick second swipe out
    /// of the Library goes on to the next space. Out of the Library at rest it gives way.
    public static func reveal(from start: CGFloat, travel: CGFloat, width: CGFloat, toward: CGFloat? = nil) -> CGFloat? {
        let r = start + travel / max(1, width)
        if r < 0 { return (toward ?? start) == 0 ? nil : -band(-r) }
        return r > 1 ? 1 + band(r - 1) : r
    }

    /// The fingers' travel past the space for a swipe that left the Library from reveal `start`:
    /// what is left to page the spaces with.
    public static func travelPastSpace(from start: CGFloat, travel: CGFloat, width: CGFloat) -> CGFloat {
        travel + start * max(1, width)
    }

    /// The space swipe's rubber band past either end: AppKit's resistance curve, halved.
    static func band(_ x: CGFloat) -> CGFloat { (1 - 1 / (x * 0.55 + 1)) * 0.5 }

    /// The sidebar's width for reveal `r`: its own `base` width on the space, the Library's
    /// `library` width with the Library in, in proportion between, and on with the rubber band (Arc).
    public static func sidebarWidth(reveal r: CGFloat, base: CGFloat, library: CGFloat) -> CGFloat {
        base + (library - base) * max(0, r)
    }

    /// Where the Library (at its full width) sits for reveal `r`: in from the left, its right
    /// edge under the fingers, then riding the sidebar's edge while it rubber-bands. The space
    /// sits right after it, like the next page.
    public static func libraryX(reveal r: CGFloat, base: CGFloat, library: CGFloat) -> CGFloat {
        r <= 1 ? (r - 1) * library : sidebarWidth(reveal: r, base: base, library: library) - library
    }
    public static func spaceX(reveal r: CGFloat, base: CGFloat, library: CGFloat) -> CGFloat {
        libraryX(reveal: r, base: base, library: library) + library
    }

    // MARK: From a hidden sidebar
    //
    // Arc 1.173.1, a 120 Hz, 2x screen recording read frame by frame, 18 Nov 2026 (a 250 pt
    // sidebar out over the page, a 405 pt Library): the same swipe on the first space brings the
    // Library in docked. It slides in from the window's edge under the floating sidebar and pushes
    // the page before it, at its full width, while the floating sidebar goes back out the way it
    // came, two points for every three the page moves (ratio 1.43 to 1.53 over 12 frames). It lands
    // as the Library does from a docked sidebar, and leaving it by a swipe slides it back out to a
    // hidden sidebar, without the floating one in between.

    /// A swipe toward the Library may start in a floating sidebar that is out, on the first space.
    public static func startsFromHiddenSidebar(floatingShown: Bool, onFirstSpace: Bool) -> Bool {
        floatingShown && onFirstSpace
    }

    /// How far the floating sidebar has gone back toward the window's edge at reveal `r`.
    public static func floatingRetreat(reveal r: CGFloat, library: CGFloat) -> CGFloat {
        max(0, r) * library / 1.5
    }

    /// The page card's leading edge at reveal `r`: against the Library's edge, and never nearer
    /// the window's than its own `inset`, where it rests with the sidebar hidden.
    public static func pageEdgeFromHidden(reveal r: CGFloat, library: CGFloat, inset: CGFloat) -> CGFloat {
        max(inset, sidebarWidth(reveal: r, base: 0, library: library))
    }

    // MARK: The Library button
    //
    // Arc slides the Library in when its button (or ⇧⌘L) opens it and out when the button or the Library's back
    // arrow leaves it, on the swipe's motion, from a hidden sidebar too: in from the window's edge under the
    // floating sidebar, and out to the hidden sidebar with no tab list on the way (#726, the reporter's recording of
    // Arc: one eased-out motion of about 320 ms either way).

    /// Where the sidebar is when the button is pressed.
    public enum ButtonSidebar: Equatable, Sendable {
        /// Docked beside the page, the Library's own or the tab list's.
        case docked
        /// Hidden, its floating panel out over the page or not.
        case hidden
        /// None to slide beside: a page full screen for its own (a video's).
        case none
    }

    /// How the button moves the Library.
    public enum ButtonMotion: Equatable, Sendable {
        /// The swipe's spring to reveal 0 or 1 in the docked sidebar, from where it shows.
        case slide(to: CGFloat)
        /// In from the window's edge under the floating sidebar, landing docked.
        case slideFromHidden
        /// At once.
        case show
        case close
    }

    /// The Library button, ⇧⌘L and the Library's back arrow. A swipe in progress keeps the fingers in charge: the
    /// button lands it at once.
    public static func buttonMotion(opening: Bool, sidebar: ButtonSidebar, swiping: Bool) -> ButtonMotion {
        guard !swiping else { return opening ? .show : .close }
        switch sidebar {
        case .docked: return .slide(to: opening ? 1 : 0)
        case .hidden: return opening ? .slideFromHidden : .close
        case .none: return opening ? .show : .close
        }
    }

    /// Where a released swipe settles: a flick goes its way, else past halfway opens.
    /// `velocity` is in reveals per second, + toward the Library.
    public static func target(reveal r: CGFloat, velocity: CGFloat) -> CGFloat {
        abs(velocity) > flickSpeed ? (velocity > 0 ? 1 : 0) : (r > 0.5 ? 1 : 0)
    }

    /// Release velocity in reveals per second from the last moments' `(time, delta)` samples.
    public static func velocity(samples: [(time: TimeInterval, dx: CGFloat)], width: CGFloat) -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.004 else { return 0 }
        return samples.reduce(0) { $0 + $1.dx } / CGFloat(last.time - first.time) / max(1, width)
    }

    /// The settle `t` seconds after release from reveal `r` moving at `velocity` reveals per second.
    public static func settle(from r: CGFloat, velocity: CGFloat, to target: CGFloat, at t: CGFloat) -> CGFloat {
        let x0 = r - target
        return target + (x0 + (velocity + omega * x0) * t) * exp(-omega * t)
    }

    /// The settle's speed `t` seconds after release, in reveals per second, so a settle can turn
    /// around without a jolt.
    public static func settleVelocity(from r: CGFloat, velocity: CGFloat, to target: CGFloat, at t: CGFloat) -> CGFloat {
        (velocity - omega * (velocity + omega * (r - target)) * t) * exp(-omega * t)
    }

    /// The settle has come to rest: within a quarter point of `target` and nearly still.
    public static func isSettled(from r: CGFloat, velocity: CGFloat, to target: CGFloat, at t: CGFloat, width: CGFloat) -> Bool {
        let x = settle(from: r, velocity: velocity, to: target, at: t)
        let speed = abs(x - settle(from: r, velocity: velocity, to: target, at: t - 0.01)) * 100 * width
        return abs(x - target) * width < 0.25 && speed < 5
    }
}

/// When a settle's time starts: at the first frame it draws, as if it had begun one frame before (#613). A release
/// switches the space, which can keep the main thread from drawing for a frame or two; a spring timed from the
/// release had run that long when it first drew, so the strip stood still for a frame and then jumped (25 to 46
/// points in one frame on the reporter's recording), where Arc's picks up speed from where the fingers left it.
public struct SettleClock: Sendable, Equatable {
    /// When the settle was asked for, and when its time counts from once it has drawn.
    public let started: TimeInterval
    public private(set) var origin: TimeInterval?

    public init(started: TimeInterval) { self.started = started }

    /// The settle's time for the frame shown at `frame` (a display link's target timestamp), `interval` apart.
    public mutating func elapsed(atFrame frame: TimeInterval, interval: TimeInterval) -> TimeInterval {
        if origin == nil { origin = frame - max(0, min(interval, frame - started)) }
        return max(0, frame - origin!)
    }

    /// The settle's time now, outside a frame (turning it around): none before it has drawn.
    public func elapsed(now: TimeInterval) -> TimeInterval {
        origin.map { max(0, now - $0) } ?? 0
    }
}
