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
    /// The space swipe's settle (Dia's zero-bounce spring, perceptual duration 0.4 s).
    public static let omega: CGFloat = 2 * .pi / 0.4
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
