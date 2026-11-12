import Foundation
import CraCore
import Testing

/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (Settings ▸ Links,
/// optionCommandClickLittleArcEntryPointEnabled): which clicked links open a Little Window.
struct LittleWindowTriggerTests {
    static func opens(_ url: String, optionCommand: Bool = true, _ change: (inout AppSettings) -> Void = { _ in }) -> Bool {
        var s = AppSettings()
        change(&s)
        return LittleWindowTrigger.opens(url, optionCommand: optionCommand, settings: s)
    }

    @Test func aLinkClickedWithOptionCommandHeldOpensOneAndIsOnByDefault() {
        #expect(AppSettings().littleWindowOnOptionCommandClick)
        #expect(Self.opens("https://example.com/a"))
        #expect(Self.opens("http://127.0.0.1:8765/lab.html"))
    }

    @Test func withoutBothKeysOrWithTheSwitchOffItLoadsAsBefore() {
        #expect(!Self.opens("https://example.com/a", optionCommand: false))
        #expect(!Self.opens("https://example.com/a") { $0.littleWindowOnOptionCommandClick = false })
    }

    @Test func onlyPagesATabCanShowOpenOne() {
        #expect(!Self.opens("file:///tmp/a.html"))
        #expect(!Self.opens("cra://settings"))
        #expect(!Self.opens("spotify:track:1"))
        #expect(!Self.opens(""))
    }

    @Test func theSwitchIsKeptInSettingsAndOlderFilesGetTheDefault() throws {
        var s = AppSettings()
        s.littleWindowOnOptionCommandClick = false
        let data = try JSONEncoder().encode(s)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: data).littleWindowOnOptionCommandClick)
        // A settings.json from before the key existed.
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).littleWindowOnOptionCommandClick)
    }
}
