/// A mouse's back and forward buttons switch spaces over the sidebar (issue #233). Arc 1.171's
/// `SidebarView.otherMouseUp:` sends its spaces reducer `focusPreviousSpace` for button 3 (back)
/// and `focusNextSpace` for button 4 (forward), the actions behind Spaces ▸ Previous/Next Space
/// (docs/arc-reverse-engineering.md, "Mouse back and forward buttons"). Over a page the buttons
/// stay Chromium's history back and forward.
public enum MouseButtonSpaceSwitch {
    /// AppKit's `buttonNumber` for a mouse's back button (the fourth button).
    public static let back = 3
    /// AppKit's `buttonNumber` for a mouse's forward button (the fifth button).
    public static let forward = 4

    /// The space step a released button makes, −1 for the previous space and +1 for the next, or
    /// nil for a button that doesn't switch spaces.
    public static func offset(buttonNumber: Int) -> Int? {
        switch buttonNumber {
        case back: -1
        case forward: 1
        default: nil
        }
    }
}
