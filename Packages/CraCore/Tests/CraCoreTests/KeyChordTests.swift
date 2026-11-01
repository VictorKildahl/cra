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
        // Caps Lock and the function-key bit are kept in the file but never shown.
        (KeyChord(key: "d", modifiers: command | 0x10000 | 0x800000), "⌘D"),
    ])
    func display(chord: KeyChord, shown: String) {
        #expect(chord.display == shown)
    }

    @Test func keysReadsTheStoredBits() {
        let chord = KeyChord(key: "s", modifiers: Self.command | KeyChord.Modifiers.shift.rawValue)
        #expect(chord.keys == KeyChord.Modifiers([.command, .shift]))
    }
}
