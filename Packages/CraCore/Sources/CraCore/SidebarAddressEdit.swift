import Foundation

/// The sidebar's URL field edited where it is (GitHub #344, not in Arc). Arc's sidebar field opens
/// the command bar on a click; Settings ▸ Tabs ▸ "Edit the address in the sidebar" turns it into a
/// text field in place instead, the way Arc's developer bar edits its URL (ContentPanelTextField).
/// ⌘L and ⌘T keep opening the command bar either way.
public enum SidebarAddressEdit {
    /// What a click on the field does.
    public enum Click: Equatable, Sendable {
        /// The address becomes editable where it is drawn, all of it selected.
        case editInPlace
        /// The command bar, editing the tab's address (Arc).
        case commandBarEditURL
        /// The command bar making a new tab: no tab is selected, so there is no address to edit.
        case commandBarNewTab
    }

    public static func click(editInPlace: Bool, hasTab: Bool) -> Click {
        guard hasTab else { return .commandBarNewTab }
        return editInPlace ? .editInPlace : .commandBarEditURL
    }

    /// Where Return sends what was typed.
    public enum Commit: Equatable, Sendable {
        /// Nothing typed: the field puts the address back and nothing loads.
        case none
        /// The selected tab loads it.
        case load(String)
        /// A new Today tab opens it: a pinned tab keeps to its host, as with ⌘L (Arc).
        case newTab(String)
    }

    /// `typed` is an address when it looks like one (`TypedURL`), else a search through
    /// `searchURL`. `currentURL` is the selected tab's page; `pinned` whether that tab is pinned.
    public static func commit(typed: String, currentURL: String, pinned: Bool, searchURL: (String) -> String) -> Commit {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .none }
        let url = TypedURL.looksLikeURL(t) ? TypedURL.fromInput(t) : searchURL(t)
        if pinned, PinnedNavigation.typedURLOpensNewTab(url, from: currentURL) { return .newTab(url) }
        return .load(url)
    }
}
