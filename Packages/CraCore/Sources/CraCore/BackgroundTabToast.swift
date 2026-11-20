import Foundation

/// What Arc's toast says when a tab opens behind the page (GitHub #543). Arc posts
/// `Arc_ShowBackgroundTabAffordance` for every tab it makes in the background, whatever made it (a
/// ⌘-click, a middle click, Open Link in New Tab, ⌘Return in the command bar), and its
/// BackgroundTabAffordanceController answers with the `backgroundTabCreated` toast "New Tab Created",
/// or `backgroundTabCreatedInSpace` "New Tab Created in %@" when the tab went to a space the window
/// isn't showing. Its strings say when: "Letting the user know a new tab has been created when the
/// sidebar is hidden." With the sidebar out, the new row in Today says it instead.
public enum BackgroundTabToast {
    /// The toast's text, or nil when the sidebar shows the new row.
    /// - Parameters:
    ///   - sidebarVisible: the window's sidebar is out (docked).
    ///   - tabSpace: the space the new tab went to.
    ///   - shownSpace: the space the window shows.
    ///   - tabSpaceTitle: `tabSpace`'s name, for a tab in another space.
    public static func text(sidebarVisible: Bool, tabSpace: UUID?, shownSpace: UUID, tabSpaceTitle: String?) -> String? {
        guard !sidebarVisible else { return nil }
        if let tabSpace, tabSpace != shownSpace, let title = tabSpaceTitle, !title.isEmpty {
            return "New Tab Created in \(title)"
        }
        return "New Tab Created"
    }

    /// What a click on the toast opens (#543, gxcodes): the toast is a button in Arc, its
    /// BackgroundTabNotificationContent carrying the window and the tab (`windowID`, `itemID`). Another
    /// background tab while it is up replaces what it holds, so the click opens the newest one, and
    /// only while that tab is still open (closed or archived meanwhile, the click opens nothing).
    /// - Parameters:
    ///   - announced: the tabs this toast announced while it stayed up, oldest first.
    ///   - isOpen: whether a tab is still open.
    public static func clickOpens(announced: [UUID], isOpen: (UUID) -> Bool) -> UUID? {
        guard let newest = announced.last, isOpen(newest) else { return nil }
        return newest
    }
}
