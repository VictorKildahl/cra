import CraCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Browse for Me" reads the web and writes the answer page. In Cra it runs on the device's own
/// Apple Intelligence model or not at all: the search and the pages are fetched by the phone, and
/// nothing typed or read is sent to an AI service. `MobileBrowseForMe` has the rules.
enum BrowseForMe {
    /// Whether this device can answer: Apple Intelligence present and switched on.
    static var isAvailable: Bool {
        if LaunchOptions.fakeModel { return true }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    enum Step {
        /// The sites being read, in order.
        case reading([String])
        case making
        /// The finished page and its title.
        case done(html: String, title: String)
        /// No results, no network, or no answer: the caller falls back to the search engine.
        case failed
    }

    private static var language: String { AnswerLanguage.englishName }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": Locale.preferredLanguages.prefix(2).joined(separator: ", "),
        ]
        return URLSession(configuration: configuration)
    }()

    private static func html(at url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        let clipped = data.prefix(LinkSummaryContent.maxHTMLLength)
        return String(data: clipped, encoding: .utf8) ?? String(decoding: clipped, as: UTF8.self)
    }

    /// Runs the whole thing for `query`, reporting each step on the main actor.
    @MainActor
    static func run(query: String, engine: MobileSearch, progress: @escaping (Step) -> Void) async {
        let hits: [MobileBrowseForMe.Hit]
        if LaunchOptions.fakeModel {
            // Tests get three made-up results and no network.
            hits = ["alpha", "beta", "gamma"].map { .init(title: "\($0.capitalized) on \(query)", url: "https://\($0).example/page", snippet: "What \($0) says about \(query).") }
        } else {
            guard let url = MobileBrowseForMe.searchURL(query), let results = await html(at: url) else { return progress(.failed) }
            hits = MobileBrowseForMe.pick(MobileBrowseForMe.hits(fromResultsHTML: results))
        }
        guard !hits.isEmpty else { return progress(.failed) }
        progress(.reading(hits.map(\.host)))

        var sources: [MobileBrowseForMe.Source]
        if LaunchOptions.fakeModel {
            // Long enough for a test to see the loading screen.
            try? await Task.sleep(for: .seconds(4))
            sources = hits.map { .init(hit: $0, title: $0.title, text: $0.snippet) }
        } else {
            sources = await withTaskGroup(of: (Int, MobileBrowseForMe.Source).self) { group in
                for (index, hit) in hits.enumerated() {
                    group.addTask {
                        guard let url = URL(string: hit.url), let page = await html(at: url) else {
                            return (index, .init(hit: hit, title: hit.title, text: hit.snippet))
                        }
                        let read = LinkSummaryContent.extractText(from: page)
                        let text = read.bodyText.isEmpty ? (read.description ?? hit.snippet) : read.bodyText
                        return (index, .init(hit: hit, title: read.title ?? hit.title, text: text, image: read.image))
                    }
                }
                var found: [(Int, MobileBrowseForMe.Source)] = []
                for await source in group { found.append(source) }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
        progress(.making)
        guard let answer = await answer(query: query, sources: sources) else { return progress(.failed) }
        let page = MobileBrowseForMe.pageHTML(query: query, answer: answer, sources: sources, searchURL: engine.searchURL(query))
        progress(.done(html: page, title: answer.title.isEmpty ? query : answer.title))
    }

    private static func answer(query: String, sources: [MobileBrowseForMe.Source]) async -> MobileBrowseForMe.Answer? {
        if LaunchOptions.fakeModel {
            try? await Task.sleep(for: .seconds(0.6))
            return MobileBrowseForMe.fakeAnswer(query: query, sources: sources).cleaned
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: MobileBrowseForMe.instructions)
                let prompt = MobileBrowseForMe.prompt(query: query, sources: sources, language: language)
                let response = try await session.respond(to: prompt, generating: GeneratedAnswer.self, options: GenerationOptions(sampling: .greedy))
                let made = response.content
                return MobileBrowseForMe.Answer(title: made.title,
                                                points: made.points.map { .init(emoji: $0.emoji, term: $0.term, text: $0.text) },
                                                sections: made.sections.map { .init(heading: $0.heading, text: $0.text) },
                                                followUps: made.followUps).cleaned
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedAnswer {
    @Guide(description: "A short title for the answer, three to seven words.")
    var title: String
    @Guide(description: "The key points.", .count(3...4))
    var points: [GeneratedPoint]
    @Guide(description: "Sections that go deeper.", .count(2...3))
    var sections: [GeneratedSection]
    @Guide(description: "Short questions the reader might ask next, each a few words, not the question itself.", .count(2...3))
    var followUps: [String]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedPoint {
    @Guide(description: "One emoji that fits the point.")
    var emoji: String
    @Guide(description: "The point's name, one to three words.")
    var term: String
    @Guide(description: "One sentence.")
    var text: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSection {
    @Guide(description: "A heading, two to five words.")
    var heading: String
    @Guide(description: "Two or three sentences.")
    var text: String
}
#endif
