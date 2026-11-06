import CraCore
import Testing

struct KeyChordTests {
    static let command = KeyChord.Modifiers.command.rawValue

    /// NSEvent.ModifierFlags' raw values, which keybindings.json has always stored.
    @Test func modifierBitsAreAppKits() {
        #expect(KeyChord.Modifiers.shift.rawValue == 0x20000)
        #expect(KeyChord.Modifiers.control.rawValue == 0x40000)
        #expect(KeyChord.Modifiers.option.rawValue == 0x80000)
        #expect(KeyChord.Modifiers.command.rawValue == 0x100000)
        #expect(KeyChord.left.unicodeScalars.map(\.value) == [0xF702] && KeyChord.right.unicodeScalars.map(\.value) == [0xF703])
        #expect(KeyChord.up.unicodeScalars.map(\.value) == [0xF700] && KeyChord.down.unicodeScalars.map(\.value) == [0xF701])
    }

    @Test(arguments: [
        (KeyChord(key: "t", modifiers: command), "⌘T"),
        (KeyChord(key: "[", modifiers: command | KeyChord.Modifiers.shift.rawValue), "⇧⌘["),
        (KeyChord(key: KeyChord.tab, modifiers: KeyChord.Modifiers.control.rawValue), "⌃⇥"),
        (KeyChord(key: KeyChord.left, modifiers: command | KeyChord.Modifiers.option.rawValue), "⌥⌘←"),
        (KeyChord(key: KeyChord.right, modifiers: command), "⌘→"),
        (KeyChord(key: KeyChord.up, modifiers: KeyChord.Modifiers([.control, .option, .shift, .command]).rawValue), "⌃⌥⇧⌘↑"),
        (KeyChord(key: KeyChord.down, modifiers: 0), "↓"),
        // Chrome's Clear Browsing Data; menus take the Delete key as NSBackspaceCharacter.
        (KeyChord(key: KeyChord.delete, modifiers: command | KeyChord.Modifiers.shift.rawValue), "⇧⌘⌫"),
        // Caps Lock and the function-key bit are kept in the file but never shown.
        (KeyChord(key: "d", modifiers: command | 0x10000 | 0x800000), "⌘D"),
    ])
    func display(chord: KeyChord, shown: String) {
        #expect(chord.display == shown)
    }

    /// A tooltip's key caps: one per modifier, then the key (Arc's space tip shows ⌃ and 3).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/152"))
    func capsSplitTheDisplay() {
        #expect(KeyChord(key: "3", modifiers: KeyChord.Modifiers.control.rawValue).caps == ["⌃", "3"])
        #expect(KeyChord(key: "l", modifiers: Self.command | KeyChord.Modifiers.shift.rawValue).caps == ["⇧", "⌘", "L"])
        #expect(KeyChord(key: KeyChord.left, modifiers: KeyChord.Modifiers([.control, .option]).rawValue).caps == ["⌃", "⌥", "←"])
    }

    @Test func keysReadsTheStoredBits() {
        let chord = KeyChord(key: "s", modifiers: Self.command | KeyChord.Modifiers.shift.rawValue)
        #expect(chord.keys == KeyChord.Modifiers([.command, .shift]))
    }

    /// ⌘Return opens the command bar's row in a background tab (GitHub #85).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/85"), arguments: [
        (UInt16(36), command, true),                      // ⌘Return
        (76, command, true),                              // ⌘Enter on the keypad
        (36, command | 0x10000 | 0x800000, true),         // Caps Lock and the function-key bit don't count
        (36, 0, false),                                   // Return
        (36, command | KeyChord.Modifiers.shift.rawValue, false),
        (36, command | KeyChord.Modifiers.option.rawValue, false),
        (36, KeyChord.Modifiers.control.rawValue, false),
        (37, command, false),                             // ⌘L
    ])
    func commandReturn(keyCode: UInt16, modifiers: UInt, matches: Bool) {
        #expect(KeyChord.isCommandReturn(keyCode: keyCode, modifiers: modifiers) == matches)
    }
}
