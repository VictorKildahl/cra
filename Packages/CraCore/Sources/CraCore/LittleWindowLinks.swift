import Foundation

/// Where a link clicked in a Little Window opens when it asks for somewhere other than its page.
///
/// A Little Window has no tabs, and every link that asked for a new tab (target=_blank, a page's
/// window.open without features) opened one more Little Window; browsing a site that opens its links
/// that way left a pile of them (#599). Little Arc keeps you in its window until you move the page with
/// ⌘O, and Arc 1.171 loads a Shift-clicked link (a new window) in the Little Arc itself, with no second
/// window (docs/arc-reverse-engineering.md, 4 Nov 2026), so such a link loads in the window too. Not
/// checked against live Arc: a target=_blank link clicked in Little Arc.
public enum LittleWindowLinks {
    /// `shiftClick`: Chrome's new-window click, which always loads here; `newTab`: the page asked for a
    /// new tab in front. Of those, only pages a window can load in place: an about:blank a script fills
    /// in later needs its opener, so it stays a pop-up of its own, as a sign-in window (window.open with
    /// features) does. A ⌘-click (a background tab) never comes here and opens another Little Window
    /// behind this one.
    public static func loadsInWindow(_ url: String, shiftClick: Bool, newTab: Bool) -> Bool {
        if shiftClick { return true }
        guard newTab, let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }
}
