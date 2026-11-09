import CraCore
import Foundation
import Testing

/// A page that accepts the connection and then takes long to answer (GitHub #256).
struct SlowResponseNoticeTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func showsAfterTenSecondsWithoutAResponse() {
        var n = SlowResponseNotice()
        n.update(.waiting, navigation: 1, now: t0)
        #expect(!n.isShown(at: at(9.9)))
        #expect(n.showsAt == at(10))
        #expect(n.isShown(at: at(10)))
        // Still waiting a while later: the clock is the wait's start, not the last update.
        n.update(.waiting, navigation: 1, now: at(16))
        #expect(n.isShown(at: at(16)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func goesWhenThePageAnswersFailsOrStops() {
        // Answered (committed: a slow image after that never brings it back), failed (Cra's error
        // page commits too) or stopped (no longer loading).
        for end in [LoadingIndicator.Phase.loading, .hidden] {
            var n = SlowResponseNotice()
            n.update(.waiting, navigation: 1, now: t0)
            n.update(end, navigation: 1, now: at(12))
            #expect(!n.isShown(at: at(12)))
            #expect(n.showsAt == nil)
            #expect(!n.isShown(at: at(60)))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func aCommittedPageThatKeepsLoadingNeverShowsIt() {
        var n = SlowResponseNotice()
        n.update(.waiting, navigation: 1, now: t0)
        n.update(.loading, navigation: 1, now: at(1))
        n.update(.loading, navigation: 1, now: at(30))
        #expect(!n.isShown(at: at(30)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func closedStaysClosedForThatWaitOnly() {
        var n = SlowResponseNotice()
        n.update(.waiting, navigation: 1, now: t0)
        n.close()
        #expect(!n.isShown(at: at(20)))
        #expect(n.showsAt == nil)
        // The next page waits again: a new clock, and it may show.
        n.update(.loading, navigation: 1, now: at(21))
        n.update(.waiting, navigation: 2, now: at(30))
        #expect(!n.isShown(at: at(39)))
        #expect(n.isShown(at: at(40)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func aNewNavigationWhileWaitingStartsAgain() {
        // Another address typed while the last one is still waiting: no phase change in between.
        var n = SlowResponseNotice()
        n.update(.waiting, navigation: 1, now: t0)
        n.close()
        n.update(.waiting, navigation: 2, now: at(8))
        #expect(!n.isShown(at: at(12)))
        #expect(n.showsAt == at(18))
        #expect(n.isShown(at: at(18)))
    }

    @Test func closeWithNothingWaitingDoesNothing() {
        var n = SlowResponseNotice()
        n.close()
        n.update(.waiting, navigation: 0, now: t0)
        #expect(n.isShown(at: at(10)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/256")) func namesTheSiteItWaitsFor() {
        #expect(SlowResponseNotice.message(for: "http://127.0.0.1:8765/") == "Still waiting for 127.0.0.1 to respond")
        #expect(SlowResponseNotice.message(for: "https://www.Example.com/a?b") == "Still waiting for example.com to respond")
        #expect(SlowResponseNotice.message(for: "https://docs.example.com/") == "Still waiting for docs.example.com to respond")
        #expect(SlowResponseNotice.message(for: "about:blank") == "Still waiting for the page to respond")
        #expect(SlowResponseNotice.message(for: "") == "Still waiting for the page to respond")
    }
}
