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

    /// Fetches destination HTML through fast URLSession streaming (first 35KB slice), falling back to Chromium CEF.
    private func fetchHTMLDirect(url: URL, profilePath: String?) async -> String? {
        if let html = await fetchViaURLSession(url: url) {
            return html
        }
        return await fetchViaCEF(url: url, profilePath: profilePath)
    }

    /// Fast path: reads up to 35 KB via native URLSession, which takes ~150-300ms and cancels the stream early.
    private func fetchViaURLSession(url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (String?) -> Void = { res in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: res)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                finish(nil)
            }

            Task {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 1.8)
                request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        finish(nil)
                        return
                    }

                    var data = Data()
                    data.reserveCapacity(35_000)
                    for try await byte in asyncBytes {
                        data.append(byte)
                        if data.count >= 35_000 {
                            break
                        }
                    }

                    let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                    finish(str)
                } catch {
                    finish(nil)
                }
            }
        }
    }

    /// Chromium CEF fallback for space profiles or authenticated sessions.
    private func fetchViaCEF(url: URL, profilePath: String?) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var resumed = false
            let finish: (String?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                finish(nil)
            }

            CraCEFRuntime.fetchURL(url.absoluteString, headers: nil, profilePath: profilePath) { status, _, _, body in
                if status == 200, !body.isEmpty {
                    finish(body)
                } else {
                    finish(nil)
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
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 85)
                )
                let parsed = LinkSummaryPrompt.parseResponse(response.content, fallbackHeadline: content.description)
                let host = LinkSummaryPrompt.host(url)
                let finalTitle = (content.title ?? title).trimmingCharacters(in: .whitespacesAndNewlines)

                CraLog.note("LinkSummary: summarized \(host) (\(parsed.bullets.count) points in Arc Max format)")
                return LinkSummaryResult(
                    url: url.absoluteString,
                    title: finalTitle.isEmpty ? host : finalTitle,
                    host: host,
                    headline: parsed.headline ?? content.description ?? "Overview of \(host).",
                    bullets: parsed.bullets.isEmpty ? [content.description ?? "Overview of \(host)."] : parsed.bullets
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
