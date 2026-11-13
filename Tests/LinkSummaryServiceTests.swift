import AppKit

@MainActor final class Gate<Value> {
    private var waiting: CheckedContinuation<Value, Never>?
    private var value: Value?
    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiting = $0 }
    }
    func resolve(_ value: Value) {
        self.value = value
        waiting?.resume(returning: value)
        waiting = nil
    }
}

@main @MainActor enum LinkSummaryServiceTests {
    private static var checks = 0
    private static let link = URL(string: "https://example.com/story")!
    private static let theme = SpaceTheme.presets[0]
    private static let html = "<head><title>A page</title><meta property='og:image' content='/hero.png'></head><body>A supported paragraph of useful information.</body>"
    private static let answer = LinkSummaryPrompt.Answer(blocked: false, quickSummary: "A current answer", details: [
        .init(label: "Detail", icon: "star", info: "A useful fact about this page")
    ])

    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }
    private static func request(profile: String? = nil, query: String? = nil, language: String = "English") -> LinkSummaryRequest {
        .init(link: link, profilePath: profile, httpsOnly: false, searchQuery: query, language: language)
    }
    private static func visibleText(_ panel: LinkSummaryPanel) -> [String] {
        panel.cardView.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.map(\.stringValue)
    }
    private static func panel(_ parent: NSWindow) -> LinkSummaryPanel? {
        parent.childWindows?.compactMap { $0 as? LinkSummaryPanel }.first
    }

    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        await LinkSummaryFetchTests.run(expect)
        await failedAndBlockedLoadsFinish()
        await cancelledImageCannotPublish()
        await imageArrivesAfterSummary()
        await cancelledModelCannotCache()
        await titleAndModelUseTheirRequestContext()
        await finalPageURLReachesMetadataAndModel()
        await cancelledTitleCannotStartFetching()
        await generationsRejectOldInspectionsAndResults()
        await hardStopClearsCompletedSharing()
        await deadlineEndsIgnoringFetch()
        await deadlineRejectsLateModelPartials()
        print("Link summary lifecycle: \(checks) checks passed")
    }

    private static func failedAndBlockedLoadsFinish() async {
        let failure = LinkSummaryService(fetch: { _ in nil })
        var cards: [LinkSummaryService.Card] = []
        await failure.load(request()) { cards.append($0) }
        expect(cards.count == 1 && cards.last?.finished == true && cards.last?.result == nil, "HTML failure must end loading with the existing empty state")
        expect(failure.cached(request()) == nil, "HTML failure must remain retryable")
        let blocked = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, partial in
            partial(answer)
            return .init(blocked: true, quickSummary: "Blocked", details: [])
        })
        cards = []
        await blocked.load(request()) { cards.append($0) }
        expect(cards.contains { $0.result != nil && !$0.finished }, "a partial answer can be shown before final validation")
        expect(cards.last?.finished == true && cards.last?.result == nil && cards.last?.image == nil, "blocked final output clears earlier rows and images")
        expect(blocked.cached(request()) == nil, "blocked final output must not enter the cache")
    }

    private static func cancelledImageCannotPublish() async {
        let imageStarted = Gate<Void>(), imageResult = Gate<NSImage?>(), finished = Gate<Void>()
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in
            imageStarted.resolve(())
            return await imageResult.wait() // Deliberately ignores cancellation until released.
        }, answer: { _, _, _, _, _ in answer })
        var cards: [LinkSummaryService.Card] = []
        let task = Task { await service.load(request()) { card in
            cards.append(card)
            if card.finished { finished.resolve(()) }
        } }
        await imageStarted.wait()
        await finished.wait()
        let before = cards.count
        task.cancel()
        imageResult.resolve(NSImage(size: NSSize(width: 10, height: 10)))
        await task.value
        expect(cards.count == before && cards.allSatisfy { $0.image == nil }, "cancelled owned image must not publish a late card")
        expect(service.cached(request())?.image == nil, "cancelled image must not enter the cache")
    }

    private static func imageArrivesAfterSummary() async {
        let imageStarted = Gate<Void>(), imageResult = Gate<NSImage?>(), finished = Gate<Void>()
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in
            imageStarted.resolve(())
            return await imageResult.wait()
        }, answer: { _, _, _, _, _ in answer })
        var cards: [LinkSummaryService.Card] = []
        let task = Task { await service.load(request()) { card in
            cards.append(card)
            if card.finished { finished.resolve(()) }
        } }
        await imageStarted.wait()
        await finished.wait()
        expect(cards.last?.finished == true && cards.last?.image == nil, "summary completion must not wait for an optional image")
        let image = NSImage(size: NSSize(width: 10, height: 10))
        imageResult.resolve(image)
        await task.value
        expect(cards.last?.finished == true && cards.last?.image === image, "a still-owned image can update the completed current card")
        expect(service.cached(request())?.image === image, "completed image is cached in its full request context")
        expect(service.cached(request(profile: "/profiles/other")) == nil, "another profile cannot reuse that card or image")
    }

    private static func cancelledModelCannotCache() async {
        let started = Gate<Void>(), final = Gate<LinkSummaryPrompt.Answer?>()
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, partial in
            started.resolve(())
            let value = await final.wait()
            if let value { partial(value) }
            return value
        })
        var cards: [LinkSummaryService.Card] = []
        let task = Task { await service.load(request()) { cards.append($0) } }
        await started.wait()
        task.cancel()
        final.resolve(answer)
        await task.value
        expect(cards.allSatisfy { !$0.finished && $0.result == nil }, "a provider that returns after cancellation cannot publish a final or partial answer")
        expect(service.cached(request()) == nil, "a cancelled model result cannot enter the cache")
    }

    private static func titleAndModelUseTheirRequestContext() async {
        let service = LinkSummaryService(fetch: { request in .init(html: "<head><title>\(request.profilePath ?? "Default")</title></head><body>Useful body text.</body>", url: request.fetchURL) },
                                         image: { _ in nil }, answer: { _, _, query, language, _ in
            .init(blocked: false, quickSummary: "\(query ?? "No query") / \(language)", details: answer.details)
        })
        expect(await service.title(request(profile: "/profiles/A")) == "/profiles/A", "title comes from profile A")
        expect(await service.title(request(profile: "/profiles/B")) == "/profiles/B", "same-URL title in B cannot reuse A")
        var last: LinkSummaryService.Card?
        let context = request(profile: "/profiles/A", query: "price", language: "Danish")
        await service.load(context) { last = $0 }
        expect(last?.result?.quickSummary == "price / Danish", "the captured query and language reach actual generation")
        expect(service.cached(context)?.result == last?.result, "the completed result is cached for that exact context")
        expect(service.cached(request(profile: "/profiles/A", query: "reviews", language: "Danish")) == nil, "another query cannot reuse the completed answer")
    }

    private static func finalPageURLReachesMetadataAndModel() async {
        let finalURL = URL(string: "https://destination.example/articles/final")!
        let redirectedHTML = "<head><title>Final</title><meta property='og:image' content='hero.png'></head><body>Useful final content.</body>"
        var imageURL: URL?
        let service = LinkSummaryService(fetch: { _ in .init(html: redirectedHTML, url: finalURL) }, image: { url in imageURL = url; return nil },
                                         answer: { url, _, _, _, _ in .init(blocked: false, quickSummary: url.absoluteString, details: answer.details) })
        var result: LinkSummaryResult?
        await service.load(request()) { result = $0.result }
        expect(result?.quickSummary == finalURL.absoluteString, "generation receives the actual final page URL")
        expect(imageURL == URL(string: "https://destination.example/articles/hero.png"), "service resolves relative metadata against the final page")
        expect(result?.url == link.absoluteString, "the original hovered URL remains the displayed/shared link")
    }

    private static func cancelledTitleCannotStartFetching() async {
        var fetches = 0
        let service = LinkSummaryService(fetch: { request in fetches += 1; return .init(html: html, url: request.fetchURL) })
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.title(request())
        }
        expect(await cancelled.value == nil, "an already-cancelled title load produces no title")
        expect(await service.title(request()) == "A page", "a fresh title request still extracts the actual page title")
        expect(fetches == 1, "a title load cancelled before it starts cannot initiate a page fetch")
    }

    private static func generationsRejectOldInspectionsAndResults() async {
        let clock = ManualScheduler()
        let started = Gate<Void>(), final = Gate<LinkSummaryPrompt.Answer?>()
        var oldPartial: ((LinkSummaryPrompt.Answer) -> Void)?
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, partial in
            oldPartial = partial
            started.resolve(())
            return await final.wait()
        })
        let controller = LinkSummaryPreviewController(clock: clock, service: service)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        defer { controller.stop(); parent.orderOut(nil) }
        let window = UUID(), tab = UUID(), runtime = NSObject()
        var current = true
        var inspections: [(@MainActor (LinkSummaryPreviewController.Inspection?) -> Void)] = []
        func hover(revision: UInt, profile: String? = nil) -> LinkSummaryPreviewController.Hover {
            .init(context: .init(request: request(profile: profile), page: URL(string: "https://news.ycombinator.com/"),
                                 windowID: window, tabID: tab, runtimeID: ObjectIdentifier(runtime), navigationRevision: revision),
                  window: parent, theme: theme, shiftHeld: false, isCurrent: { current }, inspect: { inspections.append($0) })
        }
        let found = LinkSummaryPreviewController.Inspection(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: link)
        controller.linkHoverChanged(hover(revision: 1))
        clock.advance(by: 1)
        controller.linkHoverChanged(hover(revision: 2, profile: "/profiles/B"))
        clock.advance(by: 1)
        controller.linkHoverChanged(hover(revision: 1))
        clock.advance(by: 1)
        expect(inspections.count == 3, "same URL in another profile/navigation must create fresh hover work")
        inspections[0](found)
        inspections[1](found)
        expect(panel(parent) == nil, "A-to-B-to-A must reject old same-URL inspections")
        inspections[2](.init(rect: found.rect, arcLink: true, link: URL(string: "https://example.com/changed")!))
        expect(panel(parent) == nil, "the inspected href must still be the hovered link")
        inspections[2](found)
        await started.wait()
        let card = panel(parent)!
        controller.stop(windowID: UUID())
        controller.pointerLeftLink(windowID: UUID(), tabID: UUID())
        controller.pointerLeftLink(windowID: window, tabID: UUID())
        expect(clock.pendingCount == 1, "another window or split tab cannot cancel the current card through a stale link leave")
        current = false
        controller.validate(windowID: window)
        oldPartial?(answer) // Delivery on another task must still fail the presentation generation guard.
        final.resolve(answer)
        // The view's retained result is inspected without ever invoking the system pasteboard.
        let retained = Mirror(reflecting: card.cardView).children.first { $0.label == "shown" }!
        expect(Mirror(reflecting: retained.value).children.isEmpty, "hard origin invalidation cannot retain or publish an old copy result")
        expect(!visibleText(card).contains("A current answer"), "late provider output cannot update the invalidated card")
        expect(clock.pendingCount == 0, "hard invalidation cancels hover/deadline work")
    }

    private static func hardStopClearsCompletedSharing() async {
        let clock = ManualScheduler()
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, _ in answer })
        await service.load(request()) { _ in }
        let controller = LinkSummaryPreviewController(clock: clock, service: service)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        defer { controller.stop(); parent.orderOut(nil) }
        let window = UUID(), runtime = NSObject()
        controller.linkHoverChanged(.init(context: .init(request: request(), page: URL(string: "https://news.ycombinator.com/"),
                                                        windowID: window, tabID: UUID(), runtimeID: ObjectIdentifier(runtime), navigationRevision: 1),
                                          window: parent, theme: theme, shiftHeld: false, isCurrent: { true }, inspect: {
            $0(.init(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: link))
        }))
        clock.advance(by: 1)
        let card = panel(parent)!
        let before = Mirror(reflecting: card.cardView).children.first { $0.label == "shown" }!
        expect(!Mirror(reflecting: before.value).children.isEmpty, "a completed current card owns a share result")
        controller.stop(windowID: window)
        let after = Mirror(reflecting: card.cardView).children.first { $0.label == "shown" }!
        expect(Mirror(reflecting: after.value).children.isEmpty, "hard stop immediately clears a completed copy result without clipboard access")
        expect(visibleText(card).contains("A current answer"), "sharing invalidation preserves the closing card's text and motion")
    }

    private static func deadlineRejectsLateModelPartials() async {
        let clock = ManualScheduler(), started = Gate<Void>(), final = Gate<LinkSummaryPrompt.Answer?>(), returned = Gate<Void>()
        var partial: ((LinkSummaryPrompt.Answer) -> Void)?
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, update in
            partial = update
            started.resolve(())
            let result = await final.wait()
            returned.resolve(())
            return result
        })
        let controller = LinkSummaryPreviewController(clock: clock, service: service)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        defer { controller.stop(); parent.orderOut(nil) }
        let runtime = NSObject()
        controller.linkHoverChanged(.init(context: .init(request: request(), page: URL(string: "https://news.ycombinator.com/"),
                                                        windowID: UUID(), tabID: UUID(), runtimeID: ObjectIdentifier(runtime), navigationRevision: 1),
                                          window: parent, theme: theme, shiftHeld: false, isCurrent: { true }, inspect: {
            $0(.init(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: link))
        }))
        clock.advance(by: 1)
        await started.wait()
        let card = panel(parent)!
        partial?(answer)
        expect(visibleText(card).contains("A current answer"), "the current model's partial answer renders normally")
        clock.advance(by: LinkSummaryPreviewController.loadingTimeout)
        partial?(answer) // This callback ignores cancellation and runs outside the cancelled load task.
        expect(visibleText(card).contains("No preview available") && !visibleText(card).contains("A current answer"),
               "the deadline invalidates late model partials even when the provider ignores cancellation")
        final.resolve(answer)
        await returned.wait()
        expect(service.cached(request()) == nil, "a timed-out model cannot cache a late final response")
    }

    private static func deadlineEndsIgnoringFetch() async {
        let clock = ManualScheduler(), started = Gate<Void>(), htmlResult = Gate<String?>(), released = Gate<Void>()
        let service = LinkSummaryService(fetch: { request in
            started.resolve(())
            let result = await htmlResult.wait()
            released.resolve(())
            return result.map { .init(html: $0, url: request.fetchURL) }
        },
                                         image: { _ in nil }, answer: { _, _, _, _, _ in answer })
        let controller = LinkSummaryPreviewController(clock: clock, service: service)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        defer { controller.stop(); parent.orderOut(nil) }
        let runtime = NSObject()
        let context = LinkSummaryContext(request: request(), page: URL(string: "https://news.ycombinator.com/"), windowID: UUID(), tabID: UUID(),
                                         runtimeID: ObjectIdentifier(runtime), navigationRevision: 1)
        controller.linkHoverChanged(.init(context: context, window: parent, theme: theme, shiftHeld: false, isCurrent: { true }, inspect: {
            $0(.init(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: link))
        }))
        clock.advance(by: 1)
        await started.wait()
        let card = panel(parent)!
        clock.advance(by: LinkSummaryPreviewController.loadingTimeout)
        expect(visibleText(card).contains("No preview available"), "deadline terminates loading without waiting for an ignoring fetch")
        htmlResult.resolve(html)
        await released.wait()
        expect(visibleText(card).contains("No preview available") && service.cached(request()) == nil, "late fetch completion cannot resurrect or cache a timed-out preview")
    }
}
