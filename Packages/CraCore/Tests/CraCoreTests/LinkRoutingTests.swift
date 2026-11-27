import CraCore
import Foundation
import Testing

/// Air Traffic Control against what Arc 1.170 did with the same routes (26 Oct 2026, links handed
/// over with `open -g -a Arc`; docs/arc-reverse-engineering.md, "Air Traffic Control").
struct LinkRoutingTests {
    @Test(arguments: [
        // Case, scheme and a leading www. go on both sides.
        (LinkMatchStyle.contains, "https://example.com/atc-scheme", "http://example.com/atc-scheme", true),
        (.contains, "https://example.com/atc-scheme", "https://www.example.com/atc-scheme", true),
        (.contains, "ATC-CASE", "https://example.com/atc-case", true),
        // Contains also sees the query and the fragment.
        (.contains, "atc-order", "https://example.com/?x=atc-order", true),
        (.contains, "atc-recent", "https://example.com/#atc-recent", true),
        (.contains, "atc-missing", "https://example.com/other", false),
        // Is equal to: host and path only, trailing slashes dropped.
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq?x=1", true),
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq#frag", true),
        (.equals, "example.com/atc-eq", "http://www.EXAMPLE.com/atc-eq/", true),
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq/more", false),
        // An empty route matches nothing.
        (.contains, "  ", "https://example.com/", false),
        (.equals, "", "https://example.com/", false),
    ])
    func matchesLikeArc(style: LinkMatchStyle, text: String, url: String, matches: Bool) {
        #expect(LinkRoute(match: style, text: text).matches(url) == matches)
    }

    @Test func firstMatchWinsElseTheDefault() {
        let work = UUID()
        var settings = AppSettings()
        settings.linkRoutes = [
            LinkRoute(match: .contains, text: "example.com", destination: .space(work)),
            LinkRoute(match: .contains, text: "example.com/call", destination: .littleWindowInUse),
            .googleMeet,
        ]
        #expect(settings.destination(forExternalURL: "https://example.com/call") == .space(work))
        #expect(settings.destination(forExternalURL: "https://meet.google.com/abc") == .mostRecentSpace)
        #expect(settings.destination(forExternalURL: "https://other.test/") == .littleWindowInUse, "no match: the default")
    }

    /// A Little Window route can name a space (#258): the route hands it on, the Little Window
    /// switch leaves it alone while it stays on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/258"))
    func littleWindowRouteNamesItsSpace() {
        let work = UUID()
        var settings = AppSettings()
        settings.linkRoutes = [LinkRoute(match: .contains, text: "work.example", destination: .littleWindow(space: work))]
        settings.defaultLinkDestination = .littleWindow(space: work)
        #expect(settings.destination(forExternalURL: "https://work.example/doc") == .littleWindow(space: work))
        #expect(settings.destination(forExternalURL: "https://other.test/") == .littleWindow(space: work))
        #expect(settings.openExternalLinksInLittleWindow)
        settings.openExternalLinksInLittleWindow = true
        #expect(settings.defaultLinkDestination == .littleWindow(space: work), "turning the switch on again keeps the space")
        settings.openExternalLinksInLittleWindow = false
        #expect(settings.defaultLinkDestination == .mostRecentSpace)
    }

