import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 5-Second Previews on the Mac's own Apple Intelligence model (FoundationModels, macOS 26): the
/// page behind a link, fetched only once its card is asked for, summarized into Arc's answer card.
/// Chromium fetches the page in the tab's own profile, as a click would load it. The text and the
/// answer stay on the Mac.
@MainActor
final class LinkSummaryService {
    static let shared = LinkSummaryService()

    /// What a card shows, as it fills in.
    struct Card {
        var title: String
        var host: String
        var image: NSImage?
        /// Nil while the model is still answering, and for a page with no preview.
        var result: LinkSummaryResult?
        var finished = false
    }

    private var cards = LinkSummaryCache()
    private var images: [LinkSummaryRequest: NSImage] = [:]
    private var imageOrder: [LinkSummaryRequest] = []
    private var titles: [LinkSummaryRequest: String] = [:]

    private let fetchPage: (LinkSummaryRequest) async -> LinkSummaryFetch.Page?
    private let fetchImage: (URL, Bool) async -> NSImage?
    private let summarize: (URL, LinkSummaryContent.Extracted, String?, String, @escaping (LinkSummaryPrompt.Answer?) -> Void) async -> LinkSummaryPrompt.Answer?

    /// Concrete fetch/model boundaries also let the production lifecycle run on controlled input.
    init(fetch: ((LinkSummaryRequest) async -> LinkSummaryFetch.Page?)? = nil,
         image: ((URL) async -> NSImage?)? = nil,
         answer: ((URL, LinkSummaryContent.Extracted, String?, String, @escaping (LinkSummaryPrompt.Answer?) -> Void) async -> LinkSummaryPrompt.Answer?)? = nil) {
        let transport = LinkSummaryFetch()
        self.fetchPage = fetch ?? { request in await transport.load(request) }
        if let image { self.fetchImage = { url, _ in await image(url) } } else { self.fetchImage = Self.image }
        self.summarize = answer ?? { await Self.ask(url: $0, content: $1, searchQuery: $2, language: $3, partial: $4) }
    }

    var isAvailable: Bool { TidyTabsService.fakeModel || TidyTabsService.shared.currentModelAvailable }

    /// Capture the output language once, so cache lookup and generation cannot disagree.
    static func request(link: URL, profilePath: String?, httpsOnly: Bool, searchQuery: String?) -> LinkSummaryRequest {
        LinkSummaryRequest(link: link, profilePath: profilePath, httpsOnly: httpsOnly,
                           searchQuery: searchQuery, language: language)
    }

    /// A card made before in this exact fetch/model context, finished.
    func cached(_ request: LinkSummaryRequest) -> Card? {
        guard let known = cards.lookup(request) else { return nil }
        return Card(title: known.title, host: known.host, image: images[request], result: known, finished: true)
    }

