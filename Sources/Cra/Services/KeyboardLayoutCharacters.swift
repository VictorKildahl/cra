import Carbon.HIToolbox

/// The characters the current keyboard layout types without ⌥, on a key alone or with Shift.
/// A shortcut whose character is among them matches only by character; one the layout can't
/// type (Danish "[" is ⌥8) also takes the key in its ANSI place (KeyChord.match, GitHub #212).
@MainActor
enum KeyboardLayoutCharacters {
    private static var cached: (layout: String, characters: Set<String>?)?

    static func types(_ character: String) -> Bool {
        // A layout without Unicode key data (none ship today) can't say: keep the place fallback.
        characters?.contains(character) ?? false
    }

    private static var characters: Set<String>? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
        if let cached, cached.layout == id { return cached.characters }
        let read = read(source)
        cached = (id, read)
        return read
    }

    private static func read(_ source: TISInputSource) -> Set<String>? {
        guard let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
        return layout.withUnsafeBytes { raw -> Set<String>? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var out = Set<String>()
            for code in 0..<UInt16(128) {
                for modifiers in [0, UInt32(shiftKey >> 8) & 0xFF] {
                    var dead: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(base, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                    if status == noErr, length > 0 { out.insert(String(utf16CodeUnits: chars, count: length).lowercased()) }
                }
            }
            return out
        }
    }
}
