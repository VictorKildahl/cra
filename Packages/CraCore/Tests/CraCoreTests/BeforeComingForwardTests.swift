import CraCore
import Foundation
import Testing

/// What was in use when Cra came forward for a link from another app.
struct BeforeComingForwardTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    let stack = [StackedWindow(number: 7, pid: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600))]

    /// A link from Slack brought Cra forward and AppKit made the full-screen Personal window key on
    /// the way: the window in use is still the work one, so the Little Window opens in its space
    /// and profile, not in Default.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/764")) func aLinkArrivingAsCraComesForwardKeepsTheWindowInUseBefore() {
        let before = BeforeComingForward(at: Self.t0, stack: stack, window: work)
        #expect(before.forLink(at: Self.t0 + 0.02, craActive: true) == before)
        #expect(before.forLink(at: Self.t0 + FrontmostAppHistory.linkGrace, craActive: true)?.window == work)
    }

    /// Cra came forward a while ago (the user is in it) or is not in front: what AppKit did then was
    /// the user's, and the window in use now counts.
    @Test func otherwiseTheWindowInUseNowCounts() {
        let before = BeforeComingForward(at: Self.t0, stack: stack, window: work)
        #expect(before.forLink(at: Self.t0 + FrontmostAppHistory.linkGrace + 0.1, craActive: true) == nil)
        #expect(before.forLink(at: Self.t0 + 0.02, craActive: false) == nil)
    }
}