    /// Streams a current card, including a terminal empty card on failure. The image task is
    /// owned until it finishes and is cancelled with its parent; completion need not wait for it.
    func load(_ request: LinkSummaryRequest, update: @escaping (Card) -> Void) async {
        guard !Task.isCancelled else { return }
        let started = Date()
        let link = request.link
        let host = LinkSummaryPrompt.displayHost(link)
        guard isAvailable, let page = await fetchPage(request) else {
            if !Task.isCancelled { update(Card(title: host, host: host, finished: true)) }
            return
        }
        guard !Task.isCancelled, isAvailable else {
            if !Task.isCancelled { update(Card(title: host, host: host, finished: true)) }
            return
        }
        let content = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: page.html) }.value
        guard !Task.isCancelled, isAvailable else {
            if !Task.isCancelled { update(Card(title: host, host: host, finished: true)) }
            return
        }
        final class Box { var card: Card; init(_ c: Card) { card = c } }
        let box = Box(Card(title: content.title ?? host, host: host))
        update(box.card)

        let imageURL = content.imageURL(page: page.url).map { LinkSummaryPolicy.fetchURL(for: $0, httpsOnly: request.httpsOnly) }
        let imageTask: Task<Void, Never>? = imageURL.map { url in
            Task { @MainActor in
                guard !Task.isCancelled, self.isAvailable, let image = await self.fetchImage(url, request.httpsOnly), !Task.isCancelled, self.isAvailable,
                      !box.card.finished || box.card.result != nil else { return }
                box.card.image = image
                if box.card.finished { self.remember(image, for: request) }
                update(box.card)
            }
        }
        await withTaskCancellationHandler {
            defer { imageTask?.cancel() }
            let final = await summarize(page.url, content, request.searchQuery, request.language) { answer in
                guard !Task.isCancelled, !box.card.finished, self.isAvailable else { return }
                if let answer {
                    guard let result = LinkSummaryPrompt.result(url: link, title: content.title, answer: answer) else { return }
                    box.card.result = result
                } else {
                    // A fresh overflow attempt cannot retain the preceding attempt's rows.
                    box.card.result = nil
                }
                update(box.card)
            }
            guard !Task.isCancelled else { return }
            box.card.result = isAvailable ? final.flatMap { LinkSummaryPrompt.result(url: link, title: content.title, answer: $0, final: true) } : nil
            box.card.finished = true
            if box.card.result == nil { box.card.image = nil }
            cards.store(box.card.result, for: request)
            if box.card.result != nil, let image = box.card.image { remember(image, for: request) }
            update(box.card)
            // Counts and time only; hovered links remain outside diagnostics.
            CraLog.note(String(format: "5-Second Previews: %@ in %.1f s", box.card.result.map { "\($0.details.count) details" } ?? "no preview",
                               Date().timeIntervalSince(started)))
            // Publish the completed summary now; keep the optional image owned until it arrives.
            if box.card.result != nil { await imageTask?.value }
        } onCancel: {
            imageTask?.cancel()
        }
    }

    /// The small card's title: the page's <title>, nil when the page didn't load.
    func title(_ request: LinkSummaryRequest) async -> String? {
        guard !Task.isCancelled, isAvailable else { return nil }
        if let known = titles[request] { return known }
        guard let page = await fetchPage(request), !Task.isCancelled, isAvailable else { return nil }
        let title = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: page.html).title }.value
        guard !Task.isCancelled, isAvailable else { return nil }
        if let title {
            if titles.count >= 40 { titles.removeAll() }
            titles[request] = title
        }
        return title
    }

    /// Image failure leaves the summary usable; the parent retains ownership until completion.
    private static func image(_ url: URL, httpsOnly: Bool) async -> NSImage? {
        guard let data = await LinkSummaryImageFetch().load(url, httpsOnly: httpsOnly),
              let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return image
    }

    private func remember(_ image: NSImage, for key: LinkSummaryRequest) {
        if images.updateValue(image, forKey: key) != nil { imageOrder.removeAll { $0 == key } }
        imageOrder.append(key)
        while imageOrder.count > 20 { images.removeValue(forKey: imageOrder.removeFirst()) }
    }

    /// The user's language by name, as Arc writes it into the prompt.
    private static var language: String {
        LinkSummaryPrompt.responseLanguage(preferredLanguages: Locale.preferredLanguages)
    }

    /// One phase deadline covers fitting, preflight and both possible attempts (Cra, not Arc timing).
    static let modelTimeout: TimeInterval = 18
    typealias ModelResponse = (LinkSummaryPrompt.Input, @escaping (LinkSummaryPrompt.Answer?) -> Void) async throws -> LinkSummaryPrompt.Answer?

    /// A concrete generation owns only its deadline, task and single terminal continuation.
    @MainActor private final class ModelWork {
        var ended = false
        // onCancel may run outside MainActor; block callback admission before queued cleanup.
        nonisolated private let cancellationLock = NSLock()
        nonisolated(unsafe) private var cancelled = false
        nonisolated var isCancelled: Bool {
            cancellationLock.lock()
            defer { cancellationLock.unlock() }
            return cancelled
        }
        nonisolated func cancel() {
            cancellationLock.lock()
            cancelled = true
            cancellationLock.unlock()
            Task { @MainActor in self.finish(nil) }
        }
        var task: Task<Void, Never>?
        var deadline: ScheduledWork?
        var continuation: CheckedContinuation<LinkSummaryPrompt.Answer?, Never>?

        func finish(_ result: LinkSummaryPrompt.Answer?) {
            guard !ended else { return }
            ended = true
            deadline?.cancel()
            deadline = nil
            task?.cancel()
            task = nil
            let continuation = continuation
            self.continuation = nil
            continuation?.resume(returning: isCancelled ? nil : result)
        }
    }

    /// Only the SDK's typed context overflow earns a fresh, smaller second attempt.
    static func ask(url: URL, content: LinkSummaryContent.Extracted, searchQuery: String?, language: String,
                    partial: @escaping (LinkSummaryPrompt.Answer?) -> Void,
                    respond: @escaping ModelResponse = { try await LinkSummaryService.respond($0, partial: $1) },
                    clock: Scheduler? = nil) async -> LinkSummaryPrompt.Answer? {
        guard !Task.isCancelled else { return nil }
        let work = ModelWork()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                work.continuation = continuation
                guard !Task.isCancelled else { work.finish(nil); return }
                work.deadline = (clock ?? LiveScheduler.shared).after(modelTimeout) { work.finish(nil) }
                let inputs = [false, true].map {
                    LinkSummaryPrompt.fitted(url: url.absoluteString, content: content, searchQuery: searchQuery, language: language, compact: $0)
                }
                work.task = Task { @MainActor in
                    for attempt in inputs.indices {
                        var accepting = true
                        defer { accepting = false }
                        do {
                            try Task.checkCancellation()
                            guard !work.ended, !work.isCancelled else { return }
                            let answer = try await respond(inputs[attempt]) { answer in
                                guard accepting, !work.ended, !work.isCancelled, !Task.isCancelled else { return }
                                partial(answer)
                            }
                            try Task.checkCancellation()
                            work.finish(answer)
                            return
                        } catch {
                            guard !work.ended, !work.isCancelled, !Task.isCancelled else { work.finish(nil); return }
                            if attempt == 0, isContextOverflow(error) {
                                partial(nil)
                                continue
                            }
                            CraLog.note("5-Second Previews: model generation failed")
                            work.finish(nil)
                            return
                        }
                    }
                }
            }
        } onCancel: {
            work.cancel()
        }
    }

    private static func isContextOverflow(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error { return true }
        #endif
        return false
    }

    private static func respond(_ input: LinkSummaryPrompt.Input, partial: @escaping (LinkSummaryPrompt.Answer?) -> Void) async throws -> LinkSummaryPrompt.Answer? {
        if TidyTabsService.fakeModel {
            let answer = LinkSummaryPrompt.fakeAnswer(content: input.content)
            try await Task.sleep(for: .seconds(0.6))
            try Task.checkCancellation()
            partial(LinkSummaryPrompt.Answer(blocked: answer.blocked, userQuestion: answer.userQuestion, quickSummary: answer.quickSummary, details: Array(answer.details.prefix(1))))
            try await Task.sleep(for: .seconds(0.6))
            try Task.checkCancellation()
            return answer
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return try await LinkSummaryModel.respond(input, partial: partial) }
        #endif
        throw CocoaError(.featureUnsupported)
    }

}

