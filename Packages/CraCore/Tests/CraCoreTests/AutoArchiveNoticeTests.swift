import CraCore
import Foundation
import Testing

/// Arc's "Auto archived %d tabs" toast. Tabs a pass archived while nobody was there (overnight, or at the launch
/// an automatic update makes) left the sidebar emptier with nothing said, and looked lost (X, 25 Nov 2026).
struct AutoArchiveNoticeTests {
    @Test func saysArcsWordsWithOneTabSingular() {
        #expect(AutoArchiveNotice.text(count: 7) == "Auto archived 7 tabs")
        #expect(AutoArchiveNotice.text(count: 1) == "Auto archived 1 tab")
    }

    @Test func waitsForSomeoneThenSaysEveryPassOnce() {
        var notice = AutoArchiveNotice()
        #expect(notice.take(userPresent: true) == nil, "nothing archived, nothing said")
        // Two passes overnight, nobody there.
        notice.archived(3)
        #expect(notice.take(userPresent: false) == nil)
        notice.archived(2)
        #expect(notice.pending == 5)
        // In the morning, one toast for both.
        #expect(notice.take(userPresent: true) == "Auto archived 5 tabs")
        #expect(notice.pending == 0)
        #expect(notice.take(userPresent: true) == nil, "said once")
        // A pass that archived nothing says nothing.
        notice.archived(0)
        #expect(notice.take(userPresent: true) == nil)
    }

    @Test func someoneIsThereOnlyWithCraActiveAndRecentInput() {
        #expect(AutoArchiveNotice.userPresent(appActive: true, idleSeconds: 5))
        #expect(!AutoArchiveNotice.userPresent(appActive: true, idleSeconds: 8 * 3600), "Cra in front all night")
        #expect(!AutoArchiveNotice.userPresent(appActive: false, idleSeconds: 0), "working in another app")
        #expect(!AutoArchiveNotice.userPresent(appActive: true, idleSeconds: AutoArchiveNotice.presenceWindow))
    }

    @Test func aCountSavedAcrossARestartIsKept() {
        // The app keeps the count in its defaults: an update restart overnight doesn't lose the earlier passes.
        var restored = AutoArchiveNotice(pending: 4)
        #expect(restored.take(userPresent: true) == "Auto archived 4 tabs")
        #expect(AutoArchiveNotice(pending: -1).pending == 0)
    }
}
