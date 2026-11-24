import Foundation

/// The address a Little Window loads again when its address pill moves the page to another profile.
///
/// A page can't move between profiles, so the other profile loads an address anew: the link the
/// window opened (or the address typed in it), never where its redirects ended. Those answered the
/// first profile's cookies (a sign-in page whose challenge only that session can finish).
public enum LittleProfileChange {
    /// `opened` is the link the window opened or the address last typed in it (nil for a popup host
    /// or the empty card), `shown` the page's address now.
    public static func address(opened: String?, shown: String) -> String {
        if let opened, isPage(opened) { return opened }
        return isPage(shown) ? shown : "about:blank"
    }

    private static func isPage(_ url: String) -> Bool { !url.isEmpty && url != "about:blank" }
}
