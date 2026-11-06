import CraCore
import Foundation
import Testing

/// Arc's per-profile Download location (#190) and the name a download is saved as.
struct DownloadLocationTests {
    let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)

    @Test func profilesWithoutAChoiceUseDownloadsWithoutAsking() {
        let s = AppSettings()
        #expect(s.downloadLocation(profileID: nil) == DownloadLocation())
        #expect(s.downloadLocation(profileID: UUID()).folderURL(downloads: downloads) { _ in true } == downloads)
    }

    @Test func eachProfileKeepsItsOwn() throws {
        var s = AppSettings()
        let work = UUID()
        s.setDownloadLocation(DownloadLocation(folder: "/Volumes/Work", askWhereToSave: false), profileID: work)
        s.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        #expect(s.downloadLocation(profileID: work).folder == "/Volumes/Work")
        #expect(s.downloadLocation(profileID: nil).askWhereToSave)
        #expect(s.downloadLocation(profileID: UUID()) == DownloadLocation())
        // Saved and loaded again.
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.downloadLocations == s.downloadLocations)
        #expect(Set(back.downloadLocations.keys) == [work.uuidString, "Default"])
    }

    @Test func goingBackToTheDefaultDropsTheEntry() {
        var s = AppSettings()
        s.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        s.setDownloadLocation(DownloadLocation(), profileID: nil)
        #expect(s.downloadLocations.isEmpty)
    }

    @Test func aMissingFolderFallsBackToDownloads() {
        let l = DownloadLocation(folder: "/Volumes/Unplugged")
        #expect(l.folderURL(downloads: downloads) { _ in false } == downloads)
        #expect(l.folderURL(downloads: downloads) { _ in true }.path == "/Volumes/Unplugged")
    }

    @Test func aRelativeFolderInTheFileIsIgnored() throws {
        let json = #"{"downloadLocations": {"Default": {"folder": "../etc", "askWhereToSave": true}, "x": 3}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        // A bad entry drops the whole map rather than the settings file.
        #expect(s.downloadLocations.isEmpty)
        let one = try JSONDecoder().decode(DownloadLocation.self, from: Data(#"{"folder": "../etc"}"#.utf8))
        #expect(one.folder == nil && !one.askWhereToSave)
    }

    @Test(arguments: [
        ("report.pdf", "report.pdf"),
        ("../../.ssh/config", "-..-.ssh-config"),
        (".hidden", "hidden"),
        ("a:b/c.txt", "a-b-c.txt"),
        ("   ", "download"),
        ("", "download"),
    ])
    func names(suggested: String, saved: String) {
        let url = DownloadFileName.unique(suggested, in: downloads) { _ in false }
        #expect(url.lastPathComponent == saved)
        #expect(url.deletingLastPathComponent().path == downloads.path)
    }

    @Test func takenNamesGetANumber() {
        let taken: Set = ["/Users/me/Downloads/a.zip", "/Users/me/Downloads/a (1).zip", "/Users/me/Downloads/README"]
        #expect(DownloadFileName.unique("a.zip", in: downloads) { taken.contains($0) }.lastPathComponent == "a (2).zip")
        #expect(DownloadFileName.unique("README", in: downloads) { taken.contains($0) }.lastPathComponent == "README (1)")
    }
}
