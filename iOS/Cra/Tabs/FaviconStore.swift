import CraCore
import UIKit

/// Site icons, one per site, fetched from the site itself (never from an icon service, which
/// would learn every site visited) and kept in the caches folder.
final class FaviconStore {
    private let directory: URL
    private var memory: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private let session: URLSession
    /// Posted when an icon arrives, so the views showing it can redraw.
    static let didChange = Notification.Name("CraFaviconStoreDidChange")

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

    /// Whether an icon is a dark colourless mark (`MobileFavicons.drawsAsMark`), worked out once.
    static func isMark(_ image: UIImage) -> Bool {
        let key = ObjectIdentifier(image)
        if let known = marks[key] { return known }
        let answer = measure(image)
        marks[key] = answer
        return answer
    }

    private static var marks: [ObjectIdentifier: Bool] = [:]

    private static func measure(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var covered = 0.0, luminance = 0.0, chroma = 0.0, light = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            covered += 1
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luminance += y
            if y > 0.6 { light += 1 }
            chroma += max(r, g, b) - min(r, g, b)
        }
        guard covered > 0 else { return false }
        return MobileFavicons.drawsAsMark(coverage: covered / Double(side * side), luminance: luminance / covered,
                                          chroma: chroma / covered, lightShare: light / covered)
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

    /// For a site the phone hasn't opened (the Mac's pinned tabs): reads the site's home page,
    /// cookies off, for the icons it names (`MobileFavicons.iconLinks`), then fetches the best.
    func fetchFromHomePage(for address: String) {
        guard let key = key(address), memory[key] == nil, !inFlight.contains(key), icon(for: address) == nil,
              let page = URL(string: address), page.scheme == "https" || page.scheme == "http",
              let home = URL(string: "/", relativeTo: page)?.absoluteURL else { return }
        inFlight.insert(key)
        session.dataTask(with: home) { [weak self] data, response, _ in
            let base = response?.url ?? home
            let html = data.flatMap { String(data: $0.prefix(200_000), encoding: .utf8) ?? String(data: $0.prefix(200_000), encoding: .isoLatin1) } ?? ""
            let urls = MobileFavicons.iconLinks(inHTML: html, page: base).compactMap(URL.init(string:))
            DispatchQueue.main.async { self?.tryNext(urls[...], key: key) }
        }.resume()
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
                NotificationCenter.default.post(name: FaviconStore.didChange, object: self)
            }
        }.resume()
    }
}
