import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The feature's on-device adapter. Every attempt owns its fitted ID mapping and a fresh session.
@MainActor
enum TidyTabsModel {
    struct Answer {
        let request: TidyTabs.Request
        let proposals: [TidyTabs.Proposal]
    }
    enum Failure: Error {
        case unavailable
        case contextLimit(TidyTabs.Request)
    }
    typealias Attempt = @MainActor (TidyTabs.Request) async throws -> Answer

    static var promptByteLimit: Int {
        #if canImport(FoundationModels)
        if #available(macOS 26.4, *) { return TidyTabs.maximumPromptBytes }
        #endif
        return TidyTabs.fallbackPromptBytes
    }

    /// One context-specific retry only. Other errors and cancellation propagate to the caller.
    static func group(_ request: TidyTabs.Request, attempt: Attempt? = nil) async throws -> Answer {
        let respond = attempt ?? nativeAttempt
        try Task.checkCancellation()
        do {
            return try await respond(request)
        } catch Failure.contextLimit(let failed) {
            try Task.checkCancellation()
            guard let reduced = failed.reduced() else { throw Failure.contextLimit(failed) }
            return try await respond(reduced)
        }
    }

    private static func nativeAttempt(_ initial: TidyTabs.Request) async throws -> Answer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else { throw Failure.unavailable }
            var request = initial
            do {
                if #available(macOS 26.4, *) {
                    // Exact SDK counts per component; 256 tokens reserve message/framing overhead.
                    let instructions = try await model.tokenCount(for: Instructions { TidyTabs.instructions })
                    let schema = try await model.tokenCount(for: TidyAnswer.generationSchema)
                    let fixed = instructions + schema + TidyTabs.framingTokens
                    while try await model.tokenCount(for: request.prompt) + fixed + request.responseTokens > model.contextSize {
                        guard let reduced = request.reduced() else { throw Failure.contextLimit(request) }
                        request = reduced
                    }
                } else {
                    guard let fitted = request.fittingEstimatedContext(model.contextSize) else {
                        throw Failure.contextLimit(request)
                    }
                    request = fitted
                }
                try Task.checkCancellation()
                let session = LanguageModelSession(model: model, instructions: TidyTabs.instructions)
                let answer = try await session.respond(to: request.prompt, generating: TidyAnswer.self,
                                                       options: GenerationOptions(sampling: .greedy,
                                                                                  maximumResponseTokens: request.responseTokens))
                return Answer(request: request, proposals: answer.content.groups.map { .init(name: $0.name, tabs: $0.tabs) })
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                throw Failure.contextLimit(request)
            }
        }
        #endif
        throw Failure.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TidyAnswer {
    @Guide(description: "The groups, each with a name and the integer IDs of its tabs")
    var groups: [TidyGroup]
}

@available(macOS 26.0, *)
@Generable
struct TidyGroup {
    @Guide(description: "A concise descriptive name, using the unique topic the tabs share")
    var name: String
    @Guide(description: "Integer IDs from the supplied tabs, each used in at most one group")
    var tabs: [Int]
}
#endif
