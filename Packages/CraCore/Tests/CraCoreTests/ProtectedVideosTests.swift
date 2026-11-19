import CraCore
import Foundation
import Testing
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// `ProtectedVideoPages` behind methods that don't mutate, so a call can sit inside `#expect`.
private final class Pages {
    var value = ProtectedVideoPages()
    let sites: ProtectedMediaSites
    init(_ sites: ProtectedMediaSites) { self.sites = sites }

    var switched: [UUID: SwitchedPage] { value.switched }
    func requested(_ tab: UUID, _ url: String, _ choices: ProtectedMediaChoices) -> ProtectedVideoPages.Step {
        value.widevineRequested(tab: tab, url: url, sites: sites, choices: choices)
    }
    func prompt(_ tab: UUID, _ url: String, incognito: Bool = false) -> ProtectedVideoPrompt? {
        value.prompt(tab: tab, url: url, incognito: incognito, sites: sites)
    }
    func asked(_ tab: UUID, _ url: String) -> Bool { value.asked(tab: tab, url: url, sites: sites) }
    func navigated(_ tab: UUID, _ url: String) { value.navigated(tab: tab, to: url, sites: sites) }
    @discardableResult
    func switching(_ tab: UUID, _ url: String, _ how: SwitchedPage.How, resumeAt: Double? = nil) -> SwitchedPage? {
        value.switching(tab: tab, url: url, how: how, resumeAt: resumeAt, sites: sites)
    }
    func declining(_ tab: UUID, _ url: String) { value.declining(tab: tab, url: url, sites: sites) }
    func leaves(_ tab: UUID, _ url: String) -> Bool { value.leaves(tab: tab, to: url, sites: sites) }
    func row(_ tab: UUID, _ url: String, _ engine: PageEngine, drm: Bool = false, _ choices: ProtectedMediaChoices) -> SafariEngineRow? {
        value.row(tab: tab, url: url, engine: engine, askedForWidevine: drm, sites: sites, choices: choices)
    }
}

/// Protected videos on sites that are mostly not DRM (YouTube's films): the page that plays one
/// moves to WebKit after the user is asked, Once or Always, and only that page.
struct ProtectedVideosTests {
    let sites = ProtectedMediaSites()
    let tab = UUID()
    let film = "https://www.youtube.com/watch?v=film1"

    // MARK: Which sites are mixed

    @Test(arguments: [
        "https://www.youtube.com/watch?v=film1",
        "https://youtube.com/",
        "https://m.youtube.com/watch?v=x",
        "https://tv.youtube.com/watch/x",
    ])
    func youTubeIsMixed(url: String) {
        #expect(sites.mixedSite(for: url)?.name == "YouTube")
        // Mixed is not listed: a page Cra opens there is still Chromium's.
        #expect(sites.engine(for: url) == .chromium)
        #expect(sites.handoff(from: .chromium, to: url, method: "GET") == nil)
    }

    @Test(arguments: [
        "https://music.youtube.com/watch?v=x",
        "https://notyoutube.com/watch?v=x",
        "https://youtube.com.evil.example/watch?v=x",
        "https://www.youtube-nocookie.com/embed/x",
        "https://www.netflix.com/watch/1",
        "https://www.google.com/search?q=youtube.com",
        "chrome://settings",
        "",
    ])
    func otherSitesAreNot(url: String) {
        #expect(sites.mixedSite(for: url) == nil)
        #expect(sites.pageKey(for: url) == nil)
    }

    @Test func offOrWholeSiteMeansNotMixed() {
        #expect(ProtectedMediaSites(isEnabled: false).mixedSite(for: film) == nil)
        // The whole site added with the existing switch: every page is WebKit's, nothing to ask.
        let added = ProtectedMediaSites(extraHosts: ["www.youtube.com"])
        #expect(added.mixedSite(for: film) == nil && added.engine(for: film) == .webKit)
        // A run can list its own (the scenarios' fixture server).
        let run = ProtectedMediaSites(mixedHosts: ["127.0.0.1", " Example.org "])
        #expect(run.mixedSite(for: "http://127.0.0.1:8000/drm.html")?.host == "127.0.0.1")
        #expect(run.mixedSite(for: "https://video.example.org/x")?.name == "example.org")
        #expect(run.mixedSite(for: film)?.name == "YouTube")
    }

