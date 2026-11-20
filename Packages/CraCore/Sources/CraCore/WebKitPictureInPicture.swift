import Foundation

/// How a WebKit tab (a protected-media service such as Paramount+, ProtectedMediaSites) goes into
/// Picture in Picture when Cra asks. View ▸ Picture in Picture did nothing on one: the WebKit tab
/// answered the request with nothing at all (GitHub #585). Asked by the person (the menu, the
/// sidebar player's button), it now takes WebKit's own toggle, the one Safari's Picture in Picture
/// uses, which needs no user gesture in the page and finds the playing video itself. Leaving a tab
/// (automatic) stays with the page's own request (PictureInPictureRequest), which on a WebKit page
/// takes a video that says `disablePictureInPicture` too (Netflix's); the Site Control Center's switch
/// turns leaving the tab off for a site.
public enum WebKitPictureInPicture: Equatable, Sendable {
    /// WebKit's own Picture in Picture toggle.
    case toggle
    /// The page's `requestPictureInPicture()` on its playing (else largest) video.
    case page
    /// Back into the page: the menu reads "Exit Picture in Picture" while a video is out.
    case exit
    /// Nothing to do.
    case none

    /// What to do for a request. `active`: already in Picture in Picture; `canToggle`: WebKit says its
    /// toggle has a video to take.
    public init(automatic: Bool, active: Bool, canToggle: Bool) {
        if automatic { self = .none }
        else if active { self = .exit }
        else { self = canToggle ? .toggle : .page }
    }

    /// After the page path of the sidebar player's button: whether the tab's own request should
    /// follow. The page's answer is "ok", "none" (no video), a DOMException ("NotAllowedError: …",
    /// WebKit runs Cra's script without a user gesture) or nil (no answer).
    public static func followsPageAnswer(_ answer: String?, automatic: Bool) -> Bool {
        guard answer != "ok" else { return false }
        return !automatic || answer == nil || answer == "none"
    }
}
