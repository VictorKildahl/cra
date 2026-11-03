import CraCore
import Testing

/// Arc's loading bar (Arc 1.171 screen recording, 2 Nov 2026).
struct LoadingIndicatorTests {
    func ends(at time: Double) -> [Double] {
        let s = LoadingIndicator.sweep(at: time)
        return [s.start, s.end].map { ($0 * 100).rounded() / 100 }
    }

    @Test func phaseFollowsLoadingAndCommit() {
        #expect(LoadingIndicator.Phase(isLoading: false, committed: false) == .hidden)
        #expect(LoadingIndicator.Phase(isLoading: false, committed: true) == .hidden)
        #expect(LoadingIndicator.Phase(isLoading: true, committed: false) == .waiting)
        #expect(LoadingIndicator.Phase(isLoading: true, committed: true) == .loading)
    }

    @Test func headSweepsThenTailThenGap() {
        #expect(ends(at: 0) == [0, 0])
        #expect(ends(at: 0.185) == [0, 0.5])
        #expect(ends(at: 0.37) == [0, 1])
        #expect(ends(at: 0.555) == [0.5, 1])
        #expect(ends(at: 0.9) == [1, 1])
        // The cycle repeats.
        #expect(ends(at: LoadingIndicator.sweepPeriod + 0.185) == [0, 0.5])
    }

    @Test func keyframesRunInOrderOverOneCycle() {
        for times in [LoadingIndicator.sweepKeyframes.map(\.time), LoadingIndicator.pulseKeyframes.map(\.time)] {
            #expect(times.first == 0)
            #expect(times.last == 1)
            #expect(times == times.sorted())
        }
        // A widening pill joins the sweep lit end to end.
        #expect(ends(at: LoadingIndicator.sweepTailStart * LoadingIndicator.sweepPeriod) == [0, 1])
    }
}
