import Foundation

/// The sidebar's URL field edited where it is (GitHub #344, not in Arc). Arc's sidebar field opens
/// its address panel on a click (SidebarAddressPanel, #663); Settings ▸ Tabs ▸ "Edit the address in
/// the sidebar" turns it into a text field in place instead, the way Arc's developer bar edits its
/// URL (ContentPanelTextField).
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

    /// A click on the toolbar's address. The same setting applies there: the address is edited
    /// where it is drawn when the toolbar holds it (Discord #help, 25 Nov). Arc's developer bar
    /// always edits in place (#42).
    public static func toolbarClick(developer: Bool, editInPlace: Bool, hasTab: Bool) -> Click {
        guard hasTab else { return .commandBarNewTab }
        return click(editInPlace: editInPlace || developer, hasTab: true)
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

/// A press outside the sidebar's address while it is open: Arc's address panel (#691) or the field
/// edited in place (#692). Both closed only when the keys moved, and some presses never move them.
public enum SidebarAddressOutsideClick {
    /// The floating sidebar's panel takes the keys only when a click needs them, so a click on its
    /// empty space left the bar holding them, open. Arc 1.174.1 closes the panel and keeps the
    /// sidebar. Any bar: the centred one closes on a click outside it too.
    public static func closesBar(barOpen: Bool, inFloatingSidebar: Bool) -> Bool {
        barOpen && inFloatingSidebar
    }

    /// A press in the window the sidebar is in (the browser window, or the floating sidebar's panel),
    /// not on the field: #344's "a click elsewhere puts the address back". A press in another window
    /// takes the keys, which ends the edit already.
    public static func endsEdit(editing: Bool, inSidebarsWindow: Bool, onField: Bool) -> Bool {
        editing && inSidebarsWindow && !onField
    }
}
