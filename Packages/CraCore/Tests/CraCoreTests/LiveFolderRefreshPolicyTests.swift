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

    @Test func gitLabFailuresNeverRetryAutomatically() {
        let lastFetch = Date(timeIntervalSince1970: 100)
        for error in [LiveFolderError.network, .notSignedIn, .rateLimited, .unexpectedPage] {
            for elapsed: TimeInterval in [0, 30, 120, 3600, 86400] {
                #expect(!LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: lastFetch, lastError: error,
                                                             now: lastFetch.addingTimeInterval(elapsed), trigger: .automatic))
            }
            #expect(!LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: nil, lastError: error,
                                                         now: lastFetch, trigger: .automatic))
        }
    }

    @Test func gitLabFailuresAllowManualRefreshAndConfigurationChanges() {
        let now = Date(timeIntervalSince1970: 100)
        for error in [LiveFolderError.network, .notSignedIn, .rateLimited, .unexpectedPage] {
            for trigger in [LiveFolderRefreshPolicy.Trigger.manual, .configuration] {
                #expect(LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: now, lastError: error,
                                                            now: now, trigger: trigger))
            }
        }
    }

    @Test func gitLabSuccessfulRefreshAllowsAutomaticUpdatesAgain() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(!LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: now, lastError: .network,
                                                     now: now.addingTimeInterval(120), trigger: .automatic))
        #expect(LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: now, lastError: nil,
                                                    now: now.addingTimeInterval(120), trigger: .automatic))
        #expect(!LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: now, lastError: nil,
                                                     now: now, trigger: .automatic))
        #expect(LiveFolderRefreshPolicy.shouldStart(source: .gitlab, lastFetch: nil, lastError: nil,
                                                    now: now, trigger: .automatic))
    }

    @Test func gitHubRetryBehaviourIsUnchanged() {
        let now = Date(timeIntervalSince1970: 100)
        for error in [LiveFolderError.network, .notSignedIn, .rateLimited, .unexpectedPage] {
            #expect(LiveFolderRefreshPolicy.shouldStart(source: .github, lastFetch: now, lastError: error,
                                                        now: now, trigger: .automatic))
        }
    }
}
