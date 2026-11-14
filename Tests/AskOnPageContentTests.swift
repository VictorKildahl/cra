import AppKit
import WebKit

/// The production extraction script in a real DOM/isolated world, with synthetic loopback HTTP only.
@main
@MainActor
enum AskOnPageContentTests {
    private static var checks = 0
    // Keep the named world alive across evaluations so the lookup lease survives until its effect.
    private static let world = WKContentWorld.world(name: "cra.ask-test")

    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    private static func evaluate(_ script: String, in web: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { done in
            web.evaluateJavaScript(script, in: nil, in: world) { done.resume(with: $0) }
        }
    }

    private static func snapshot(_ web: WKWebView) async throws -> (AskOnPagePrompt.Page?, [String: Any]) {
        let value = try await evaluate(AskOnPageContent.script, in: web) as! [String: Any]
        let result = String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": value]]), encoding: .utf8)!
        return (AskOnPageContent.page(evaluation: result, expectedURL: web.url!.absoluteString), value)
    }

    // promise: #393
    private static func liveQuoteRanges(_ web: WKWebView, fixture: URL, navigation: Navigation) async throws {
        let quote = "The synthetic article contains a supported sentence across inline elements."
        func lookup(_ text: String, lease: UUID) async throws -> AskOnPageQuoteDOM.Match {
            let value = try await evaluate(AskOnPageQuoteDOM.lookup(text, url: fixture.absoluteString, lease: lease), in: web)
            let encoded = String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": value]]), encoding: .utf8)!
            guard case .match(let match) = AskOnPageQuoteDOM.result(encoded) else { fatalError("fixture quote must have an exact bounded range") }
            return match
        }
        func effect(_ text: String, lease: UUID, match: AskOnPageQuoteDOM.Match, stage: String) async throws -> Bool {
            let value = try await evaluate(AskOnPageQuoteDOM.effect(text, url: fixture.absoluteString, lease: lease, match: match), in: web)
            let encoded = String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": value]]), encoding: .utf8)!
            guard let found = AskOnPageQuoteDOM.effected(encoded) else {
                throw NSError(domain: "AskOnPageContentTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(stage) expected completed quote evidence; received \(type(of: value))"])
            }
            return found
        }
        let lease = UUID()
        let current = try await lookup(quote, lease: lease)
        let found = try await effect(quote, lease: lease, match: current, stage: "inline effect")
        expect(found, "the exact inline quote completes its live Range operation")
        let selected = try await evaluate("getSelection().toString()", in: web) as! String
        expect(AskOnPage.normalized(selected) == quote, "the real selection contains the complete literal quote across inline nodes")
        _ = try await evaluate("getSelection().removeAllRanges(); document.querySelector('main').textContent = 'The original quoted source was removed before its effect.'", in: web)
        let missing = try await effect(quote, lease: lease, match: current, stage: "mutated effect")
        expect(!missing, "DOM mutation between lookup and effect never reuses an obsolete range")
        let empty = try await evaluate("getSelection().toString()", in: web) as! String
        expect(empty.isEmpty, "a failed live revalidation cannot create a selection")
        try await navigation.load(fixture, in: web)
        let stale = try await evaluate(AskOnPageQuoteDOM.effect(quote, url: fixture.absoluteString, lease: lease, match: current), in: web)
        expect(stale is NSNull, "same-URL new document globals reject the old lookup lease")
        _ = try await evaluate(#"document.body.innerHTML = '<p id="first">Cafe<span>\u0301 opens at 09:30. 👩‍🔬 &amp; &lt;literal&gt;</span></p><p>Café opens at 09:30. 👩‍🔬 &amp; &lt;literal&gt;</p>'"#, in: web)
        let unicode = "Café opens at 09:30. 👩‍🔬 & <literal>", unicodeLease = UUID()
        let unicodeMatch = try await lookup(unicode, lease: unicodeLease)
        let unicodeFound = try await effect(unicode, lease: unicodeLease, match: unicodeMatch, stage: "Unicode effect")
        expect(unicodeFound, "inline decomposed Unicode and literal symbols produce a real exact range")
        let first = try await evaluate("getSelection().anchorNode.parentElement.id", in: web) as! String
        expect(first == "first", "repeated normalized quotes use the first exact current occurrence")
        try await navigation.load(fixture, in: web)
    }

