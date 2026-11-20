import CraCore
import Testing

/// Arc's Library shortcuts are show/hide toggles (GitHub #649).
struct LibraryShortcutTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/649"))
    func openLibraryTogglesTheLibrary() {
        #expect(LibraryShortcut.step(requested: String?.none, shown: String?.none) == .show)
        #expect(LibraryShortcut.step(requested: String?.none, shown: "media") == .close)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/649"))
    func viewDownloadsClosesItsOwnPageAndGoesToItFromAnother() {
        #expect(LibraryShortcut.step(requested: "downloads", shown: String?.none) == .show)
        #expect(LibraryShortcut.step(requested: "downloads", shown: "downloads") == .close)
        #expect(LibraryShortcut.step(requested: "downloads", shown: "media") == .show)
    }
}
