import CraCore
import Testing

struct WebKitPictureInPictureTests {
    /// GitHub #585: on a WebKit tab (Paramount+), View ▸ Picture in Picture did nothing. Asked for it,
    /// the tab takes WebKit's own toggle when it has a video, else the page's request.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func askedForItAWebKitTabTogglesPictureInPicture() {
        #expect(WebKitPictureInPicture(automatic: false, active: false, canToggle: true) == .toggle)
        #expect(WebKitPictureInPicture(automatic: false, active: false, canToggle: false) == .page)
        // The player's button: the page's request failed without a gesture, so the tab's own follows.
        #expect(WebKitPictureInPicture.followsPageAnswer("NotAllowedError: The request is not allowed", automatic: false))
        #expect(WebKitPictureInPicture.followsPageAnswer(nil, automatic: false))
        #expect(!WebKitPictureInPicture.followsPageAnswer("ok", automatic: false))
    }

    /// Leaving a tab never pops a video out through the toggle; asked again while out, it comes back.
    @Test func leavingATabTogglesNothingAndAskingAgainExits() {
        #expect(WebKitPictureInPicture(automatic: true, active: false, canToggle: true) == .none)
        #expect(WebKitPictureInPicture(automatic: true, active: true, canToggle: true) == .none)
        #expect(WebKitPictureInPicture(automatic: false, active: true, canToggle: true) == .exit)
        // Leaving a tab: a refused page request ends there (the page kept the video in).
        #expect(!WebKitPictureInPicture.followsPageAnswer("NotAllowedError: x", automatic: true))
        #expect(WebKitPictureInPicture.followsPageAnswer("none", automatic: true))
        #expect(WebKitPictureInPicture.followsPageAnswer(nil, automatic: true))
    }
}
