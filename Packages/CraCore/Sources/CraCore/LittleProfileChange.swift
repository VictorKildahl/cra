import Foundation

/// The address a Little Window loads again when its address pill moves the page to another profile.
///
/// A page can't move between profiles, so the other profile loads an address anew: the link the
/// window opened (or the address typed in it), never where its redirects ended. Those answered the
/// first profile's cookies (a sign-in page whose challenge only that session can finish). Once the
/// page has gone on from that entry (a link clicked in it), the page shown is the one to keep.
public enum LittleProfileChange {
    /// `opened` is the link the window opened or the address typed into its empty card (nil for a
    /// popup host), `shown` the page's address now. `wentOn` is true when the page left the entry it
    /// opened on (Back has somewhere to go): server redirects replace that entry, a clicked link adds one.
    public static func address(opened: String?, shown: String, wentOn: Bool) -> String {
        if !wentOn, let opened, isPage(opened) { return opened }
        return isPage(shown) ? shown : "about:blank"
    }

    private static func isPage(_ url: String) -> Bool { !url.isEmpty && url != "about:blank" }
}
