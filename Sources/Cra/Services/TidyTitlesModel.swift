import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidy Tab Titles' call to the Mac's own model: one fresh session per title, Arc's answer
/// schema, and the context check before the request is sent. TidyTitlesService decides when to
/// ask and what to do with the answer.
@MainActor
enum TidyTitlesModel {
    static func respond(instructions: String, prompt: String, responseLimit: Int) async throws -> TidyTitles.Answer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            try Task.checkCancellation()
            if #available(macOS 26.4, *) {
                let model = SystemLanguageModel.default
                let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
                try Task.checkCancellation()
                let promptTokens = try await model.tokenCount(for: prompt)
                try Task.checkCancellation()
                let schemaTokens = try await model.tokenCount(for: TidyTitleAnswer.generationSchema)
                try Task.checkCancellation()
                guard TidyTitles.fitsContext(inputTokens: instructionTokens + promptTokens + schemaTokens, contextSize: model.contextSize) else {
                    throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "Pinned title input exceeds local context budget"))
                }
            }
            let session = LanguageModelSession(instructions: instructions)
            let result = try await session.respond(to: prompt, generating: TidyTitleAnswer.self,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: responseLimit))
            return TidyTitles.Answer(filtered: result.content.filtered, rewritten: result.content.rewritten)
        }
        #endif
        throw CocoaError(.featureUnsupported)
    }

    static func isContextOverflow(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let generationError = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError { return true }
        #endif
        return false
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TidyTitleAnswer {
    // Arc's schema comments, word for word.
    @Guide(description: "The title translated and filtered to remove the cruft. No word limit.")
    var filtered: String
    @Guide(description: "The title rewritten in 1-3 words")
    var rewritten: String
}
#endif
