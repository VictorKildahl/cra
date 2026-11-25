import CraCore
import Foundation
import Testing

/// Screenshots in the downloads list, as Arc's Library button had them: the ones the system took
/// lately show up by themselves next to the downloads (byearc's "Screenshots in Library").
struct ScreenshotFeedTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func shot(_ name: String, minutesAgo m: Double, folder: String = "/Users/me/Desktop") -> ScreenshotFeed.Shot {
        .init(path: folder + "/" + name, date: now.addingTimeInterval(-m * 60))
    }

    /// The last day's screenshots and screen recordings show, oldest first; older ones, hidden ones,
    /// the system's dotted file while it is still being written, and other kinds don't.
    @Test func listsTheLastDaysScreenshotsOnly() {
        let shots = [
            shot("Screenshot 2026-11-25 at 20.10.00.png", minutesAgo: 5),
            shot("Screen Recording 2026-11-25 at 19.00.00.mov", minutesAgo: 70),
            shot("Screenshot 2026-11-24 at 09.00.00.png", minutesAgo: 25 * 60),
            shot("Hidden one.png", minutesAgo: 2),
            shot(".Screenshot 2026-11-25 at 20.14.00.png", minutesAgo: 1),
            shot("Screenshot.txt", minutesAgo: 3),
            shot("Shot moved to Pictures.heic", minutesAgo: 10, folder: "/Users/me/Pictures"),
        ]
        let rows = ScreenshotFeed.entries(shots, enabled: true, hidden: ["/Users/me/Desktop/Hidden one.png"], downloads: [], now: now)
        #expect(rows.map(\.name) == ["Screen Recording 2026-11-25 at 19.00.00.mov", "Shot moved to Pictures.heic",
                                     "Screenshot 2026-11-25 at 20.10.00.png"])
        #expect(rows.last?.date == now.addingTimeInterval(-300))
    }

    /// Unticking Screenshots in the Library button's "Show media" menu takes them out of the list
    /// (Arc's source preference); it is ticked by default, and Library ▸ Media's own Show Media
    /// switch, off by default, doesn't matter.
    @Test func showMediaScreenshotsTickTurnsItOff() {
        let shots = [shot("Screenshot a.png", minutesAgo: 1)]
        #expect(ScreenshotFeed.enabled(folders: MediaLibrary.Folder.allCases))
        #expect(!ScreenshotFeed.enabled(folders: [.desktop, .downloads]))
        #expect(ScreenshotFeed.entries(shots, enabled: false, hidden: [], downloads: [], now: now).isEmpty)
        #expect(AppSettings().mediaFolders.contains(.screenshots) && !AppSettings().mediaLibraryEnabled)
    }

    /// A row keeps its id while Spotlight reports the file again, so the list doesn't redraw it as new;
    /// a file reported twice is one row, and one already listed as a download isn't listed again.
    @Test func oneStableRowPerFile() {
        let a = shot("Screenshot a.png", minutesAgo: 3)
        let dl = DownloadList.Entry(id: UUID(), path: "/Users/me/Desktop/Screenshot b.png", date: now)
        let rows = ScreenshotFeed.entries([a, a, shot("Screenshot b.png", minutesAgo: 1)], enabled: true, hidden: [], downloads: [dl], now: now)
        #expect(rows.map(\.name) == ["Screenshot a.png"])
        #expect(rows[0].id == ScreenshotFeed.id(for: a.path))
        #expect(ScreenshotFeed.id(for: a.path) != ScreenshotFeed.id(for: "/Users/me/Desktop/Screenshot b.png"))
    }

    /// In the tray a screenshot takes its place among the downloads by date, as a finished file
    /// (draggable, with Open, Copy, Show in Finder), and the tray still shows the newest few.
    @Test func trayMixesScreenshotsWithDownloadsByDate() {
        let d1 = DownloadList.Entry(id: UUID(), path: "/Downloads/old.zip", date: now.addingTimeInterval(-3600))
        let d2 = DownloadList.Entry(id: UUID(), path: "/Downloads/new.pdf", date: now.addingTimeInterval(-60))
        let shots = ScreenshotFeed.entries([shot("Screenshot a.png", minutesAgo: 10), shot("Screenshot gone.png", minutesAgo: 5)],
                                           enabled: true, hidden: [], downloads: [d1, d2], now: now)
        let rows = DownloadList.tray(entries: [d1, d2], live: [], screenshots: shots, limit: 2,
                                     fileExists: { !$0.hasSuffix("gone.png") })
        #expect(rows.map(\.name) == ["Screenshot a.png", "new.pdf"])
        guard case .finished = rows[0] else { Issue.record("a screenshot is a finished file"); return }
        #expect(DownloadMenu.sections(for: rows[0], fileExists: { _ in true }).first == [.open, .copy, .showInFinder])
    }
}
