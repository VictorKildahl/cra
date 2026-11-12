import AppKit
import WebKit

/// The production extraction script in a real DOM/isolated world, with synthetic local files only.
@main
@MainActor
enum AskOnPageContentTests {
    private static var checks = 0

    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    private static func evaluate(_ script: String, in web: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { done in
            web.evaluateJavaScript(script, in: nil, in: .world(name: "cra.ask-test")) { done.resume(with: $0) }
        }
    }

    private static func snapshot(_ web: WKWebView) async throws -> (AskOnPagePrompt.Page?, [String: Any]) {
        let value = try await evaluate(AskOnPageContent.script, in: web) as! [String: Any]
        let result = String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": value]]), encoding: .utf8)!
        return (AskOnPageContent.page(evaluation: result, expectedURL: web.url!.absoluteString), value)
    }

    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/AskOnPage/article.html")
        let navigation = Navigation()
        try await navigation.load(fixture, in: web)
        let (page, _) = try await snapshot(web)
        expect(page?.text.contains("The synthetic article contains a supported sentence across inline elements.") == true,
               "inline nodes retain their visible sentence and spacing")
        expect(page?.text.contains("Café and 漢字") == true && page?.text.contains("\n") == true,
               "Unicode and paragraph boundaries survive extraction")
        expect(page?.text.contains("final word.\nThe second visible paragraph") == true,
               "CSS block text retains the visible separator rather than joining source words")
        expect(page?.text.contains("Genuineinline adjacency stays joined.") == true,
               "CSS inline elements retain genuine text adjacency even with default block tags")
        expect(page?.text.contains("secret") == false && page?.text.contains("Navigation should") == false
               && page?.text.contains("Footer chrome") == false, "hidden/chrome/control/script text stays out of context")
        expect(page?.title == "Synthetic Ask on Page article" && page?.wasTruncated == false, "title and complete readable document are reported")
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
            web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { waiting?.resume(); waiting = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { waiting?.resume(throwing: error); waiting = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { waiting?.resume(throwing: error); waiting = nil }
}
