import CraCore
import Foundation
import Testing

struct LinkSummaryTests {
    private func u(_ s: String) -> URL { URL(string: s)! }

    // MARK: - Which hovers show a card

    @Test func autoSitesAreArcsThree() {
        #expect(LinkSummaryPolicy.autoSite(page: u("https://news.ycombinator.com/")) == .hackerNews)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://news.ycombinator.com/item?id=1")) == .hackerNews)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://x.com/home")) == .x)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://twitter.com/someone/status/1")) == .x)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://www.google.com/search?q=swift")) == .google)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://www.google.co.uk/search?q=london")) == .google)
        #expect(LinkSummaryPolicy.autoSite(page: u("https://google.fr/search?q=paris")) == .google)
        for s in ["https://mail.google.com/mail/u/0/", "https://google.evil.com/search?q=x", "https://duckduckgo.com/?q=x",
                  "https://www.bing.com/search?q=x", "https://www.threads.net/", "https://github.com/VictorKildahl/cra",
                  "file:///tmp/page.html"] {
            #expect(LinkSummaryPolicy.autoSite(page: u(s)) == nil, "\(s)")
        }
        #expect(LinkSummaryPolicy.autoSite(page: nil) == nil)
    }

    @Test func arcsSelectorsPickTheLinksPerSite() {
        #expect(LinkSummaryPolicy.selectors(for: .hackerNews) == [".title .titleline > a"])
        #expect(LinkSummaryPolicy.selectors(for: .x).count == 3)
        #expect(LinkSummaryPolicy.selectors(for: .google).first == "#search a")
        #expect(!LinkSummaryPolicy.selectors(for: .google).contains { $0.contains("rhs") })
        let script = LinkSummaryPolicy.hoverScript(pointer: CGPoint(x: 0.25, y: 0.5), site: .hackerNews)
        #expect(script.contains(#"[".title .titleline > a"]"#))
        #expect(script.contains("elementFromPoint(0.25 * vv.width"))
        #expect(LinkSummaryPolicy.hoverScript(pointer: .zero, site: nil).contains("const arc = [].some"))
    }

