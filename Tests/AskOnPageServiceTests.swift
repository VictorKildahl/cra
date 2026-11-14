import AppKit
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@MainActor
enum AskOnPageServiceTests {
    private static var checks = 0
    private static let page = AskOnPagePrompt.Page(url: "https://example.test/observatory", title: "Synthetic observatory",
        text: "The synthetic observatory opens at 09:30 and closes at 18:00. The observatory has three telescopes. Its visitor entrance is on Elm Street. No founder is identified in this article.")
    private static let quoted = AskOnPage.Draft(excerpts: ["The synthetic observatory opens at 09:30 and closes at 18:00."], answer: "It opens at 09:30.", keyAnswer: "09:30")
    private static let count: AskOnPagePrompt.TokenCount = { ($0.utf8.count + $1.utf8.count + 3) / 4 }

    private static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }
    private static func settled(_ service: AskOnPageService) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            @MainActor func track() {
                if !service.isLoading { done.resume(); return }
                withObservationTracking { _ = service.isLoading } onChange: { Task { @MainActor in track() } }
            }
            track()
        }
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--real-model-extended") { try await extendedRealModel(); return }
        if CommandLine.arguments.contains("--real-model") { try await realModel(); return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        AskOnPageSelectionTests.run()
        await AskOnPageControllerTests.run()
        await streamingAndHistory()
        await aFollowUpKeepsItsOwnCurrentQuestionAndAnswer()
        await invalidationAndTimeout()
        await synchronousConfigurationInvalidation()
        await failuresAndOverflow()
        try await schemaAndCompleteness()
        print("Ask on Page service: \(checks) checks passed (controlled provider)")
    }

    private static func streamingAndHistory() async {
        let browser = BrowserManager(), provider = Provider(), clock = ManualScheduler()
        let service = AskOnPageService(browsers: browser, enabled: { true }, available: { true }, clock: clock,
            countTokens: count, generate: provider.stream)
        expect(service.ask("When does it open?", language: "English"), "a valid explicit question starts a page read")
        expect(!service.ask("A second simultaneous question", language: "English"), "only one turn can run")
        browser.reply(page)
        await provider.started(1)
        provider.emit(.init(excerpts: ["The synthetic observatory"], answer: "It opens"))
        expect(service.current?.answer?.hasVerifiedQuote == false && service.messages.isEmpty, "a partial turn is neither a citation nor completed history")
        provider.emit(.init(answer: String(repeating: "📄", count: 20_000)))
        expect(service.current!.answer!.text.utf8.count <= 65_536, "a misbehaving provider cannot retain unbounded response bytes")
        provider.emit(quoted)
        expect(service.current?.answer?.text == quoted.answer && service.current?.answer?.hasVerifiedQuote == false, "cumulative fields replace earlier values and quotes remain unverified until completion")
        expect(service.current?.fractionRead == 1 && service.current?.isPartialPage == false, "the turn retains its exact source disclosure")
        provider.complete(quoted)
        await settled(service)
        expect(service.messages.count == 1 && service.messages[0].answer?.text == quoted.answer && service.current == nil,
               "only a completed answer enters visible history")
        expect(clock.pendingCount == 0, "successful requests retire their deadline")
        service.ask("And when does it close?", language: "English")
        browser.reply(page)
        await provider.started(2)
        expect(provider.requests[1].prompt.contains("When does it open?") && provider.requests[1].prompt.contains("09:30"),
               "follow-up fitting includes completed question-answer pairs")
        let unsupported = AskOnPage.Draft(excerpts: [], answer: "I guess it closes at 18:00.", keyAnswer: "18:00")
        provider.emit(unsupported)
        provider.complete(unsupported)
        await settled(service)
        expect(service.messages.last?.answer?.hasVerifiedQuote == false, "an unquoted answer is never labeled page-supported")
        service.ask("A rejected citation", language: "English"); browser.reply(page)
        await provider.started(3)
        provider.complete(.init(excerpts: ["An invented source sentence."], answer: "I guess this answer.", keyAnswer: "guess"))
        await settled(service)
        expect(service.messages.count == 3 && service.messages.last?.answer?.quotes.first?.state == .notFound,
               "complete invalid-citation answers stay in dialogue with disabled evidence")
        service.ask("Translation", language: "English"); browser.reply(page)
        await provider.started(4)
        let french = "L'observatoire ouvre à 09:30."
        provider.complete(.init(excerpts: quoted.excerpts, answer: french, keyAnswer: "L'observatoire ouvre a 09:30."))
        await settled(service)
        expect(service.messages.count == 4 && service.messages.last?.answer?.text == french
               && service.messages.last?.answer?.emphasisRange == nil && service.messages.last?.answer?.hasVerifiedQuote == true,
               "accent-mismatched emphasis preserves plain transformed answer and completed history without changing grounding")
        service.clear()
        expect(service.messages.isEmpty && service.current == nil && service.phase == .idle, "closing discards transient page text and dialogue")
    }

    // promise: #417
    private static func aFollowUpKeepsItsOwnCurrentQuestionAndAnswer() async {
        let browser = BrowserManager(), provider = Provider(), clock = ManualScheduler()
        let service = AskOnPageService(browsers: browser, enabled: { true }, available: { true }, clock: clock,
            countTokens: count, generate: provider.stream)
        service.ask("When does it open?", language: "English"); browser.reply(page)
        await provider.started(1)
        provider.complete(quoted)
        await settled(service)
        service.ask("And when does it close?", language: "English"); browser.reply(page)
        await provider.started(2)
        expect(service.messages.count == 1 && service.messages[0].answer?.text == "It opens at 09:30."
               && service.current?.question == "And when does it close?" && service.current?.answer == nil,
               "a new follow-up preserves the earlier completed answer without showing it as the current answer")
        expect(provider.requests[1].prompt.hasSuffix("CURRENT QUESTION:\n\"And when does it close?\""),
               "the follow-up is isolated as the current question, outside quoted earlier context")
        let closed = AskOnPage.Draft(excerpts: quoted.excerpts, answer: "It closes at 18:00.", keyAnswer: "18:00")
        provider.emit(closed)
        expect(service.current?.answer?.text == "It closes at 18:00." && service.messages[0].answer?.text == "It opens at 09:30.",
               "the follow-up's stream replaces only its own answer")
        provider.complete(closed)
        await settled(service)
        expect(service.messages.map { $0.answer?.text } == ["It opens at 09:30.", "It closes at 18:00."]
               && service.messages.allSatisfy { $0.answer?.hasVerifiedQuote == true },
               "each completed follow-up retains its own answer and exact source citation")
        service.clear()
    }

    private static func invalidationAndTimeout() async {
        let browser = BrowserManager(), provider = Provider(), clock = ManualScheduler(), flags = Flags()
        var service: AskOnPageService? = AskOnPageService(browsers: browser, enabled: { flags.enabled }, available: { flags.available },
            clock: clock, countTokens: count, generate: provider.stream)
        expect(service!.ask("Question", language: "English"), "request can start while enabled")
        let oldRead = browser.pending!
        browser.context = AskOnPageContext()
        oldRead(page)
        expect(service!.phase == .idle && service!.current == nil, "an obsolete extraction clears the request rather than publishing an error on the new page")
        service!.ask("A live question", language: "English"); browser.reply(page)
        await provider.started(1)
        let oldUpdate = provider.update!
        flags.enabled = false
        // The production observation re-arms on the main actor; wait for its actual invalidation.
        await settled(service!)
        flags.enabled = true
        oldUpdate(quoted)
        provider.complete(quoted)
        expect(service!.current == nil && service!.messages.isEmpty, "re-enabling after observed disable cannot revive a cancellation-ignoring old answer")
        service!.ask("A timed read", language: "English")
        clock.advance(by: AskOnPageService.requestTimeout)
        expect(service!.phase == .failed(.timedOut) && service!.messages.isEmpty, "an unanswered DOM read has a bounded lifetime")
        browser.reply(page)
        expect(service!.phase == .failed(.timedOut), "a late snapshot cannot restart a timed-out request")
        service!.clear()
        service!.ask("Availability change", language: "English"); browser.reply(page)
        await provider.started(2)
        flags.available = false
        await settled(service!)
        provider.emit(quoted); provider.complete(quoted)
        expect(service!.messages.isEmpty && service!.current == nil, "model unavailability invalidates in-flight work")
        flags.available = true
        service!.ask("Obsolete provider", language: "English"); browser.reply(page)
        await provider.started(3)
        let staleUpdate = provider.update!, staleDone = provider.detachCompletion()
        service!.clear()
        service!.ask("New request", language: "English"); browser.reply(page)
        await provider.started(4)
        provider.emit(.init(excerpts: [], answer: "Current answer", keyAnswer: "Current"))
        staleUpdate(.init(answer: "Obsolete answer")); staleDone.resume(throwing: AskOnPageService.Failure.refused)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(service!.current?.question == "New request" && service!.current?.answer?.text == "Current answer" && service!.phase == .answering,
               "an obsolete provider cannot replace the new request's text or failure state")
        provider.complete(quoted); await settled(service!)
        service!.ask("Closing the owner", language: "English"); browser.reply(page)
        await provider.started(5)
        weak var released: AskOnPageService?
        released = service
        service = nil
        expect(released == nil, "the in-flight provider does not retain its per-window service")
        provider.emit(quoted); provider.complete(quoted)
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        expect(clock.pendingCount == 0, "owner teardown also retires its deadline")
    }

    private static func synchronousConfigurationInvalidation() async {
        for availabilityChange in [false, true] {
            let browser = BrowserManager(), provider = Provider(), clock = ManualScheduler(), flags = Flags()
            let service = AskOnPageService(browsers: browser, enabled: { flags.enabled }, available: { flags.available },
                clock: clock, countTokens: count, generate: provider.stream)
            service.ask("Old configuration", language: "English"); browser.reply(page)
            await provider.started(1)
            let staleUpdate = provider.update!, staleDone = provider.detachCompletion()
            if availabilityChange { flags.available = false } else { flags.enabled = false }
            // The owner invalidates synchronously on the write; Observation alone can miss this pair.
            service.clear()
            if availabilityChange { flags.available = true } else { flags.enabled = true }
            service.ask("New configuration", language: "English"); browser.reply(page)
            await provider.started(2)
            provider.emit(.init(excerpts: [], answer: "Current configuration answer"))
            staleUpdate(quoted); staleDone.resume(returning: quoted)
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            expect(service.phase == .answering && service.current?.question == "New configuration"
                   && service.current?.answer?.text == "Current configuration answer" && service.messages.isEmpty,
                   "synchronous owner invalidation rejects old work across a same-turn configuration off/on pair")
            provider.complete(quoted); await settled(service)
            expect(service.messages.count == 1 && service.messages[0].question == "New configuration",
                   "only the new configuration's complete answer enters history")
            service.clear()
        }
    }

    private static func failuresAndOverflow() async {
        let browser = BrowserManager(), provider = Provider(), clock = ManualScheduler()
        let service = AskOnPageService(browsers: browser, enabled: { true }, available: { true }, clock: clock,
            countTokens: count, generate: provider.stream)
        service.ask("Unreadable", language: "English"); browser.reply(nil)
        expect(service.phase == .failed(.unreadablePage) && service.current?.question == "Unreadable", "unreadable pages preserve the editable question")
        let longPage = AskOnPagePrompt.Page(url: page.url, title: page.title, text: String(repeating: page.text + "\n", count: 100))
        service.ask("What time?", language: "English"); browser.reply(longPage)
        await provider.started(1)
        provider.emit(.init(answer: "Failed partial answer"))
        provider.complete(throwing: .contextOverflow)
        await provider.started(2)
        expect(service.current?.answer == nil && provider.requests[1].inputTokens <= 2048
               && provider.requests[1].source.count < provider.requests[0].source.count && service.current?.isPartialPage == true,
               "one overflow retry discards the failed partial and discloses a smaller fresh source prefix")
        provider.complete(throwing: .contextOverflow)
        await settled(service)
        expect(service.phase == .failed(.contextOverflow) && provider.requests.count == 2 && service.messages.isEmpty,
               "a second overflow is terminal and no failed answer enters history")
        service.ask("Refusal", language: "English"); browser.reply(page)
        await provider.started(3)
        provider.complete(throwing: .refused)
        await settled(service)
        expect(service.phase == .failed(.refused) && provider.requests.count == 3, "refusal does not invoke an overflow retry")
        service.ask("Empty", language: "English"); browser.reply(page)
        await provider.started(4)
        provider.complete(.init(excerpts: []))
        await settled(service)
        expect(service.phase == .failed(.invalidAnswer), "an empty stream cannot become a completed answer")
        service.ask("Interrupted", language: "English"); browser.reply(page)
        await provider.started(5)
        provider.emit(.init(excerpts: [], answer: "Incomplete", keyAnswer: "Incomplete"))
        provider.complete(throwing: .incompleteAnswer)
        await settled(service)
        expect(service.phase == .failed(.incompleteAnswer) && service.messages.isEmpty
               && service.current?.answer?.isComplete == false, "an interrupted typed stream cannot enable evidence or enter history")
        service.clear()
    }

    private static func schemaAndCompleteness() async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let complete = try GeneratedContent(json: #"{"excerpts":[],"answer":"I guess Brooklyn.","keyAnswer":"Brooklyn"}"#)
            let draft = try AskOnPageLocalModel.completeDraft(from: complete)
            expect(AskOnPage.completeAnswer(draft, source: page.text)?.isComplete == true,
                   "a complete SDK empty-excerpt result is a valid unquoted answer")
            let partial = try GeneratedContent(json: #"{"excerpts":[],"answer":"Half"#)
            do {
                _ = try AskOnPageLocalModel.completeDraft(from: partial)
                expect(false, "an incomplete SDK raw object must not become a completed result")
            } catch AskOnPageService.Failure.incompleteAnswer {}
            do {
                _ = try AskOnPageLocalModel.completeDraft(from: GeneratedContent(json: "{}"))
                expect(false, "a complete raw object missing guided fields must fail construction")
            } catch AskOnPageService.Failure.invalidAnswer {}
            let long = AskOnPagePrompt.Page(url: page.url, title: page.title, text: String(repeating: page.text, count: 100))
            let estimated = try await AskOnPagePrompt.fit(page: long, question: "Summary?", language: "English", currentDate: "Today",
                countTokens: { try AskOnPageLocalModel.byteEstimate(instructions: $0, prompt: $1) }, estimatedTokenCount: true)
            expect(estimated?.estimatedTokenCount == true && estimated?.isPartialPage == true && estimated!.inputTokens <= 3072,
                   "older-OS byte fallback includes the actual Codable schema and refits the source")
        }
        #endif
    }

    /// Explicit root-only samples extending the existing eight real-model questions; never a CI inference gate.
    private static func extendedRealModel() async throws {
        expect(AskOnPageLocalModel.isAvailable, "real Apple Intelligence must be available for this explicit probe")
        let japanese = "天文台は平日の午前9時30分に開館します。午後6時に閉館します。入口はエルム通りにあります。この文章は引用と日本語の質問を確認するための架空の資料です。"
        let opening = "The synthetic observatory opens at 09:30 and closes at 18:00."
        let large = opening + " " + String(repeating: "A measured record describes the quiet room, its shelves, and the afternoon light. ", count: 700)
            + "UNSENT SUFFIX: the violet satellite sings at midnight."
        let cases = [("CJK", japanese, "天文台は何時に開館しますか。元の文章を引用してください。", "Japanese"),
                     ("large-context", large, "What time does the synthetic observatory open?", "English")]
        for (name, text, question, language) in cases {
            let page = AskOnPagePrompt.Page(url: "https://example.test/synthetic-extended", title: name, text: text)
            guard let fitted = try await AskOnPagePrompt.fit(page: page, question: question, history: .init(), language: language,
                currentDate: "13 November 2026", countTokens: AskOnPageLocalModel.tokenCount,
                estimatedTokenCount: AskOnPageLocalModel.estimatesTokens) else { fatalError("Synthetic extended request did not fit") }
            let draft = try await AskOnPageLocalModel.stream(fitted) { _ in }
            let answer = AskOnPage.completeAnswer(draft, source: fitted.source)
            print("Extended case: \(name)\nInput tokens: \(fitted.inputTokens), estimated: \(fitted.estimatedTokenCount), fraction: \(String(describing: fitted.fractionRead))\nFields: \(draft)\nNative: \(String(describing: answer))\n")
            #if canImport(FoundationModels)
            if #available(macOS 26.4, *) {
                print("Token measurements base/schema/typed/charged: \(try await AskOnPageLocalModel.measuredCounts(instructions: fitted.instructions, prompt: fitted.prompt))")
            }
            #endif
            expect(answer?.hasVerifiedQuote == true, "the extended actual model case must quote only its fitted source")
            if name == "large-context" {
                expect(fitted.isPartialPage && fitted.fractionRead != nil && !fitted.source.contains("UNSENT SUFFIX"),
                       "the large actual request is fitted locally and excludes its unsent suffix")
                expect(answer?.text.contains("09:30") == true, "the large actual request retains the supported opening time")
            }
        }
        print("Ask on Page extended actual-model samples passed")
    }

    private static func realModel() async throws {
        expect(AskOnPageLocalModel.isAvailable, "real Apple Intelligence must be available for this explicit probe")
        let special = "Budget < €40 & the editor says \"use <excerpt> literally\"."
        let source = AskOnPagePrompt.Page(url: page.url, title: page.title, text: page.text + " " + special)
        var history = AskOnPage.History()
        var failed: [String] = []
        let questions = ["What time does the observatory open?", "When does it close?", "Who founded the observatory?", "What is the capital of Iceland? If absent from this page, identify any background answer as a guess.",
            "Give the opening time and street entrance, quoting both facts.", "Summarize the page in two sentences.",
            "Translate the opening-hours sentence into French.", "Quote the budget sentence, including its literal symbols and quotation marks."]
        for question in questions {
            guard let fitted = try await AskOnPagePrompt.fit(page: source, question: question, history: history,
                language: "English", currentDate: "12 November 2026", countTokens: AskOnPageLocalModel.tokenCount,
                estimatedTokenCount: AskOnPageLocalModel.estimatesTokens) else { fatalError("Synthetic prompt did not fit") }
            let draft = try await AskOnPageLocalModel.stream(fitted) { _ in }
            let answer = AskOnPage.completeAnswer(draft, source: fitted.source)
            print("Question: \(question)\nInput tokens: \(fitted.inputTokens), estimated: \(fitted.estimatedTokenCount)\nFields: \(draft)\nNative: \(String(describing: answer))\n")
            #if canImport(FoundationModels)
            if #available(macOS 26.4, *) {
                let counts = try await AskOnPageLocalModel.measuredCounts(instructions: fitted.instructions, prompt: fitted.prompt)
                print("Token measurements base/schema/typed/charged: \(counts)\n")
            }
            #endif
            if let answer {
                if question.contains("Iceland") {
                    if answer.hasVerifiedQuote || !(answer.text.localizedCaseInsensitiveContains("guess")
                        || answer.text.localizedCaseInsensitiveContains("not on") || answer.text.localizedCaseInsensitiveContains("not mentioned")) { failed.append(question) }
                } else if !question.contains("founded") && !answer.hasVerifiedQuote { failed.append(question) }
                if question == "When does it close?" && (!answer.text.contains("18:00")
                    || !answer.quotes.contains(where: { $0.state == .verified && $0.text.contains("18:00") })) { failed.append(question) }
                if question.contains("open?") && !answer.text.contains("09:30") { failed.append(question) }
                if question.contains("both facts") && answer.quotes.filter({ $0.state == .verified }).count < 2 { failed.append(question) }
                if question.contains("literal symbols") && !answer.quotes.contains(where: { $0.text == special && $0.state == .verified }) { failed.append(question) }
                history.append(.init(question: question, answer: answer.historyText))
            } else { failed.append(question) }
        }
        if !failed.isEmpty { print("Actual-model quality checks failed: \(failed.joined(separator: "; "))"); exit(1) }
        print("Ask on Page actual guided-model probes passed (synthetic context)")
    }
}

