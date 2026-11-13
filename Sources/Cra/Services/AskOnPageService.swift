import AppKit
import CraCEF
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ask on Page on the Mac's own Apple Intelligence model (FoundationModels, macOS 26): the page's
/// text, read by a script in Cra's isolated world, and Arc's prompt (AskOnPagePrompt). The text and
/// the answer stay on the Mac.
@MainActor
final class AskOnPageService {
    static let shared = AskOnPageService()
    private init() {}

    var isAvailable: Bool { TidyTabsService.fakeModel || TidyTabsService.shared.modelAvailable }

    /// The page as the script read it.
    struct Page: Sendable {
        var url: String
        var title: String?
        var text: String
        /// The page's whole length; more than `text` when the script stopped reading.
        var total: Int
    }

    /// Reads the page's text. Nil when the page doesn't answer (it is loading, or not a web page).
    func read(_ browser: CraBrowser) async -> Page? {
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": AskOnPagePolicy.pageTextScript, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return await withCheckedContinuation { (c: CheckedContinuation<Page?, Never>) in
            browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, _ in
                guard let data = result?.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["exceptionDetails"] == nil,
                      let value = (json["result"] as? [String: Any])?["value"] as? [String: Any],
                      let text = value["text"] as? String else { c.resume(returning: nil); return }
                let title = (value["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                c.resume(returning: Page(url: value["url"] as? String ?? "", title: title, text: text,
                                         total: (value["total"] as? NSNumber)?.intValue ?? text.count))
            }
        }
    }

    /// The user's language by name, as Arc writes it into the prompt.
    private static var language: String {
        let code = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        return Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
    }

    /// Answers `question` about `page`, streaming the reply so far into `update` along with how much
    /// of the page was read (nil: all of it). Returns the whole reply, Arc's sorry when the page has
    /// no text or the model failed, or nil when cancelled.
    func answer(question: String, turns: [AskOnPagePrompt.Turn], page: Page,
                update: @escaping (String, Double?) -> Void) async -> String? {
        let started = Date()
        guard page.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= AskOnPagePrompt.minimumText else {
            update(AskOnPagePrompt.unreadable, nil)
            return AskOnPagePrompt.unreadable
        }
        let instructions = AskOnPagePrompt.instructions(language: Self.language)
        let dialogue = AskOnPagePrompt.dialogue(turns: turns, question: question)
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)

        if TidyTabsService.fakeModel {
            let cut = AskOnPagePrompt.truncate(page.text, budget: 4_000, total: page.total)
            echo: for attempt in 0...AskOnPagePrompt.echoRetries {
                let reply = AskOnPagePrompt.fakeAnswer(question: question, text: page.text, attempt: attempt)
                // About a token every 20 ms, as the on-device model streams a long answer.
                for end in stride(from: 5, to: reply.count, by: 5) {
                    try? await Task.sleep(for: .milliseconds(20))
                    if Task.isCancelled { return nil }
                    let part = String(reply.prefix(end))
                    if AskOnPageReply.echoesPrompt(part) { Self.noteEcho(attempt); continue echo }
                    update(part, cut.fractionRead)
                }
                if AskOnPageReply.echoesPrompt(reply) { Self.noteEcho(attempt); continue }
                update(reply, cut.fractionRead)
                return reply
            }
            update(AskOnPagePrompt.failed, nil)
            return AskOnPagePrompt.failed
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            var budget = AskOnPagePrompt.characterBudget(contextTokens: Self.contextSize(model), instructions: instructions, dialogue: dialogue)
            var echoes = 0
            // Three characters a token is Arc's estimate; the model counts for real where it can, and a
            // prompt still too long is cut by the share it is over and tried again. A reply that copies
            // the page block back is asked for again.
            for attempt in 0..<(3 + AskOnPagePrompt.echoRetries) {
                let cut = AskOnPagePrompt.truncate(page.text, budget: budget, total: page.total)
                let conversation = AskOnPagePrompt.conversation(url: page.url, title: page.title, date: date, text: cut.text, turns: turns, question: question)
                let counted = await Self.tokens(model, instructions: instructions, conversation: conversation)
                if let counted, attempt < 2 {
                    let allowed = Self.contextSize(model) - AskOnPagePrompt.answerTokens
                    let smaller = AskOnPagePrompt.shrink(budget: min(budget, cut.text.count), promptTokens: counted, allowedTokens: allowed)
                    if smaller < min(budget, cut.text.count) { budget = smaller; continue }
                }
                var last = ""
                do {
                    let session = Self.session(model, instructions: instructions, earlier: conversation.earlier)
                    // A long answer (a summary) ends where the context does instead of overflowing it.
                    let options = AskOnPagePrompt.responseTokens(contextTokens: Self.contextSize(model), promptTokens: counted)
                        .map { GenerationOptions(maximumResponseTokens: $0) } ?? GenerationOptions()
                    var echoed = false
                    for try await snapshot in session.streamResponse(to: conversation.prompt, options: options) {
                        if Task.isCancelled { return nil }
                        last = snapshot.content
                        if AskOnPageReply.echoesPrompt(last) { echoed = true; break }
                        update(last, cut.fractionRead)
                    }
                    if echoed {
                        Self.noteEcho(echoes)
                        echoes += 1
                        if echoes > AskOnPagePrompt.echoRetries { break }
                        continue
                    }
                    CraLog.note(String(format: "Ask on Page: answered in %.1f s (%d of %d characters read)",
                                       Date().timeIntervalSince(started), min(cut.text.count, page.total), page.total))
                    return last
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    switch AskOnPagePrompt.afterOverflow(streamed: last) {
                    case .keepAnswer:
                        CraLog.note("Ask on Page: the answer reached the end of the context; kept as written")
                        return last
                    case .readLess:
                        CraLog.note("Ask on Page: the page didn't fit at \(budget) characters")
                        budget = budget * 3 / 5
                    }
                } catch {
                    if Task.isCancelled { return nil }
                    CraLog.note("Ask on Page: the model failed: \(error)")
                    break
                }
            }
        }
        #endif
        update(AskOnPagePrompt.failed, nil)
        return AskOnPagePrompt.failed
    }

    private static func noteEcho(_ attempt: Int) {
        CraLog.note("Ask on Page: the answer repeated the page; " + (attempt < AskOnPagePrompt.echoRetries ? "asking again" : "giving up"))
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func contextSize(_ model: SystemLanguageModel) -> Int {
        if #available(macOS 26.4, *) { return model.contextSize }
        return 4_096
    }

    /// A session that has already taken the conversation's earlier turns, each a turn of its own
    /// rather than "Human:"/"Assistant:" text, which the model copied into its answer (#417).
    @available(macOS 26.0, *)
    private static func session(_ model: SystemLanguageModel, instructions: String, earlier: [AskOnPagePrompt.Exchange]) -> LanguageModelSession {
        guard !earlier.isEmpty else { return LanguageModelSession(model: model, instructions: instructions) }
        func text(_ s: String) -> [Transcript.Segment] { [.text(Transcript.TextSegment(content: s))] }
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: text(instructions), toolDefinitions: []))]
        for turn in earlier {
            entries.append(.prompt(Transcript.Prompt(segments: text(turn.prompt))))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: text(turn.response))))
        }
        return LanguageModelSession(model: model, transcript: Transcript(entries: entries))
    }

    @available(macOS 26.0, *)
    private static func tokens(_ model: SystemLanguageModel, instructions: String, conversation: AskOnPagePrompt.Conversation) async -> Int? {
        guard #available(macOS 26.4, *) else { return nil }
        let sent = (conversation.earlier.flatMap { [$0.prompt, $0.response] } + [conversation.prompt]).joined(separator: "\n")
        guard let a = try? await model.tokenCount(for: Instructions(instructions)), let b = try? await model.tokenCount(for: sent) else { return nil }
        return a + b
    }
    #endif
}
