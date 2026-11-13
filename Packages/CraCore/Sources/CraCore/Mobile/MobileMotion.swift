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

    /// The page under a finger dragging the bar upwards: it shrinks towards its card as it rises.
    /// 0 is the whole page, 1 the card in the row; a 300 pt drag gets there.
    public static func switcherProgress(dragUp distance: CGFloat) -> CGFloat {
        min(1, max(0, distance / 300))
    }

    /// Whether letting go of that drag settles into the tab row: far enough, or flicked upwards.
    public static func opensSwitcher(dragUp distance: CGFloat, velocityUp: CGFloat) -> Bool {
        distance > 110 || (distance > 20 && velocityUp > 500)
    }
}
