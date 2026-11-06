import CraCore
import Foundation
import Testing

/// Hidden tabs whose page windows draw once so Chromium's evicted frames release their tiles (#195).
struct HiddenFrameReleaseTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func tab(_ n: Int, minutesAgo: Double, released: Bool = false) -> HiddenFrameRelease.Tab {
        let hidden = now.addingTimeInterval(-minutesAgo * 60)
        return .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, hiddenAt: hidden, releasedFor: released ? hidden : nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func recentTabsWithinTheCapKeepTheirFrames() {
        let hidden = (1...9).map { tab($0, minutesAgo: Double($0)) }
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now).isEmpty)
    }

    /// Chromium keeps the 10 most recent frames (the visible tab's among them); older ones are evicted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func tabsPastTheCapAreDueOldestFirst() {
        let hidden = (1...12).map { tab($0, minutesAgo: Double($0) / 10) }
        let due = HiddenFrameRelease.due(hidden, visible: 1, now: now)
        #expect(due == hidden.suffix(3).map(\.id))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func tabsHiddenLongerThanTheCullAreDue() {
        let hidden = [tab(1, minutesAgo: 3), tab(2, minutesAgo: 11)]
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now) == [hidden[1].id])
    }

    /// Once drawn for this hiding, a tab isn't done again until it has been shown and hidden again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func eachHidingReleasesOnce() {
        let hidden = [tab(1, minutesAgo: 20, released: true), tab(2, minutesAgo: 20)]
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now) == [hidden[1].id])
    }
}