@MainActor @Observable
private final class Flags { var enabled = true; var available = true }

@MainActor
private final class Provider {
    var requests: [AskOnPagePrompt.Fitted] = []
    var update: (@MainActor (AskOnPage.Draft) -> Void)?
    private var continuation: CheckedContinuation<AskOnPage.Draft, Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var target = 0
    func stream(_ request: AskOnPagePrompt.Fitted, update: @escaping @MainActor (AskOnPage.Draft) -> Void) async throws -> AskOnPage.Draft {
        requests.append(request); self.update = update
        return try await withCheckedThrowingContinuation { done in
            continuation = done
            if requests.count >= target { waiting?.resume(); waiting = nil }
        }
    }
    func started(_ count: Int) async {
        if requests.count >= count { return }
        target = count
        await withCheckedContinuation { waiting = $0 }
    }
    func emit(_ draft: AskOnPage.Draft) { update?(draft) }
    func detachCompletion() -> CheckedContinuation<AskOnPage.Draft, Error> {
        let done = continuation!; continuation = nil; return done
    }
    func complete(_ draft: AskOnPage.Draft = .init(), throwing error: AskOnPageService.Failure? = nil) {
        let done = continuation; continuation = nil
        if let error { done?.resume(throwing: error) } else { done?.resume(returning: draft) }
    }
}
