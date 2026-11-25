import CoreGraphics

/// The ticks a page gives while it is pulled down to reload (`MobileSwipe.pullToRefreshDistance`).
/// They begin faint at 24 pt, strengthen with each 2 pt of pull, and stop at the refresh line:
/// the tick there is the strongest and is played with a firmer impact. Pushing the pull back up
/// ticks down through them again. Past the line the page can still be pulled, but it says nothing
/// more. Letting go at the line plays the app's own impact and reloads.
public struct MobilePullHaptics: Sendable {
    /// One tick's strength, and whether it is the one at the refresh line.
    public struct Tick: Equatable, Sendable {
        /// The impact's strength, 0...1.
        public let intensity: Double
        /// The tick at the refresh line, where letting go reloads: the app plays a firmer impact.
        public let isFinal: Bool

        public init(intensity: Double, isFinal: Bool) {
            self.intensity = intensity
            self.isFinal = isFinal
        }
    }

    /// Where the first, faintest tick is.
    public static let firstTick: CGFloat = 24
    /// How far apart the ticks are.
    public static let step: CGFloat = 2
    /// How far the pull must move back past a tick before that tick can play again. The small gap
    /// keeps a finger resting on a boundary from ticking twice, without thinning the return ticks.
    static let rearm: CGFloat = 1
    /// The intensity of the tick at `firstTick`: nearly silent.
    public static let faintest = 0.15
    /// The intensity of the tick at the refresh line: the strongest.
    public static let strongest = 0.9

    /// The tick that last played, or nil while the pull is above its start.
    public private(set) var last: Int?

    public init() {}

    /// The page was pulled `pull` points past the top. Returns the tick to play now, or nil when
    /// none is due. A pull that skips several ticks in one movement plays only the one it
    /// reached, so a quick fling is one strong tick, not a burst.
    public mutating func tick(pull: CGFloat) -> Tick? {
        guard pull.isFinite else { return nil }
        if pull < Self.firstTick {
            // Pushing the whole pull back out gives the first tick once more as it leaves.
            guard self.last != nil, pull < Self.firstTick - Self.rearm else { return nil }
            self.last = nil
            return Self.tick(for: 0)
        }
        let index = min(Self.count - 1, Int(((pull - Self.firstTick) / Self.step).rounded(.down)))
        guard let last else {
            self.last = index
            return Self.tick(for: index)
        }
        if index > last {
            // Pulling deeper: the tick at the detent reached.
            self.last = index
            return Self.tick(for: index)
        }
        if index < last, pull < Self.position(of: last) - Self.rearm {
            // Pushing back up: the ticks run the other way too, once clear of the last gap.
            self.last = index
            return Self.tick(for: index)
        }
        return nil
    }

    /// The tick to play as the finger lifts at `pull`: the line's own, when the pull got there
    /// and its tick has not played yet. A slow pull's last move lands past the line after the
    /// last tick it saw, and letting go reloads from where the finger is.
    public mutating func tickOnRelease(pull: CGFloat) -> Tick? {
        guard pull >= MobileSwipe.pullToRefreshDistance, last != Self.count - 1 else { return nil }
        last = Self.count - 1
        return Self.tick(for: Self.count - 1)
    }

    /// The page is no longer being pulled: the next pull starts from silence.
    public mutating func reset() {
        last = nil
    }

    /// How many ticks one pull from `firstTick` to the refresh line has.
    static let count = Int(((MobileSwipe.pullToRefreshDistance - firstTick) / step).rounded()) + 1

    static func position(of index: Int) -> CGFloat {
        firstTick + CGFloat(index) * step
    }

    static func tick(for index: Int) -> Tick {
        Tick(intensity: intensity(for: index), isFinal: index == count - 1)
    }

    static func intensity(for index: Int) -> Double {
        guard count > 1 else { return strongest }
        let progress = Double(index) / Double(count - 1)
        // Ease in: the early ticks stay subtle, and the last one is the cue to let go.
        return faintest + (strongest - faintest) * progress * progress
    }
}
