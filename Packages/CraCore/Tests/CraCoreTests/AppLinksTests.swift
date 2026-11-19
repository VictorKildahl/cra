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
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/560")) func aPagesOwnRedirectAsksOncePerPageLoad() {
        var guarded = AppLinks.RedirectGuard()
        enum Step { case redirect, click, load }
        let asked = [
            Step.redirect, // the page's first redirect asks
            .redirect,     // a second gets nothing (history.pushState included: it is no load)
            .click,        // a click always asks
            .redirect,     // and doesn't renew the redirect's question
            .load,         // the next page, or this one reloaded,
            .redirect,     // asks again
            .redirect,     // once
        ].compactMap { step -> Bool? in
            switch step {
            case .load: guarded.pageLoaded(); return nil
            case .click: return guarded.mayAsk(userGesture: true)
            case .redirect: return guarded.mayAsk(userGesture: false)
            }
        }
        #expect(asked == [true, false, true, false, true, false])
    }
}
