import CraCore
import Foundation
import Testing

struct LinkSummaryTests {
    // MARK: - Auto-hover sites policy

    @Test func autoHoverMatchesAllRequiredSites() {
        let autoURLs = [
            "https://www.google.com/search?q=apple+intelligence",
            "https://google.com/search?q=swift",
            "https://google.fr/search?q=paris",
            "https://google.co.uk/search?q=london",
            "https://duckduckgo.com/?q=cra+browser",
            "https://html.duckduckgo.com/html/?q=test",
            "https://www.bing.com/search?q=bing",
            "https://bing.com/",
            "https://twitter.com/TheBrowserComp",
            "https://x.com/TheBrowserComp",
            "https://mobile.twitter.com/someone",
            "https://www.threads.net/@zuck",
            "https://threads.net/t/12345",
            "https://news.ycombinator.com/",
            "https://news.ycombinator.com/item?id=40000000",
            "https://hacker-news.firebaseio.com/v0/item/1.json",
        ]
        for s in autoURLs {
            let url = URL(string: s)!
            #expect(LinkSummaryPolicy.isAutoHoverSite(url: url), "Expected auto-hover for \(s)")
        }
    }

    @Test func otherSitesRequireShift() {
        let otherURLs = [
            "https://en.wikipedia.org/wiki/Earth",
            "https://github.com/VictorKildahl/cra",
            "https://apple.com/apple-intelligence",
            "https://nytimes.com/article/today",
            "https://reddit.com/r/mac",
            "https://crabrowser.app",
        ]
        for s in otherURLs {
            let url = URL(string: s)!
            #expect(!LinkSummaryPolicy.isAutoHoverSite(url: url), "Expected NOT auto-hover for \(s)")
            // Without Shift, should NOT trigger
            #expect(!LinkSummaryPolicy.shouldTrigger(pageURL: url, isShiftPressed: false))
            // With Shift, should trigger
            #expect(LinkSummaryPolicy.shouldTrigger(pageURL: url, isShiftPressed: true))
        }
    }

    @Test func autoHoverSitesTriggerWithoutShift() {
        let google = URL(string: "https://www.google.com/search?q=query")!
        #expect(LinkSummaryPolicy.shouldTrigger(pageURL: google, isShiftPressed: false))
        #expect(LinkSummaryPolicy.shouldTrigger(pageURL: google, isShiftPressed: true))

        let hn = URL(string: "https://news.ycombinator.com/news")!
        #expect(LinkSummaryPolicy.shouldTrigger(pageURL: hn, isShiftPressed: false))
    }

    // MARK: - Link validity

