import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

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
        .init(label: "Detail", icon: "star", info: "A useful fact about this page"),
        .init(label: "Context", icon: "info.circle", info: "Another useful fact from the page")
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
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guidedSchemaAndOptionalPartials()
            await callerCancellationRejectsImmediateLatePartial()
            await modelRetryErrorsAndDeadline()
            await retryResetIsVisibleAndOffOnCancels()
        }
        if #available(macOS 26.4, *) {
            await modelPreflightAndFreshRetry()
            await deadlineAndCancellationDuringPreflight()
        }
        #endif
        await optionalAndEmptyModelOutput()
        await LinkSummaryFetchTests.run(expect)
        await failedAndBlockedLoadsFinish()
        await imageFailureKeepsSummary()
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

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func guidedSchemaAndOptionalPartials() {
        let schema = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(HoverCardAnswer.generationSchema)) as! [String: Any]
        expect(schema["x-order"] as? [String] == ["blocked", "userQuestion", "quickSummary", "details"], "actual guided field order generates search focus before the summary and details")
        expect(schema["required"] as? [String] == ["blocked", "details"], "focus and quickSummary are optional in the actual static guided schema")
        let properties = schema["properties"] as! [String: Any]
        let details = properties["details"] as! [String: Any]
        expect(details["minItems"] as? Int == 2 && details["maxItems"] as? Int == 4, "the actual guided schema retains 2-4 detail rows")
        let focus = properties["userQuestion"] as! [String: Any]
        expect((focus["description"] as? String)?.contains("Leave nil when no search query") == true, "the static schema explicitly handles queryless requests")
        let missing = try! HoverCardAnswer.PartiallyGenerated(GeneratedContent(properties: ["blocked": false]))
        let empty = LinkSummaryPrompt.Answer(missing)
        expect(empty.userQuestion == nil && empty.quickSummary == nil && empty.details.isEmpty, "missing generated optional fields stay absent")
        let focusOnly = try! HoverCardAnswer.PartiallyGenerated(GeneratedContent(properties: ["blocked": false, "userQuestion": "Price"]))
        let partial = LinkSummaryPrompt.Answer(focusOnly)
        expect(partial.userQuestion == "Price" && partial.quickSummary == nil, "the typed adapter does not confuse generated focus with quickSummary")
        expect(LinkSummaryPrompt.result(url: link, title: nil, answer: partial) == nil, "focus-only streaming cannot manufacture a visible answer")
        let complete = try! HoverCardAnswer.PartiallyGenerated(GeneratedContent(json: """
        {"blocked":false,"details":[{"label":"Cost","icon":"tag","info":"Twenty euros per person"},{"label":"Choice","icon":"star","info":"A useful local option"}]}
        """))
        expect(LinkSummaryPrompt.result(url: link, title: nil, answer: .init(complete), final: true)?.details.count == 2, "typed streamed details remain usable without either optional field")
    }
    #endif

    private static func optionalAndEmptyModelOutput() async {
        var attempt = 0
        let service = LinkSummaryService(fetch: { .init(html: html, url: $0.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, partial in
            attempt += 1
            if attempt == 1 {
                let value = LinkSummaryPrompt.Answer(blocked: false, userQuestion: "Price", quickSummary: nil, details: [])
                partial(value)
                return value
            }
            return .init(blocked: false, quickSummary: nil, details: answer.details)
        })
        var last: LinkSummaryService.Card?
        await service.load(request(query: "price")) { last = $0 }
        expect(last?.finished == true && last?.result == nil && service.cached(request(query: "price")) == nil,
               "focus-only final output ends empty without a transient negative cache entry")
        await service.load(request(query: "price")) { last = $0 }
        expect(last?.result?.quickSummary == nil && last?.result?.details == answer.details,
               "the next hover recovers with useful details and no optional quickSummary")
        expect(service.cached(request(query: "price"))?.result == last?.result, "only the usable recovered result is cached")
        let incomplete = LinkSummaryService(fetch: { .init(html: html, url: $0.fetchURL) }, image: { _ in nil }, answer: { _, _, _, _, partial in
            let value = LinkSummaryPrompt.Answer(blocked: false, quickSummary: "Only a summary", details: [])
            partial(value)
            return value
        })
        await incomplete.load(request()) { last = $0 }
        expect(last?.finished == true && last?.result == nil && incomplete.cached(request()) == nil,
               "incomplete final details clear earlier partial content and remain retryable")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func overflow() -> LanguageModelSession.GenerationError {
        .exceededContextWindowSize(.init(debugDescription: "controlled context overflow"))
    }

    @available(macOS 26.4, *)
    private static func modelPreflightAndFreshRetry() async {
        let clock = ManualScheduler(), second = Gate<Void>(), release = Gate<Void>()
        var measured: [String] = [], streamed: [String] = [], sessions: [LanguageModelSession] = []
        var events: [LinkSummaryPrompt.Answer?] = []
        var oldPartial: ((LinkSummaryPrompt.Answer?) -> Void)?
        let source = LinkSummaryContent.Extracted(title: String(repeating: "Title ", count: 1_000),
                                                   description: String(repeating: "Description ", count: 1_000),
                                                   bodyText: String(repeating: "Useful content. ", count: 1_000))
        let task = Task {
            await LinkSummaryService.ask(url: link, content: source, searchQuery: "price", language: "Danish", partial: { events.append($0) }, respond: { input, partial in
                try await LinkSummaryModel.respond(input, partial: partial, count: { component in
                    switch component {
                    case .instructions(let instructions):
                        expect(instructions == LinkSummaryPrompt.instructions, "preflight counts actual full trusted instructions once")
                        return 100
                    case .prompt(let prompt):
                        expect(prompt == input.prompt, "counted prompt is exactly the fitted string sent to the stream")
                        measured.append(prompt)
                        return 1_000
                    case .schema(let schema):
                        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(schema)) as! [String: Any]
                        expect(encoded["x-order"] as? [String] == ["blocked", "userQuestion", "quickSummary", "details"], "preflight counts the actual single guided schema")
                        return 1_716 // Controlled total 2816, exactly context minus output/safety reserves.
                    case .transcript(let history):
                        expect(history.isEmpty, "fresh sessions contain no invented prior-hover transcript after instructions are counted once")
                        return 0
                    }
                }, contextSize: 4_096, stream: { session, prompt, limit, update in
                    sessions.append(session)
                    streamed.append(prompt)
                    expect(limit == 1_024, "the stream enforces the same output reserve used by preflight")
                    if streamed.count == 1 {
                        oldPartial = update
                        update(answer)
                        clock.advance(by: 10)
                        throw overflow()
                    }
                    second.resolve(())
                    await release.wait()
                    update(.init(blocked: false, quickSummary: "Fresh attempt", details: answer.details))
                    return .init(blocked: false, quickSummary: "Fresh attempt", details: answer.details)
                })
            }, clock: clock)
        }
        await second.wait()
        expect(events.count == 2 && events[0]?.quickSummary == answer.quickSummary && events[1] == nil,
               "overflow clears the first attempt's already emitted rows before the new provider starts")
        expect(measured == streamed && streamed[1].utf8.count < streamed[0].utf8.count, "the second actual transmitted/counted prompt is substantially smaller")
        expect(sessions.count == 2 && sessions[0] !== sessions[1], "retry uses a distinct fresh SDK session")
        expect(clock.pendingCount == 1, "both attempts share one model deadline")
        oldPartial?(answer)
        expect(events.count == 2, "an abandoned attempt cannot publish into the fresh stream")
        release.resolve(())
        let result = await task.value
        expect(result?.quickSummary == "Fresh attempt" && events.last.flatMap { $0 }?.quickSummary == "Fresh attempt", "only fresh output becomes the returned answer")
        oldPartial?(answer)
        expect(events.count == 3 && clock.pendingCount == 0, "completion rejects late partials and releases its sole deadline")

        let input = LinkSummaryPrompt.fitted(url: link.absoluteString, content: source, searchQuery: "price", language: "Danish")
        for schemaOnly in [true, false] {
            var countCalls = 0, streamCalls = 0
            let refused = await LinkSummaryService.ask(url: link, content: source, searchQuery: "price", language: "Danish", partial: { _ in }, respond: { input, partial in
                try await LinkSummaryModel.respond(input, partial: partial, count: { component in
                    switch component {
                    case .instructions: return schemaOnly ? 0 : 500
                    case .prompt: return schemaOnly ? 0 : 1_200
                    case .schema:
                        countCalls += 1
                        return schemaOnly ? 2_817 : 1_117
                    case .transcript: return 0
                    }
                }, contextSize: 4_096, stream: { _, _, _, _ in streamCalls += 1; return answer })
            }, clock: ManualScheduler())
            expect(refused == nil && countCalls == 2 && streamCalls == 0,
                   "schema and combined instruction/prompt/schema costs cannot bypass output/safety reserves; preflight retries once without generation")
        }
        expect(input.prompt.utf8.count <= 1_536, "an oversized fixed/schema budget cannot be bypassed by already bounded metadata")
    }

    @available(macOS 26.4, *)
    private static func deadlineAndCancellationDuringPreflight() async {
        for cancel in [false, true] {
            let clock = ManualScheduler(), entered = Gate<Void>(), release = Gate<Void>(), adapterReturned = Gate<Void>()
            var streams = 0
            let task = Task {
                await LinkSummaryService.ask(url: link, content: .init(bodyText: "Useful text"), searchQuery: nil, language: "English", partial: { _ in preconditionFailure("preflight cannot stream or reset after cancellation/deadline") }, respond: { input, partial in
                    defer { adapterReturned.resolve(()) }
                    return try await LinkSummaryModel.respond(input, partial: partial, count: { component in
                        if case .schema = component {
                            entered.resolve(())
                            await release.wait() // Deliberately ignores token-counter cancellation.
                        }
                        return 0
                    }, stream: { _, _, _, _ in streams += 1; return answer })
                }, clock: clock)
            }
            await entered.wait()
            if cancel { task.cancel() } else { clock.advance(by: LinkSummaryService.modelTimeout) }
            let result = await task.value
            expect(result == nil && streams == 0 && clock.pendingCount == 0, "preflight cancellation/deadline ends promptly before generation and releases the timer")
            release.resolve(())
            await adapterReturned.wait()
            expect(streams == 0, "late token-count completion cannot start a model stream after termination")
        }
    }

    @available(macOS 26.0, *)
    private static func callerCancellationRejectsImmediateLatePartial() async {
        let clock = ManualScheduler(), entered = Gate<Void>(), release = Gate<Void>(), providerReturned = Gate<Void>()
        var late: ((LinkSummaryPrompt.Answer?) -> Void)?, events = 0
        let task = Task {
            await LinkSummaryService.ask(url: link, content: .init(bodyText: "Useful text"), searchQuery: nil, language: "English", partial: { _ in events += 1 }, respond: { _, partial in
                late = partial
                entered.resolve(())
                await release.wait()
                providerReturned.resolve(())
                return answer
            }, clock: clock)
        }
        await entered.wait()
        task.cancel()
        late?(answer) // Same actor turn, before an asynchronously scheduled cancellation cleanup.
        expect(events == 0, "caller cancellation immediately rejects provider partials delivered from another task")
        let result = await task.value
        expect(result == nil && clock.pendingCount == 0, "caller cancellation terminates without waiting for an ignoring provider")
        release.resolve(())
        await providerReturned.wait()
    }

    @available(macOS 26.0, *)
    private static func modelRetryErrorsAndDeadline() async {
        let errors: [Error] = [CancellationError(), CocoaError(.coderReadCorrupt),
                              NSError(domain: "exceededContextWindowSize", code: 1),
                              LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "guardrail")),
                              LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "schema")),
                              LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(.init(debugDescription: "language")),
                              LanguageModelSession.GenerationError.assetsUnavailable(.init(debugDescription: "unavailable")),
                              LanguageModelSession.GenerationError.refusal(.init(transcriptEntries: []), .init(debugDescription: "refusal"))]
        for error in errors {
            var calls = 0, resets = 0
            let clock = ManualScheduler()
            let result = await LinkSummaryService.ask(url: link, content: .init(bodyText: "Useful text"), searchQuery: nil, language: "English", partial: { if $0 == nil { resets += 1 } }, respond: { _, _ in calls += 1; throw error }, clock: clock)
            expect(result == nil && calls == 1 && resets == 0 && clock.pendingCount == 0, "non-overflow errors neither retry nor retain model work: \(type(of: error))")
        }
        var calls = 0, resets = 0
        let twice = await LinkSummaryService.ask(url: link, content: .init(bodyText: "Useful text"), searchQuery: nil, language: "English", partial: { if $0 == nil { resets += 1 } }, respond: { _, _ in calls += 1; throw overflow() }, clock: ManualScheduler())
        expect(twice == nil && calls == 2 && resets == 1, "a second typed overflow is terminal, with no third attempt")
        calls = 0
        let cancelled = await LinkSummaryService.ask(url: link, content: .init(), searchQuery: nil, language: "English", partial: { _ in preconditionFailure("cancelled overflow cannot reset") }, respond: { _, _ in
            calls += 1
            withUnsafeCurrentTask { $0?.cancel() }
            throw overflow()
        }, clock: ManualScheduler())
        expect(cancelled == nil && calls == 1, "task cancellation during overflow delivery prevents retry")

        let clock = ManualScheduler(), entered = Gate<Void>(), release = Gate<Void>(), providerReturned = Gate<Void>()
        var late: ((LinkSummaryPrompt.Answer?) -> Void)?, events = 0, attempts = 0
        let timeout = Task {
            await LinkSummaryService.ask(url: link, content: .init(bodyText: "Useful text"), searchQuery: nil, language: "English", partial: { _ in events += 1 }, respond: { _, partial in
                attempts += 1
                if attempts == 1 { clock.advance(by: 10); throw overflow() }
                late = partial
                entered.resolve(())
                await release.wait() // Deliberately ignores cancellation.
                providerReturned.resolve(())
                return answer
            }, clock: clock)
        }
        await entered.wait()
        clock.advance(by: 8)
        let result = await timeout.value
        expect(result == nil && attempts == 2 && clock.pendingCount == 0, "one 18-second phase deadline includes preflight/retry and does not wait for an ignoring provider")
        let before = events
        late?(answer)
        expect(events == before, "terminal deadline invalidates provider partials delivered on another task")
        release.resolve(())
        await providerReturned.wait()
    }

    @available(macOS 26.0, *)
    private static func retryResetIsVisibleAndOffOnCancels() async {
        let clock = ManualScheduler(), entered = Gate<Void>(), release = Gate<Void>(), returned = Gate<Void>()
        var enabled = true, calls = 0
        var late: ((LinkSummaryPrompt.Answer?) -> Void)?
        let service = LinkSummaryService(fetch: { .init(html: html, url: $0.fetchURL) }, image: { _ in nil }, answer: { url, content, query, language, partial in
            let result = await LinkSummaryService.ask(url: url, content: content, searchQuery: query, language: language, partial: partial, respond: { _, update in
                calls += 1
                if calls == 1 { update(answer); throw overflow() }
                late = update
                entered.resolve(())
                await release.wait()
                return answer
            }, clock: clock)
            returned.resolve(())
            return result
        })
        let controller = LinkSummaryPreviewController(clock: clock, service: service)
        let parent = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderBack(nil)
        defer { controller.stop(); parent.orderOut(nil) }
        let window = UUID(), runtime = NSObject()
        let origin = LinkSummaryContext(request: request(), page: URL(string: "https://news.ycombinator.com/"),
                                        windowID: window, tabID: UUID(), runtimeID: ObjectIdentifier(runtime), navigationRevision: 1)
        controller.linkHoverChanged(.init(context: origin, window: parent, theme: theme, shiftHeld: false, isCurrent: { enabled }, inspect: {
            $0(.init(rect: NSRect(x: -9800, y: -9500, width: 100, height: 16), arcLink: true, link: link))
        }))
        clock.advance(by: 1)
        await entered.wait()
        let card = panel(parent)!
        expect(!visibleText(card).contains("A current answer") && !visibleText(card).contains("No preview available"), "the fresh attempt visibly resets old rows to the existing loading card")
        let sharing = Mirror(reflecting: card.cardView).children.first { $0.label == "shown" }!
        expect(Mirror(reflecting: sharing.value).children.isEmpty, "a retry cannot share an abandoned partial result")
        enabled = false
        controller.validate(windowID: window)
        enabled = true // Same-turn off/on must not revive the accepted retry/provider.
        await returned.wait()
        late?(answer)
        expect(service.cached(request()) == nil && calls == 2, "off/on during retry cancels model work without caching or another automatic attempt")
        release.resolve(())
    }
    #endif

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

    private static func imageFailureKeepsSummary() async {
        let service = LinkSummaryService(fetch: { request in .init(html: html, url: request.fetchURL) },
                                         image: { _ in nil }, answer: { _, _, _, _, _ in answer })
        var last: LinkSummaryService.Card?
        await service.load(request()) { last = $0 }
        expect(last?.finished == true && last?.result?.quickSummary == answer.quickSummary && last?.image == nil,
               "a rejected optional image leaves the completed summary usable")
        expect(service.cached(request())?.result == last?.result,
               "an image transport failure does not discard a successful summary cache entry")
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
        var oldPartial: ((LinkSummaryPrompt.Answer?) -> Void)?
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
        var partial: ((LinkSummaryPrompt.Answer?) -> Void)?
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
