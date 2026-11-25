import CoreGraphics
import CraCore
import Testing

/// The ticks of a pull down to reload: faint from 24 pt, one every 2 pt, strongest at the 128 pt
/// line, silent past it, and running the other way as the pull is pushed back up.
struct MobilePullHapticsTests {
    private func played(_ pulls: [CGFloat]) -> [MobilePullHaptics.Tick] {
        var haptics = MobilePullHaptics()
        return pulls.compactMap { haptics.tick(pull: $0) }
    }

    @Test func aPullBelowTwentyFourIsSilent() {
        #expect(played([0, 12, 23, 23.9]).isEmpty)
    }

    @Test func aTickPlaysEveryTwoPointsFromTwentyFour() {
        let ticks = played((24...128).map(CGFloat.init))
        #expect(ticks.count == 53)
        #expect(ticks.first?.intensity == MobilePullHaptics.faintest)
        #expect(ticks.last?.intensity == MobilePullHaptics.strongest)
        #expect(ticks.last?.isFinal == true)
        #expect(ticks.dropLast().allSatisfy { !$0.isFinal })
    }

    @Test func theTicksOnlyEverGetStronger() {
        let ticks = played(stride(from: 24, through: 128, by: 2).map(CGFloat.init))
        #expect(ticks.count == 53)
        #expect(zip(ticks.map(\.intensity), ticks.dropFirst().map(\.intensity)).allSatisfy { $0 < $1 })
    }

    /// The strongest tick is the line where letting go reloads, and the one played with a firmer
    /// impact, not some point before it.
    @Test func theStrongestTickLandsOnTheRefreshLine() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: MobileSwipe.pullToRefreshDistance - 0.1)?.isFinal == false)
        let final = haptics.tick(pull: MobileSwipe.pullToRefreshDistance)
        #expect(final?.isFinal == true)
        #expect(final?.intensity == MobilePullHaptics.strongest)
    }

    @Test func pastTheLineThePullIsSilent() {
        let ticks = played([128, 140, 200, 400])
        #expect(ticks.count == 1)
        #expect(ticks.first?.isFinal == true)
    }

    /// A quick pull that jumps over several ticks is one strong tick, not a burst.
    @Test func aFlingPlaysTheTickItReached() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 150)?.isFinal == true)
        #expect(haptics.tick(pull: 160) == nil)
    }

    /// Pushing the pull back up ticks through the detents too, at the same 2 pt cadence.
    @Test func retreatingAndPullingAgainTicksBothWays() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 80) != nil)
        #expect(haptics.tick(pull: 82) != nil)
        #expect(haptics.tick(pull: 81.5) == nil, "inside the 1 pt gap")
        let back = haptics.tick(pull: 80.5)
        #expect(back != nil, "pushing the pull back up ticks")
        #expect(back!.intensity < MobilePullHaptics.strongest)
        #expect(haptics.tick(pull: 82) != nil, "and pulling down again ticks")
    }

    /// The whole pull pushed away gives the first tick once more as it leaves.
    @Test func pushingThePullAllTheWayOutTicksOnceMore() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 24) != nil)
        #expect(haptics.tick(pull: 23.5) == nil, "inside the gap")
        #expect(haptics.tick(pull: 22.9)?.intensity == MobilePullHaptics.faintest)
        #expect(haptics.tick(pull: 0) == nil)
    }

    /// A finger resting on a tick's position must not retrigger it with a point of jitter.
    @Test func jitterAroundATickIsSilent() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 80) != nil)
        #expect(haptics.tick(pull: 79) == nil)
        #expect(haptics.tick(pull: 80) == nil)
        #expect(haptics.tick(pull: 81) == nil)
        #expect(haptics.tick(pull: 79.5) == nil)
    }

    /// A slow pull's last move can land past the line after the tick it last saw, and letting go
    /// from there reloads: the line's tick plays on the release, once.
    @Test func aReleasePastTheLinePlaysTheTickItSkipped() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 126)?.isFinal == false)
        let release = haptics.tickOnRelease(pull: 130)
        #expect(release?.isFinal == true)
        #expect(release?.intensity == MobilePullHaptics.strongest)
        #expect(haptics.tickOnRelease(pull: 130) == nil, "only once")
    }

    @Test func aReleaseShortOfTheLineIsSilent() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 100) != nil)
        #expect(haptics.tickOnRelease(pull: 127) == nil)
        #expect(haptics.tickOnRelease(pull: 0) == nil)
    }

    /// The line's tick already played: the release does not play it a second time.
    @Test func aReleaseOnALineThatTickedIsSilent() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 128)?.isFinal == true)
        #expect(haptics.tickOnRelease(pull: 128) == nil)
    }

    @Test func aNewDragStartsFromSilence() {
        var haptics = MobilePullHaptics()
        #expect(haptics.tick(pull: 60) != nil)
        haptics.reset()
        let first = haptics.tick(pull: 24)
        #expect(first?.intensity == MobilePullHaptics.faintest)
        #expect(first?.isFinal == false)
    }
}
