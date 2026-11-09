import AppKit

/// A site's icon for a site no tab has shown yet (a boost on Library ▸ Boosts): its home page's
/// declared icons, then /favicon.ico (CraCore SiteIcon), fetched without cookies as the WebKit tabs'
/// icons are, kept in the favicon cache under the site's key.
@MainActor
final class SiteIconLoader {
    static let shared = SiteIconLoader()
    private var asked: Set<String> = []

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"]
        return URLSession(configuration: c)
    }()

    /// Fetches `host`'s icon once a session; `done` runs when it is in `cache`.
    func load(host: String, into cache: FaviconCache, done: @escaping () -> Void) {
        guard !host.isEmpty, asked.insert(host).inserted, let home = URL(string: "https://\(host)/") else { return }
        session.dataTask(with: home) { [session] data, response, _ in
            let base = response?.url ?? home
            let html = data.flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) } ?? ""
            Self.firstImage(SiteIcon.candidates(html: html, base: base), session: session) { image in
                guard let image else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let key = FaviconKey.key(for: home.absoluteString) else { return }
                        cache.store(image, forKey: key)
                        CraLog.note("site icon for \(host) stored")
                        done()
                    }
                }
            }
        }.resume()
    }

    private nonisolated static func firstImage(_ urls: [URL], session: URLSession, done: @escaping @Sendable (NSImage?) -> Void) {
        guard let url = urls.first else { done(nil); return }
        session.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            if ok, let data, let image = NSImage(data: data), image.size.width > 0 { done(image); return }
            firstImage(Array(urls.dropFirst()), session: session, done: done)
        }.resume()
    }
}