    @Test func canSummarizeFiltersInvalidAndSamePageLinks() {
        let page = URL(string: "https://example.com/blog/article")!

        // Valid external links
        #expect(LinkSummaryPolicy.canSummarize(targetURL: URL(string: "https://example.org/about"), pageURL: page))
        #expect(LinkSummaryPolicy.canSummarize(targetURL: URL(string: "http://example.com/other"), pageURL: page))

        // Same page fragment
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "https://example.com/blog/article#comments"), pageURL: page))

        // Unsupported schemes
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "javascript:void(0)"), pageURL: page))
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "mailto:hello@example.com"), pageURL: page))
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "cra://settings"), pageURL: page))
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "about:blank"), pageURL: page))

        // Local hosts
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "http://localhost:3000/app"), pageURL: page))
        #expect(!LinkSummaryPolicy.canSummarize(targetURL: URL(string: "http://127.0.0.1:8080/"), pageURL: page))
    }

    // MARK: - HTML Content Extraction

    @Test func extractsTitleDescriptionAndBodyText() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Swift 6.0 Released &amp; Details &mdash; Swift.org</title>
            <meta name="description" content="Swift 6 brings full concurrency checks and new language features.">
            <style>body { font-size: 14px; }</style>
            <script>console.log("analytics");</script>
        </head>
        <body>
            <noscript>Turn on JavaScript</noscript>
            <header><nav><a href="/">Home</a></nav></header>
            <main>
                <h1>Swift 6</h1>
                <p>Swift 6 is now available. This release introduces complete data-race safety by default.</p>
                <p>It also enhances interoperability with C++ and includes standard testing libraries.</p>
            </main>
            <footer>&copy; 2026 Apple Inc.</footer>
        </body>
        </html>
        """

        let extracted = LinkSummaryContent.extractText(from: html)
        #expect(extracted.title == "Swift 6.0 Released & Details — Swift.org")
        #expect(extracted.description == "Swift 6 brings full concurrency checks and new language features.")
        #expect(!extracted.bodyText.contains("console.log"))
        #expect(!extracted.bodyText.contains("font-size"))
        #expect(!extracted.bodyText.contains("<p>"))
        #expect(extracted.bodyText.contains("Swift 6 is now available"))
        #expect(extracted.bodyText.contains("complete data-race safety"))
    }

    @Test func extractsOpenGraphMetaDescription() {
        let html = """
        <html>
        <head>
            <meta property="og:description" content="A fast, modern native browser for macOS.">
        </head>
        <body>
            <p>Welcome to Cra.</p>
        </body>
        </html>
        """
        let extracted = LinkSummaryContent.extractText(from: html)
        #expect(extracted.description == "A fast, modern native browser for macOS.")
    }

    @Test func decodesEntitiesAndCleansWhitespace() {
        let raw = "  Hello &amp; welcome &quot;friends&quot; &ndash; &#39;Cra&#39;   "
        let clean = LinkSummaryContent.cleanHTMLText(raw)
        #expect(clean == "Hello & welcome \"friends\" – 'Cra'")
    }

    // MARK: - Prompt & Bullets

    @Test func promptContainsTitleUrlAndContent() {
        let p = LinkSummaryPrompt.prompt(title: "Article Title", url: "https://example.com/post", content: "Paragraph text.")
        #expect(p.contains("Title: Article Title"))
        #expect(p.contains("URL: https://example.com/post"))
        #expect(p.contains("Content:\nParagraph text."))

        let withDesc = LinkSummaryPrompt.prompt(
            title: "Article Title",
            url: "https://example.com/post",
            description: "High-level summary description.",
            content: "Paragraph text."
        )
        #expect(withDesc.contains("Description: High-level summary description."))
    }

    @Test func extractTextHandlesLargeHTMLSwiftly() {
        var bigHTML = "<html><head><title>Large Page Title</title><meta name=\"description\" content=\"Fast summary metadata.\"></head><body>"
        // Append 200 KB of repetitive paragraphs
        let chunk = "<p>Here is some long repeated paragraph content for testing performance on heavy web pages.</p>"
        for _ in 0..<2000 {
            bigHTML.append(chunk)
        }
        bigHTML.append("</body></html>")

        let start = Date()
        let extracted = LinkSummaryContent.extractText(from: bigHTML)
        let duration = Date().timeIntervalSince(start)

        #expect(extracted.title == "Large Page Title")
        #expect(extracted.description == "Fast summary metadata.")
        #expect(extracted.bodyText.count <= LinkSummaryContent.maxContentLength)
        #expect(duration < 0.1, "HTML extraction should complete in under 100ms on large pages")
    }

    @Test func cleanBulletsStripsMarkersAndLimitsCount() {
        let raw = [
            "• First key takeaway with important fact.",
            "- Second point summarizing consequences.",
            "1. Third point outlining next steps.",
            "4. Extra bullet point that exceeds limit.",
        ]
        let cleaned = LinkSummaryPrompt.cleanBullets(raw)
        #expect(cleaned.count == 3)
        #expect(cleaned[0] == "First key takeaway with important fact.")
        #expect(cleaned[1] == "Second point summarizing consequences.")
        #expect(cleaned[2] == "Third point outlining next steps.")
    }

    @Test func fakeAnswerGeneratesMeaningfulSummary() {
        let url = URL(string: "https://news.ycombinator.com/item?id=123")!
        let content = LinkSummaryContent.Extracted(
            title: "Show HN: Cra Browser",
            description: "Native macOS browser matching Arc.",
            bodyText: "Discussion regarding the open source release of Cra for macOS. Many users praised the sidebar and tab management."
        )
        let result = LinkSummaryPrompt.fakeAnswer(title: "Show HN", url: url, content: content)
        #expect(result.host == "news.ycombinator.com")
        #expect(result.title == "Show HN: Cra Browser")
        #expect(result.bullets.count >= 2)
        #expect(result.bullets[0] == "Native macOS browser matching Arc.")
    }

    // MARK: - Settings

    @Test func fiveSecondPreviewsDefaultIsOff() throws {
        let s = AppSettings()
        #expect(s.fiveSecondPreviews == false)

        let encoded = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(decoded.fiveSecondPreviews == false)

        var enabled = AppSettings()
        enabled.fiveSecondPreviews = true
        let encEnabled = try JSONEncoder().encode(enabled)
        let decEnabled = try JSONDecoder().decode(AppSettings.self, from: encEnabled)
        #expect(decEnabled.fiveSecondPreviews == true)
    }
}
