import CoreGraphics
import Foundation

/// Arc Search's easter egg: the logo on the empty home screen spins like a fidget spinner when
/// flicked, slows down by itself and settles upright with a small bounce.
public enum MobileFidget {
    /// The spin loses speed with this time constant, in seconds.
    public static let friction: Double = 1.4
    /// Slower than this (radians a second) the spin gives way to settling upright.
    public static let restSpeed: Double = 1.2
    /// A flick spins no faster than this.
    public static let maximumSpeed: Double = 60

    /// The angle and speed one frame later.
    public static func step(angle: Double, speed: Double, elapsed: Double) -> (angle: Double, speed: Double) {
        let slowed = speed * exp(-elapsed / friction)
        // The mean of the speed before and after: exact enough for a frame.
        return (angle + (speed + slowed) / 2 * elapsed, slowed)
    }

    public static func isSpinning(speed: Double) -> Bool {
        abs(speed) >= restSpeed
    }

    /// The upright angle the logo settles on: the whole turn it is heading for.
    public static func restAngle(from angle: Double, speed: Double) -> Double {
        let turn = 2 * Double.pi
        return (speed >= 0 ? (angle / turn).rounded(.up) : (angle / turn).rounded(.down)) * turn
    }

    /// The speed a flick starts with, from how fast the finger went round the centre.
    public static func launchSpeed(angularVelocity: Double) -> Double {
        min(maximumSpeed, max(-maximumSpeed, angularVelocity))
    }

    /// How many quarter turns lie between two angles: one tick of the haptics for each.
    public static func quarterTurns(from: Double, to: Double) -> Int {
        abs(Int((to / (.pi / 2)).rounded(.down)) - Int((from / (.pi / 2)).rounded(.down)))
    }
}

/// How the page sits behind the search sheet: pushed back as a card, the way Arc Search shows it.
public enum MobilePageBehindSearch {
    /// The card's distance from each side of the screen.
    public static let sideInset: CGFloat = 10
    public static let cornerRadius: CGFloat = 12
    /// How dark the page gets: black at 0.2 over it, which turns a white page #cccccc as in the
    /// TidBITS screenshot.
    public static let dim: CGFloat = 0.2

    /// The page's scale and its shift down, for a screen of `size` whose status bar ends at `safeTop`:
    /// the card's top edge sits right under the status bar.
    public static func transform(in size: CGSize, safeTop: CGFloat) -> (scale: CGFloat, shiftDown: CGFloat) {
        guard size.width > 0 else { return (1, 0) }
        let scale = (size.width - 2 * sideInset) / size.width
        return (scale, safeTop - size.height * (1 - scale) / 2)
    }
}
