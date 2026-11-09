/// A mouse's back and forward buttons switch spaces over the sidebar (issue #233). Arc 1.171's
/// `SidebarView.otherMouseUp:` sends its spaces reducer `focusPreviousSpace` for button 3 (back)
/// and `focusNextSpace` for button 4 (forward), the actions behind Spaces ▸ Previous/Next Space
/// (docs/arc-reverse-engineering.md, "Mouse back and forward buttons"). Over a page the buttons
/// stay Chromium's history back and forward.
///
/// An MX Master with Logi Options+ never emits those buttons. Options+ takes the HID report and,
/// when Back is assigned a keystroke, types ⌥← (and ⌥→ for Forward). That key is what Chrome
/// navigates on. It is not a mouse event, and a key's window is the focused page, so the sidebar
/// check has to be the pointer's, not the event's.
public enum MouseButtonSpaceSwitch {
    /// AppKit's `buttonNumber` for a mouse's back button (the fourth button).
    public static let back = 3
    /// AppKit's `buttonNumber` for a mouse's forward button (the fifth button).
    public static let forward = 4
    /// The left arrow's virtual key code (`kVK_LeftArrow`). Logi Options+ types this with Option.
    public static let backKeyCode: UInt16 = 123
    /// The right arrow's virtual key code (`kVK_RightArrow`).
    public static let forwardKeyCode: UInt16 = 124

    /// What a side button does once it has been recognized: switch space, or go back or forward
    /// in the tab. `offset` is −1 for back and +1 for forward.
    public enum Action: Equatable {
        case switchSpace(Int)
        case history(Int)
    }

    /// The space step a released button makes, −1 for the previous space and +1 for the next, or
    /// nil for a button that doesn't switch spaces.
    public static func offset(buttonNumber: Int) -> Int? {
        switch buttonNumber {
        case back: -1
        case forward: 1
        default: nil
        }
    }

    /// The step ⌥← or ⌥→ makes, or nil for any other chord. Only Option alone: ⌥⌘← is already
    /// Previous Space, ⌘← is Go Back, and ⌥⇧← selects a word. Caps Lock is not a shortcut
    /// modifier. An empty `key` still matches the arrow's key code, which is what an injector
    /// that leaves the characters blank delivers.
    public static func offset(key: String, keyCode: UInt16, modifiers: UInt) -> Int? {
        let four: KeyChord.Modifiers = [.shift, .control, .option, .command]
        guard KeyChord.Modifiers(rawValue: modifiers).intersection(four) == .option else { return nil }
        if key == KeyChord.left || keyCode == backKeyCode { return -1 }
        if key == KeyChord.right || keyCode == forwardKeyCode { return 1 }
        return nil
    }

    /// Over the sidebar the button switches spaces, even if a text field has the key. Over a
    /// page it goes back or forward, unless that field has the key: ⌥← moves by word there.
    public static func action(offset: Int, pointerOverSidebar: Bool, editingText: Bool) -> Action? {
        if pointerOverSidebar { return .switchSpace(offset) }
        if editingText { return nil }
        return .history(offset)
    }
}
