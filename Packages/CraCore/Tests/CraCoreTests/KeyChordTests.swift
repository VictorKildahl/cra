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

    // MARK: Key presses

    static let shift = KeyChord.Modifiers.shift.rawValue
    /// Cra's View menu, in the order the registry lists it.
    static let zoom: [(id: String, chords: [KeyChord])] = [
        ("resetZoom", [KeyChord(key: "0", modifiers: command)]),
        ("zoomIn", [KeyChord(key: "=", modifiers: command), KeyChord(key: "=", modifiers: command | shift)]),
        ("zoomOut", [KeyChord(key: "-", modifiers: command)]),
        ("back", [KeyChord(key: "[", modifiers: command)]),
    ]
    /// What Turkish-QWERTY-PC types without ⌥ (UCKeyTranslate, macOS 26): "=" is ⇧0, "-" sits
    /// on the ANSI "=" key, "*" on the ANSI "-" key, "[" and "]" need ⌥.
    static let turkishQ: Set<String> = Set("1234567890*-qwertyuıopğüasdfghjklşi,zxcvbnmöç.\"!'^+%&/()=?_é<>;:".map(String.init))
    /// Danish: "+" on the ANSI "-" key, "-" on the ANSI "/" key, "[" is ⌥8.
    static let danish: Set<String> = Set("1234567890+´qwertyuiopå¨asdfghjklæø'zxcvbnm,.-<>!\"#€%&/()=?`^*;:_".map(String.init))

    static func pressed(_ chars: String, _ code: UInt16, _ mods: UInt, on layout: Set<String>) -> String? {
        KeyChord.first(in: zoom, chords: \.chords, press: .init(characters: chars, keyCode: code, modifiers: mods),
                       typable: { layout.contains($0) })?.id
    }

    /// Turkish Q: each zoom key does what the View menu says, and no other key zooms (GitHub #212).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/212"), arguments: [
        ("-", UInt16(24), command, "zoomOut"),         // ⌘- (the ANSI "=" key) zooms out, not in
        ("*", 27, command, nil),                       // ⌘* (the ANSI "-" key) does nothing
        ("=", 29, command | shift, "zoomIn"),          // ⌘= is ⌘⇧0
        ("0", 29, command, "resetZoom"),               // ⌘0
        ("ğ", 33, command, "back"),                    // "[" needs ⌥: ⌘[ takes the key in its place
    ] as [(String, UInt16, UInt, String?)])
    func turkishQZoomKeys(chars: String, code: UInt16, mods: UInt, action: String?) {
        #expect(Self.pressed(chars, code, mods, on: Self.turkishQ) == action)
    }

    /// US and Danish keep working: "+" is "=" with Shift, Danish ⌘[ is the key right of P.
    @Test(arguments: [
        ("=", UInt16(24), command, "zoomIn"),
        ("+", 24, command | shift, "zoomIn"),
        ("-", 27, command, "zoomOut"),
        ("[", 33, command, "back"),
    ] as [(String, UInt16, UInt, String?)])
    func usKeys(chars: String, code: UInt16, mods: UInt, action: String?) {
        let us = Set("1234567890-=qwertyuiop[]asdfghjkl;'\\`zxcvbnm,./!@#$%^&*()_+{}:\"|~<>?".map(String.init))
        #expect(Self.pressed(chars, code, mods, on: us) == action)
    }

    @Test(arguments: [
        ("+", UInt16(27), command, "zoomIn"),          // ⌘+ ("+" is "=" with Shift, by character)
        ("-", 44, command, "zoomOut"),                 // ⌘- where Danish has it
        ("å", 33, command, "back"),                    // ⌘[ by place
        ("´", 24, command, nil),                       // the ANSI "=" key types "´": "=" is ⇧0 here
    ] as [(String, UInt16, UInt, String?)])
    func danishKeys(chars: String, code: UInt16, mods: UInt, action: String?) {
        #expect(Self.pressed(chars, code, mods, on: Self.danish) == action)
    }

    @Test func modifiersMustMatchExactlyButCapsLockDoesNotCount() {
        let chord = KeyChord(key: "=", modifiers: Self.command)
        let any: (String) -> Bool = { _ in true }
        #expect(chord.match(.init(characters: "=", keyCode: 24, modifiers: Self.command | 0x10000), typable: any) == .character)
        #expect(chord.match(.init(characters: "=", keyCode: 24, modifiers: Self.command | Self.shift), typable: any) == nil)
        #expect(chord.match(.init(characters: "", keyCode: 24, modifiers: Self.command), typable: any) == nil)
        #expect(KeyChord.Press(characters: "{", keyCode: 33, modifiers: 0).key == "[")
        #expect(KeyChord.Press(characters: "\u{19}", keyCode: 48, modifiers: 0).key == KeyChord.tab)
        #expect(KeyChord.Press(characters: "T", keyCode: 17, modifiers: 0).key == "t")
    }

    /// Arc's Shortcuts list shows Developer Tools F12 and Reveal Current Tab ⌃⎵.
    @Test func showsFunctionKeysAndSpace() {
        #expect(KeyChord(key: KeyChord.f12, modifiers: 0).display == "F12")
        #expect(KeyChord(key: KeyChord.space, modifiers: KeyChord.Modifiers.control.rawValue).display == "⌃⎵")
        let press = KeyChord.Press(characters: "\u{F70F}", keyCode: 111, modifiers: 1 << 23)
        #expect(KeyChord(key: KeyChord.f12, modifiers: 0).match(press, typable: { _ in true }) == .character,
                "the function-key bit a press carries doesn't count")
    }

    /// Arc's Switch to Split View 1 is ⌃⇧1: ⇧1 types "!" (US) or "!" and ⇧2 types "\"" (Danish).
    @Test(arguments: [("!", UInt16(18), "1"), ("\"", UInt16(19), "2"), ("@", UInt16(19), "2"), ("¤", UInt16(21), "4")])
    func shiftedDigitsAreTheirDigit(chars: String, code: UInt16, digit: String) {
        let mods = KeyChord.Modifiers([.control, .shift]).rawValue
        let press = KeyChord.Press(characters: chars, keyCode: code, modifiers: mods)
        #expect(KeyChord(key: digit, modifiers: mods).match(press, typable: { _ in true }) == .position)
        let ctrl = KeyChord.Modifiers.control.rawValue
        #expect(KeyChord(key: digit, modifiers: ctrl).match(KeyChord.Press(characters: chars, keyCode: code, modifiers: ctrl),
                                                            typable: { _ in true }) == nil, "without ⇧ in the chord, the character counts")
    }
}
