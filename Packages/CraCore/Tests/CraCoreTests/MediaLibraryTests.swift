import CraCore
import Foundation
import Testing

/// Arc's Library ▸ Media (Arc 1.172.1, offline Arc on a fake home, 7 Nov 2026): screenshots on
/// the Desktop and photos in Downloads, newest first, two to a row, no date headers.
struct MediaLibraryTests {
    static func file(_ path: String, _ minutesAgo: Double) -> MediaLibrary.File {
        .init(path: path, date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    }

    @Test func newestFirstAndOnlyMedia() {
        let files = [Self.file("/d/Screenshot 1.png", 30), Self.file("/d/notes.txt", 1), Self.file("/dl/photo.JPG", 5),
                     Self.file("/dl/clip.mov", 60), Self.file("/d/.hidden.png", 0), Self.file("/doc/report.pdf", 2)]
        #expect(MediaLibrary.shown(files, query: "").map(\.name) == ["photo.JPG", "Screenshot 1.png", "clip.mov"])
    }

    @Test func aFolderListedTwiceShowsItsFilesOnce() {
        let shot = Self.file("/Users/me/Desktop/Screenshot.png", 3)
        #expect(MediaLibrary.shown([shot, shot], query: "").count == 1)
    }

    @Test func searchesFileNames() {
        let files = [Self.file("/d/Screenshot 1.png", 30), Self.file("/dl/photo.jpg", 5)]
        #expect(MediaLibrary.shown(files, query: " SCREEN ").map(\.name) == ["Screenshot 1.png"])
    }

    @Test func twoToARow() {
        let files = (0..<5).map { Self.file("/d/\($0).png", Double($0)) }
        #expect(MediaLibrary.rows(files).map(\.count) == [2, 2, 1])
    }

    @Test func keepsTheNewestWhenThereAreTooMany() {
        let files = (0..<10).map { Self.file("/d/\($0).png", Double($0)) }
        #expect(MediaLibrary.shown(files, query: "", limit: 3).map(\.name) == ["0.png", "1.png", "2.png"])
    }
}
