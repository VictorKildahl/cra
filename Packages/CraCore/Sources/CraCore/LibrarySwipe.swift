import CoreGraphics
import Foundation

/// Swiping into the Library: past the first space two fingers pull the Library in from the left,
/// in the Library they push it back out. Arc 1.171 has this gesture (docs/arc-reverse-engineering.md,
/// "Swiping into the Library"), but its Library follows the fingers at half speed and widens the
/// sidebar as it comes; Cra moves it exactly like a space swipe instead (Victor, 1 Nov 2026): the
/// Library is a page before the first space, 1:1 under the fingers in the sidebar's width, the same
/// rubber band, release rule and spring, and the sidebar widens once it has landed.
/// The reveal is 0 on the space, 1 with the Library in, past 1 while it rubber-bands.
public enum LibrarySwipe {
    /// The space swipe's settle (Dia's zero-bounce spring, perceptual duration 0.4 s).
    public static let omega: CGFloat = 2 * .pi / 0.4
    /// A release faster than this (pages per second) goes its way whatever the position.
    public static let flickSpeed: CGFloat = 0.8

    /// The reveal for `travel` points of finger movement (+ toward the Library) from `start`
    /// across a sidebar `width` wide; nil when a swipe that began on the space goes the other
    /// way, toward the next space.
    public static func reveal(from start: CGFloat, travel: CGFloat, width: CGFloat) -> CGFloat? {
        let r = start + travel / max(1, width)
        if r < 0 { return start == 0 ? nil : -band(-r) }
        return r > 1 ? 1 + band(r - 1) : r
    }

    /// The space swipe's rubber band past either end: AppKit's resistance curve, halved.
    static func band(_ x: CGFloat) -> CGFloat { (1 - 1 / (x * 0.55 + 1)) * 0.5 }

    /// Where the Library and the space sit for reveal `r`, side by side like two space pages.
    public static func libraryX(reveal r: CGFloat, width: CGFloat) -> CGFloat { (r - 1) * width }
    public static func spaceX(reveal r: CGFloat, width: CGFloat) -> CGFloat { r * width }

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

    /// The settle has come to rest: within a quarter point of `target` and nearly still.
    public static func isSettled(from r: CGFloat, velocity: CGFloat, to target: CGFloat, at t: CGFloat, width: CGFloat) -> Bool {
        let x = settle(from: r, velocity: velocity, to: target, at: t)
        let speed = abs(x - settle(from: r, velocity: velocity, to: target, at: t - 0.01)) * 100 * width
        return abs(x - target) * width < 0.25 && speed < 5
    }
}
