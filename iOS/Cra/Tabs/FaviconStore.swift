import CraCore
import UIKit

/// Site icons, one per site, fetched from the site itself (never from an icon service, which
/// would learn every site visited) and kept in the caches folder.
final class FaviconStore {
    private let directory: URL
    private var memory: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private let session: URLSession

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        session = URLSession(configuration: configuration)
    }

    private func key(_ address: String) -> String? {
        URL(string: address)?.host.map(MobileSettings.siteKey)
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    func icon(for address: String) -> UIImage? {
        guard let key = key(address) else { return nil }
        if let image = memory[key] { return image }
        guard let image = UIImage(contentsOfFile: file(key).path) else { return nil }
        memory[key] = image
        return image
    }

    /// Fetches the icon a page names (`candidates`, best first), falling back to /favicon.ico.
    /// Incognito pages are never asked: nothing about them is kept.
    func fetch(for address: String, candidates: [String]) {
        guard let key = key(address), memory[key] == nil, !inFlight.contains(key), let page = URL(string: address),
              page.scheme == "https" || page.scheme == "http" else { return }
        var urls = candidates.compactMap { URL(string: $0, relativeTo: page)?.absoluteURL }
        if let fallback = URL(string: "/favicon.ico", relativeTo: page)?.absoluteURL { urls.append(fallback) }
        inFlight.insert(key)
        tryNext(urls[...], key: key)
    }

    private func tryNext(_ urls: ArraySlice<URL>, key: String) {
        guard let url = urls.first else {
            inFlight.remove(key)
            return
        }
        session.dataTask(with: url) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = ok ? data.flatMap { UIImage(data: $0) } : nil
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image, image.size.width >= 8 else { return self.tryNext(urls.dropFirst(), key: key) }
                self.inFlight.remove(key)
                self.memory[key] = image
                try? image.pngData()?.write(to: self.file(key), options: .atomic)
            }
        }.resume()
    }
}