    /// A URL typed in the ⌘T bar goes through the routes as in Arc 1.173 (#421): the first match
    /// wins and a route to a space sends the new tab there. The default never applies (a typed URL
    /// that matches nothing stays in the space in use, in Arc too), and neither does a first match
    /// to Most Recent Space or a Little Window, which leave it where it is.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/421"))
    func typedURLFollowsSpaceRoutes() {
        let personal = UUID(), work = UUID()
        var settings = AppSettings()
        settings.defaultLinkDestination = .space(work)
        settings.linkRoutes = [
            LinkRoute(match: .contains, text: "meet.google.com/abc", destination: .littleWindowInUse),
            LinkRoute(match: .contains, text: "meet.google.com", destination: .space(personal)),
            LinkRoute(match: .equals, text: "youtube.com", destination: .space(personal)),
            LinkRoute(match: .contains, text: "news.example", destination: .mostRecentSpace),
            LinkRoute(match: .contains, text: "example", destination: .space(work)),
        ]
        #expect(settings.space(forTypedURL: "https://meet.google.com/atc-typed-abc-defg") == personal)
        #expect(settings.space(forTypedURL: "https://www.youtube.com/") == personal)
        #expect(settings.space(forTypedURL: "https://example.com/a") == work)
        #expect(settings.space(forTypedURL: "https://meet.google.com/abc-defg") == nil, "first match: a Little Window")
        #expect(settings.space(forTypedURL: "https://news.example/") == nil, "first match: Most Recent Space")
        #expect(settings.space(forTypedURL: "https://other.test/") == nil, "no match: not the default")
    }

    /// settings.json: a Little Window without a space is saved as before #258, so files don't change
    /// on update, and one with a space still reads as a Little Window in Cra from before #258
    /// instead of failing and taking every route with it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/258"))
    func littleWindowSpaceFormat() throws {
        let work = try #require(UUID(uuidString: "A0000000-0000-0000-0000-000000000002"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ d: LinkDestination) throws -> String { String(decoding: try encoder.encode(d), as: UTF8.self) }
        #expect(try json(.littleWindowInUse) == #"{"littleWindow":{}}"#)
        #expect(try json(.littleWindow(space: work)) == #"{"littleWindow":{"space":"A0000000-0000-0000-0000-000000000002"}}"#)

        let decoder = JSONDecoder()
        #expect(try decoder.decode(LinkDestination.self, from: Data(#"{"littleWindow":{}}"#.utf8)) == .littleWindowInUse)
        #expect(try decoder.decode(LinkDestination.self, from: encoder.encode(LinkDestination.littleWindow(space: work))) == .littleWindow(space: work))

        let saved = try encoder.encode([LinkRoute(text: "a", destination: .littleWindow(space: work)), LinkRoute(text: "b", destination: .space(work))])
        let older = try decoder.decode([RouteBefore258].self, from: saved)
        #expect(older.map(\.destination) == [.littleWindow, .space(work)])
    }

    /// LinkRoute and LinkDestination as Cra 0.1.36 declared them.
    private struct RouteBefore258: Decodable {
        enum Destination: Decodable, Equatable { case mostRecentSpace, space(UUID), littleWindow }
        var destination: Destination
    }

    @Test func styles() {
        #expect(LinkMatchStyle.allCases.map(\.label) == ["Is equal to", "Contains"])
        #expect(LinkMatchStyle.allCases.map(\.id) == ["equals", "contains"])
        let route = LinkRoute()
        #expect(route.match == .contains && route.text.isEmpty && route.destination == .mostRecentSpace)
    }

    /// Peek's "other site": the registrable domain, with co.uk-style suffixes kept together.
    @Test(arguments: [
        ("https://mail.google.com/a", "google.com"),
        ("https://accounts.google.com/", "google.com"),
        ("https://Shop.Example.co.uk/basket", "example.co.uk"),
        ("https://a.b.example.com.au/", "example.com.au"),
        ("https://news.bbc.uk/", "bbc.uk"),
        ("https://example.com/", "example.com"),
        ("http://192.168.0.10:8080/", "192.168.0.10"),
        ("http://localhost:3000/", "localhost"),
    ])
    func siteOf(url: String, site: String) {
        #expect(SiteKey.site(of: url) == site)
    }

    @Test(arguments: ["file:///tmp/a.html", "about:blank", "chrome://extensions", "notes", "https:///path"])
    func noSiteOutsideTheWeb(url: String) {
        #expect(SiteKey.site(of: url) == nil)
    }

