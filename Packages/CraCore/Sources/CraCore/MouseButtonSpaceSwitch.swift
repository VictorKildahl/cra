/// A mouse's back and forward buttons switch spaces over the sidebar (issue #233). Arc 1.171's
/// `SidebarView.otherMouseUp:` sends its spaces reducer `focusPreviousSpace` for button 3 (back)
/// and `focusNextSpace` for button 4 (forward), the actions behind Spaces ▸ Previous/Next Space
/// (docs/arc-reverse-engineering.md, "Mouse back and forward buttons"). Over a page the buttons
/// stay Chromium's history back and forward.
///
/// An MX Master with Logi Options+ never emits those buttons. Options+ takes the HID report and,
/// when Back is assigned the keystroke ⌥←, types it (and ⌥→ for Forward). That is not a mouse
/// event, and a key's window is the focused page, so the sidebar
/// check has to be the pointer's, not the event's. With Options+'s own Back and Forward
/// assignments it posts a swipe event instead (`offset(swipeDeltaX:deltaY:)`).
public enum MouseButtonSpaceSwitch {
    /// AppKit's `buttonNumber` for a mouse's back button (the fourth button).
    public static let back = 3
    /// AppKit's `buttonNumber` for a mouse's forward button (the fifth button).
    public static let forward = 4
    /// The left arrow's virtual key code (`kVK_LeftArrow`). Logi Options+ types this with Option.
    public static let backKeyCode: UInt16 = 123
    /// The right arrow's virtual key code (`kVK_RightArrow`).
    public static let forwardKeyCode: UInt16 = 124

    /// What a side button does once it has been recognized: switch space, go back or forward in
    /// the tab, or swallow a held button's repeat. `offset` is −1 for back and +1 for forward.
    public enum Action: Equatable {
        case switchSpace(Int)
        case history(Int)
        case swallow
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

    /// The step a swipe event makes, −1 for back and +1 for forward, or nil for an up, down or
    /// too small swipe. Logi Options+'s default Back and Forward (its OSX_GESTURE_BACK/FORWARD
    /// actions) post this event instead of button 3 or 4, as a three-finger swipe between pages
    /// on a trackpad does. AppKit's sign: left is positive, so deltaX 1 is back. Chromium's page
    /// view hands `swipeWithEvent:` to Chrome's browser window, which an embedded page lacks.
    public static func offset(swipeDeltaX dx: Double, deltaY dy: Double) -> Int? {
        guard abs(dx) > 0.5, abs(dx) > abs(dy) else { return nil }
        return dx > 0 ? -1 : 1
    }

    /// What ⌥← or ⌥→ does, or nil to leave the key to whoever has it. A text field always keeps
    /// it, wherever the pointer is: ⌥← moves by word, and the pointer rests on the sidebar while
    /// someone renames a tab. Otherwise the sidebar switches spaces and a page goes back or
    /// forward. A repeat of a key acted on is swallowed, so a held button doesn't walk every space,
    /// while a held ⌥← in text keeps moving word by word.
    public static func action(offset: Int, pointerOverSidebar: Bool, editingText: Bool, isRepeat: Bool) -> Action? {
        if editingText { return nil }
        if isRepeat { return .swallow }
        return pointerOverSidebar ? .switchSpace(offset) : .history(offset)
    }
}
