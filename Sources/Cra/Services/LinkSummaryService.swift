import AppKit
import CraCEF
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
    private var images: [String: NSImage] = [:]
    private var imageOrder: [String] = []
    private var titles: [String: String] = [:]

    /// Banner pictures come over a session that keeps nothing on disk and sends no cookies.
    private let imageSession = URLSession(configuration: .ephemeral)

    private init() {}

    var isAvailable: Bool { TidyTabsService.fakeModel || TidyTabsService.shared.modelAvailable }

    /// A card made before, finished.
    func cached(_ link: URL) -> Card? {
        guard let known = cards.lookup(link.absoluteString) else { return nil }
        let host = LinkSummaryPrompt.displayHost(link)
        return Card(title: known?.title ?? host, host: host, image: images[link.absoluteString], result: known, finished: true)
    }

    /// Fetches the page, then streams the model's answer into `update`. `update` first fires once
    /// the page has arrived (title and banner, no rows yet): that is when the card opens. Nothing
    /// fires when the page doesn't load. Cancelling the task stops the model.
    func load(link: URL, profilePath: String?, httpsOnly: Bool, searchQuery: String?, update: @escaping (Card) -> Void) async {
        guard isAvailable else { return }
        let started = Date()
        let fetchURL = LinkSummaryPolicy.fetchURL(for: link, httpsOnly: httpsOnly)
        guard let html = await Self.fetch(fetchURL, profilePath: profilePath), !Task.isCancelled else {
            CraLog.note("5-Second Previews: no page (\(Task.isCancelled ? "cancelled" : "didn't load"))")
            return
        }
        let content = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: html) }.value
        let host = LinkSummaryPrompt.displayHost(link)
        // One card that the picture and the streamed answer both fill in.
        final class Box { var card: Card; init(_ c: Card) { card = c } }
        let box = Box(Card(title: content.title ?? host, host: host))
        update(box.card)

        if let imageURL = content.imageURL(page: fetchURL).map({ LinkSummaryPolicy.fetchURL(for: $0, httpsOnly: httpsOnly) }) {
            Task { @MainActor in
                guard let image = await self.image(imageURL), !Task.isCancelled else { return }
                self.remember(image, for: link.absoluteString)
                box.card.image = image
                update(box.card)
            }
        }

        let final = await Self.ask(url: fetchURL, content: content, searchQuery: searchQuery) { answer in
            guard let partial = LinkSummaryPrompt.result(url: link, title: content.title, answer: answer) else { return }
            box.card.result = partial
            update(box.card)
        }
        guard !Task.isCancelled else { return }
        box.card.result = final.flatMap { LinkSummaryPrompt.result(url: link, title: content.title, answer: $0) }
        box.card.finished = true
        cards.store(box.card.result, for: link.absoluteString)
        update(box.card)
        // Counts and time only: the links people hover stay out of the log (it goes into diagnostics).
        CraLog.note(String(format: "5-Second Previews: %@ in %.1f s", box.card.result.map { "\($0.details.count) details" } ?? "no preview",
                           Date().timeIntervalSince(started)))
    }

    /// The small card's title: the page's <title>, nil when the page didn't load.
    func title(link: URL, profilePath: String?, httpsOnly: Bool) async -> String? {
        if let known = titles[link.absoluteString] { return known }
        guard let html = await Self.fetch(LinkSummaryPolicy.fetchURL(for: link, httpsOnly: httpsOnly), profilePath: profilePath) else { return nil }
        let title = await Task.detached(priority: .userInitiated) { LinkSummaryContent.extractText(from: html).title }.value
        if let title {
            if titles.count >= 40 { titles.removeAll() }
            titles[link.absoluteString] = title
        }
        return title
    }

    /// The page's HTML, or nil when it isn't an HTML page that loaded.
    private static func fetch(_ url: URL, profilePath: String?) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            CraCEFRuntime.fetchURL(url.absoluteString, headers: ["Accept": "text/html,application/xhtml+xml"], profilePath: profilePath) {
                status, _, mime, body in
                let html = (200..<300).contains(status) && (mime.isEmpty || mime.contains("html")) && !body.isEmpty
                c.resume(returning: html ? body : nil)
            }
        }
    }

    /// The banner: a picture of at most 4 MB.
    private func image(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await imageSession.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 4_000_000, let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return image
    }

    private func remember(_ image: NSImage, for key: String) {
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
    private static func ask(url: URL, content: LinkSummaryContent.Extracted, searchQuery: String?,
                            partial: (LinkSummaryPrompt.Answer) -> Void) async -> LinkSummaryPrompt.Answer? {
        if TidyTabsService.fakeModel {
            let answer = LinkSummaryPrompt.fakeAnswer(content: content)
            try? await Task.sleep(for: .seconds(0.6))
            partial(LinkSummaryPrompt.Answer(blocked: answer.blocked, quickSummary: answer.quickSummary, details: Array(answer.details.prefix(1))))
            try? await Task.sleep(for: .seconds(0.6))
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
