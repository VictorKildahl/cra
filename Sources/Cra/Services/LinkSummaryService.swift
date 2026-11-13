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

    /// Banner pictures come over a session that keeps nothing on disk and sends no cookies.
    private static let imageSession = URLSession(configuration: .ephemeral)

    private let fetchPage: (LinkSummaryRequest) async -> LinkSummaryFetch.Page?
    private let fetchImage: (URL) async -> NSImage?
    private let summarize: (URL, LinkSummaryContent.Extracted, String?, String, @escaping (LinkSummaryPrompt.Answer) -> Void) async -> LinkSummaryPrompt.Answer?

    /// Concrete fetch/model boundaries also let the production lifecycle run on controlled input.
    init(fetch: ((LinkSummaryRequest) async -> LinkSummaryFetch.Page?)? = nil,
         image: ((URL) async -> NSImage?)? = nil,
         answer: ((URL, LinkSummaryContent.Extracted, String?, String, @escaping (LinkSummaryPrompt.Answer) -> Void) async -> LinkSummaryPrompt.Answer?)? = nil) {
        let transport = LinkSummaryFetch()
        self.fetchPage = fetch ?? { request in await transport.load(request) }
        self.fetchImage = image ?? Self.image
        self.summarize = answer ?? Self.ask
    }

    var isAvailable: Bool { TidyTabsService.fakeModel || TidyTabsService.shared.modelAvailable }

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
        guard !Task.isCancelled else { return }
        let content = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: page.html) }.value
        guard !Task.isCancelled else { return }
        final class Box { var card: Card; init(_ c: Card) { card = c } }
        let box = Box(Card(title: content.title ?? host, host: host))
        update(box.card)

        let imageURL = content.imageURL(page: page.url).map { LinkSummaryPolicy.fetchURL(for: $0, httpsOnly: request.httpsOnly) }
        let imageTask: Task<Void, Never>? = imageURL.map { url in
            Task { @MainActor in
                guard !Task.isCancelled, let image = await self.fetchImage(url), !Task.isCancelled,
                      !box.card.finished || box.card.result != nil else { return }
                box.card.image = image
                if box.card.finished { self.remember(image, for: request) }
                update(box.card)
            }
        }
        await withTaskCancellationHandler {
            defer { imageTask?.cancel() }
            let final = await summarize(page.url, content, request.searchQuery, request.language) { answer in
                guard !Task.isCancelled, !box.card.finished, let partial = LinkSummaryPrompt.result(url: link, title: content.title, answer: answer) else { return }
                box.card.result = partial
                update(box.card)
            }
            guard !Task.isCancelled else { return }
            box.card.result = final.flatMap { LinkSummaryPrompt.result(url: link, title: content.title, answer: $0) }
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
        guard let page = await fetchPage(request), !Task.isCancelled else { return nil }
        let title = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: page.html).title }.value
        guard !Task.isCancelled else { return nil }
        if let title {
            if titles.count >= 40 { titles.removeAll() }
            titles[request] = title
        }
        return title
    }

    /// The banner: a picture of at most 4 MB.
    private static func image(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await imageSession.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 4_000_000, let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return image
    }

    private func remember(_ image: NSImage, for key: LinkSummaryRequest) {
        if images.updateValue(image, forKey: key) != nil { imageOrder.removeAll { $0 == key } }
        imageOrder.append(key)
        while imageOrder.count > 20 { images.removeValue(forKey: imageOrder.removeFirst()) }
    }

    /// The user's language by name, as Arc writes it into the prompt.
    private static var language: String {
        let code = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    /// The model's answer; `partial` gets it as it streams. Nil when the model failed.
    private static func ask(url: URL, content: LinkSummaryContent.Extracted, searchQuery: String?, language: String,
                            partial: @escaping (LinkSummaryPrompt.Answer) -> Void) async -> LinkSummaryPrompt.Answer? {
        if TidyTabsService.fakeModel {
            let answer = LinkSummaryPrompt.fakeAnswer(content: content)
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return nil }
            partial(LinkSummaryPrompt.Answer(blocked: answer.blocked, quickSummary: answer.quickSummary, details: Array(answer.details.prefix(1))))
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return nil }
            return answer
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let prompt = LinkSummaryPrompt.prompt(url: url.absoluteString, content: content, searchQuery: searchQuery, language: language)
            do {
                let session = LanguageModelSession(instructions: LinkSummaryPrompt.instructions)
                let stream = session.streamResponse(to: prompt, generating: HoverCardAnswer.self, options: GenerationOptions(sampling: .greedy))
                var last: LinkSummaryPrompt.Answer?
                for try await snapshot in stream {
                    if Task.isCancelled { return nil }
                    let answer = LinkSummaryPrompt.Answer(snapshot.content)
                    last = answer
                    partial(answer)
                }
                return last
            } catch {
                // A refusal, or a page too long for the context: the card says there's no preview.
                CraLog.note("5-Second Previews: the model failed: \(error)")
                return nil
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
/// Arc's `Response` schema (HoverCardViewModel), field for field.
@available(macOS 26.0, *)
@Generable
struct HoverCardAnswer {
    @Guide(description: "Does this page ask the user to enable Javascript or complete a security check before accessing the content?")
    var blocked: Bool
    @Guide(description: "3-8 words the user is most likely to want to know, beyond the page's title. Provide a fact or opinion, not just a title.")
    var quickSummary: String
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
        self.init(blocked: p.blocked ?? false, quickSummary: p.quickSummary ?? "",
                  details: (p.details ?? []).map { .init(label: $0.label ?? "", icon: $0.icon ?? "", info: $0.info ?? "") })
    }
}
#endif