    /// In-app link clicks route to configured space routes (#868), excluding defaults,
    /// same-space, missing/standalone spaces, and non-http(s) schemes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/868"))
    func inAppLinkRoutesToTargetSpace() {
        let pro = UUID(), personal = UUID(), missing = UUID()
        var settings = AppSettings()
        settings.defaultLinkDestination = .space(personal)
        settings.linkRoutes = [
            LinkRoute(match: .contains, text: "scaler.com/stay", destination: .mostRecentSpace),
            LinkRoute(match: .contains, text: "scaler.com/little", destination: .littleWindowInUse),
            LinkRoute(match: .contains, text: "scaler.com", destination: .space(personal)),
            LinkRoute(match: .contains, text: "gone.example", destination: .space(missing)),
        ]
        let available: (UUID) -> Bool = { $0 == pro || $0 == personal }

        #expect(settings.space(forLinkURL: "https://www.scaler.com/problems/1", currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == personal)
        #expect(settings.space(forLinkURL: "https://www.scaler.com/problems/1", currentSpaceID: personal, isStandalone: false, spaceAvailable: available) == nil, "already in target space")
        #expect(settings.space(forLinkURL: "https://www.scaler.com/problems/1", currentSpaceID: pro, isStandalone: true, spaceAvailable: available) == nil, "standalone/incognito stays put")
        #expect(settings.space(forLinkURL: "https://www.scaler.com/stay", currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == nil, "first match Most Recent Space")
        #expect(settings.space(forLinkURL: "https://www.scaler.com/little", currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == nil, "first match Little Window")
        #expect(settings.space(forLinkURL: "https://gone.example/x", currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == nil, "deleted/unavailable space")
        #expect(settings.space(forLinkURL: "https://unmatched.example/", currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == nil, "default never applies")

        for nonWeb in ["about:blank", "data:text/html,scaler.com", "javascript:scaler.com", "blob:https://scaler.com/1", "cra://open?url=scaler.com", "chrome://version", "file:///scaler.com", ""] {
            #expect(settings.space(forLinkURL: nonWeb, currentSpaceID: pro, isStandalone: false, spaceAvailable: available) == nil)
        }
    }

