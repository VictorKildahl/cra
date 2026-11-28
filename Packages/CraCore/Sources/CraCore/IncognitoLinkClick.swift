public enum IncognitoLinkClick {
    /// A Shift-clicked link in an incognito page (Chrome's new window) opens as a foreground tab in
    /// that incognito window. Chrome's off-the-record window reached the stray page handler, which
    /// opened it in a normal window in the Default profile (#907). Arc peeks there; Cra has no Peek
    /// in incognito. New-tab links (target=_blank, ⌘⇧) already stay in incognito.
    public static func opensTab(shiftClick: Bool, newTab: Bool) -> Bool { shiftClick && !newTab }
}