    // promise: #393
    private static func liveQuoteEdgeMatrix(_ web: WKWebView, fixture: URL, navigation: Navigation) async throws {
        func value(_ script: String) async throws -> String {
            let result = try await evaluate(script, in: web)
            return String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": result]]), encoding: .utf8)!
        }
        func lookup(_ text: String, _ lease: UUID) async throws -> AskOnPageQuoteDOM.Lookup? {
            AskOnPageQuoteDOM.result(try await value(AskOnPageQuoteDOM.lookup(text, url: fixture.absoluteString, lease: lease)))
        }
        func effect(_ text: String, _ lease: UUID, _ match: AskOnPageQuoteDOM.Match) async throws -> Bool? {
            AskOnPageQuoteDOM.effected(try await value(AskOnPageQuoteDOM.effect(text, url: fixture.absoluteString, lease: lease, match: match)))
        }
        _ = try await evaluate(#"document.body.innerHTML = '<main><p id="exact">Café 👩‍🔬 exact.</p></main>'; getSelection().removeAllRanges(); scrollTo(0,0); true"#, in: web)
        for quote in ["café 👩‍🔬 exact.", "Cafe 👩‍🔬 exact.", "Café 👩‍🔬 exact!", "👩", "absent"] {
            let result = try await lookup(quote, UUID())
            expect(result == .notFound, "real DOM lookup never repairs case/accent/punctuation/grapheme or absent source")
        }
        let text = "Café 👩‍🔬 exact.", oldLease = UUID(), newLease = UUID()
        guard case .match(let oldMatch) = try await lookup(text, oldLease),
              case .match(let newMatch) = try await lookup(text, newLease) else { fatalError("exact lease fixture must match") }
        let retired = try await effect(text, oldLease, oldMatch)
        expect(retired == nil, "a newer isolated-world lease rejects an older exact effect")
        _ = try await evaluate("(()=>{\(AskOnPageQuoteDOM.retire(oldLease));return true})()", in: web)
        let current = try await effect(text, newLease, newMatch)
        expect(current == true, "retiring an old lease preserves the current exact operation")
        _ = try await evaluate("(()=>{\(AskOnPageQuoteDOM.retire(newLease));return true})()", in: web)
        let cleared = try await effect(text, newLease, newMatch)
        expect(cleared == nil, "explicit current retirement prevents later range effects")
        _ = try await evaluate("document.body.innerHTML = '<main></main>'; document.querySelector('main').textContent = 'x'.repeat(65537) + ' target'; getSelection().removeAllRanges();true", in: web)
        let bounded = try await lookup("target", UUID())
        expect(bounded == nil, "exhausted live DOM work is unknown rather than a fabricated not-found result")
        let quote = "The evening telescope demonstration starts at 17:45.", lease = UUID()
        _ = try await evaluate(#"document.body.innerHTML = '<main style="max-width:700px;font:16px/24px system-ui"><p>' + 'A measured record describes the quiet room, its shelves, and the afternoon light. '.repeat(80) + '<span id="long-quote">The evening telescope demonstration starts at 17:45.</span></p></main>'; getSelection().removeAllRanges(); scrollTo(0,0); true"#, in: web)
        guard case .match(let match) = try await lookup(quote, lease) else { fatalError("long-paragraph fixture must have an exact quote") }
        let selected = try await effect(quote, lease, match)
        expect(selected == true, "long-paragraph current script builds the exact live range")
        let actual = try await evaluate("getSelection().toString()", in: web) as? String
        expect(actual.map(AskOnPage.normalized) == quote, "long-paragraph script selection is the complete normalized literal")
        // Record viewport evidence separately: production manager performs native Find after this script.
        // A script-only parent scroll is not combined native quote visibility or a passing viewport gate.
        let viewport = try await evaluate(#"(()=>{const r=getSelection().getRangeAt(0).getBoundingClientRect();return {scriptOnly:true,visible:r.bottom>0&&r.top<innerHeight,top:Math.round(r.top),bottom:Math.round(r.bottom),viewport:innerHeight}})()"#, in: web)
        let receipt = String(data: try JSONSerialization.data(withJSONObject: viewport, options: [.sortedKeys]), encoding: .utf8)!
        print("Ask long-paragraph script-only viewport observation (native Find not exercised): \(receipt)")
        try await navigation.load(fixture, in: web)
    }

    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        guard CommandLine.arguments.count == 2, let fixture = URL(string: CommandLine.arguments[1]), fixture.scheme == "http" else {
            fatalError("the harness must supply its loopback HTTP fixture URL")
        }
        expect(!AskOnPageContent.supportsURL("file:///tmp/article.html"), "local files remain ineligible for Ask")
        let navigation = Navigation()
        try await navigation.load(fixture, in: web)
        let (page, _) = try await snapshot(web)
        expect(page?.text.contains("The synthetic article contains a supported sentence across inline elements.") == true,
               "inline nodes retain their visible sentence and spacing")
        expect(page?.text.contains("Café and 漢字") == true && page?.text.contains("\n") == true,
               "Unicode and paragraph boundaries survive extraction")
        expect(page?.text.contains("Budget < €40 & the editor says \"use <excerpt> literally\".") == true,
               "source representation retains visible literal symbols and marker-like text")
        expect(page?.text.contains("final word.\nThe second visible paragraph") == true,
               "CSS block text retains the visible separator rather than joining source words")
        expect(page?.text.contains("Genuineinline adjacency stays joined.") == true,
               "CSS inline elements retain genuine text adjacency even with default block tags")
        expect(page?.text.contains("secret") == false && page?.text.contains("Navigation should") == false
               && page?.text.contains("Footer chrome") == false, "hidden/chrome/control/script text stays out of context")
        expect(page?.title == "Synthetic Ask on Page article" && page?.wasTruncated == false, "title and complete readable document are reported")
        try await liveQuoteRanges(web, fixture: fixture, navigation: navigation)
        try await liveQuoteEdgeMatrix(web, fixture: fixture, navigation: navigation)
        _ = try await evaluate("document.querySelector('main').append(Object.assign(document.createElement('p'), {textContent: 'Added after loading: this authenticated-style DOM text is current context.'}))", in: web)
        let (changed, _) = try await snapshot(web)
        expect(changed?.text.contains("Added after loading") == true, "the already loaded DOM is read again without a URL fetch")

        _ = try await evaluate("document.body.innerHTML = '<p>A readable document without main or article markers still supplies its body text.</p><p>Another paragraph.</p>'", in: web)
        let (body, _) = try await snapshot(web)
        expect(body?.text == "A readable document without main or article markers still supplies its body text.\nAnother paragraph.",
               "unmarked documents fall back to readable body text with block boundaries")

        _ = try await evaluate("document.body.innerHTML = '<main><p>A complete readable introduction that remains before a very large hidden tree.</p>' + '<span hidden>hidden</span>'.repeat(20000) + '<p>UNVISITED END SENTINEL</p></main>'", in: web)
        let (limited, _) = try await snapshot(web)
        expect(limited?.wasTruncated == true && limited?.text.contains("UNVISITED END SENTINEL") == false,
               "mostly-hidden DOM work stops at its traversal ceiling and discloses an unknown denominator")

        _ = try await evaluate("document.body.innerHTML = '<main></main>'; document.querySelector('main').textContent = 'A complete readable introduction before a very large composed character. ' + 'a' + '\\u0301'.repeat(50000)", in: web)
        let (composed, raw) = try await snapshot(web)
        expect(composed?.wasTruncated == true && composed?.text == "A complete readable introduction before a very large composed character.",
               "the truncated final grapheme is omitted whole")
        expect((raw["text"] as? String)?.utf8.count ?? Int.max <= 65_536, "returned readable text stays within the native byte ceiling")
        print("Ask on Page DOM: \(checks) checks passed")
    }
}

@MainActor
private final class Navigation: NSObject, WKNavigationDelegate {
    private var waiting: CheckedContinuation<Void, Error>?
    func load(_ file: URL, in web: WKWebView) async throws {
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { done in
            waiting = done
            web.load(URLRequest(url: file))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { waiting?.resume(); waiting = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { waiting?.resume(throwing: error); waiting = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { waiting?.resume(throwing: error); waiting = nil }
}