    /// A new tab moves to the route's space when its redirect lands (#868): while its first page loads, and
    /// for `clientRedirectGrace` after, so a 200 redirector (google.com/url?q=…) that moves on by script still
    /// routes. It moves once, and the window follows only when the tab is the one in front.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/868"))
    func transientTabMovesOnRedirectAndGuardedAgainstLoops() {
        let pro = UUID(), personal = UUID(), work = UUID()
        let available: (UUID) -> Bool = { $0 == pro || $0 == personal || $0 == work }
        let routes = [
            LinkRoute(match: .contains, text: "scaler.com", destination: .space(personal)),
            LinkRoute(match: .contains, text: "pro.example", destination: .space(pro)),
            LinkRoute(match: .contains, text: "work.example", destination: .space(work)),
        ]
        let t0 = Date(timeIntervalSince1970: 1_000)
        func decide(_ url: String, in space: UUID = pro, inFront: Bool = true, standalone: Bool = false,
                    _ state: inout LinkRedirectState, at now: Date) -> LinkRedirectDecision {
            LinkRedirectRouting.decision(for: url, currentSpaceID: space, isStandalone: standalone, isPinnedOrFavorite: false,
                                         inSplit: false, isInFront: inFront, state: &state, routes: routes,
                                         spaceAvailable: available, now: now)
        }

        // The redirector loads and finishes; its script moves on inside the grace: the tab goes, the window with it.
        var fg = LinkRedirectState()
        #expect(decide("about:blank", &fg, at: t0) == .none)
        #expect(decide("https://www.google.com/url?q=encoded", &fg, at: t0) == .none)
        #expect(fg.isTransient)
        fg.noteLoadFinished(at: t0)
        #expect(fg.isWithinTransientWindow(at: t0.addingTimeInterval(LinkRedirectState.clientRedirectGrace - 0.5)))
        #expect(decide("https://www.scaler.com/problems/1", &fg, at: t0.addingTimeInterval(1)) == .moveTab(toSpace: personal, follow: true))
        #expect(!fg.isTransient)

        // Moved once: a redirect on to another routed space doesn't bounce it again.
        #expect(decide("https://pro.example/back", in: personal, &fg, at: t0.addingTimeInterval(1.1)) == .none)
        #expect(decide("https://work.example/next", in: personal, &fg, at: t0.addingTimeInterval(1.2)) == .none)

        // A tab that isn't the one in front (opened behind, or the user went to another tab) moves on its own.
        var behind = LinkRedirectState()
        #expect(decide("https://www.scaler.com/problems/2", inFront: false, &behind, at: t0) == .moveTab(toSpace: personal, follow: false))

        // Before the first page has loaded there's no deadline: a slow redirect chain still routes.
        var slow = LinkRedirectState()
        #expect(decide("https://www.scaler.com/problems/slow", &slow, at: t0.addingTimeInterval(60)) == .moveTab(toSpace: personal, follow: true))

        // Past the grace the tab has settled: the address stays in it, for good.
        var expired = LinkRedirectState()
        expired.noteLoadFinished(at: t0)
        let afterGrace = t0.addingTimeInterval(LinkRedirectState.clientRedirectGrace + 0.5)
        #expect(!expired.isWithinTransientWindow(at: afterGrace))
        #expect(decide("https://www.scaler.com/problems/3", &expired, at: afterGrace) == .none)
        #expect(!expired.isTransient)

        // An incognito or standalone tab never routes.
        var standalone = LinkRedirectState()
        #expect(decide("https://www.scaler.com/problems/4", standalone: true, &standalone, at: t0) == .none)
        #expect(LinkRedirectRouting.normalizedHost(of: "https://WWW.Scaler.com/a") == "scaler.com")
        #expect(LinkRedirectRouting.normalizedHost(of: "about:blank") == nil)
    }

    /// A navigation inside any other tab stays in that tab and its space (#868), as in Arc, whose Air Traffic
    /// Control never routes in-tab navigation: a pinned, favorite or split tab, one that has settled, and one
    /// whose address the user typed (⌘L).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/868"))
    func settledPinnedFavoriteAndSplitTabsStayInTheirTab() {
        let pro = UUID(), personal = UUID()
        let available: (UUID) -> Bool = { $0 == pro || $0 == personal }
        let routes = [LinkRoute(match: .contains, text: "scaler", destination: .space(personal))]
        let t0 = Date(timeIntervalSince1970: 2_000)

        for (pinnedOrFavorite, inSplit) in [(true, false), (false, true)] {
            var state = LinkRedirectState()
            #expect(LinkRedirectRouting.decision(for: "https://www.scaler.com/problems/1", currentSpaceID: pro, isStandalone: false,
                                                 isPinnedOrFavorite: pinnedOrFavorite, inSplit: inSplit, isInFront: true, state: &state,
                                                 routes: routes, spaceAvailable: available, now: t0) == .none)
        }

        var settled = LinkRedirectState()
        settled.noteLoadFinished(at: t0)
        var typed = LinkRedirectState()
        typed.retireTransient()
        for var state in [settled, typed] {
            for (i, url) in ["https://www.scaler.com/problems/1", "https://www.google.com/search?q=scaler"].enumerated() {
                #expect(LinkRedirectRouting.decision(for: url, currentSpaceID: pro, isStandalone: false, isPinnedOrFavorite: false,
                                                     inSplit: false, isInFront: true, state: &state, routes: routes,
                                                     spaceAvailable: available, now: t0.addingTimeInterval(5 + Double(i))) == .none)
            }
        }
    }
}
