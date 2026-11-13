import Foundation
import CraCEF

/// One preview page load. CEF stops at each redirect; no next target is requested until the
/// Swift policy has validated it. Generic browser and restricted plugin fetches are untouched.
@MainActor
final class LinkSummaryFetch {
    struct Page { var html: String; var url: URL }
    struct Response {
        var status: Int
        var url: String
        var location: String = ""
        var mime: String = "text/html"
        var body: String = ""
        var receivedBytes: Int
    }
    typealias Start = (URL, String?, Int, TimeInterval, @escaping @MainActor (Response) -> Void) -> (@MainActor () -> Void)
    private let clock: Scheduler
    private let start: Start

    init(clock: Scheduler? = nil, start: Start? = nil) {
        self.clock = clock ?? LiveScheduler.shared
        self.start = start ?? { url, profile, maximumBytes, timeout, done in
            let handle = CraCEFRuntime.fetchPreviewURL(url.absoluteString, profilePath: profile, maximumBytes: UInt(maximumBytes), timeout: timeout) {
                status, finalURL, location, mime, body, bytes in
                MainActor.assumeIsolated {
                    done(Response(status: status, url: finalURL, location: location, mime: mime, body: body, receivedBytes: Int(bytes)))
                }
            }
            return { handle.cancel() }
        }
    }

    func load(_ request: LinkSummaryRequest) async -> Page? {
        let operation = Operation(request: request, clock: clock, start: start)
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Page?, Never>) in
                // Cancellation may have won before the continuation was registered.
                guard !operation.ended else { continuation.resume(returning: nil); return }
                operation.continuation = continuation
                if Task.isCancelled { operation.finish(nil) } else { operation.begin() }
            }
        } onCancel: {
            Task { @MainActor in operation.finish(nil) }
        }
        return Task.isCancelled ? nil : result
    }

    /// Concrete per-load ownership: one continuation, one active hop and one aggregate deadline.
    @MainActor private final class Operation {
        let request: LinkSummaryRequest
        let clock: Scheduler
        let start: Start
        var continuation: CheckedContinuation<Page?, Never>?
        var cancelHop: (@MainActor () -> Void)?
        var timer: ScheduledWork?
        var ended = false
        var hop = 0
        var redirects = 0
        var receivedBytes = 0
        var visited: Set<URL> = []
        let expires: Date

        init(request: LinkSummaryRequest, clock: Scheduler, start: @escaping Start) {
            self.request = request
            self.clock = clock
            self.start = start
            self.expires = clock.now.addingTimeInterval(LinkSummaryFetchPolicy.timeout)
        }

        func begin() {
            timer = clock.after(LinkSummaryFetchPolicy.timeout) { [weak self] in self?.finish(nil) }
            guard let url = LinkSummaryFetchPolicy.target(request.link.absoluteString, httpsOnly: request.httpsOnly) else { finish(nil); return }
            fetch(url)
        }

        func fetch(_ url: URL) {
            let remaining = expires.timeIntervalSince(clock.now)
            guard !ended, remaining > 0, receivedBytes < LinkSummaryFetchPolicy.maximumBytes,
                  visited.insert(url).inserted else { finish(nil); return }
            hop += 1
            let current = hop
            let cancel = start(url, request.profilePath, LinkSummaryFetchPolicy.maximumBytes - receivedBytes, remaining) { [weak self] response in
                guard let self, !self.ended, self.hop == current else { return }
                self.cancelHop = nil
                self.receive(response)
            }
            // Create can fail/complete synchronously, including a whole redirect chain. Never
            // overwrite its next active handle or retain a finished handle in that race.
            if ended || hop != current { cancel() } else { cancelHop = cancel }
        }

        func receive(_ response: Response) {
            guard clock.now < expires, response.receivedBytes >= 0,
                  response.receivedBytes <= LinkSummaryFetchPolicy.maximumBytes - receivedBytes,
                  let finalURL = LinkSummaryFetchPolicy.target(response.url, httpsOnly: false),
                  !request.httpsOnly || finalURL.scheme == "https" else { finish(nil); return }
            receivedBytes += response.receivedBytes
            if [301, 302, 303, 307, 308].contains(response.status) {
                guard redirects < LinkSummaryFetchPolicy.maximumRedirects, !response.location.isEmpty,
                      let next = LinkSummaryFetchPolicy.target(response.location, relativeTo: finalURL, httpsOnly: request.httpsOnly) else { finish(nil); return }
                redirects += 1
                fetch(next)
                return
            }
            let mime = response.mime.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard (200..<300).contains(response.status), mime.isEmpty || mime == "text/html" || mime == "application/xhtml+xml",
                  !response.body.isEmpty else { finish(nil); return }
            finish(Page(html: response.body, url: finalURL))
        }

        func finish(_ page: Page?) {
            guard !ended else { return }
            ended = true
            timer?.cancel()
            timer = nil
            let cancel = cancelHop
            cancelHop = nil
            let done = continuation
            continuation = nil
            cancel?()
            done?.resume(returning: page)
        }
    }
}
