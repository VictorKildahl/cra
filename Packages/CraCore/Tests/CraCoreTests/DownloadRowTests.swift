import CraCore
import Foundation
import Testing

/// Downloads show their progress and failures in the downloads list, as in Arc (#85 follow-up).
struct DownloadRowTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func runningShowsProgressAndSpeed() {
        let s = DownloadRow.subtitle(.downloading(received: 3_000_000, total: 10_000_000, bytesPerSecond: 1_500_000), now: now)
        #expect(s == "3 MB of 10 MB — 1.5 MB/s")
        #expect(DownloadRow.subtitle(.downloading(received: 3_000_000, total: -1, bytesPerSecond: nil), now: now) == "3 MB")
    }

    @Test func failedAndCancelled() {
        #expect(DownloadRow.subtitle(.failed, now: now) == "Failed to Download")
        #expect(DownloadRow.subtitle(.cancelled, now: now) == "Cancelled")
    }

    @Test func finishedShowsItsAge() {
        #expect(DownloadRow.subtitle(.finished(at: now.addingTimeInterval(-54)), now: now) == "54 seconds ago")
        // Just finished, or a clock that ran backwards: never "in 0 seconds".
        #expect(DownloadRow.subtitle(.finished(at: now), now: now) == "1 second ago")
        #expect(DownloadRow.subtitle(.finished(at: now.addingTimeInterval(2)), now: now) == "1 second ago")
    }

    @Test(arguments: [(Int64(980), "980 bytes"), (12_400, "12 KB"), (3_000_000, "3 MB"), (1_540_000_000, "1.5 GB"), (999_960, "1 MB")])
    func sizesInEnglish(n: Int64, text: String) {
        #expect(DownloadRow.bytes(n) == text)
    }

    @Test func speedNeedsASpanAndGrowth() {
        #expect(DownloadRow.speed(fromBytes: 0, at: now, toBytes: 1_000, at: now.addingTimeInterval(0.1)) == nil)
        #expect(DownloadRow.speed(fromBytes: 1_000, at: now, toBytes: 500, at: now.addingTimeInterval(1)) == nil)
        #expect(DownloadRow.speed(fromBytes: 0, at: now, toBytes: 2_000, at: now.addingTimeInterval(2)) == 1_000)
    }
}