    // MARK: What a page is

    @Test func pageIsItsVideo() {
        #expect(sites.pageKey(for: film) == "youtube.com/watch?v=film1")
        // A time, a playlist, a fragment or another YouTube host don't make it another page.
        for same in ["https://www.youtube.com/watch?v=film1&t=90s", "https://youtube.com/watch?list=PL1&v=film1&index=2",
                     "https://m.youtube.com/watch?v=film1#comments", "https://www.youtube.com/watch/?v=film1"] {
            #expect(sites.pageKey(for: same) == sites.pageKey(for: film), "\(same)")
        }
        #expect(sites.pageKey(for: "https://www.youtube.com/watch?v=film2") == "youtube.com/watch?v=film2")
        #expect(sites.pageKey(for: "https://www.youtube.com/watch?v=Film1") != sites.pageKey(for: film))
        #expect(sites.pageKey(for: "https://www.youtube.com/") == "youtube.com")
        #expect(sites.pageKey(for: "https://www.youtube.com/feed/library?v=film1") == "youtube.com/feed/library?v=film1")
        // A site with no video parameter: the whole query is the page.
        let run = ProtectedMediaSites(mixedHosts: ["127.0.0.1"])
        #expect(run.pageKey(for: "http://127.0.0.1:8000/drm.html?n=1&a=2#x") == "127.0.0.1/drm.html?a=2&n=1")
        #expect(run.pageKey(for: "http://127.0.0.1:8000/drm.html?n=2") != run.pageKey(for: "http://127.0.0.1:8000/drm.html?n=1"))
    }

    // MARK: A switched page stays that page

    @Test func switchedPageHoldsForItsVideoAndSignIn() {
        let page = SwitchedPage(site: "youtube.com", key: "youtube.com/watch?v=film1", how: .once)
        for stays in [film, film + "&t=10s", "https://accounts.google.com/ServiceLogin?service=youtube",
                      "https://accounts.google.co.in.example/".replacingOccurrences(of: ".co.in.example", with: ".com"),
                      "https://accounts.youtube.com/accounts/SetSID?x=1", "https://consent.youtube.com/m?continue=x",
                      "https://www.youtube.com/signin?action_handle_signin=true&next=%2Fwatch%3Fv%3Dfilm1"] {
            #expect(sites.holds(page, at: stays), "\(stays)")
            #expect(sites.engine(for: stays, switched: page) == .webKit)
        }
        for leaves in ["https://www.youtube.com/watch?v=film2", "https://www.youtube.com/", "https://www.youtube.com/results?search_query=x",
                       "https://music.youtube.com/watch?v=film1", "https://example.com/", "https://www.youtube.com/signing",
                       "about:blank"] {
            #expect(!sites.holds(page, at: leaves), "\(leaves)")
            #expect(sites.engine(for: leaves, switched: page) == .chromium)
        }
        // A listed service is WebKit's with or without a switch; no switch changes nothing.
        #expect(sites.engine(for: "https://www.netflix.com/", switched: page) == .webKit)
        #expect(sites.engine(for: film, switched: nil) == .chromium)
        #expect(!ProtectedMediaSites(isEnabled: false).holds(page, at: film))
    }

    // MARK: Asking, Once, Always

    @Test func asksOnceAndOnlyOnMixedSites() {
        let pages = Pages(sites)
        let choices = ProtectedMediaChoices()
        #expect(pages.requested(tab, "https://stream.example.org/film", choices) == .nothing)
        #expect(pages.prompt(tab, film) == nil)
        #expect(pages.requested(tab, film, choices) == .asks)
        let prompt = pages.prompt(tab, film)
        #expect(prompt?.site.name == "YouTube" && prompt?.choices == [.once, .always])
        #expect(ProtectedVideoPrompt.text.contains("Safari's engine") && ProtectedVideoPrompt.text.contains("no extensions"))
        // The prompt is that page's: not another tab's, not this tab's at another video.
        #expect(pages.prompt(UUID(), film) == nil)
        #expect(pages.prompt(tab, "https://www.youtube.com/watch?v=other") == nil)
        // Asked again while it waits (the player asks more than once): still one prompt.
        #expect(pages.requested(tab, film + "&t=5s", choices) == .asks)
        // An incognito page offers Once only.
        #expect(pages.prompt(tab, film, incognito: true)?.choices == [.once])
    }

