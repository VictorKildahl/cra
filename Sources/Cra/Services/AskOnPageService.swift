import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One window's transient conversation. The controller calls refresh when its focused page changes.
/// The owner must call clear synchronously on disable/unavailable transitions, before re-enabling:
/// level-triggered Observation can coalesce a same-turn off/on pair and cannot preserve that edge.
@MainActor @Observable
final class AskOnPageService {
    enum Failure: Error, Equatable {
        case unreadablePage, inputTooLong, unavailable, contextOverflow, refused, generationFailed, incompleteAnswer, invalidAnswer, timedOut
    }
    enum Phase: Equatable { case idle, reading, answering, failed(Failure) }
    struct Message: Identifiable {
        let id: UUID
        let question: String
        var answer: AskOnPage.Answer?
        var source = ""
        var isPartialPage = false
        var fractionRead: Double?
        var olderMessagesHidden = false
    }
    typealias Generate = @MainActor (AskOnPagePrompt.Fitted, @escaping @MainActor (AskOnPage.Draft) -> Void) async throws -> AskOnPage.Draft
    static let requestTimeout: TimeInterval = 90

    private(set) var phase: Phase = .idle
    private(set) var messages: [Message] = []
    private(set) var current: Message?
    private(set) var olderMessagesHidden = false
    var isLoading: Bool { phase == .reading || phase == .answering }
    var failureText: String? {
        guard case .failed(let failure) = phase else { return nil }
        switch failure {
        case .unreadablePage: return AskOnPagePrompt.unreadable
        case .inputTooLong: return "This question is too long. Try a shorter question."
        case .unavailable: return "Apple Intelligence isn’t available right now."
        case .timedOut: return "Sorry, the answer took too long. Try again."
        default: return AskOnPagePrompt.failed
        }
    }

    @ObservationIgnored private let browsers: BrowserManager
    @ObservationIgnored private let enabled: @MainActor () -> Bool
    @ObservationIgnored private let available: @MainActor () -> Bool
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private let countTokens: AskOnPagePrompt.TokenCount
    @ObservationIgnored private let estimatedTokenCount: Bool
    @ObservationIgnored private let clock: Scheduler
    @ObservationIgnored private var context: AskOnPageContext?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: ScheduledWork?

    init(browsers: BrowserManager, enabled: @escaping @MainActor () -> Bool,
         available: @escaping @MainActor () -> Bool = { TidyTabsService.shared.modelAvailable && AskOnPageLocalModel.isAvailable },
         clock: Scheduler? = nil, countTokens: AskOnPagePrompt.TokenCount? = nil, generate: Generate? = nil) {
        self.browsers = browsers; self.enabled = enabled; self.available = available
        self.clock = clock ?? LiveScheduler.shared
        self.countTokens = countTokens ?? AskOnPageLocalModel.tokenCount
        self.estimatedTokenCount = countTokens == nil && AskOnPageLocalModel.estimatesTokens
        self.generate = generate ?? AskOnPageLocalModel.stream
        // Backstop for sustained unusability; synchronous owner invalidation handles transient changes.
        observeChanges(of: { [weak self] in self.map { $0.enabled() && $0.available() } ?? false }) { [weak self] usable in
            if !usable { self?.clear() }
        }
    }

    deinit {
        task?.cancel()
        Task { @MainActor [deadline] in deadline?.cancel() }
    }

    /// Closing the panel/window clears page text and history and invalidates even a cancellation-ignoring provider.
    func clear() {
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        context = nil; current = nil; messages = []; olderMessagesHidden = false; phase = .idle
    }

    func refresh() {
        if !enabled() || !available() || context.map({ !browsers.isCurrentAskOnPage($0) }) == true { clear() }
    }

    @discardableResult
    func ask(_ question: String, language: String) -> Bool {
        refresh()
        guard enabled(), available(), !isLoading,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let pageContext = browsers.askOnPageContext() else { return false }
        context = pageContext
        let id = UUID()
        current = Message(id: id, question: question)
        phase = .reading
        deadline = clock.after(Self.requestTimeout) { [weak self] in self?.fail(.timedOut, id: id) }
        let date = clock.now.formatted(.dateTime.year().month(.wide).day())
        browsers.askOnPageSnapshot(pageContext) { [weak self] page in
            guard let self else { return }
            guard self.accepts(id) else { self.refresh(); return }
            guard let page else { self.fail(.unreadablePage, id: id); return }
            self.start(page: page, question: question, language: language, date: date, id: id)
        }
        return true
    }