#if canImport(FoundationModels)
/// A fresh SDK session per attempt. The injectable count/stream boundaries use this same adapter.
@MainActor @available(macOS 26.0, *)
enum LinkSummaryModel {
    enum TokenInput {
        case instructions(String)
        case prompt(String)
        case schema(GenerationSchema)
        case transcript([Transcript.Entry])
    }
    typealias Counter = (TokenInput) async throws -> Int
    typealias Stream = (LanguageModelSession, String, Int, @escaping (LinkSummaryPrompt.Answer?) -> Void) async throws -> LinkSummaryPrompt.Answer?

    static func respond(_ input: LinkSummaryPrompt.Input, partial: @escaping (LinkSummaryPrompt.Answer?) -> Void,
                        count: Counter? = nil, contextSize: Int? = nil, stream: Stream? = nil) async throws -> LinkSummaryPrompt.Answer? {
        try Task.checkCancellation()
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(model: model, instructions: LinkSummaryPrompt.instructions)
        let prompt = input.prompt
        let size = contextSize ?? model.contextSize
        if #available(macOS 26.4, *) {
            // The fresh transcript already contains instructions. Count those through Instructions
            // once, then any actual non-instruction entries; never invent previous hover history.
            let history = session.transcript.filter { if case .instructions = $0 { return false }; return true }
            let count = count ?? tokenCount
            var tokens = 0
            for component in [TokenInput.instructions(LinkSummaryPrompt.instructions), .prompt(prompt),
                              .schema(HoverCardAnswer.generationSchema), .transcript(history)] {
                tokens += try await count(component)
                try Task.checkCancellation()
            }
            guard LinkSummaryPrompt.fitsContext(inputTokens: tokens, contextSize: size) else { throw overflow() }
        } else {
            // Earlier systems have no token API. This is an explicitly conservative byte estimate.
            guard LinkSummaryPrompt.fitsFallback(input, contextSize: size) else { throw overflow() }
        }
        try Task.checkCancellation()
        return try await (stream ?? generate)(session, prompt, LinkSummaryPrompt.responseTokenLimit, partial)
    }

    @available(macOS 26.4, *)
    private static func tokenCount(_ input: TokenInput) async throws -> Int {
        let model = SystemLanguageModel.default
        switch input {
        case .instructions(let instructions): return try await model.tokenCount(for: Instructions(instructions))
        case .prompt(let prompt): return try await model.tokenCount(for: prompt)
        case .schema(let schema): return try await model.tokenCount(for: schema)
        case .transcript(let entries): return try await model.tokenCount(for: entries)
        }
    }

    private static func overflow() -> LanguageModelSession.GenerationError {
        .exceededContextWindowSize(.init(debugDescription: "Preview input exceeds local context budget"))
    }

    private static func generate(session: LanguageModelSession, prompt: String, limit: Int,
                                 partial: @escaping (LinkSummaryPrompt.Answer?) -> Void) async throws -> LinkSummaryPrompt.Answer? {
        let stream = session.streamResponse(to: prompt, generating: HoverCardAnswer.self,
                                            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: limit))
        var last: LinkSummaryPrompt.Answer?
        for try await snapshot in stream {
            try Task.checkCancellation()
            let answer = LinkSummaryPrompt.Answer(snapshot.content)
            last = answer
            partial(answer)
        }
        return last
    }
}