    @Test func closingThePromptLeavesThatPageInChromium() {
        let pages = Pages(sites)
        let choices = ProtectedMediaChoices()
        _ = pages.requested(tab, film, choices)
        pages.declining(tab, film)
        #expect(pages.prompt(tab, film) == nil)
        #expect(pages.requested(tab, film, choices) == .nothing)
        #expect(pages.requested(tab, film + "&t=30s", choices) == .nothing)
        #expect(pages.prompt(tab, film) == nil)
        // Another video in the tab, and the same video in another tab, are asked about.
        #expect(pages.requested(tab, "https://www.youtube.com/watch?v=film2", choices) == .asks)
        #expect(pages.requested(UUID(), film, choices) == .asks)
        // The row still offers it.
        _ = pages.requested(tab, film, choices)
        #expect(pages.row(tab, film, .chromium, choices) == .videosOff)
    }

    @Test func aPromptLeftOpenGoesWithItsPage() {
        let pages = Pages(sites)
        _ = pages.requested(tab, film, ProtectedMediaChoices())
        pages.navigated(tab, film + "&t=40s")
        #expect(pages.prompt(tab, film) != nil)
        pages.navigated(tab, "https://www.youtube.com/watch?v=cat")
        #expect(pages.prompt(tab, film) == nil)
        #expect(!pages.asked(tab, film))
    }

    @Test func onceMovesThatPageOnly() {
        let pages = Pages(sites)
        let choices = ProtectedMediaChoices()
        _ = pages.requested(tab, film, choices)
        let page = pages.switching(tab, film + "&t=90s", .once, resumeAt: 90)
        #expect(page == SwitchedPage(site: "youtube.com", key: "youtube.com/watch?v=film1", how: .once, resumeAt: 90))
        #expect(pages.switched[tab] == page)
        #expect(pages.prompt(tab, film) == nil)
        pages.value.resumed(tab: tab)
        #expect(pages.switched[tab]?.resumeAt == nil)
        // Nothing was stored for the site.
        #expect(choices.protectedVideos.isEmpty)
        // The same video, a time in it and the sign-in keep the page; the next video sends it back.
        #expect(!pages.leaves(tab, film + "&t=200s"))
        #expect(!pages.leaves(tab, "https://accounts.google.com/signin"))
        #expect(pages.switched[tab] != nil)
        #expect(pages.leaves(tab, "https://www.youtube.com/watch?v=cat"))
        #expect(pages.switched[tab] == nil)
        #expect(!pages.leaves(tab, "https://www.youtube.com/"), "a tab with no switched page has nothing to return")
        // Back at the film in Chromium it asks again: Once was for that time.
        #expect(pages.requested(tab, film, choices) == .asks)
        // Off a mixed site there is nothing to switch.
        #expect(pages.switching(tab, "https://example.com/", .once) == nil)
    }

