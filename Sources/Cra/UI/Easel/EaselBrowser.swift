import AppKit
import CraCEF

/// An Easel's page (Arc's File ▸ New Easel ⌃⇧E, measured on Arc 1.172.1; docs/arc-parity.md
/// "Easels, measured"). Like WebKitBrowser it is a CraBrowser hosting its own view in
/// `containerView`, so the tab, split view, the sidebar row and closing work as for any page. The
/// tab's address is `easel://<id>`; the easel itself is `Easels/<id>.json` in the data folder, with
/// its pictures in `Easels/<id>/`.
final class EaselBrowser: CraBrowser, NativePage {
    /// Arc's Peek shows the canvas on #0B0B0B, where a tab shows the space's backdrop through it.
    func usePeekLook() { canvas.layer?.backgroundColor = NSColor(white: 11.0 / 255, alpha: 1).cgColor }
    /// In a tab again (Peek's ⤢): the veiled backdrop.
    func usePageLook() { canvas.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor }

    nonisolated func owns(_ url: String) -> Bool { url == address }

    private let container: NSView
    private let canvas: EaselCanvasView
    private let address: String
    private var closed = false

    override init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?) {
        container = NSView(frame: frame)
        address = url ?? ""
        let id = url.flatMap(Easel.id(fromURL:)) ?? UUID()
        canvas = MainActor.assumeIsolated { EaselCanvasView(document: EaselFiles.load(id)) }
        super.init()
        self.delegate = delegate
        MainActor.assumeIsolated {
            container.wantsLayer = true
            container.autoresizesSubviews = true
            canvas.frame = container.bounds
            canvas.autoresizingMask = [.width, .height]
            container.addSubview(canvas)
            canvas.onTitle = { [weak self] title in
                guard let self else { return }
                self.delegate?.browser(self, didChangeTitle: title)
            }
        }
        // Like a page, it reports its address and title a turn later, once the tab holds it.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            let title = MainActor.assumeIsolated { self.canvas.document.title }
            self.delegate?.browser(self, didChangeURL: self.address)
            self.delegate?.browser(self, didChangeTitle: title)
            self.delegate?.browser?(self, didChangeCommittedLoad: true)
            self.delegate?.browser(self, didChangeLoading: false, canGoBack: false, canGoForward: false)
            self.delegate?.browser(self, didFinishLoadingURL: self.address, title: title, statusCode: 200)
            // Arc's canvas is the window's backdrop under a 50 % black veil (#63614B over a gold
            // space's #C6BE96 sidebar): the card lets the backdrop through, the canvas veils it.
            self.delegate?.browser?(self, didReportBackgroundColor: "clear")
            // A dark bar colour, so the toolbar's glyphs and address are light over the veil.
            self.delegate?.browser(self, didReportThemeColor: "#1E1E1E")
        }
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: false, profilePath: nil)
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: nil)
    }

    override var containerView: NSView { container }
    override var hostWindow: NSWindow? { nil }
    override var currentURL: String { address }
    override var currentTitle: String { MainActor.assumeIsolated { canvas.document.title } }
    override var isLoading: Bool { false }
    override var hasCommittedLoad: Bool { true }
    override var canGoBack: Bool { false }
    override var canGoForward: Bool { false }
    override var isCreated: Bool { !closed }
    override var isClosed: Bool { closed }
    override var hasDevTools: Bool { false }

    /// Another address typed into an easel's tab goes to a page of its own, as the other engine's do.
    override func loadURL(_ url: String) {
        guard url != address else { return }
        _ = delegate?.browser?(self, handsOffNavigationToURL: url, method: "GET")
    }
    override func reload() {}
    override func reloadIgnoringCache() {}
    override func stopLoading() {}
    override func goBack() {}
    override func goForward() {}
    override func setFocused(_ focused: Bool) {
        MainActor.assumeIsolated { if focused { canvas.focus() } }
    }
    override func probeBackgroundColor() {}
    override func executeJavaScript(_ script: String) {}
    override func evaluate(inIsolatedWorld world: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "an Easel has no page") }
    }
    override func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "\(method): an Easel has no page") }
    }
    override func sslStatus() -> CraSSLStatus? { nil }
    override func print() {}
    override func viewSource() {}
    override func notifyMoveOrResizeStarted() {}

    override func close() {
        guard !closed else { return }
        closed = true
        MainActor.assumeIsolated {
            canvas.saveNow()
            canvas.removeFromSuperview()
        }
        DispatchQueue.main.async { [self] in delegate?.browserDidClose(self) }
    }
}

extension EaselBrowser {
    /// PageEngines' hook: an easel's address gets its canvas.
    static func register() {
        PageEngines.nativePage = { frame, url, delegate, incognito, profilePath in
            Easel.id(fromURL: url) == nil ? nil : EaselBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        }
    }
}

/// Where easels live: one JSON file each, their pictures in a folder of the same name.
@MainActor
enum EaselFiles {
    static var folder: URL {
        let u = AppPaths.supportDir.appendingPathComponent("Easels", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func store(_ id: UUID) -> JSONStore<Easel> {
        _ = folder
        return JSONStore<Easel>("Easels/\(id.uuidString).json")
    }
    static func load(_ id: UUID) -> Easel { store(id).load(or: { Easel(id: id) }) }

    /// Arc's capture menu ▸ Send To…: the capture added below what the easel holds.
    static func add(picture png: Data, to id: UUID) -> Bool {
        guard let image = NSImage(data: png) else { return false }
        var easel = load(id)
        let name = UUID().uuidString + ".png"
        guard (try? png.write(to: pictures(id).appendingPathComponent(name))) != nil else { return false }
        let scale = min(1, 640 / max(image.size.width, image.size.height, 1))
        let bottom = easel.items.map { $0.frame.y + $0.frame.height }.max() ?? 160
        easel.items.append(Easel.Item(kind: .image(file: name), frame: .init(x: 120, y: bottom + 40, width: image.size.width * scale,
                                                                             height: image.size.height * scale)))
        store(id).saveNow(easel)
        return true
    }

    /// Arc's capture menu ▸ New Easel: an easel with the capture on it, under the title.
    static func create(withPicture png: Data) -> Easel? {
        guard let image = NSImage(data: png) else { return nil }
        var easel = Easel()
        let name = UUID().uuidString + ".png"
        guard (try? png.write(to: pictures(easel.id).appendingPathComponent(name))) != nil else { return nil }
        let scale = min(1, 640 / max(image.size.width, image.size.height, 1))
        easel.items = [Easel.Item(kind: .image(file: name), frame: .init(x: 120, y: 160, width: image.size.width * scale,
                                                                        height: image.size.height * scale))]
        store(easel.id).saveNow(easel)
        return easel
    }

    /// Every easel on disk, newest edit first, for Library ▸ Easels.
    static func all() -> [(id: UUID, title: String, edited: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> (id: UUID, title: String, edited: Date)? in
            guard let data = try? Data(contentsOf: url), let e = try? decoder.decode(Easel.self, from: data) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (e.id, e.title, date)
        }.sorted { $0.edited > $1.edited }
    }
    static func pictures(_ id: UUID) -> URL {
        let u = folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