    @Test func whichCardARestedHoverOpens() {
        let hn = u("https://news.ycombinator.com/news")
        let story = u("https://www.blender.org/")
        let comments = u("https://news.ycombinator.com/item?id=1")
        // A hover alone: only Arc's links on its sites.
        #expect(LinkSummaryPolicy.kind(link: story, page: hn, shiftHeld: false, arcLink: true) == .summary)
        #expect(LinkSummaryPolicy.kind(link: comments, page: hn, shiftHeld: false, arcLink: false) == nil)
        #expect(LinkSummaryPolicy.kind(link: story, page: u("https://example.com/"), shiftHeld: false, arcLink: true) == nil)
        // Shift held as the pointer arrived: the summary, or the small card within the site.
        #expect(LinkSummaryPolicy.kind(link: comments, page: hn, shiftHeld: true, arcLink: false) == .link)
        #expect(LinkSummaryPolicy.kind(link: u("https://www.iana.org/help/example-domains"), page: u("https://example.com/"),
                                       shiftHeld: true, arcLink: false) == .summary)
        #expect(LinkSummaryPolicy.kind(link: story, page: nil, shiftHeld: true, arcLink: false) == .summary)
        #expect(LinkSummaryPolicy.mayOpen(page: hn, shiftHeld: false))
        #expect(!LinkSummaryPolicy.mayOpen(page: u("https://example.com/"), shiftHeld: false))
        #expect(LinkSummaryPolicy.mayOpen(page: u("https://example.com/"), shiftHeld: true))
        #expect(LinkSummaryPolicy.rest == .seconds(1))
    }

    @Test func smallCardShowsTheAddressWithoutScheme() {
        #expect(LinkSummaryPolicy.displayAddress(u("https://news.ycombinator.com/item?id=50422069")) == "news.ycombinator.com/item?id=50422069")
        #expect(LinkSummaryPolicy.displayAddress(u("http://www.example.com/")) == "example.com")
        #expect(LinkSummaryPolicy.displayAddress(u("https://example.com/a/")) == "example.com/a/")
    }

    // MARK: - Which links may be fetched

    @Test func onlyPublicWebPagesArePreviewed() {
        let page = u("https://example.com/blog/article?x=1")
        #expect(LinkSummaryPolicy.canPreview(link: u("https://example.org/about"), page: page))
        #expect(LinkSummaryPolicy.canPreview(link: u("http://example.com/other"), page: page))
        #expect(LinkSummaryPolicy.canPreview(link: u("https://8.8.8.8/"), page: page))
        #expect(!LinkSummaryPolicy.canPreview(link: u("https://example.com/blog/article?x=1#comments"), page: page))
        #expect(!LinkSummaryPolicy.canPreview(link: nil))
        for s in ["javascript:void(0)", "mailto:hello@example.com", "cra://settings", "about:blank", "file:///etc/hosts",
                  "http://localhost:3000/", "http://app.localhost/", "http://127.0.0.1:8080/", "http://127.1:8765/",
                  "http://[::1]:8765/", "http://[fe80::1]/", "http://10.0.0.1/", "http://172.16.4.2/", "http://172.31.0.1/",
                  "http://192.168.1.1/", "http://169.254.169.254/latest/meta-data", "http://100.64.0.1/", "http://0.0.0.0/",
                  "http://router/", "http://printer.local/", "http://nas.lan/", "http://wiki.corp/", "http://x.home.arpa/",
                  "http://localhost./"] {
            #expect(!LinkSummaryPolicy.canPreview(link: u(s), page: page), "\(s)")
        }
        #expect(LinkSummaryPolicy.isPublicHost("172.32.0.1"))
        #expect(LinkSummaryPolicy.isPublicHost("crabrowser.app."))
    }

    @Test func everyFetchTargetIsCanonicalPublicAndCredentialFree() {
        let base = u("https://EXAMPLE.com/directory/page")
        #expect(LinkSummaryFetchPolicy.target("../final#quote", relativeTo: base, httpsOnly: true) == u("https://example.com/final"))
        #expect(LinkSummaryFetchPolicy.target("http://example.com:80", httpsOnly: true) == u("https://example.com/"))
        #expect(LinkSummaryFetchPolicy.target("https://example.com:443/", httpsOnly: false) == u("https://example.com/"))
        for raw in ["http://127.0.0.1/", "http://0177.0.0.1/", "http://0x7f.0.0.1/", "http://2130706433/",
                    "http://10.0.0.1/", "http://printer.local/", "http://[::1]/", "file:///tmp/page.html",
                    "https://user@example.com/", "https://:password@example.com/", "javascript:alert(1)"] {
            #expect(LinkSummaryFetchPolicy.target(raw, httpsOnly: false) == nil, "no request may start for \(raw)")
        }
    }

    @Test func httpsOnlyUpgradesTheFetch() {
        #expect(LinkSummaryPolicy.fetchURL(for: u("http://example.com/a?b=1"), httpsOnly: true) == u("https://example.com/a?b=1"))
        #expect(LinkSummaryPolicy.fetchURL(for: u("http://example.com:80/a"), httpsOnly: true) == u("https://example.com/a"))
        #expect(LinkSummaryPolicy.fetchURL(for: u("http://example.com/a"), httpsOnly: false) == u("http://example.com/a"))
        #expect(LinkSummaryPolicy.fetchURL(for: u("https://example.com/a"), httpsOnly: true) == u("https://example.com/a"))
    }

    @Test func googleSearchQueryFocusesTheCard() {
        #expect(LinkSummaryPolicy.searchQuery(page: u("https://www.google.com/search?q=best+pizza+oslo&hl=en")) == "best pizza oslo")
        #expect(LinkSummaryPolicy.searchQuery(page: u("https://www.google.com/search?q=c%2B%2B+%26+rust")) == "c++ & rust")
        #expect(LinkSummaryPolicy.searchQuery(page: u("https://www.google.com/search?hl=en")) == nil)
        #expect(LinkSummaryPolicy.searchQuery(page: u("https://news.ycombinator.com/?q=x")) == nil)
    }

    // MARK: - Page text

    @Test func extractsTitleDescriptionAndArticleText() {
        let html = """
        <!DOCTYPE html><html><head>
            <title>Swift 6.0 Released &amp; Details &mdash; Swift.org</title>
            <meta content='Swift 6 brings "complete" concurrency checks.' name='description'>
            <style>body { font-size: 14px; }</style>
            <script>console.log("analytics");</script>
        </head><body>
            <nav><a href="/">Home</a> Blog Docs</nav>
            <article>
                <h1>Swift 6</h1>
                <p>Swift 6 is now available. It brings data-race safety by default.</p>
                <script>track()</script><!-- hidden -->
            </article>
            <footer>&copy; 2026 Apple Inc. &#8212; &#x2014;</footer>
        </body></html>
        """
        let e = LinkSummaryContent.extractText(from: html)
        #expect(e.title == "Swift 6.0 Released & Details — Swift.org")
        #expect(e.description == "Swift 6 brings \"complete\" concurrency checks.")
        #expect(e.bodyText == "Swift 6 Swift 6 is now available. It brings data-race safety by default.")
    }

    @Test func fallsBackToOpenGraphAndWholeBody() {
        let html = """
        <html><head><meta property="og:title" content="Cra"><meta property="og:description" content="A native browser for macOS."></head>
        <body><p>Welcome to&nbsp;Cra &#8212; fast.</p></body></html>
        """
        let e = LinkSummaryContent.extractText(from: html)
        #expect(e.title == "Cra")
        #expect(e.description == "A native browser for macOS.")
        #expect(e.bodyText == "Welcome to Cra — fast.")
    }

    @Test func bannerPictureIsThePagesShareImage() {
        let page = u("https://foldableflight.com/planes/")
        let html = #"<html><head><meta property="og:image" content="/img/hero.png?w=1&amp;h=2"><meta name="twitter:image" content="https://x.example/t.png"></head><body></body></html>"#
        let e = LinkSummaryContent.extractText(from: html)
        #expect(e.image == "/img/hero.png?w=1&h=2")
        #expect(e.imageURL(page: page) == u("https://foldableflight.com/img/hero.png?w=1&h=2"))
        #expect(LinkSummaryContent.extractText(from: #"<head><meta name="twitter:image" content="https://x.example/t.png"></head>"#).image == "https://x.example/t.png")
        #expect(LinkSummaryContent.Extracted(image: "http://192.168.1.1/cam.jpg").imageURL(page: page) == nil)
        #expect(LinkSummaryContent.Extracted(image: "data:image/png;base64,AAAA").imageURL(page: page) == nil)
        #expect(LinkSummaryContent.Extracted().imageURL(page: page) == nil)
    }

    @Test func decodesEntitiesOnce() {
        #expect(LinkSummaryContent.cleanHTMLText("  Hello &amp; welcome &quot;friends&quot; &ndash; &#39;Cra&#39;   ") == "Hello & welcome \"friends\" – 'Cra'")
        // &amp;lt; is the text "&lt;", not "<".
        #expect(LinkSummaryContent.cleanHTMLText("a &amp;lt; b &#xZZ; &#128512;") == "a &lt; b &#xZZ; 😀")
    }

    @Test func caps() {
        let big = "<html><head><title>Big</title></head><body>" + String(repeating: "<p>Some long paragraph text here.</p>", count: 20_000)
            + "<p>FAR AWAY</p></body></html>"
        let e = LinkSummaryContent.extractText(from: big)
        #expect(e.title == "Big")
        #expect(e.bodyText.count == LinkSummaryContent.maxContentLength)
        #expect(!e.bodyText.contains("FAR AWAY"))
        #expect(LinkSummaryContent.extractText(from: "").bodyText.isEmpty)
    }

    // MARK: - The model's answer

    @Test func promptIsArcsWithTheSearchAndLanguage() {
        let content = LinkSummaryContent.Extracted(title: "Pizza", description: "Best slices", bodyText: "Text.")
        let p = LinkSummaryPrompt.prompt(url: "https://example.com/p", content: content, searchQuery: "pizza oslo", language: "English")
        #expect(p.contains("<webpage>\nURL: https://example.com/p\nTitle: Pizza\nDescription: Best slices\nText.\n</webpage>"))
        #expect(p.contains("'pizza oslo'"))
        #expect(p.hasSuffix("Write responses in English."))
        let bare = LinkSummaryPrompt.prompt(url: "https://e.com", content: .init(), searchQuery: nil, language: "Danish")
        #expect(!bare.contains("search query"))
        #expect(LinkSummaryPrompt.instructions.contains("glanceable \"answer card\""))
    }

    @Test func answerBecomesACard() {
        let url = u("https://www.blender.org/download/releases/5-3/")
        let answer = LinkSummaryPrompt.Answer(blocked: false, quickSummary: " **Gaussian splats** arrive ", details: [
            .init(label: "Highlights:", icon: "sparkles", info: "Splat rendering in Cycles and EEVEE"),
            .init(label: "Empty", icon: "x", info: "  "),
            .init(label: "Price", icon: "tag", info: "\"Free and open source\""),
            .init(label: "3", icon: "3.circle", info: "Three"),
            .init(label: "4", icon: "4.circle", info: "Four"),
            .init(label: "5", icon: "5.circle", info: "Five"),
        ])
        let r = LinkSummaryPrompt.result(url: url, title: " Blender 5.3 ", answer: answer)
        #expect(r?.title == "Blender 5.3")
        #expect(r?.host == "blender.org")
        #expect(r?.quickSummary == "Gaussian splats arrive")
        #expect(r?.details.map(\.label) == ["Highlights", "Price", "3", "4"])
        #expect(r?.details[1].info == "Free and open source")
        #expect(LinkSummaryPrompt.result(url: url, title: nil, answer: answer)?.title == "blender.org")
    }

    @Test func blockedOrEmptyAnswerHasNoPreview() {
        let url = u("https://example.com/")
        let detail = LinkSummaryResult.Detail(label: "A", icon: "a.circle", info: "Something")
        #expect(LinkSummaryPrompt.result(url: url, title: "T", answer: .init(blocked: true, quickSummary: "Hi", details: [detail])) == nil)
        #expect(LinkSummaryPrompt.result(url: url, title: "T", answer: .init(blocked: false, quickSummary: " ", details: [])) == nil)
        #expect(LinkSummaryPrompt.result(url: url, title: "T", answer: .init(blocked: false, quickSummary: "Only this", details: []))?.details == [])
    }

    @Test func fakeModelAnswersFromThePage() {
        let a = LinkSummaryPrompt.fakeAnswer(content: .init(title: "T", description: "D", bodyText: "First sentence here. Second one is here too."))
        #expect(a.quickSummary == "D")
        #expect(a.details.map(\.info) == ["First sentence here", "Second one is here too"])
        #expect(LinkSummaryPrompt.fakeAnswer(content: .init()).blocked)
    }

    // MARK: - Placement

    @Test func cardHangsUnderTheLinkLikeArcs() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let size = CGSize(width: 300, height: 335)
        // Arc's measured card: the link's text starts at 416 pt, the card at 409; 6 pt under the link.
        let link = CGRect(x: 416, y: 900, width: 280, height: 16)
        #expect(LinkSummaryCardLayout.origin(size: size, link: link, pointer: .zero, screen: screen) == CGPoint(x: 409, y: 559))
        // No room under it: above the link.
        let low = CGRect(x: 416, y: 100, width: 280, height: 16)
        #expect(LinkSummaryCardLayout.origin(size: size, link: low, pointer: .zero, screen: screen) == CGPoint(x: 409, y: 122))
        // Near the right edge and with no link frame: under the pointer, kept on the screen.
        let right = LinkSummaryCardLayout.origin(size: size, link: nil, pointer: CGPoint(x: 1700, y: 700), screen: screen)
        #expect(right == CGPoint(x: 1420, y: 349))
        // A second screen to the left (negative x).
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(LinkSummaryCardLayout.origin(size: size, link: CGRect(x: -1925, y: 500, width: 50, height: 16), pointer: .zero, screen: left).x == -1912)
    }

    // MARK: - Share menu

    @Test func copyAsTextIsArcsFormat() {
        // Arc 1.171's Copy as Text for a Google result (10 Nov 2026), with Cra's attribution.
        let r = LinkSummaryResult(url: "https://www.youtube.com/watch?v=0tR7dlqDu3E", title: "T", host: "youtube.com",
                                  quickSummary: "Best paper airplane for distance.", details: [
            .init(label: "Record Holder", icon: "trophy", info: "2026 world record for distance."),
            .init(label: "Video Link", icon: "video", info: "Watch on YouTube for instructions."),
            .init(label: "Technique", icon: "pencil", info: "Learn folding techniques for optimal flight."),
            .init(label: "Materials", icon: "paperplane", info: "Use lightweight paper for best results."),
        ])
        #expect(LinkSummaryShare.text(r, attribution: "AI Summary by Cra") == """
            Best paper airplane for distance.
            🏆 Record Holder: 2026 world record for distance.
            📹 Video Link: Watch on YouTube for instructions.
            ✏️ Technique: Learn folding techniques for optimal flight.
            ✈️ Materials: Use lightweight paper for best results.
            AI Summary by Cra
            https://www.youtube.com/watch?v=0tR7dlqDu3E
            """)
    }

    @Test func symbolsBecomeEmoji() {
        #expect(LinkSummaryShare.emoji(forSymbol: "trophy.fill") == "🏆")
        #expect(LinkSummaryShare.emoji(forSymbol: "video.circle") == "📹")
        #expect(LinkSummaryShare.emoji(forSymbol: "fork.knife") == "🍴")
        #expect(LinkSummaryShare.emoji(forSymbol: "Fork.Knife.Circle") == "🍴")
        #expect(LinkSummaryShare.emoji(forSymbol: "person.2.fill") == "👥")
        #expect(LinkSummaryShare.emoji(forSymbol: "building.2") == "🏢")
        #expect(LinkSummaryShare.emoji(forSymbol: "no.such.symbol") == "•")
        #expect(LinkSummaryShare.emoji(forSymbol: "") == "•")
    }

    // MARK: - Cache

    private func request(_ link: String = "https://example.com/private", profile: String? = nil,
                         httpsOnly: Bool = false, query: String? = nil, language: String = "English") -> LinkSummaryRequest {
        LinkSummaryRequest(link: u(link), profilePath: profile, httpsOnly: httpsOnly, searchQuery: query, language: language)
    }

    @Test func failedPreviewCanBeRetried() {
        var cache = LinkSummaryCache()
        cache.store(nil, for: request())
        #expect(cache.lookup(request()) == nil,
                "A temporary preview failure must not become a cached no-preview result")
        #expect(cache.count == 0)
        let recovered = LinkSummaryResult(url: "https://example.com/private", title: "Recovered", host: "example.com",
                                          quickSummary: "Available again", details: [])
        cache.store(recovered, for: request())
        #expect(cache.lookup(request()) == recovered)
    }

    @Test func cachedPreviewNeverCrossesFetchOrModelContexts() {
        let original = request(profile: "/profiles/a", query: "price")
        let variants = [
            request(profile: "/profiles/b", query: "price"),
            request(query: "price"),
            request(profile: "/profiles/a", query: "reviews"),
            request(profile: "/profiles/a"),
            request(profile: "/profiles/a", query: "price", language: "Danish"),
            request(profile: "/profiles/a", httpsOnly: true, query: "price"),
            request("https://example.com/other", profile: "/profiles/a", query: "price"),
        ]
        var cache = LinkSummaryCache()
        let privateCard = LinkSummaryResult(url: original.link.absoluteString, title: "Profile A's page", host: "example.com",
                                            quickSummary: "Account-specific information", details: [])
        cache.store(privateCard, for: original)
        #expect(cache.lookup(request(profile: "/profiles/a", query: "price")) == privateCard)
        for context in variants {
            #expect(cache.lookup(context) == nil, "A cached preview must not cross profile, query, language or HTTPS context")
        }
    }

    @Test func requestCapturesDefaultProfileAndEffectiveFetchURL() {
        let defaultRequest = request("http://example.com/private", httpsOnly: true, query: "price", language: "Danish")
        #expect(defaultRequest.profile == .default)
        #expect(defaultRequest.profilePath == nil)
        #expect(defaultRequest == request("http://example.com/private", profile: "", httpsOnly: true, query: "price", language: "Danish"))
        #expect(defaultRequest.link == u("http://example.com/private"))
        #expect(defaultRequest.fetchURL == u("https://example.com/private"))
        #expect(defaultRequest.searchQuery == "price")
        #expect(defaultRequest.language == "Danish")
        let named = request(profile: "/profiles/a")
        #expect(named.profile == .path("/profiles/a"))
        #expect(named.profilePath == "/profiles/a")
    }

    @Test func sameLinkDoesNotIdentifyTheOriginatingDocument() {
        let runtime = NSObject(), replacement = NSObject()
        let window = UUID(), tab = UUID()
        let page = u("https://www.google.com/search?q=price")
        func context(_ window: UUID, _ tab: UUID, _ runtime: NSObject, _ revision: UInt, _ page: URL?) -> LinkSummaryContext {
            .init(request: request(), page: page, windowID: window, tabID: tab,
                  runtimeID: ObjectIdentifier(runtime), navigationRevision: revision)
        }
        let original = context(window, tab, runtime, 1, page)
        #expect(original == context(window, tab, runtime, 1, page))
        let changes = [context(UUID(), tab, runtime, 1, page), context(window, UUID(), runtime, 1, page),
                       context(window, tab, replacement, 1, page), context(window, tab, runtime, 2, page),
                       context(window, tab, runtime, 1, u("https://www.google.com/search?q=reviews"))]
        for changed in changes {
            #expect(original != changed, "same-URL preview work must be scoped to its window, tab, runtime, revision and source page")
        }
    }

    @Test func cacheKeepsTheNewest() {
        var c = LinkSummaryCache(limit: 2)
        let a = request("https://a.example"), b = request("https://b.example"), third = request("https://c.example")
        let r = LinkSummaryResult(url: "https://a.example", title: "A", host: "a.example", quickSummary: nil, details: [])
        c.store(r, for: a)
        c.store(r, for: b)
        c.store(r, for: a)  // stored again: "b" is now the oldest
        c.store(r, for: third)
        #expect(c.count == 2)
        #expect(c.lookup(b) == nil)
        #expect(c.lookup(a) == r)
        #expect(c.lookup(third) == r)
    }

    // MARK: - Settings

    @Test func fiveSecondPreviewsIsOffByDefaultAndRoundTrips() throws {
        #expect(AppSettings().fiveSecondPreviews == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).fiveSecondPreviews == false)
        var on = AppSettings()
        on.fiveSecondPreviews = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).fiveSecondPreviews)
    }
}
