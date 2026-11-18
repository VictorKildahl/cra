import CraCore
import Testing

struct AppLinksTests {
    @Test(arguments: [
        // Spotify's "Open in Desktop app" (GitHub #207) and other apps' links.
        ("spotify:album:06CjF89lLSSiVWXujVVtQs", AppLinks.Kind.asksFirst),
        ("SPOTIFY:playlist:1", .asksFirst),
        ("zoommtg://zoom.us/join?confno=1", .asksFirst),
        ("itms-apps://apps.apple.com/app/id1", .asksFirst),
        ("x-apple.systempreferences:com.apple.preference", .asksFirst),
        ("mailto:a@example.com", .opens),
        ("news:comp.lang", .opens),
        // Pages.
        ("https://open.spotify.com/album/1", .page),
        ("http://localhost:3000", .page),
        ("about:blank", .page),
        ("", .page),
        ("blob:https://example.com/1", .page),
        ("data:text/html,hi", .page),
        ("chrome-extension://abc/popup.html", .page),
        ("devtools://devtools/bundled/inspector.html", .page),
        ("web+cra:thing", .page),
        ("/relative/path", .page),
        ("1password:x", .page),
        // Never to an app.
        ("cra://action/closeTab", .refused),
        ("CRA:action", .refused),
        ("afp://server/share", .refused),
        ("ms-help://x", .refused),
        // The engines' own, allowed or not: never an app's.
        ("file:///etc/passwd", .page),
        ("javascript:alert(1)", .page),
        ("view-source:https://example.com", .page),
    ])
    func kind(url: String, kind: AppLinks.Kind) {
        #expect(AppLinks.kind(of: url) == kind)
    }

    // Slack's "Launching…" page after a browser sign-in redirects to slack: with no click; a
    // Chromium page dropped it, and there is no button to click instead.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/560")) func aPagesOwnRedirectAsksOncePerPage() {
        var guarded = AppLinks.RedirectGuard()
        let slack = "https://acme.slack.com/ssb/redirect"
        let spotify = "https://open.spotify.com/album/1"
        let asked = [
            (false, slack),   // the page's first redirect asks
            (false, slack),   // a second gets nothing
            (true, slack),    // a click always asks
            (false, slack),   // and doesn't renew the redirect's question
            (false, spotify), // the next page asks again
            (false, slack),   // and so does coming back
        ].map { guarded.mayAsk(userGesture: $0.0, page: $0.1) }
        #expect(asked == [true, false, true, false, true, true])
    }
}