    private func accepts(_ id: UUID) -> Bool {
        current?.id == id && isLoading && enabled() && available()
            && context.map { browsers.isCurrentAskOnPage($0) } == true
    }

    private func start(page: AskOnPagePrompt.Page, question: String, language: String, date: String, id: UUID) {
        let history = history
        let generate = generate, countTokens = countTokens, estimated = estimatedTokenCount
        task = Task { [weak self] in
            do {
                for attempt in 0...1 {
                    try Task.checkCancellation()
                    // Overflow retry has a smaller budget and a fresh provider session. Failed partial text is replaced.
                    guard let fitted = try await AskOnPagePrompt.fit(page: page, question: question, history: history,
                        language: language, currentDate: date, inputLimit: attempt == 0 ? 3072 : 2048, countTokens: countTokens, estimatedTokenCount: estimated) else {
                        self?.fail(.inputTooLong, id: id); return
                    }
                    guard self?.accepts(id) == true else { self?.refresh(); return }
                    self?.phase = .answering
                    self?.current?.answer = nil
                    self?.current?.source = fitted.source
                    self?.current?.isPartialPage = fitted.isPartialPage
                    self?.current?.fractionRead = fitted.fractionRead
                    self?.current?.olderMessagesHidden = fitted.olderMessagesHidden
                    do {
                        let final = try await generate(fitted) { [weak self] snapshot in
                            guard let self, self.accepts(id) else { return }
                            // A snapshot is the whole answer so far, never a delta.
                            self.current?.answer = AskOnPage.partialAnswer(snapshot)
                        }
                        guard let answer = AskOnPage.completeAnswer(final, source: fitted.source) else {
                            self?.fail(.invalidAnswer, id: id); return
                        }
                        guard self?.accepts(id) == true else { self?.refresh(); return }
                        self?.current?.answer = answer
                    } catch Failure.contextOverflow where attempt == 0 { continue }
                    try Task.checkCancellation()
                    self?.finish(id)
                    return
                }
            } catch is CancellationError {
                self?.fail(.generationFailed, id: id)
            } catch {
                self?.fail(error as? Failure ?? .generationFailed, id: id)
            }
        }
    }

    private func finish(_ id: UUID) {
        guard accepts(id), let message = current else { refresh(); return }
        guard message.answer?.isComplete == true else { fail(.incompleteAnswer, id: id); return }
        messages.append(message)
        let bounded = history
        messages.removeFirst(messages.count - bounded.turns.count)
        olderMessagesHidden = bounded.olderMessagesHidden
        deadline?.cancel(); deadline = nil; task = nil; current = nil; phase = .idle
    }

    private func fail(_ error: Failure, id: UUID) {
        guard current?.id == id, isLoading else { return }
        guard accepts(id) else { refresh(); return }
        task?.cancel(); task = nil; deadline?.cancel(); deadline = nil
        phase = .failed(error)
    }

    private var history: AskOnPage.History {
        var history = AskOnPage.History(olderMessagesHidden: olderMessagesHidden)
        for message in messages { history.append(.init(question: message.question, answer: message.answer?.historyText ?? "")) }
        return history
    }
}