    @Test func alwaysIsStoredPerSiteAndSkipsThePrompt() {
        let pages = Pages(sites)
        let youTube = try! #require(sites.mixedSite(for: film))
        let choices = ProtectedMediaChoices(added: ["www.viaplay.dk"], told: ["Spotify"]).switchingProtectedVideos(true, on: youTube)
        #expect(choices.protectedVideos == ["youtube.com"] && choices.added == ["www.viaplay.dk"] && choices.told == ["Spotify"])
        #expect(choices.switchingProtectedVideos(true, on: youTube) == choices)
        // Not the whole site: its pages are still Chromium's.
        #expect(ProtectedMediaSites(extraHosts: choices.added, removedHosts: choices.removed).engine(for: film) == .chromium)
        #expect(pages.requested(tab, film, choices) == .switches)
        #expect(pages.prompt(tab, film) == nil)
        // A page left in Chromium earlier switches too once Always is chosen.
        pages.declining(tab, film)
        #expect(pages.requested(tab, film, choices) == .switches)
        // The per-page rule still holds.
        pages.switching(tab, film, .always)
        #expect(pages.leaves(tab, "https://www.youtube.com/"))
        // Taken back, it asks again.
        let back = choices.switchingProtectedVideos(false, on: youTube)
        #expect(back.protectedVideos.isEmpty && back.added == ["www.viaplay.dk"])
        let fresh = Pages(sites)
        #expect(fresh.requested(tab, film, back) == .asks)
        // The other choices leave it alone.
        #expect(choices.telling("Max").protectedVideos == ["youtube.com"])
        #expect(choices.choosing(.webKit, for: "https://stream.example.org/").protectedVideos == ["youtube.com"])
    }

    // MARK: The Site Control Center's row

    @Test func rowSaysWhatIsInForce() {
        let pages = Pages(sites)
        let none = ProtectedMediaChoices()
        let youTube = try! #require(sites.mixedSite(for: film))
        let always = none.switchingProtectedVideos(true, on: youTube)
        func row(_ url: String, _ engine: PageEngine, drm: Bool = false, _ choices: ProtectedMediaChoices) -> SafariEngineRow? {
            pages.row(tab, url, engine, drm: drm, choices)
        }
        // As before for whole sites: on for a WebKit page, off for a Chromium page that asked, else no row.
        #expect(row("https://www.netflix.com/", .webKit, none) == .on)
        #expect(row("https://stream.example.org/", .chromium, drm: true, none) == .off)
        #expect(row("https://stream.example.org/", .chromium, none) == nil)
        // A mixed site: nothing until a page asks, then Off.
        #expect(row(film, .chromium, none) == nil)
        #expect(row(film, .chromium, drm: true, none) == nil, "a mixed site's row follows the request Cra saw, per page")
        _ = pages.requested(tab, film, none)
        #expect(row(film, .chromium, none) == .videosOff)
        #expect(row("https://www.youtube.com/watch?v=cat", .chromium, none) == nil)
        // Always: on any page of the site, switched or not.
        #expect(row("https://www.youtube.com/", .chromium, always) == .protectedVideos)
        #expect(row("https://music.youtube.com/", .chromium, always) == nil)
        // Switched Once; with Always in force the row says that instead.
        pages.switching(tab, film, .once)
        #expect(row(film, .webKit, none) == .thisVideo)
        #expect(row("https://accounts.google.com/", .webKit, none) == .thisVideo)
        #expect(row(film, .webKit, always) == .protectedVideos)
        // Turned off on a switched page: back to Chromium, and that page isn't asked about again.
        pages.value.returning(tab: tab)
        #expect(pages.switched[tab] == nil)
        #expect(pages.requested(tab, film, none) == .nothing)
        #expect(row(film, .chromium, none) == .videosOff)
        // Its click (Always) switches it after all.
        #expect(pages.switching(tab, film, .always) != nil)
        pages.value.returning(tab: tab)
        pages.value.forget(tab: tab)
        #expect(pages.requested(tab, film, none) == .asks)

        #expect(ProtectedVideoPages.rowSwitch(incognito: false) == .always && ProtectedVideoPages.rowSwitch(incognito: true) == .once)
        #expect(SafariEngineRow.on.state == "On" && SafariEngineRow.off.state == "Off" && SafariEngineRow.videosOff.state == "Off")
        #expect(SafariEngineRow.protectedVideos.state == "Protected Videos" && SafariEngineRow.thisVideo.state == "This Video")
        #expect([SafariEngineRow.on, .protectedVideos, .thisVideo].allSatisfy(\.isOn) && !SafariEngineRow.off.isOn && !SafariEngineRow.videosOff.isOn)
    }

    // MARK: protected-media.json

