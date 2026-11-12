import CraCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a page's summary with the device's own model (`MobileSummary` has the prompt and the
/// answer's shape). Nothing leaves the phone.
enum Summarizer {
    private static var language: String { AnswerLanguage.englishName }

    /// The summary, or nil when the model could not write one (too little text, a refusal).
    static func summarize(title: String, text: String) async -> MobileSummary.Answer? {
        guard MobileSummary.canSummarize(text: text) else { return nil }
        if LaunchOptions.fakeModel {
            try? await Task.sleep(for: .seconds(0.8))
            return MobileSummary.fakeAnswer(title: title, text: text).cleaned
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: MobileSummary.instructions)
                let prompt = MobileSummary.prompt(title: title, text: text, language: language)
                let response = try await session.respond(to: prompt, generating: GeneratedSummary.self, options: GenerationOptions(sampling: .greedy))
                return MobileSummary.Answer(overview: response.content.overview,
                                            sections: response.content.sections.map { .init(title: $0.title, body: $0.body, symbol: $0.symbol) }).cleaned
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
private struct GeneratedSummary {
    @Guide(description: "One short paragraph saying what the page is about.")
    var overview: String
    @Guide(description: "Three to five sections covering the page's main points.", .count(3...5))
    var sections: [GeneratedSection]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSection {
    @Guide(description: "A short title, two to five words.")
    var title: String
    @Guide(description: "Two or three sentences.")
    var body: String
    @Guide(description: "Relevant SF Symbol systemName, e.g. \"heart.fill\", \"leaf.fill\", \"clock.fill\"")
    var symbol: String
}
#endif
