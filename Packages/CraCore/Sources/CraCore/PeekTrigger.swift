import Foundation

/// Which clicked links open Arc's Peek (Settings ▸ Tabs ▸ Links) instead of loading where they are.
///
/// Arc 1.171, offline Arc with both Links settings on (`modalEnabled`, `shiftClickModalEntryPointEnabled`),
/// HID clicks in a pinned tab (4 Nov 2026): a link to another host peeked, plain or target=_blank; a
/// same-host link loaded in the tab, but the same link with target=_blank peeked, and so did
/// window.open; a ⌘-click opened a background tab. A Shift-click peeked from any tab. Links clicked
/// inside the Peek load in it.
public enum PeekTrigger {
    /// `newTab`: the page asked for a new tab (target=_blank, window.open without features).
    /// `fromPinned`: a pinned tab or favorite.
    public static func opens(_ url: String, from page: String, shiftClick: Bool, newTab: Bool, fromPinned: Bool,
                             settings: AppSettings) -> Bool {
        guard SiteKey.site(of: url) != nil else { return false }
        if shiftClick { return settings.peekOnShiftClick }
        // Another host, not another site: Arc peeks from pin.lvh.me to away.lvh.me (GitHub #139).
        return settings.peekLinksToOtherSites && (settings.peekInEveryTab || fromPinned)
            && (newTab || PinnedNavigation.linkLeavesHost(url, from: page))
    }

    /// A link clicked inside the Peek that asks for a new tab (target=_blank, window.open without
    /// features) leaves the Peek: Arc 1.171 (6 Nov 2026, GitHub #202) closed the Peek and opened
    /// the page as a selected Today tab in the space, below the tab the Peek came from, with no
    /// second Little Arc. A Shift-click still loads in the Peek. Only pages a tab can show: an
    /// about:blank a script fills in later needs its opener, so it stays a popup.
    public static func leavesPeek(_ url: String, shiftClick: Bool, newTab: Bool) -> Bool {
        guard newTab, !shiftClick, let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }
}