/// The production on-device adapter: guided native fields, without a generated-markup parser.
@MainActor
enum AskOnPageLocalModel {
    static var isAvailable: Bool {
        if TidyTabsService.fakeModel { return true }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }
    static var estimatesTokens: Bool {
        if TidyTabsService.fakeModel { return true }
        if #available(macOS 26.4, *) { return false }
        return true
    }
    static var tokenCount: AskOnPagePrompt.TokenCount {
        { instructions, prompt in
            try Task.checkCancellation()
            // Deterministic UI fixture only: no tokenizer or on-device model is invoked.
            if TidyTabsService.fakeModel { return (instructions.utf8.count + prompt.utf8.count + 2) / 3 + 256 }
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if #available(macOS 26.4, *) {
                    let counts = try await measuredCounts(instructions: instructions, prompt: prompt)
                    return counts.total
                }
                return try byteEstimate(instructions: instructions, prompt: prompt)
            }
            #endif
            throw AskOnPageService.Failure.unavailable
        }
    }
    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static var options: GenerationOptions {
        GenerationOptions(sampling: .greedy, maximumResponseTokens: AskOnPagePrompt.maximumResponseTokens)
    }
    @available(macOS 26.0, *)
    static func byteEstimate(instructions: String, prompt: String) throws -> Int {
        let schema = try JSONEncoder().encode(AskOnPageGeneratedAnswer.generationSchema)
        return instructions.utf8.count + prompt.utf8.count + schema.count
    }
    @available(macOS 26.0, *)
    static func completeDraft(from raw: GeneratedContent?) throws -> AskOnPage.Draft {
        guard let raw, raw.isComplete else { throw AskOnPageService.Failure.incompleteAnswer }
        do {
            let final = try AskOnPageGeneratedAnswer(raw)
            return .init(excerpts: final.excerpts, answer: final.answer, keyAnswer: final.keyAnswer)
        } catch { throw AskOnPageService.Failure.invalidAnswer }
    }
    @available(macOS 26.4, *)
    static func measuredCounts(instructions: String, prompt: String) async throws -> (base: Int, schema: Int, typed: Int, total: Int) {
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(instructions: instructions)
        let segments: [Transcript.Segment] = [.text(.init(content: prompt))]
        let base = try await model.tokenCount(for: Array(session.transcript) + [.prompt(.init(segments: segments, options: options))])
        let schema = try await model.tokenCount(for: AskOnPageGeneratedAnswer.generationSchema)
        let typed = try await model.tokenCount(for: Array(session.transcript) + [.prompt(.init(segments: segments, options: options,
            responseFormat: .init(type: AskOnPageGeneratedAnswer.self)))])
        return (base, schema, typed, max(typed, base + schema))
    }
    #endif

    static func stream(_ fitted: AskOnPagePrompt.Fitted, update: @escaping @MainActor (AskOnPage.Draft) -> Void) async throws -> AskOnPage.Draft {
        guard isAvailable else { throw AskOnPageService.Failure.unavailable }
        if TidyTabsService.fakeModel {
            let draft = AskOnPage.fixtureDraft(question: fitted.question, source: fitted.source)
            update(.init(excerpts: draft.excerpts, answer: nil))
            await Task.yield()
            try Task.checkCancellation()
            update(draft)
            return draft
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: fitted.instructions)
                var last: GeneratedContent?
                for try await snapshot in session.streamResponse(to: fitted.prompt, generating: AskOnPageGeneratedAnswer.self, options: options) {
                    try Task.checkCancellation()
                    guard snapshot.rawContent.jsonString.utf8.count <= 300_000 else { throw AskOnPageService.Failure.invalidAnswer }
                    last = snapshot.rawContent
                    update(.init(excerpts: snapshot.content.excerpts, answer: snapshot.content.answer, keyAnswer: snapshot.content.keyAnswer))
                }
                return try completeDraft(from: last)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .exceededContextWindowSize: throw AskOnPageService.Failure.contextOverflow
                case .refusal, .guardrailViolation: throw AskOnPageService.Failure.refused
                case .assetsUnavailable: throw AskOnPageService.Failure.unavailable
                default: throw AskOnPageService.Failure.generationFailed
                }
            }
        }
        #endif
        throw AskOnPageService.Failure.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct AskOnPageGeneratedAnswer {
    // Apple guided generation follows declaration order; Arc likewise asks for source quotes before its short answer.
    @Guide(description: "First select only unchanged PAGE SOURCE sentences answering CURRENT QUESTION, including punctuation. Return [] if the source does not answer; never unrelated quotes or background facts.", .count(0...4))
    var excerpts: [String]
    @Guide(description: "Directly answer CURRENT QUESTION, not a previous question. Plain text in the requested language; allow summaries/translations. Identify background guesses.")
    var answer: String
    @Guide(description: "Optional bold hint copied exactly from answer, preserving accents, punctuation and case. Prefer a decisive number/name; nil if no suitable phrase.")
    var keyAnswer: String?
}
#endif
