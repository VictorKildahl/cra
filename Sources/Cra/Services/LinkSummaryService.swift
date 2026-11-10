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
    @ObservationIgnored private var prefetchTasks: [String: Task<String?, Never>] = [:]
    @ObservationIgnored private var htmlCache: [String: String] = [:]

    private init() {}

    /// Whether Apple Intelligence is available to generate summaries.
    var isAvailable: Bool {
        TidyTabsService.shared.modelAvailable
    }

    /// Immediate synchronous lookup in the in-memory cache for 0ms previews.
    func cachedResult(for url: URL) -> LinkSummaryResult? {
        cache[url.absoluteString]
    }

    /// Speculatively prefetches the target webpage HTML in the background as soon as the
    /// pointer hovers over a link, so network latency is eliminated by the time the hover
    /// dwell delay expires or Shift is pressed.
    func prefetch(url: URL, profilePath: String?) {
        guard isAvailable else { return }
        let key = url.absoluteString
        if cache[key] != nil || htmlCache[key] != nil || prefetchTasks[key] != nil {
            return
        }

        let task = Task<String?, Never> { @MainActor in
            defer { prefetchTasks.removeValue(forKey: key) }
            guard let html = await fetchHTMLDirect(url: url, profilePath: profilePath) else {
                return nil
            }
            htmlCache[key] = html
            return html
        }
        prefetchTasks[key] = task
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

    /// Fetches destination HTML using prefetched cache if available, falling back to direct network fetch.
    private func fetchHTML(url: URL, profilePath: String?) async -> String? {
        let key = url.absoluteString
        if let cached = htmlCache[key] { return cached }
        if let existingPrefetch = prefetchTasks[key] {
            return await existingPrefetch.value
        }
        let html = await fetchHTMLDirect(url: url, profilePath: profilePath)
        if let html {
            htmlCache[key] = html
        }
        return html
    }

    /// Fetches destination HTML through Chromium CEF with the space's profile, falling back to URLSession.
    private func fetchHTMLDirect(url: URL, profilePath: String?) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var resumed = false
            let finish: (String?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            // Timeout after 2.5 seconds so slow/unresponsive servers don't stall the UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                finish(nil)
            }

            CraCEFRuntime.fetchURL(url.absoluteString, headers: nil, profilePath: profilePath) { status, _, _, body in
                if status == 200, !body.isEmpty {
                    finish(body)
                } else {
                    Task {
                        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 2.5)
                        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                        if let (data, response) = try? await URLSession.shared.data(for: request),
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
                    description: content.description,
                    content: content.bodyText
                )
                let response = try await session.respond(
                    to: prompt,
                    generating: LinkSummaryModelAnswer.self,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 90)
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
