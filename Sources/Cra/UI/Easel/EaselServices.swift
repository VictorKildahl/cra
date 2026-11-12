import AppKit
import CraCEF

/// The app's side of EaselHooks: links open in tabs, link cards read the page they point at, a
/// dragged sidebar tab becomes its address, captures show their site's icon and go live.
extension EaselBrowser {
    static func registerServices(_ app: AppDelegate) {
        EaselHooks.openURL = { [weak app] url in
            guard let app else { return }
            _ = app.useNormalWindow()
            _ = app.store.createTab(url: url, select: true)
        }
        EaselHooks.fetchLink = { url, done in EaselLinkFetcher.fetch(url, done: done) }
        EaselHooks.sidebarLink = { [weak app] data in
            guard let app, let drag = try? JSONDecoder().decode(SidebarDragItem.self, from: data),
                  let tab = app.store.item(drag.id)?.tab, Easel.webAddress(tab.url) != nil else { return nil }
            return (tab.url, app.store.item(drag.id)?.displayTitle ?? "")
        }
        EaselHooks.favicon = { [weak app] url in app?.favicons.image(for: url) }
        EaselHooks.live = { capture, profile in EaselLivePage(capture: capture, profilePath: profile) }
    }
}

extension EaselLivePage: EaselLive {}

/// Reads a page once for its link card, as Arc's metaFetcher does: the HTML's head for the og: tags
/// (EaselLinkMetadata), then the og:image. Nothing else is sent; the request is the same as opening
/// the address, without cookies.
enum EaselLinkFetcher {
    static let maxImageBytes = 5 * 1024 * 1024

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
                                   "Accept": "text/html,application/xhtml+xml"]
        return URLSession(configuration: c)
    }()

    static func fetch(_ url: String, done: @escaping @MainActor (EaselLinkMetadata?, Data?, Data?) -> Void) {
        guard let u = URL(string: url) else { Task { @MainActor in done(nil, nil, nil) }; return }
        session.dataTask(with: u) { data, response, _ in
            guard let data, (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) ?? false else {
                Task { @MainActor in done(nil, nil, nil) }
                return
            }
            let head = data.prefix(EaselLinkMetadata.maxBytes)
            let html = String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
            let meta = EaselLinkMetadata.parse(html: html, url: response?.url?.absoluteString ?? url)
            // The picture and the icon, each only if it is an image of a sane size.
            let group = DispatchGroup()
            var picture: Data?, icon: Data?
            for (address, store) in [(meta.image, { (d: Data) in picture = d }), (meta.icon, { (d: Data) in icon = d })] {
                guard let address, let u = URL(string: address) else { continue }
                group.enter()
                session.dataTask(with: u) { body, response, _ in
                    let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "image/"
                    if let body, body.count <= maxImageBytes, type.hasPrefix("image/"), NSImage(data: body) != nil { store(body) }
                    group.leave()
                }.resume()
            }
            group.notify(queue: .main) { [picture, icon] in MainActor.assumeIsolated { done(meta, picture, icon) } }
        }.resume()
    }
}

extension EaselCanvasView {
    /// cra://debug?easelLive=<s>: the first capture goes live; what it holds and the pictures it got, logged.
    func debugLive(after wait: Double) {
        guard let item = sheetView.document.items.first(where: { if case .capture = $0.kind { return true }; return false }),
              case .capture(let c) = item.kind else { CraLog.note("easel live: no capture"); return }
        let vp = c.viewport.map { "\(Int($0.width))x\(Int($0.height))" } ?? "none"
        let area = c.area.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.x)),\(Int($0.y))" } ?? "none"
        CraLog.note("easel capture: host=\(URL(string: c.url)?.host ?? "?") viewport=\(vp) area=\(area) canGoLive=\(c.canGoLive)")
        sheetView.setLive(true, for: item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            let image = self.sheetView.liveImages[item.id]
            CraLog.note("easel live: frames=\(self.sheetView.liveFrameCount) image=\(image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none")")
        }
    }

    /// cra://debug?easelPick=<n>: what a picked item shows: the colour picker and its colour, and the menu's rows.
    func debugPick(_ n: Int) {
        guard let item = sheetView.pick(index: n) else { CraLog.note("easel pick: none"); return }
        let picker = sheetView.colorPicker
        let rows = sheetView.objectMenu(for: item).items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: "|")
        CraLog.note("easel pick: picker=\(picker.isHidden ? "hidden" : "shown") color=\(picker.current?.rawValue ?? "none") menu=\(rows)")
    }

    /// cra://debug?easelLink=<url>: a link card, as if pasted; what it read, logged once filled in.
    func debugLink(_ url: String) {
        sheetView.addLink(url, title: nil, at: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, case .link(let l)? = self.sheetView.document.items.last?.kind else { CraLog.note("easel link: none"); return }
            CraLog.note("easel link: host=\(l.host) title=\(l.title ?? "none") summary=\(l.summary == nil ? "no" : "yes") picture=\(l.image == nil ? "no" : "yes")")
        }
    }
}
