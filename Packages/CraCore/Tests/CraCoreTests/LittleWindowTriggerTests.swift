import Foundation
import CraCore
import Testing

/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (Settings ▸ Links,
/// optionCommandClickLittleArcEntryPointEnabled): which clicked links open a Little Window. The keys
/// are the click's own (the page's last mouse-up or Return), not the ones held when Chromium asks.
struct LittleWindowTriggerTests {
    static let option = KeyChord.Modifiers.option.rawValue
    static let command = KeyChord.Modifiers.command.rawValue
    static let shift = KeyChord.Modifiers.shift.rawValue
    static let control = KeyChord.Modifiers.control.rawValue
    /// Caps Lock (NSEvent.ModifierFlags.capsLock) and Fn (.function).
    static let capsLock: UInt = 1 << 16
    static let function: UInt = 1 << 23
    static let link = "https://example.com/a"

    static func opens(_ url: String = link, keys: UInt = option | command, age: TimeInterval = 0.05,
                      _ change: (inout AppSettings) -> Void = { $0.littleWindowOnOptionCommandClick = true }) -> Bool {
        var s = AppSettings()
        change(&s)
        return LittleWindowTrigger.opens(url, clickModifiers: keys, clickAge: age, enabled: s.littleWindowOnOptionCommandClick)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func aLinkClickedWithOptionCommandOpensOneWhenTheSwitchIsOn() {
        #expect(Self.opens())
        #expect(Self.opens("http://127.0.0.1:8765/lab.html", age: 0))
        // Caps Lock or Fn held as well still is a ⌥⌘-click.
        #expect(Self.opens(keys: Self.option | Self.command | Self.capsLock | Self.function))
        // The switch off: Chromium's own ⌘⌥-click, Split View (#298).
        #expect(!Self.opens { $0.littleWindowOnOptionCommandClick = false })
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func theKeysAreTheClicksNotTheOnesHeldWhenChromiumAsks() {
        // A plain click, a ⌘-click (a background tab) and an Option-click (Split View) stay what they are,
        // even when ⌥⌘ are down by the time Chromium's callback arrives.
        #expect(!Self.opens(keys: 0))
        #expect(!Self.opens(keys: Self.command))
        #expect(!Self.opens(keys: Self.option))
        // ⇧ or ⌃ as well make it another click (Peek, a right-click).
        #expect(!Self.opens(keys: Self.option | Self.command | Self.shift))
        #expect(!Self.opens(keys: Self.option | Self.command | Self.control))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func onlyAClickInThisPageJustNowCounts() {
        #expect(Self.opens(age: LinkSplitClick.freshness))
        #expect(!Self.opens(age: LinkSplitClick.freshness + 0.01), "a page's own window.open long after the click")
        #expect(!Self.opens(age: -1), "the last click was in another page or window")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func onlyPagesATabCanShowOpenOne() {
        #expect(!Self.opens("file:///tmp/a.html"))
        #expect(!Self.opens("cra://settings"))
        #expect(!Self.opens("spotify:track:1"))
        #expect(!Self.opens(""))
    }

    /// Off by default, unlike Arc: since 0.1.38 a ⌘⌥-click opens Split View (#298, Chromium 156's split
    /// view click), and the switch would take that click over.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func theSwitchIsKeptInSettingsAndOlderFilesGetTheDefault() throws {
        #expect(!AppSettings().littleWindowOnOptionCommandClick)
        var s = AppSettings()
        s.littleWindowOnOptionCommandClick = true
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).littleWindowOnOptionCommandClick)
        // A settings.json from before the key existed.
        #expect(try !JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).littleWindowOnOptionCommandClick)
    }
}
