import Foundation

/// Whether the sidebar is shown docked in a browser window.
///
/// In Arc, when a window has no tab selected / open (e.g. after starting on a new tab,
/// or when all tabs in the space are closed), the sidebar is always visible so the user
/// can select their first tab (favorites, pinned tabs, spaces). Even if the user has
/// hidden the sidebar (⌘S), it stays visible while no tab is selected, and hides
/// automatically once a tab is selected.
public enum SidebarVisibility {
    /// - Parameters:
    ///   - userVisible: the persistent setting for this window (`WindowSession.sidebarVisible`).
    ///   - hasSelectedTab: whether a tab is currently selected in this window.
    public static func isShown(userVisible: Bool, hasSelectedTab: Bool) -> Bool {
        userVisible || !hasSelectedTab
    }
}
