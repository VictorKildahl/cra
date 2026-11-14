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
}
