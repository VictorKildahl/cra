import Foundation

/// Archive ▸ View History (⌘Y), as in Arc (GitHub #590): Chromium's History page, opened in a new
/// tab of the space in use, so it lists that space's profile's browsing history.
///
/// Arc 1.172's MainMenu.nib gives View History the action `viewHistory` ("Show History; History"
/// in the command bar) and the selector `showAllHistory:`, Chromium's history. Its archive of
/// closed tabs is a separate item, View Archive (`viewArchive`), with no key; Cra's is
/// `showArchive`. Cra's ⌘Y opened that archive, which holds closed tabs from every profile, until
/// #590. From an incognito window the page opens in the normal window, as in Chrome
/// (SidebarStore.createTab, #412).
public enum HistoryPage {
    public static let url = "chrome://history"

    /// The key binding that runs it. The id stays `viewArchive`, which ⌘Y has had since the first
    /// keybindings.json, so a shortcut someone gave View History keeps working; Arc's own
    /// `viewArchive` is Cra's `showArchive`.
    public static let action = "viewArchive"

    /// The command bar words for it, Arc's "Show History; History" with Chrome's name for the page.
    public static let triggers = ["history", "show history", "browsing history"]
}
