import CraCore
import Testing

struct WebKitFullscreenCloseTests {
    /// A WebKit tab closed while its video was still going into full screen: taking its view down then freed
    /// WebKit's full-screen controller with the entry pending, and WebKit trapped. It waits for WebKit instead,
    /// asks it to leave once in, and goes once out.
    @Test(.bug(id: "crash-webkit-tab-closed-entering-fullscreen"))
    func aTabClosedOnItsWayIntoFullScreenWaitsForWebKit() {
        #expect(WebKitFullscreenClose(.entering) == .wait)
        #expect(WebKitFullscreenClose(.inFullscreen) == .leave)
        #expect(WebKitFullscreenClose(.exiting) == .wait)
        #expect(WebKitFullscreenClose(.out) == .removeNow)
    }

    /// The wait has an end, well past WebKit's own animations.
    @Test func theWaitEnds() {
        #expect(WebKitFullscreenClose.longestWait >= 2 && WebKitFullscreenClose.longestWait <= 10)
    }
}
