import Foundation

/// The toolbar's buttons from the keyboard. With Full Keyboard Access on (System Settings ▸ Keyboard ▸
/// Keyboard navigation), Tab moves the focus through them as through any Mac window's buttons, and the
/// floating toolbar comes out for the one that has it (`ToolbarAutoHideTracker.focus`).
public enum ToolbarKeyboard {
    /// Whether Tab stops at a button: only with Full Keyboard Access, as for AppKit's own buttons, and
    /// not at one that is greyed out (Back with no history).
    public static func tabStops(fullKeyboardAccess: Bool, enabled: Bool) -> Bool {
        fullKeyboardAccess && enabled
    }

    /// Whether a button takes the focus it is offered. A click never moves it: pressing Back with the
    /// pointer leaves the keys with the page, as before. Only the keyboard (Tab, Shift-Tab) puts the
    /// focus on a button.
    public static func takesFocus(enabled: Bool, byClick: Bool) -> Bool {
        enabled && !byClick
    }

    /// Whether a key pressed on the focused button presses it: Space, as on every Mac button, and Return
    /// or Enter, as in Chrome's toolbar. With ⌘, ⌥ or ⌃ held it is a shortcut and goes on to the menus.
    public static func presses(characters: String, command: Bool, option: Bool, control: Bool) -> Bool {
        guard !command, !option, !control else { return false }
        return characters == " " || characters == "\r" || characters == "\u{3}"
    }
}
