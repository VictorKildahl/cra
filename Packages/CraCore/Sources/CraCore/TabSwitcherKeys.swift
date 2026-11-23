import Foundation

/// What a key does while Arc's tab switcher (⌃Tab) is open: Tab / ⇧Tab and → / ← move (wrapping),
/// Return or Enter switches, Esc cancels. ` steps back, as in macOS's ⌘Tab switcher and in Arc
/// (GitHub #696), ⇧` forward; it is the key above Tab, a different key code on ISO keyboards.
public enum TabSwitcherKeys {
    public enum Action: Equatable, Sendable {
        case move(Int)
        case commit
        case cancel
    }

    /// `keyCode`: the key's virtual key code (NSEvent.keyCode).
    public static func action(keyCode: UInt16, shift: Bool) -> Action? {
        switch keyCode {
        case 48: .move(shift ? -1 : 1)        // Tab
        case 50, 10: .move(shift ? 1 : -1)    // `  (kVK_ANSI_Grave; kVK_ISO_Section, above Tab on ISO)
        case 124: .move(1)                    // →
        case 123: .move(-1)                   // ←
        case 53: .cancel                      // Esc
        case 36, 76: .commit                  // Return, Enter
        default: nil
        }
    }
}
