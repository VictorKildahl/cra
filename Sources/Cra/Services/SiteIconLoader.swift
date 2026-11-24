import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A site's icon for a row that shows none: sidebar tabs and favorites on screen, command-bar rows for
/// the user's tabs, archive and history, and Library ▸ Boosts. Its home page's declared icons, then
/// /favicon.ico (CraCore SiteIcon), fetched from the page's own origin without cookies, in the order
/// SiteIconQueue gives, kept in the favicon cache under the site's key unless an icon got there first.
@MainActor
final class SiteIconLoader {
    static let shared = SiteIconLoader()
    private var queue = SiteIconQueue()
    private var waiting: [String: [() -> Void]] = [:]
    private var pumpQueued = false
    private weak var cache: FaviconCache?
    /// How long one site may hold a fetch slot, all its requests together.
    private let deadline: Duration

    /// What one response may download: a home page's head is near its top, and an icon is small.
    nonisolated static let pageLimit = 512 * 1024, iconLimit = 1024 * 1024
    /// How many of a page's declared icons are tried, best first.
    nonisolated static let candidateLimit = 4

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"]
        return URLSession(configuration: c)
    }()

    init(deadline: Duration = .seconds(30)) { self.deadline = deadline }

    /// Asks for the icon of the row's site when SiteIconQueue says it may, once a launch, rows on screen
    /// first. It only queues: the fetches start on the next turn of the main loop, so a view may call it
    /// while it reads the cache. `done` runs when that fetch ends, stored or not.
    func want(_ row: SiteIconQueue.Row, into cache: FaviconCache, done: (() -> Void)? = nil) {
        self.cache = cache
        guard queue.want(row) else { return }
        if let done, let host = FaviconKey.key(for: row.url) { waiting[host, default: []].append(done) }
        guard !pumpQueued else { return }
        pumpQueued = true
        DispatchQueue.main.async { MainActor.assumeIsolated { self.pump() } }
    }

    private func pump() {
        pumpQueued = false
        while let fetch = queue.next() {
            Task {
                let png = await Self.icon(at: fetch.origin, session: session, deadline: deadline)
                queue.finished(fetch.host)
                // The engine's icon, or another source's, that arrived meanwhile stays.
                if let png, let image = NSImage(data: png), let cache, cache.image(forKey: fetch.host) == nil {
                    cache.store(image, forKey: fetch.host)
                    CraLog.note("site icon for \(fetch.host) stored")
                }
                waiting.removeValue(forKey: fetch.host)?.forEach { $0() }
                pump()
            }
        }
    }

    /// The site's icon as a PNG at most 64 px on its long side, or nil once `deadline` has passed.
    private nonisolated static func icon(at origin: URL, session: URLSession, deadline: Duration) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await firstIcon(at: origin, session: session) }
            group.addTask { try? await Task.sleep(for: deadline); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The first of the home page's best icons that is `isIcon` and FaviconCache.png reads, which refuses one
    /// claiming too many pixels before decoding it. A page that answers with an error still has
    /// /favicon.ico; a site that can't be reached is not asked again. Every request and redirect
    /// passes SiteIcon.mayFetch, so a public page's icons never reach the local network.
    private nonisolated static func firstIcon(at origin: URL, session: URLSession) async -> Data? {
        let page: (data: Data, url: URL)?
        do { page = try await get(origin, for: origin, limit: pageLimit, session: session) } catch { return nil }
        let html = page.map { String(decoding: $0.data.prefix(pageLimit), as: UTF8.self) } ?? ""
        let candidates = SiteIcon.candidates(html: html, base: page?.url ?? origin).filter { SiteIcon.mayFetch($0, for: origin) }
        for url in candidates.prefix(candidateLimit) {
            guard !Task.isCancelled else { return nil }
            guard let data = try? await get(url, for: origin, limit: iconLimit, session: session)?.data, data.count <= iconLimit,
                  isIcon(data), let png = FaviconCache.png(data) else { continue }
            return png
        }
        return nil
    }

    /// Whether a site's bytes may be read as an icon: a bitmap ImageIO knows, or SVG text. Not a PDF or
    /// another format AppKit would draw when FaviconCache.png falls back to NSImage.
    nonisolated static func isIcon(_ data: Data) -> Bool {
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) {
            // ImageIO names a PDF too (com.adobe.pdf), which is no image type.
            return UTType(type as String)?.conforms(to: .image) == true
        }
        return SiteIcon.isSVG(data)
    }

    /// A 2xx response's body, cut off past `limit` bytes, and the address it came from after redirects;
    /// nil for another status or a redirect `origin`'s site may not follow. Throws when the site can't be
    /// reached or `url` may not be fetched.
    private nonisolated static func get(_ url: URL, for origin: URL, limit: Int, session: URLSession) async throws -> (data: Data, url: URL)? {
        guard SiteIcon.mayFetch(url, for: origin) else { throw URLError(.cancelled) }
        let body = Body(origin: origin, limit: limit)
        let task = session.dataTask(with: url)
        task.delegate = body
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { body.start(task, $0) }
        } onCancel: { task.cancel() }
    }

    /// A response's body, collected in the chunks URLSession delivers; the download stops past `limit` bytes,
    /// and a redirect is followed only where `origin`'s site may fetch.
    private final class Body: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let origin: URL
        private let limit: Int
        private let lock = NSLock()
        private var data = Data()
        private var full = false
        private var done: CheckedContinuation<(data: Data, url: URL)?, Error>?

        init(origin: URL, limit: Int) {
            self.origin = origin
            self.limit = limit
        }

        func start(_ task: URLSessionDataTask, _ done: CheckedContinuation<(data: Data, url: URL)?, Error>) {
            lock.withLock { self.done = done }
            task.resume()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            // Refused, the redirect itself is the response, and it is no 2xx.
            completionHandler(request.url.map { SiteIcon.mayFetch($0, for: origin) } == true ? request : nil)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            let over = lock.withLock {
                data.append(chunk)
                full = data.count > limit
                return full
            }
            if over { dataTask.cancel() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let (done, body, full) = lock.withLock { () -> (CheckedContinuation<(data: Data, url: URL)?, Error>?, Data, Bool) in
                defer { self.done = nil }
                return (self.done, data, full)
            }
            guard let http = task.response as? HTTPURLResponse, error == nil || full else {
                done?.resume(throwing: error ?? URLError(.badServerResponse))
                return
            }
            let url = http.url ?? task.originalRequest?.url
            guard (200..<300).contains(http.statusCode), let url else { done?.resume(returning: nil); return }
            done?.resume(returning: (body, url))
        }
    }
}
