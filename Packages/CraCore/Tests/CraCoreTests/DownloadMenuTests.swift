import CraCore
import Foundation
import Testing

/// Acting on a download from its row: the menu, the paused row, the Library button's ring and
/// the question before quitting (#272).
struct DownloadMenuTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func live(_ id: UInt32, path: String = "/Downloads/big.dmg", received: Int64 = 100, total: Int64 = 400,
              paused: Bool = false, failed: Bool = false, cancelled: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: id, name: (path as NSString).lastPathComponent, path: path, started: t0,
                                  received: received, total: total, percent: 25, updated: t0)
        (l.paused, l.failed, l.cancelled) = (paused, failed, cancelled)
        return l
    }

    /// Arc's Download Context Menu for a finished file; Cancel Download only while one runs.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/272"))
    func finishedFileGetsArcsMenu() {
        let e = DownloadList.Entry(id: UUID(), path: "/Downloads/cat.png", date: t0)
        #expect(DownloadMenu.sections(for: .finished(e), fileExists: { _ in true }) == [[.open, .copy, .showInFinder], [.hide, .moveToTrash]])
        // Gone from disk since: only the row can go.
        #expect(DownloadMenu.sections(for: .finished(e), fileExists: { _ in false }) == [[.hide]])
    }

    /// A running download can be paused and cancelled, a paused one resumed and cancelled; one
    /// that ended without a file can only leave the list.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/272"))
    func liveRowsPauseResumeAndCancel() {
        let exists: (String) -> Bool = { $0 == "/Downloads/big.dmg" }
        #expect(DownloadMenu.sections(for: .live(live(1)), fileExists: exists) == [[.showInFinder], [.pause, .cancel]])
        #expect(DownloadMenu.sections(for: .live(live(1, paused: true)), fileExists: exists) == [[.showInFinder], [.resume, .cancel]])
        // No file yet (the save panel's answer, or Chromium hasn't named it): nothing to show.
        #expect(DownloadMenu.sections(for: .live(live(1, path: "")), fileExists: exists) == [[.pause, .cancel]])
        #expect(DownloadMenu.sections(for: .live(live(1, failed: true)), fileExists: exists) == [[.hide]])
        #expect(DownloadMenu.sections(for: .live(live(1, cancelled: true)), fileExists: exists) == [[.hide]])
    }

    @Test(arguments: [(DownloadMenu.Kind?.some(.image), "photo.heic", "Open Image"), (.pdf, "a.pdf", "Open PDF"),
                      (.zip, "a.zip", "Open Zip Archive"), (nil, "notes.txt", "Open txt"), (nil, "README", "Open File")])
    func openNamesTheKind(kind: DownloadMenu.Kind?, file: String, title: String) {
        #expect(DownloadMenu.title(.open, kind: kind, fileName: file) == title)
    }

    @Test func otherTitles() {
        #expect(DownloadMenu.title(.copy, kind: .diskImage, fileName: "x.dmg") == "Copy Disk Image")
        #expect(DownloadMenu.title(.cancel, kind: nil, fileName: "x") == "Cancel Download")
        #expect(DownloadMenu.title(.pause, kind: nil, fileName: "x") == "Pause Download")
        #expect(DownloadMenu.title(.resume, kind: nil, fileName: "x") == "Resume Download")
        #expect(DownloadMenu.title(.hide, kind: nil, fileName: "x") == "Hide from Cra")
        #expect(DownloadMenu.title(.moveToTrash, kind: nil, fileName: "x") == "Move to Trash")
        #expect(DownloadMenu.title(.showInFinder, kind: nil, fileName: "x") == "Show in Finder")
    }

    /// Arc tests the kinds in its order, so a zip reads "Zip Archive", not "Archive".
    @Test func kindsInArcsOrder() {
        #expect(DownloadMenu.Kind.first { [.zip, .archive].contains($0) } == .zip)
        #expect(DownloadMenu.Kind.first { _ in false } == nil)
    }

    /// A paused download says so, as Arc's row does, and is still in progress.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/272"))
    func pausedRow() {
        let l = live(1, paused: true)
        #expect(l.row == .paused)
        #expect(DownloadRow.subtitle(l.row, now: t0) == "Paused")
        #expect(l.running)
    }

    /// The Library button's ring: every running download's bytes together, paused ones too.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/272"))
    func ringProgress() {
        #expect(DownloadList.progress([]) == nil)
        #expect(DownloadList.progress([live(1, failed: true), live(2, cancelled: true)]) == nil)
        #expect(DownloadList.progress([live(1, received: 100, total: 400), live(2, received: 300, total: 400, paused: true)]) == 0.5)
        // Unknown size: counted as nothing yet, never past the end.
        #expect(DownloadList.progress([live(1, received: 50, total: -1)]) == 0)
        #expect(DownloadList.progress([live(1, received: 500, total: 400)]) == 1)
    }

    /// Quitting while a download runs asks Arc's "Downloads in progress" instead of "Quit Cra?";
    /// restarts into an update or another engine ask nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/272"))
    func quitAsksAboutDownloads() {
        #expect(QuitPrompt.on(source: .appMenu, downloadsRunning: true, warnBeforeQuitting: true) == .downloadsInProgress)
        #expect(QuitPrompt.on(source: .appleEvent, downloadsRunning: true, warnBeforeQuitting: false) == .downloadsInProgress)
        #expect(QuitPrompt.on(source: .menuBarItem, downloadsRunning: true, warnBeforeQuitting: false) == .downloadsInProgress)
        #expect(QuitPrompt.on(source: .relaunch, downloadsRunning: true, warnBeforeQuitting: true) == .none)
        #expect(QuitPrompt.on(source: .appMenu, downloadsRunning: false, warnBeforeQuitting: true) == .confirmQuit)
        #expect(QuitPrompt.on(source: .appMenu, downloadsRunning: false, warnBeforeQuitting: false) == .none)
    }
}
