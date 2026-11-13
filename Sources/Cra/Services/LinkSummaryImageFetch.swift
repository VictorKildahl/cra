import Foundation

/// Preview-only image bytes. The card owns this work independently of summary completion.
@MainActor
final class LinkSummaryImageFetch {
    nonisolated static let maximumBytes = 4_000_000
    nonisolated static let timeout: TimeInterval = 8
    private let configuration: URLSessionConfiguration
    private let clock: Scheduler

    init(configuration: URLSessionConfiguration = .ephemeral, clock: Scheduler? = nil) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.clock = clock ?? LiveScheduler.shared
    }

    func load(_ url: URL, httpsOnly: Bool) async -> Data? {
        guard !Task.isCancelled,
              let target = LinkSummaryFetchPolicy.target(url.absoluteString, httpsOnly: httpsOnly) else { return nil }
        let operation = Operation(url: target, httpsOnly: httpsOnly, configuration: configuration)
        // One deadline covers all redirects and body delivery; an idle timeout alone restarts.
        let deadline = clock.after(Self.timeout) { operation.cancel() }
        defer { deadline.cancel() }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { operation.start($0) }
        } onCancel: {
            operation.cancel()
        }
        return Task.isCancelled ? nil : result
    }

    /// URLSession delegates and cancellation serialize on this operation's queue. The session's
    /// delegate retain ends on invalidation; terminal delivery first drops all owned references.
    private final class Operation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let queue = DispatchQueue(label: "app.cra.preview-image")
        private let url: URL
        private let httpsOnly: Bool
        private let configuration: URLSessionConfiguration
        private var continuation: CheckedContinuation<Data?, Never>?
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var ended = false
        private var body = Data()
        private var visited: Set<URL>
        private var redirects = 0

        init(url: URL, httpsOnly: Bool, configuration: URLSessionConfiguration) {
            self.url = url
            self.httpsOnly = httpsOnly
            self.configuration = configuration.copy() as! URLSessionConfiguration
            self.visited = [url]
        }

        func start(_ continuation: CheckedContinuation<Data?, Never>) {
            queue.async {
                guard !self.ended else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                self.configuration.httpCookieStorage = nil
                self.configuration.httpShouldSetCookies = false
                self.configuration.urlCredentialStorage = nil
                self.configuration.urlCache = nil
                self.configuration.httpAdditionalHeaders = nil
                let delegates = OperationQueue()
                delegates.maxConcurrentOperationCount = 1
                delegates.underlyingQueue = self.queue
                let session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: delegates)
                self.session = session
                let task = session.dataTask(with: self.request(self.url))
                self.task = task
                task.resume()
            }
        }

        func cancel() { queue.async { self.finish(nil) } }

        private func request(_ url: URL) -> URLRequest {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: LinkSummaryImageFetch.timeout)
            request.httpShouldHandleCookies = false
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            return request
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard !ended, redirects < LinkSummaryFetchPolicy.maximumRedirects,
                  let base = response.url, validFinal(base), let raw = request.url,
                  let next = LinkSummaryFetchPolicy.target(raw.absoluteString, httpsOnly: httpsOnly),
                  visited.insert(next).inserted else {
                completionHandler(nil)
                finish(nil)
                return
            }
            redirects += 1
            completionHandler(self.request(next))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard !ended, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), let url = http.url, validFinal(url),
                  let contentType = http.value(forHTTPHeaderField: "Content-Type"),
                  let mime = contentType.lowercased().split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces), mime.hasPrefix("image/"), mime.count > 6,
                  http.expectedContentLength <= Int64(LinkSummaryImageFetch.maximumBytes) else {
                completionHandler(.cancel)
                finish(nil)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !ended else { return }
            guard data.count <= LinkSummaryImageFetch.maximumBytes - body.count else { finish(nil); return }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard !ended else { return }
            finish(error == nil && !body.isEmpty ? body : nil)
        }

        private func validFinal(_ url: URL) -> Bool {
            LinkSummaryFetchPolicy.target(url.absoluteString, httpsOnly: false) != nil
                && (!httpsOnly || url.scheme?.lowercased() == "https")
        }

        private func finish(_ data: Data?) {
            guard !ended else { return }
            ended = true
            let done = continuation
            continuation = nil
            body = Data()
            let session = self.session, task = self.task
            self.session = nil
            self.task = nil
            if data == nil { task?.cancel(); session?.invalidateAndCancel() } else { session?.finishTasksAndInvalidate() }
            done?.resume(returning: data)
        }
    }
}
