import Foundation

@MainActor enum LinkSummaryFetchTests {
    private static let seed = URL(string: "https://example.com/start")!
    private static let html = "<head><title>Final page</title><meta property='og:image' content='hero.jpg'></head><body>Useful content.</body>"
    private static func request(_ url: URL? = nil, secure: Bool = false) -> LinkSummaryRequest {
        .init(link: url ?? seed, profilePath: "/profiles/A", httpsOnly: secure, searchQuery: nil, language: "English")
    }
    static func run(_ expect: (Bool, String) -> Void) async {
        var targets: [URL] = []
        var profiles: [String?] = []
        let redirect = LinkSummaryFetch(clock: ManualScheduler(), start: { url, profile, _, _, done in
            targets.append(url); profiles.append(profile)
            if targets.count == 1 {
                done(.init(status: 302, url: url.absoluteString, location: "/directory/final", body: "redirect", receivedBytes: 8))
            } else {
                done(.init(status: 200, url: url.absoluteString, body: html, receivedBytes: html.utf8.count))
            }
            return {}
        })
        let page = await redirect.load(request(URL(string: "http://example.com/start")!, secure: true))
        expect(targets == [seed, URL(string: "https://example.com/directory/final")!], "each hop honors HTTPS-only and relative redirects")
        expect(profiles.allSatisfy { $0 == "/profiles/A" }, "every hop preserves the originating profile")
        expect(page?.url == URL(string: "https://example.com/directory/final") && page?.html == html, "the actual final URL accompanies the fetched body")
        if let page {
            expect(LinkSummaryContent.extractText(from: page.html).imageURL(page: page.url) == URL(string: "https://example.com/directory/hero.jpg"), "relative images resolve against the final page")
        }
        for location in ["http://127.0.0.1/private", "http://192.168.1.1/", "http://0x7f.0.0.1/", "http://0177.0.0.1/",
                         "http://[::1]/", "file:///etc/hosts", "cra://debug", "https://user:password@example.com/", ""] {
            var sent: [URL] = []
            let blocked = LinkSummaryFetch(clock: ManualScheduler(), start: { url, _, _, _, done in
                sent.append(url)
                done(.init(status: 302, url: url.absoluteString, location: location, receivedBytes: 0))
                return {}
            })
            expect(await blocked.load(request()) == nil && sent == [seed], "blocked/missing redirect is rejected before another request: \(location)")
        }
        for count in [5, 6] {
            var sent = 0
            let chain = LinkSummaryFetch(clock: ManualScheduler(), start: { url, _, _, _, done in
                sent += 1
                if sent <= count {
                    done(.init(status: 302, url: url.absoluteString, location: "/hop\(sent)", receivedBytes: 0))
                } else { done(.init(status: 200, url: url.absoluteString, body: html, receivedBytes: html.utf8.count)) }
                return {}
            })
            let result = await chain.load(request())
            expect(count == 5 ? result?.url.path == "/hop5" && sent == 6 : result == nil && sent == 6, "five redirects are allowed; a sixth cannot start another request")
        }
        var loops = 0
        let loop = LinkSummaryFetch(clock: ManualScheduler(), start: { url, _, _, _, done in
            loops += 1
            done(.init(status: 301, url: url.absoluteString, location: seed.absoluteString + "#different", receivedBytes: 0))
            return {}
        })
        expect(await loop.load(request()) == nil && loops == 1, "fragments cannot conceal a redirect loop")
        var budgets: [Int] = []
        let oversized = LinkSummaryFetch(clock: ManualScheduler(), start: { url, _, maximum, _, done in
            budgets.append(maximum)
            if budgets.count == 1 {
                done(.init(status: 302, url: url.absoluteString, location: "/next", receivedBytes: maximum - 10))
            } else { done(.init(status: 200, url: url.absoluteString, body: html, receivedBytes: 11)) }
            return {}
        })
        expect(await oversized.load(request()) == nil && budgets == [LinkSummaryFetchPolicy.maximumBytes, 10], "redirect bytes reduce the next native allowance and cannot exceed the aggregate cap")
        for response in [
            LinkSummaryFetch.Response(status: 200, url: "http://example.com/final", body: html, receivedBytes: html.utf8.count),
            .init(status: 200, url: "http://127.0.0.1/final", body: html, receivedBytes: html.utf8.count),
            .init(status: 404, url: seed.absoluteString, body: html, receivedBytes: html.utf8.count),
            .init(status: 200, url: seed.absoluteString, mime: "image/png", body: html, receivedBytes: html.utf8.count),
            .init(status: 200, url: seed.absoluteString, body: "", receivedBytes: 0),
        ] {
            let invalid = LinkSummaryFetch(clock: ManualScheduler(), start: { _, _, _, _, done in done(response); return {} })
            expect(await invalid.load(request(secure: true)) == nil, "invalid final URL/status/MIME/body cannot produce a page")
        }
        await cancellationRaces(expect)
        await aggregateDeadline(expect)
    }

    private static func cancellationRaces(_ expect: (Bool, String) -> Void) async {
        let ready = Gate<Void>()
        var second: (@MainActor (LinkSummaryFetch.Response) -> Void)?
        var cancelledSecond = false
        let loader = LinkSummaryFetch(clock: ManualScheduler(), start: { url, _, _, _, done in
            if url == seed {
                done(.init(status: 302, url: url.absoluteString, location: "/next", receivedBytes: 0))
                return { done(.init(status: 200, url: url.absoluteString, body: "stale", receivedBytes: 5)) }
            }
            second = done
            ready.resolve(())
            return { cancelledSecond = true; done(.init(status: 0, url: url.absoluteString, receivedBytes: 0)) }
        })
        let task = Task { await loader.load(request()) }
        await ready.wait()
        task.cancel()
        let result = await task.value
        expect(result == nil && cancelledSecond, "old synchronous completion cannot replace the next handle; cancellation finishes and cancels that active hop")
        second?(.init(status: 200, url: "https://example.com/next", body: html, receivedBytes: html.utf8.count))
        expect(result == nil, "late completion cannot resume a cancelled continuation twice")
        var began = false
        let cancelled = LinkSummaryFetch(clock: ManualScheduler(), start: { _, _, _, _, _ in began = true; return {} })
        let entry = Task { await cancelled.load(request()) }
        entry.cancel()
        expect(await entry.value == nil && !began, "a cancelled entry cannot initiate a native request")
    }

    private static func aggregateDeadline(_ expect: (Bool, String) -> Void) async {
        let clock = ManualScheduler(), ready = Gate<Void>()
        var remaining: [TimeInterval] = []
        var cancelled = false
        var last: (@MainActor (LinkSummaryFetch.Response) -> Void)?
        let loader = LinkSummaryFetch(clock: clock, start: { url, _, _, timeout, done in
            remaining.append(timeout)
            if url == seed {
                clock.advance(by: 15)
                done(.init(status: 302, url: url.absoluteString, location: "/slow", receivedBytes: 0))
            } else { last = done; ready.resolve(()) }
            return { if url != seed { cancelled = true } }
        })
        let task = Task { await loader.load(request()) }
        await ready.wait()
        clock.advance(by: 5)
        expect(await task.value == nil && cancelled && remaining == [20, 5], "one deadline spans hops and cancels the active native handle")
        last?(.init(status: 200, url: "https://example.com/slow", body: html, receivedBytes: html.utf8.count))
        expect(clock.pendingCount == 0, "completion releases deadline work and ignores late delivery")
    }
}
