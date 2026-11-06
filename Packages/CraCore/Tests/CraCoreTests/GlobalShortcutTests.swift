import CraCore
import Testing

/// New Little Window's shortcut from any app (Arc's "Open Little Arc when I press ⌥⌘N", GitHub #195).
struct GlobalShortcutTests {
    private let optCmdN = KeyChord(key: "n", modifiers: KeyChord.Modifiers([.option, .command]).rawValue)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func theFirstChordIsTakenWhileTheSettingIsOn() {
        #expect(GlobalShortcut.registrable([optCmdN], enabled: true) == optCmdN)
        #expect(GlobalShortcut.registrable([optCmdN], enabled: false) == nil)
        #expect(GlobalShortcut.registrable([], enabled: true) == nil)
    }

    /// A key without ⌘, ⌃ or ⌥ would stop typing that key in every app.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func aChordThatTypesIsNeverTakenFromOtherApps() {
        let shiftN = KeyChord(key: "n", modifiers: KeyChord.Modifiers.shift.rawValue)
        let tab = KeyChord(key: KeyChord.tab, modifiers: 0)
        #expect(GlobalShortcut.registrable([shiftN, tab], enabled: true) == nil)
        #expect(GlobalShortcut.registrable([shiftN, optCmdN], enabled: true) == optCmdN)
        let ctrlSpace = KeyChord(key: " ", modifiers: KeyChord.Modifiers.control.rawValue)
        #expect(GlobalShortcut.registrable([ctrlSpace], enabled: true) == ctrlSpace)
    }

    /// Carbon's cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func modifiersInCarbonBits() {
        #expect(GlobalShortcut.carbonModifiers([.option, .command]) == 0x900)
        #expect(GlobalShortcut.carbonModifiers([.shift, .control]) == 0x1200)
        #expect(GlobalShortcut.carbonModifiers([]) == 0)
    }
}
