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
    /// A mail link without a click of its own (a new window a page opened, then sent to mailto:, or a page's
    /// own redirect after a send) gets Chrome's one go per page load, as another app's link does: Chrome's
    /// flood guard lets mailto: through once without a gesture. Cra opened nothing (#684).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/684")) func mailGetsOneGoWithoutAClick() {
        #expect(AppLinks.mayGoWithoutClick("mailto:a@example.com"))
        #expect(AppLinks.mayGoWithoutClick("spotify:album:1"))
        #expect(!AppLinks.mayGoWithoutClick("https://example.com"), "a page loads, nothing to guard")
        #expect(!AppLinks.mayGoWithoutClick("afp://server/share"), "a refused scheme never goes")
        #expect(!AppLinks.mayGoWithoutClick("cra://action/closeTab"))
    }

    /// A new tab or window that never showed a page, only sent to another app's address, closes once that is
    /// handed to macOS, as Chrome closes it (external_protocol_handler.cc: IsInitialNavigation). It stayed as an
    /// empty about:blank window over the page (#684). A page that loaded, or has history, stays.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/684")) func aBlankRequesterCloses() {
        #expect(AppLinks.closesRequester(currentURL: "about:blank", canGoBack: false))
        #expect(AppLinks.closesRequester(currentURL: "", canGoBack: false))
        #expect(!AppLinks.closesRequester(currentURL: "https://example.com/contact", canGoBack: false))
        #expect(!AppLinks.closesRequester(currentURL: "about:blank", canGoBack: true), "back to a page it showed")
        #expect(AppLinks.closesRequester(currentURL: "about:blank#x", canGoBack: false), "still the blank page")
    }

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

struct TypedAppLinksTests {
    /// GitHub #604: todoist:// typed in ⌘T and sent with Return opened nothing. Another app's address
    /// typed in the command bar opens that app; with no app for it, it is searched for; a refused
    /// scheme stays refused; a web address loads as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/604"))
    func aTypedAppAddressOpensItsApp() {
        #expect(AppLinks.typed("todoist://", hasApp: true) == .openApp)
        #expect(AppLinks.typed("zoommtg://zoom.us/join?confno=1", hasApp: true) == .openApp)
        #expect(AppLinks.typed("mailto:someone@example.com", hasApp: true) == .openApp)
        #expect(AppLinks.typed("todoist://", hasApp: false) == .search)
        #expect(AppLinks.typed("afp://server/share", hasApp: true) == .refuse)
        #expect(AppLinks.typed("cra://open?url=x", hasApp: true) == .refuse)
        #expect(AppLinks.typed("https://todoist.com", hasApp: true) == .load)
        #expect(AppLinks.typed("about:blank", hasApp: false) == .load)
    }

    /// Obsidian Web Clipper sends the tab to obsidian:// through chrome.tabs.update, so its own origin asks, and
    /// "Always allow" is offered for it as in Chrome: one tick and the clipper opens Obsidian from every page without
    /// asking again. A page with no origin Chrome may remember (plain http) gets the question without the box.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/785"))
    func anOriginChromeMayRememberIsOfferedAlwaysAllow() {
        let clipper = AppLinks.ask(app: "Obsidian", initiator: "chrome-extension://cnjifjpddelmedmihgijeibhnjfabmlf",
                                   rememberable: true, pageHost: "example.com")
        #expect(clipper.title == "Open Obsidian?")
        #expect(clipper.message == "chrome-extension://cnjifjpddelmedmihgijeibhnjfabmlf wants to open this application.")
        #expect(clipper.alwaysAllow == "Always allow chrome-extension://cnjifjpddelmedmihgijeibhnjfabmlf to open links of this type in the associated app")
        let site = AppLinks.ask(app: "Zoom", initiator: "https://zoom.us", rememberable: true, pageHost: "zoom.us")
        #expect(site.message == "zoom.us wants to open this application.")
        #expect(site.alwaysAllow == "Always allow zoom.us to open links of this type in the associated app")
        let plain = AppLinks.ask(app: "Zoom", initiator: "http://intranet", rememberable: false, pageHost: "intranet")
        #expect(plain.message == "http://intranet wants to open this application.")
        #expect(plain.alwaysAllow == nil)
        let typed = AppLinks.ask(app: "Spotify", initiator: nil, rememberable: false, pageHost: "open.spotify.com")
        #expect(typed.message == "open.spotify.com wants to open this application." && typed.alwaysAllow == nil)
    }
}

/// Another app's address whose app on this Mac is Cra itself (#821).
struct AppLinksHandedBackTests {
    static let own = "/Applications/Cra.app"

    /// A mailto: link froze Cra in an endless run of Little Windows: Cra was the Mac's mail app, so handing the
    /// address to macOS sent it straight back as a link from another app, which opened in a Little Window, which
    /// handed it over again. Chrome never launches a scheme it is the default app for; Cra doesn't either now.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/821"))
    func anAddressWhoseAppIsCraIsNotHandedBack() {
        #expect(AppLinks.handsBackToCra(handlerBundleID: "dk.kildahl.cra", handlerPath: "/Applications/Cra.app",
                                        ownBundleID: "dk.kildahl.cra", ownPath: Self.own))
        #expect(AppLinks.handsBackToCra(handlerBundleID: "DK.Kildahl.Cra", handlerPath: "/Users/x/Downloads/Cra.app",
                                        ownBundleID: "dk.kildahl.cra", ownPath: Self.own), "another copy of Cra: macOS hands it to the one running")
        #expect(AppLinks.handsBackToCra(handlerBundleID: nil, handlerPath: "/Applications/Cra.app/",
                                        ownBundleID: "dk.kildahl.cra", ownPath: Self.own), "this very app, by its place")
        #expect(!AppLinks.handsBackToCra(handlerBundleID: "com.apple.mail", handlerPath: "/System/Applications/Mail.app",
                                         ownBundleID: "dk.kildahl.cra", ownPath: Self.own))
        #expect(!AppLinks.handsBackToCra(handlerBundleID: nil, handlerPath: nil, ownBundleID: "dk.kildahl.cra", ownPath: Self.own))
    }

    /// The Little Window a mail link from macOS opened shows no page, only the address it was sent to: it closes once
    /// that address has gone nowhere, instead of staying empty on screen.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/821"))
    func aWindowOpenedOnlyOnTheAppsAddressCloses() {
        #expect(AppLinks.closesRequester(currentURL: "mailto:someone@example.com", canGoBack: false))
        #expect(AppLinks.closesRequester(currentURL: "news:from-another-app", canGoBack: false))
        #expect(!AppLinks.closesRequester(currentURL: "mailto:someone@example.com", canGoBack: true), "back to a page it showed")
        #expect(!AppLinks.closesRequester(currentURL: "https://example.com/contact", canGoBack: false))
    }

    /// Typed in the command bar, such an address has no other app to open it: searched, as Chrome does (#604).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/821"))
    func aTypedAddressWhoseAppIsCraIsSearched() {
        #expect(AppLinks.typed("mailto:someone@example.com", hasApp: true, appIsCra: true) == .search)
        #expect(AppLinks.typed("mailto:someone@example.com", hasApp: true, appIsCra: false) == .openApp)
        #expect(AppLinks.typed("https://example.com", hasApp: true, appIsCra: true) == .load)
    }
}
