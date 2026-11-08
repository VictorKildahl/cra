import CraCore
import Testing

/// A WebKit tab's speaker and now-playing card: on as sound starts, off 2 s after it stops.
struct AudibleHoldTests {
    @Test func soundStartingAnnouncesTheTab() {
        var hold = AudibleHold()
        let r1 = hold.setPlaying(true)
        #expect(r1 == .announce)
        #expect(hold.audible)
    }

    @Test func soundStoppingGoesQuietOnlyAfterTheHold() {
        var hold = AudibleHold()
        _ = hold.setPlaying(true)
        let r2 = hold.setPlaying(false)
        #expect(r2 == .holdThenQuiet)
        #expect(hold.audible, "still audible during the hold")
        let r3 = hold.quietEnded()
        #expect(r3)
        #expect(!hold.audible)
    }

    /// A track change: sound stops and starts again within the hold, and the speaker stays on.
    @Test func soundBackWithinTheHoldStaysAudible() {
        var hold = AudibleHold()
        _ = hold.setPlaying(true)
        _ = hold.setPlaying(false)
        _ = hold.setPlaying(true)
        let q = hold.quietEnded()
        #expect(!q, "the stale hold doesn't silence a playing tab")
        #expect(hold.audible)
    }

    /// Paused from the sidebar's card (which then shows paused) and played again on the page
    /// within 2 s: the card has to hear the tab plays again, though it never went quiet. Before,
    /// the card stayed on paused while the video played (nightly webkit-drm-tabs, 6 Nov 2026).
    @Test func soundBackWithinTheHoldIsAnnouncedAgain() {
        var hold = AudibleHold()
        _ = hold.setPlaying(true)
        _ = hold.setPlaying(false)
        let r4 = hold.setPlaying(true)
        #expect(r4 == .announce)
    }

    /// WebKit repeats "playing" while it plays: one announcement per start, not per report.
    @Test func repeatedPlayingReportsAnnounceOnce() {
        var hold = AudibleHold()
        _ = hold.setPlaying(true)
        let r5 = hold.setPlaying(true)
        #expect(r5 == .nothing)
    }

    @Test func silenceFromTheStartDoesNothing() {
        var hold = AudibleHold()
        let r6 = hold.setPlaying(false)
        #expect(r6 == .nothing)
        let q = hold.quietEnded()
        #expect(!q)
    }
}
