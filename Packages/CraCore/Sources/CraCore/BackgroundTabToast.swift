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
}
