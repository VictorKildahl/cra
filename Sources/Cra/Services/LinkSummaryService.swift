import AppKit
import CraCEF
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Link summary previews on the Mac's own Apple Intelligence model (FoundationModels, macOS 26).
/// Arc Max's 5-Second Previews: hovering or Shift-hovering on a link summarizes the destination page
/// in 2 to 3 concise bullet points without clicking. Nothing leaves the Mac.
@MainActor @Observable
final class LinkSummaryService {
    static let shared = LinkSummaryService()

    @ObservationIgnored private var cache: [String: LinkSummaryResult] = [:]
    @ObservationIgnored private var inFlight: [String: Task<LinkSummaryResult?, Never>] = [:]

    private init() {}

    /// Whether Apple Intelligence is available to generate summaries.
    var isAvailable: Bool {
        TidyTabsService.shared.modelAvailable
    }

    /// Fetches the target webpage and generates a 2-3 bullet point summary using Apple Intelligence.
    func summarize(url: URL, title: String = "", profilePath: String?) async -> LinkSummaryResult? {
        guard isAvailable else { return nil }
        let key = url.absoluteString

        if let cached = cache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<LinkSummaryResult?, Never> { @MainActor in
            defer { inFlight.removeValue(forKey: key) }
            let html = await fetchHTML(url: url, profilePath: profilePath) ?? ""
            let extracted = LinkSummaryContent.extractText(from: html)
            guard let result = await Self.ask(title: title, url: url, content: extracted) else {
                return nil
            }
            cache[key] = result
            return result
        }

        inFlight[key] = task
        return await task.value
    }

    /// Fetches destination HTML through Chromium CEF with the space's profile, falling back to URLSession.
    private func fetchHTML(url: URL, profilePath: String?) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var resumed = false
            let finish: (String?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            // Timeout after 3.5 seconds so a slow server doesn't leave the preview hung.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                finish(nil)
            }

            CraCEFRuntime.fetchURL(url.absoluteString, headers: nil, profilePath: profilePath) { status, _, _, body in
                if status == 200, !body.isEmpty {
                    finish(body)
                } else {
                    Task {
                        if let (data, response) = try? await URLSession.shared.data(from: url),
                           (response as? HTTPURLResponse)?.statusCode == 200,
                           let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                            finish(str)
                        } else {
                            finish(nil)
                        }
                    }
                }
            }
        }
    }

    /// Asks the Apple Intelligence model (or the fake model when testing).
    private static func ask(title: String, url: URL, content: LinkSummaryContent.Extracted) async -> LinkSummaryResult? {
        if TidyTabsService.fakeModel {
            return LinkSummaryPrompt.fakeAnswer(title: title, url: url, content: content)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: LinkSummaryPrompt.instructions)
                let prompt = LinkSummaryPrompt.prompt(
                    title: content.title ?? title,
                    url: url.absoluteString,
                    content: content.bodyText
                )
                let response = try await session.respond(
                    to: prompt,
                    generating: LinkSummaryModelAnswer.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                let bullets = LinkSummaryPrompt.cleanBullets(response.content.bullets)
                let cleanTitle = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = cleanTitle.isEmpty ? (content.title ?? title) : cleanTitle
                let host = LinkSummaryPrompt.host(url)

                CraLog.note("LinkSummary: summarized \(host) (\(bullets.count) points)")
                return LinkSummaryResult(
                    url: url.absoluteString,
                    title: finalTitle.isEmpty ? host : finalTitle,
                    host: host,
                    bullets: bullets.isEmpty ? [content.description ?? "Overview of \(host)."] : bullets
                )
            } catch {
                CraLog.note("LinkSummary: model failed: \(error)")
                return LinkSummaryPrompt.fakeAnswer(title: title, url: url, content: content)
            }
        }
        #endif

        return LinkSummaryPrompt.fakeAnswer(title: title, url: url, content: content)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct LinkSummaryModelAnswer {
    @Guide(description: "A short, readable title for the webpage or article")
    var title: String
    @Guide(description: "Two or three concise bullet points capturing the key facts, announcements, or takeaways")
    var bullets: [String]
}
#endif
