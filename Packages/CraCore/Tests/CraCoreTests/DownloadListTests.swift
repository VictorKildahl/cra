import CraCore
import Foundation
import Testing

/// What the downloads tray and Library ▸ Downloads list.
struct DownloadListTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func entry(_ name: String, at s: TimeInterval) -> DownloadList.Entry {
        DownloadList.Entry(id: UUID(), path: "/Downloads/" + name, date: t0.addingTimeInterval(s))
    }

    func live(_ id: UInt32, _ name: String, at s: TimeInterval, failed: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: id, name: name, path: "", started: t0.addingTimeInterval(s), received: 172_200_000,
                                  total: 257_100_000, percent: 66, updated: t0.addingTimeInterval(s))
        l.failed = failed
        return l
    }

    /// A download still running shows on Library ▸ Downloads, not only in the tray, with the ones
    /// that failed this session; newest first, next to the finished files still on disk.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/245"))
    func libraryListsRunningDownloads() {
        let old = entry("report.pdf", at: 0), gone = entry("deleted.zip", at: 10), done = entry("photo.jpg", at: 20)
        let rows = DownloadList.library(entries: [old, gone, done], live: [live(7, "big.dmg", at: 30), live(8, "broken.iso", at: 5, failed: true)],
                                        query: "", fileExists: { $0 != gone.path })
        #expect(rows.map(\.name) == ["big.dmg", "photo.jpg", "broken.iso", "report.pdf"])
        #expect(rows.first == .live(live(7, "big.dmg", at: 30)))
    }

    @Test func librarySearchMatchesRunningAndFinishedNames() {
        let rows = DownloadList.library(entries: [entry("Invoice-March.pdf", at: 0), entry("cat.png", at: 1)],
                                        live: [live(1, "invoice-april.pdf", at: 2)], query: " INVOICE ", fileExists: { _ in true })
        #expect(rows.map(\.name) == ["invoice-april.pdf", "Invoice-March.pdf"])
    }

    /// The tray keeps the newest few, oldest at the top, live rows included (Arc's tray).
    @Test func trayKeepsTheNewestOldestFirst() {
        let rows = DownloadList.tray(entries: [entry("a", at: 0), entry("b", at: 1), entry("c", at: 3)], live: [live(1, "d", at: 2)],
                                     limit: 3, fileExists: { $0 != "/Downloads/c" })
        #expect(rows.map(\.name) == ["a", "b", "d"])
    }
}
