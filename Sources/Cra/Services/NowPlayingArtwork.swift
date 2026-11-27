import AppKit
import CraCEF
import Observation

/// The island player's artwork (Discussion #761): the picture a page's media session names, loaded through
/// that page's own network session (DevTools' Network.loadNetworkResource, read back as a stream), so it goes
/// where the page's own requests go: no cookies sent, the page's proxy and profile. A `data:` picture is decoded
/// here. A WebKit page has no DevTools session: its island shows the site's icon instead. The last 24 are kept.
@MainActor @Observable
final class NowPlayingArtwork {
    static let shared = NowPlayingArtwork()

    /// The artwork is drawn 48 pt wide, so a Retina display wants about this many pixels.
    static let pixels = 112
    private static let limit = 24
    private static let maxBytes = 4 << 20

    struct Picture {
        let image: NSImage
    }

    private(set) var pictures: [String: Picture] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []

    func picture(_ url: String?) -> Picture? { url.flatMap { pictures[$0] } }

    /// cra://debug's readout: "WxH" of the loaded picture, "loading", "failed" or "none".
    func debugState(_ url: String?) -> String {
        guard let url else { return "none" }
        if let p = pictures[url] { return "\(Int(p.image.size.width))x\(Int(p.image.size.height))" }
        return loading.contains(url) ? "loading" : failed.contains(url) ? "failed" : "none"
    }

    func load(_ url: String, through browser: CraBrowser) {
        guard pictures[url] == nil, !loading.contains(url), !failed.contains(url) else { return }
        if url.hasPrefix("data:") { return finish(url, Self.decodeDataURL(url)) }
        guard url.hasPrefix("https://") || url.hasPrefix("http://"), !(browser is WebKitBrowser) else {
            failed.insert(url)
            return
        }
        loading.insert(url)
        Task { @MainActor [weak browser] in
            var data: Data?
            if let browser { data = await Self.fetch(url, through: browser) }
            self.loading.remove(url)
            self.finish(url, data)
        }
    }

    private func finish(_ url: String, _ data: Data?) {
        guard let data, let image = NSImage(data: data), image.isValid, image.size.width > 0 else {
            failed.insert(url)
            return
        }
        pictures[url] = Picture(image: image)
        order.append(url)
        while order.count > Self.limit { pictures[order.removeFirst()] = nil }
    }

    // MARK: Loading

    private static func decodeDataURL(_ url: String) -> Data? {
        guard url.count <= maxBytes * 2, let comma = url.firstIndex(of: ",") else { return nil }
        let header = url[..<comma], body = String(url[url.index(after: comma)...])
        return header.hasSuffix(";base64") ? Data(base64Encoded: body) : body.removingPercentEncoding.map { Data($0.utf8) }
    }

    private static func call(_ browser: CraBrowser, _ method: String, _ params: [String: Any]) async -> [String: Any]? {
        let json = (try? JSONSerialization.data(withJSONObject: params)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return await withCheckedContinuation { (done: CheckedContinuation<[String: Any]?, Never>) in
            browser.sendDevToolsMethod(method, params: json) { result, error in
                let object = error == nil ? result?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                done.resume(returning: object)
            }
        }
    }

    private static func fetch(_ url: String, through browser: CraBrowser) async -> Data? {
        guard let tree = await call(browser, "Page.getFrameTree", [:]),
              let frame = ((tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any])?["id"] as? String,
              let answer = await call(browser, "Network.loadNetworkResource",
                                      ["frameId": frame, "url": url, "options": ["disableCache": false, "includeCredentials": false]]),
              let resource = answer["resource"] as? [String: Any], resource["success"] as? Bool == true,
              let stream = resource["stream"] as? String else { return nil }
        var data = Data(), complete = false
        while data.count <= maxBytes {
            guard let chunk = await call(browser, "IO.read", ["handle": stream, "size": 65536]), let text = chunk["data"] as? String,
                  let bytes = chunk["base64Encoded"] as? Bool == true ? Data(base64Encoded: text) : Data(text.utf8) else { break }
            data.append(bytes)
            if chunk["eof"] as? Bool == true {
                complete = true
                break
            }
        }
        _ = await call(browser, "IO.close", ["handle": stream])
        return complete ? data : nil
    }
}