/// Arc's ordered fields, with one static optional focus instead of a query-specific schema.
/// Queryless requests ask for nil focus; it guides later fields and is never displayed.
@available(macOS 26.0, *)
@Generable
struct HoverCardAnswer {
    @Guide(description: "Does this page ask the user to enable Javascript or complete a security check before accessing the content?")
    var blocked: Bool
    @Guide(description: "1-word question to focus the rest of the answer card upon; based on the User search query in the request. Leave nil when no search query is supplied.")
    var userQuestion: String?
    @Guide(description: "3-8 words the user is most likely to want to know, beyond the page's title. Provide a fact or opinion, not just a title.")
    var quickSummary: String?
    @Guide(description: "2-4 key points, solutions or items.", .count(2...4))
    var details: [HoverCardDetail]
}

@available(macOS 26.0, *)
@Generable
struct HoverCardDetail {
    @Guide(description: "e.g. \"Price:\", \"Story:\", \"Solution 1:\", \"Highlights:\", \"Criticism:\"")
    var label: String
    @Guide(description: "Relevant SF Symbol systemName, e.g. \"fork.knife\"")
    var icon: String
    @Guide(description: "5-10 word summary, extremely concise")
    var info: String
}

@available(macOS 26.0, *)
extension LinkSummaryPrompt.Answer {
    /// A streamed answer so far: fields not yet written are empty.
    init(_ p: HoverCardAnswer.PartiallyGenerated) {
        self.init(blocked: p.blocked ?? false, userQuestion: p.userQuestion, quickSummary: p.quickSummary,
                  details: (p.details ?? []).map { .init(label: $0.label ?? "", icon: $0.icon ?? "", info: $0.info ?? "") })
    }
}
#endif