    @Test func alwaysIsAFieldOfItsOwnInTheFile() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A file from before the field loads with none, and is written back as it was.
        let old = try JSONDecoder().decode(ProtectedMediaChoices.self, from: Data(#"{"added":["a.com"],"removed":[],"told":["Netflix"]}"#.utf8))
        #expect(old.protectedVideos.isEmpty)
        #expect(String(data: try encoder.encode(old), encoding: .utf8) == #"{"added":["a.com"],"removed":[],"told":["Netflix"]}"#)
        let youTube = try #require(sites.mixedSite(for: film))
        let chosen = old.switchingProtectedVideos(true, on: youTube)
        let written = try #require(String(data: try encoder.encode(chosen), encoding: .utf8))
        #expect(written == #"{"added":["a.com"],"protectedVideos":["youtube.com"],"removed":[],"told":["Netflix"]}"#)
        #expect(try JSONDecoder().decode(ProtectedMediaChoices.self, from: Data(written.utf8)) == chosen)
    }

    // MARK: What goes with the page

    @Test func theAddressCarriesTheTimeWhereTheSiteHasOne() {
        var r = ProtectedVideoHandoff.address(for: film, at: 754.6, sites: sites)
        #expect(r.url == "https://www.youtube.com/watch?v=film1&t=754s" && r.seek == nil)
        r = ProtectedVideoHandoff.address(for: film + "&t=12s&list=PL1", at: 90, sites: sites)
        #expect(r.url == "https://www.youtube.com/watch?v=film1&list=PL1&t=90s" && r.seek == nil)
        #expect(sites.pageKey(for: r.url) == sites.pageKey(for: film))
        // The start of a video, no video, or nonsense: the address as it is.
        for none: Double? in [nil, -1, 0, 4.9, .nan, .infinity] {
            r = ProtectedVideoHandoff.address(for: film, at: none, sites: sites)
            #expect(r.url == film && r.seek == nil)
        }
        // A site with no time in its address keeps it, and the page seeks.
        let run = ProtectedMediaSites(mixedHosts: ["127.0.0.1"])
        r = ProtectedVideoHandoff.address(for: "http://127.0.0.1:8000/drm.html?n=1", at: 42.5, sites: run)
        #expect(r.url == "http://127.0.0.1:8000/drm.html?n=1" && r.seek == 42.5)
        // Off a mixed site nothing is carried.
        r = ProtectedVideoHandoff.address(for: "https://example.com/v", at: 42, sites: sites)
        #expect(r.url == "https://example.com/v" && r.seek == nil)
    }

    @Test func cookiesOfTheSiteAndItsSignInAreCopied() throws {
        let youTube = try #require(sites.mixedSite(for: film))
        #expect(ProtectedVideoHandoff.cookieDomains(for: youTube) == ["youtube.com", "google.com", "accounts.youtube.com", "consent.youtube.com"])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let answer = """
        {"cookies":[
          {"name":"SID","value":"s1","domain":".google.com","path":"/","expires":1900000000.5,"httpOnly":false,"secure":false,"session":false},
          {"name":"__Secure-1PSID","value":"s2","domain":".google.com","path":"/","expires":1900000000,"httpOnly":true,"secure":true,"session":false,"sameSite":"None"},
          {"name":"__Host-GAPS","value":"g","domain":"accounts.google.com","path":"/","expires":1900000000,"httpOnly":true,"secure":true,"session":false},
          {"name":"LOGIN_INFO","value":"l","domain":".youtube.com","path":"/","expires":1900000000,"httpOnly":true,"secure":true,"session":false,"sameSite":"None"},
          {"name":"PREF","value":"f6=4","domain":".youtube.com","path":"/","expires":-1,"httpOnly":false,"secure":true,"session":true,"sameSite":"Lax"},
          {"name":"strict","value":"1","domain":"www.youtube.com","path":"/feed","expires":1900000000,"session":false,"sameSite":"Strict"},
          {"name":"old","value":"1","domain":".youtube.com","path":"/","expires":1700000000,"session":false},
          {"name":"embed","value":"1","domain":".youtube.com","path":"/","expires":1900000000,"session":false,"partitionKey":{"topLevelSite":"https://example.com","hasCrossSiteAncestor":true}},
          {"name":"music","value":"1","domain":"music.youtube.com","path":"/","expires":1900000000,"session":false},
          {"name":"sid","value":"bank","domain":".bank.example","path":"/","expires":1900000000,"session":false},
          {"name":"x","value":"1","domain":".notgoogle.com","path":"/","expires":1900000000,"session":false},
          {"name":"y","value":"1","domain":"google.com.evil.example","path":"/","expires":1900000000,"session":false},
          {"name":"","value":"1","domain":".youtube.com","path":"/"},
          {"value":"1","domain":".youtube.com"}
        ]}
        """
        let cookies = ProtectedVideoHandoff.cookies(fromProtocolAnswer: answer, for: youTube, now: now)
        #expect(cookies.map(\.name) == ["SID", "__Secure-1PSID", "__Host-GAPS", "LOGIN_INFO", "PREF", "strict"])
        let by = Dictionary(uniqueKeysWithValues: cookies.map { ($0.name, $0) })
        let sid = try #require(by["SID"])
        #expect(sid.value == "s1" && sid.domain == ".google.com" && sid.path == "/" && !sid.isSecure && !sid.isHTTPOnly && !sid.isSessionOnly)
        // Foundation caps a cookie's life at 400 days from today, so the date is at most the one given.
        #expect((sid.expiresDate?.timeIntervalSince1970 ?? .infinity) <= 1_900_000_001)
        let secure = try #require(by["__Secure-1PSID"])
        #expect(secure.isSecure && secure.isHTTPOnly && secure.sameSitePolicy == nil)
        // A host-only cookie stays host-only.
        #expect(by["__Host-GAPS"]?.domain == "accounts.google.com")
        let pref = try #require(by["PREF"])
        #expect(pref.isSessionOnly && pref.expiresDate == nil && pref.sameSitePolicy == .sameSiteLax)
        #expect(by["strict"]?.sameSitePolicy == .sameSiteStrict && by["strict"]?.path == "/feed")
        // An answer that isn't one copies nothing.
        #expect(ProtectedVideoHandoff.cookies(fromProtocolAnswer: "", for: youTube).isEmpty)
        #expect(ProtectedVideoHandoff.cookies(fromProtocolAnswer: #"{"error":"no"}"#, for: youTube).isEmpty)
        // A plain mixed site copies its own only.
        let run = try #require(ProtectedMediaSites(mixedHosts: ["127.0.0.1"]).mixedSite(for: "http://127.0.0.1:1/"))
        let own = ProtectedVideoHandoff.cookies(fromProtocolAnswer: #"{"cookies":[{"name":"a","value":"1","domain":"127.0.0.1","path":"/","expires":-1,"session":true},{"name":"b","value":"1","domain":"localhost","path":"/","expires":-1,"session":true}]}"#, for: run, now: now)
        #expect(own.map(\.name) == ["a"] && own.first?.domain == "127.0.0.1")
    }

    #if canImport(JavaScriptCore)
    // MARK: A request in any frame is the page's

    /// A top frame, a player frame of its origin and one of another origin (`deep`), each with the
    /// page's world wrapper and Cra's world, as PageScript runs them: `top`, `frame` and `deep` are the windows, `ask(w)` is the frame's page calling
    /// requestMediaKeySystemAccess, `seen` what the page's own message listener got.
    private func framedPage() throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, error in Issue.record("script threw: \(error?.toString() ?? "?")") }
        let pageWorld = try #require(String(data: JSONEncoder().encode(WidevineSignal.pageWorld(channel: "chan")), encoding: .utf8))
        let isolated = try #require(String(data: JSONEncoder().encode(WidevineSignal.isolatedWorld(channel: "chan")), encoding: .utf8))
        context.evaluateScript("""
        function CustomEvent(type) { this.type = type; }
        function makeWindow(href, top) {
          const w = { listeners: [], location: { href }, asked: [] };
          w.top = top || w;
          w.addEventListener = (type, f, capture) => w.listeners.push({ type, f });
          w.dispatchEvent = e => {
            let stopped = false;
            e.stopImmediatePropagation = () => { stopped = true; };
            for (const l of w.listeners.slice()) { if (l.type === e.type && !stopped) l.f(e); }
          };
          w.postMessage = (data, origin) => w.dispatchEvent({ type: 'message', data });
          function Navigator() {}
          Navigator.prototype.requestMediaKeySystemAccess = function (keySystem) { w.asked.push(keySystem); return 'access'; };
          w.Navigator = Navigator;
          w.navigator = new Navigator();
          // Cra's world first (document start), then the page's world and the page's own listener.
          new Function('window', 'addEventListener', 'location', 'CustomEvent', 'const cra = window.__cra = {};' + \(isolated))(w, w.addEventListener, w.location, CustomEvent);
          new Function('window', 'dispatchEvent', 'CustomEvent', \(pageWorld))(w, w.dispatchEvent, CustomEvent);
          return w;
        }
        var top = makeWindow('https://athome.example/watch/1');
        var seen = [];
        top.addEventListener('message', e => seen.push(e.data));
        var frame = makeWindow('https://athome.example/player_frame.html', top);
        // A frame of another origin sees a top it can post to and nothing else.
        var posted = 0;
        var foreignTop = { postMessage: (data, origin) => { posted++; top.postMessage(data, origin); },
                           get dispatchEvent() { throw new Error('SecurityError'); } };
        var deep = makeWindow('https://player.example/inner.html', foreignTop);
        var ask = (w, keySystem) => w.navigator.requestMediaKeySystemAccess(keySystem || 'com.widevine.alpha');
        var next = []; var wait = () => { top.__cra.drmNext().then(v => next.push(v)); };
        """)
        return context
    }

    @Test func aFramesRequestCountsForItsPage() throws {
        let page = try framedPage()
        func bool(_ js: String) -> Bool { page.evaluateScript(js).toBool() }
        func text(_ js: String) -> String { page.evaluateScript(js).toString() }
        #expect(!bool("top.__cra.drm === true"))
        // Another key system, in the frame: not Widevine, nothing is told; the call still goes through.
        #expect(text("ask(frame, 'com.apple.fps')") == "access" && !bool("top.__cra.drm === true || frame.__cra.drm === true"))
        // The player frame asks for Widevine: the top frame knows, without a message the page could see.
        page.evaluateScript("wait()")
        #expect(text("next.join()") == "")
        #expect(text("ask(frame)") == "access" && text("frame.asked.join()") == "com.apple.fps,com.widevine.alpha")
        #expect(bool("frame.__cra.drm === true") && bool("top.__cra.drm === true"))
        #expect(text("seen.join()") == "" && text("posted") == "0")
        #expect(text("next.join()") == "https://athome.example/watch/1", "the waiting ask answers with the page's address, not the frame's")
        // Any other message reaches the page as before.
        page.evaluateScript("top.postMessage('hello')")
        #expect(text("seen.join()") == "hello")
        // A frame of another origin can't reach the top window: it posts, and the top frame keeps that
        // message from the page's own listeners.
        page.evaluateScript("wait(); ask(deep, 'com.widevine.alpha.experiment')")
        #expect(text("next.length") == "2" && text("top.__cra.drmN") == "2" && text("posted") == "1")
        #expect(text("seen.join()") == "hello")
    }

    @Test func thePageTellsWhenItAsksAgain() throws {
        let page = try framedPage()
        func text(_ js: String) -> String { page.evaluateScript(js).toString() }
        // The top frame's own request, made before anyone waits, is kept for the first ask.
        page.evaluateScript("ask(top); wait()")
        #expect(text("next.join('|')") == "https://athome.example/watch/1")
        // A second ask waits for the next request; a third takes its place, and the second answers "".
        page.evaluateScript("wait(); wait()")
        #expect(text("next.length") == "2" && text("next[1]") == "")
        // The next video without a new request: its `encrypted` event counts, in the frame that asked.
        page.evaluateScript("frame.dispatchEvent({ type: 'encrypted' })")
        #expect(text("next.length") == "2", "the frame never asked for Widevine: its encrypted media isn't a request")
        page.evaluateScript("top.location.href = 'https://athome.example/watch/2'; top.dispatchEvent({ type: 'encrypted' })")
        #expect(text("next.length") == "3" && text("next[2]") == "https://athome.example/watch/2")
        page.evaluateScript("ask(frame); wait(); frame.dispatchEvent({ type: 'encrypted' }); wait()")
        #expect(text("next.length") == "5" && text("top.__cra.drmN") == "4")
        // Encrypted media on a page that never asked for Widevine (FairPlay, Clear Key) is nobody's request.
        let other = try framedPage()
        other.evaluateScript("wait(); top.dispatchEvent({ type: 'encrypted' }); frame.dispatchEvent({ type: 'encrypted' })")
        #expect(other.evaluateScript("next.length").toString() == "0" && !other.evaluateScript("top.__cra.drm === true").toBool())
    }

    /// The scripts run in a JavaScript engine against stand-ins for the page.
    @Test func theTimeIsThePlayingVideos() throws {
        func time(_ videos: String) throws -> Double {
            let context = try #require(JSContext())
            context.evaluateScript("var document = { querySelectorAll: () => \(videos) };")
            return try #require(context.evaluateScript(ProtectedVideoHandoff.playbackTimeScript)).toDouble()
        }
        #expect(try time("[]") == -1)
        #expect(try time("[{ currentTime: 0, duration: 100, paused: true }]") == -1)
        #expect(try time("[{ currentTime: 12.5, duration: 100, paused: true }]") == 12.5)
        // The one that plays, not a paused preview further in; a live stream has no place.
        #expect(try time("[{ currentTime: 80, duration: 100, paused: true }, { currentTime: 30, duration: 5400, paused: false }]") == 30)
        #expect(try time("[{ currentTime: 80, duration: 100, paused: true }, { currentTime: 30, duration: 5400, paused: true }]") == 80)
        #expect(try time("[{ currentTime: 300, duration: Infinity, paused: false }]") == -1)
    }

    @Test func thePageSeeksOnceOnItsOwnAddress() throws {
        func seeks(href: String, now: Double, top: Bool = true) throws -> [Double] {
            let context = try #require(JSContext())
            context.evaluateScript("""
            var listeners = {}; var seeks = [];
            function HTMLVideoElement(d) { this.duration = d; }
            Object.defineProperty(HTMLVideoElement.prototype, 'currentTime', { set(t) { seeks.push(t); } });
            var window = this; var top = \(top ? "this" : "{}");
            var location = { href: '\(href)' };
            Date.now = () => \(now);
            function addEventListener(type, f) { listeners[type] = f; }
            """)
            context.evaluateScript(ProtectedVideoHandoff.seekScript(url: "http://127.0.0.1:8000/drm.html?n=1", seconds: 42.5, until: 2000))
            context.evaluateScript("""
            if (listeners.loadedmetadata) {
              listeners.loadedmetadata({ target: {} });
              listeners.loadedmetadata({ target: new HTMLVideoElement(NaN) });
              listeners.durationchange({ target: new HTMLVideoElement(30) });
              listeners.durationchange({ target: new HTMLVideoElement(600) });
              listeners.loadedmetadata({ target: new HTMLVideoElement(600) });
            }
            """)
            return (context.evaluateScript("seeks").toArray() as? [Double]) ?? []
        }
        #expect(try seeks(href: "http://127.0.0.1:8000/drm.html?n=1", now: 1000) == [42.5])
        #expect(try seeks(href: "http://127.0.0.1:8000/drm.html?n=2", now: 1000).isEmpty)
        #expect(try seeks(href: "http://127.0.0.1:8000/drm.html?n=1", now: 3000).isEmpty)
        #expect(try seeks(href: "http://127.0.0.1:8000/drm.html?n=1", now: 1000, top: false).isEmpty)
    }
    #endif
}
