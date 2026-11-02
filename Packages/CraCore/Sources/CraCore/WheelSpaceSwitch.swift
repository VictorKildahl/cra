import CoreGraphics
import Foundation

/// Switching spaces with a mouse wheel over the sidebar (issue #93). macOS turns Shift + wheel
/// into a horizontal wheel before an app sees it, so this reads a wheel's horizontal deltas, the
/// same as a mouse's own sideways wheel; Arc 1.171 switches on both. Arc pages this way through
/// `PageSwipeController`'s `NonGesturalScrollState {cumulativeDistance, lastEventTime,
/// lastTriggerTime}`: quick wheel events add up, and past one line the next or previous space
/// comes in, at most once per `cooldown` (docs/arc-reverse-engineering.md, "Shift + wheel").
public struct WheelSpaceSwitch: Sendable {
    /// More than this many lines (AppKit's `scrollingDeltaX` for a wheel) switch: one slow
    /// notch does nothing, a flick does (Arc: 1 line never, 2 lines always).
    public static let distance: CGFloat = 1
    /// A longer gap between wheel events forgets what had added up (Arc: two notches 35 ms
    /// apart switch, 45 ms apart half the time, 65 ms apart never).
    public static let pause: TimeInterval = 0.045
    /// After a switch the wheel does nothing for this long (Arc: one switch for a 0.245 s burst,
    /// two for 0.254 s).
    public static let cooldown: TimeInterval = 0.25

    public private(set) var cumulativeDistance: CGFloat = 0
    public private(set) var lastEventTime: TimeInterval = -.infinity
    public private(set) var lastTriggerTime: TimeInterval = -.infinity

    public init() {}

    /// Feeds one wheel event of `dx` lines at `time`. Returns the page step it makes: +1 toward
    /// the next space, −1 toward the previous one (a positive `dx`, as two fingers moving right
    /// go back), 0 none.
    public mutating func step(dx: CGFloat, at time: TimeInterval) -> Int {
        defer { lastEventTime = time }
        guard dx != 0, time - lastTriggerTime >= Self.cooldown else { return 0 }
        if time - lastEventTime > Self.pause || (dx > 0) != (cumulativeDistance > 0) { cumulativeDistance = 0 }
        cumulativeDistance += dx
        guard abs(cumulativeDistance) > Self.distance else { return 0 }
        let step = cumulativeDistance > 0 ? -1 : 1
        cumulativeDistance = 0
        lastTriggerTime = time
        return step
    }

    /// Where a wheel step goes, the Library being the page before the first space as in a swipe.
    public enum Target: Equatable, Sendable {
        case space(Int)
        case openLibrary
        case closeLibrary
    }

    /// The page `step` leads to from space `index` of `count`, or from the Library when
    /// `inLibrary`; nil at either end (Arc doesn't wrap). `libraryAllowed` is false where a swipe
    /// can't bring the Library in either (a hidden or floating sidebar).
    public static func target(step: Int, index: Int, count: Int, inLibrary: Bool, libraryAllowed: Bool) -> Target? {
        if inLibrary { return step > 0 ? .closeLibrary : nil }
        let next = index + step
        if next < 0 { return libraryAllowed && step < 0 ? .openLibrary : nil }
        return next < count && step != 0 ? .space(next) : nil
    }
}
