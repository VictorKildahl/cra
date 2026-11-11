import CraCore
import Foundation

/// Asks the search engine what the typed text might become. One request at a time: a newer
/// keystroke cancels the one before it. Nothing is stored (an ephemeral session, no cookies).
final class SuggestionService {
    private let session: URLSession
    private var task: URLSessionDataTask?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 4
        session = URLSession(configuration: configuration)
    }

    func completions(for typed: String, engine: MobileSearchEngine, done: @escaping ([String]) -> Void) {
        task?.cancel()
        let query = typed.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let url = engine.suggestURL(query) else { return done([]) }
        let task = session.dataTask(with: url) { data, _, error in
            if (error as NSError?)?.code == NSURLErrorCancelled { return }
            let found = data.map(MobileSuggestions.completions(fromOpenSearch:)) ?? []
            DispatchQueue.main.async { done(found) }
        }
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
    }
}
