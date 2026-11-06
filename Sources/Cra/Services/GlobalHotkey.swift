import AppKit
import Carbon.HIToolbox

/// Arc's "Open Little Arc when I press ⌥⌘N" (GitHub #195): New Little Window's shortcut works
/// from every app, full-screen ones included, while the setting is on. A Carbon hot key, as Arc's
/// GlobalHotkeyManager uses: it needs no Accessibility permission and sees no other key presses.
/// While Cra is in front the hot key takes the press before the menu does; both open a Little Window.
@MainActor
final class GlobalHotkey {
    private let run: () -> Void
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: (chord: KeyChord, code: UInt32)?
    private static let signature: OSType = 0x4352_4C57  // "CRLW"

    init(run: @escaping () -> Void) {
        self.run = run
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.run() }
            return noErr
        }, 1, &spec, me, &handler)
    }

    /// Registers `chord` (nil: none), replacing what was registered.
    func set(_ chord: KeyChord?) {
        let code = chord.flatMap(Self.keyCode(for:))
        if let registered, let chord, let code, registered.chord == chord, registered.code == code { return }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
        guard let chord, let code else { return }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(code, GlobalShortcut.carbonModifiers(chord.keys), EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            CraLog.note("global shortcut: \(chord.display) not registered (\(status))")
            return
        }
        ref = newRef
        registered = (chord, code)
    }

    /// The key that types `chord.key` on the current keyboard layout (Carbon hot keys take key
    /// codes): Danish ⌥⌘N is the same key as US, but a Dvorak "n" is not.
    static func keyCode(for chord: KeyChord) -> UInt32? {
        let special: [String: Int] = [Shortcut.tab: kVK_Tab, Shortcut.left: kVK_LeftArrow, Shortcut.right: kVK_RightArrow,
                                      Shortcut.up: kVK_UpArrow, Shortcut.down: kVK_DownArrow, Shortcut.delete: kVK_Delete]
        if let code = special[chord.key] { return UInt32(code) }
        if let scalar = chord.key.unicodeScalars.first, chord.key.unicodeScalars.count == 1, (0xF704...0xF70F).contains(scalar.value) {
            let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
            let i = Int(scalar.value - 0xF704)
            return i < fKeys.count ? UInt32(fKeys[i]) : nil
        }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
        return layout.withUnsafeBytes { raw -> UInt32? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<UInt16(128) {
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(base, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length).lowercased() == chord.key { return UInt32(code) }
            }
            return nil
        }
    }
}
