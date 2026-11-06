import Foundation
import CraCore
import Testing

struct LiveFolderRefreshPolicyTests {
    @Test func manualRefreshWorksImmediatelyAfterAnAutomaticRefresh() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(LiveFolderRefreshPolicy.shouldStart(lastFetch: now, lastError: nil, now: now, trigger: .manual))
        #expect(!LiveFolderRefreshPolicy.shouldStart(lastFetch: now, lastError: nil, now: now, trigger: .automatic))
        #expect(LiveFolderRefreshPolicy.shouldStart(lastFetch: now, lastError: nil, now: now.addingTimeInterval(10), trigger: .automatic))
    }

    @Test func fastManualResponsesStillHaveVisibleFeedback() {
        let start = Date(timeIntervalSince1970: 100)
        let delay = LiveFolderRefreshPolicy.feedbackDelay(startedAt: start, now: start.addingTimeInterval(0.05))
        #expect(delay >= 0.3 && delay <= 0.5)
        #expect(LiveFolderRefreshPolicy.feedbackDelay(startedAt: start, now: start.addingTimeInterval(1)) == 0)
        #expect(LiveFolderRefreshPolicy.feedbackDelay(startedAt: nil, now: start) == 0)
    }
}
