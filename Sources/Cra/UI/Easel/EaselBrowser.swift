import AppKit
import CraCEF
import Observation

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
            canvas.profilePath = incognito ? nil : profilePath
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
            self.probeBackgroundColor()
        }
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: false, profilePath: nil)
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: nil)
    }

    override var containerView: NSView { container }
    /// View ▸ Zoom In, Zoom Out and Actual Size zoom the canvas (#580).
    override func zoomLevel() -> Double { MainActor.assumeIsolated { canvas.zoomLevel } }
    override func setZoomLevel(_ level: Double) { MainActor.assumeIsolated { canvas.zoomLevel = level } }
    var canvasView: EaselCanvasView { MainActor.assumeIsolated { canvas } }
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
    override func probeBackgroundColor() {
        // Arc's canvas is the window's backdrop under a 50 % black veil (#63614B over a gold
        // space's #C6BE96 sidebar): the card lets the backdrop through, the canvas veils it.
        delegate?.browser?(self, didReportBackgroundColor: "clear")
        // A dark bar colour, so the toolbar's glyphs and address are light over the veil.
        delegate?.browser(self, didReportThemeColor: "#1E1E1E")
    }
    override func executeJavaScript(_ script: String) {}
    override func evaluate(inIsolatedWorld world: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "an Easel has no page") }
    }
    override func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "\(method): an Easel has no page") }
    }
    override func sslStatus() -> CraSSLStatus? { nil }
    override func print() {}
    override func notifyMoveOrResizeStarted() {}

    override func close() {
        guard !closed else { return }
        closed = true
        MainActor.assumeIsolated {
            canvas.saveNow()
            EaselFiles.closed(canvas)
            canvas.closeLives()
            canvas.removeFromSuperview()
        }
        DispatchQueue.main.async { [self] in delegate?.browserDidClose(self) }
    }
}

extension EaselBrowser {
    /// PageEngines' hook: an easel's address gets its canvas.
    static func register() {
        PageEngines.isNativePage = { Easel.id(fromURL: $0) != nil }
        PageEngines.nativePage = { frame, url, delegate, incognito, profilePath in
            Easel.id(fromURL: url) == nil ? nil : EaselBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        }
    }
}

/// Where easels live: one JSON file each, their pictures in a folder of the same name.
@MainActor
enum EaselFiles {
    static var folder: URL {
        let u = AppPaths.supportDir.appendingPathComponent(SettingsSync.easelsName, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func store(_ id: UUID) -> JSONStore<Easel> {
        _ = folder
        return JSONStore<Easel>("\(SettingsSync.easelsName)/\(id.uuidString).json")
    }
    static func load(_ id: UUID) -> Easel { store(id).load(or: { Easel(id: id) }) }

    // MARK: Easels open in tabs

    /// A canvas holds what its easel is now; its file follows 0.4 s after an edit (JSONStore.save)
    /// and, after an edit, is written again when the tab closes. So whatever reads or changes an easel that is open
    /// goes through its canvas. One easel can be open on several (a tab and a Peek).
    private final class Open { weak var canvas: EaselCanvasView? }
    private static var open: [UUID: [Open]] = [:]

    static func opened(_ canvas: EaselCanvasView) {
        let entry = Open()
        entry.canvas = canvas
        open[canvas.document.id] = (open[canvas.document.id] ?? []).filter { $0.canvas != nil } + [entry]
    }

    static func closed(_ canvas: EaselCanvasView) {
        let id = canvas.document.id
        open[id]?.removeAll { $0.canvas == nil || $0.canvas === canvas }
        if open[id]?.isEmpty == true { open[id] = nil }
    }

    /// Every canvas showing the easel, the one opened last at the end.
    static func canvases(for id: UUID) -> [EaselCanvasView] { open[id]?.compactMap(\.canvas) ?? [] }

    static func canvas(for id: UUID) -> EaselCanvasView? { canvases(for: id).last }

    /// The easel as it is now: its canvas's, or its file's.
    static func current(_ id: UUID) -> Easel { canvas(for: id)?.document ?? load(id) }

    /// Library ▸ Easels and the capture menu list the easels: this counts the changes they show
    /// (one made, renamed, deleted, a capture added), so a list on screen follows.
    @Observable final class Changes {
        @MainActor static let shared = Changes()
        var count = 0
    }

    static func listChanged() { Changes.shared.count += 1 }

    /// Sync's change to an easel open in a tab, made on each of its canvases: `change` gets what that canvas
    /// shows and returns the easel it shows next, nil to delete it. False when no tab has it open, or it
    /// was deleted here: that canvas saves nothing, so the service writes the file.
    static func changeOpen(_ id: UUID, _ change: (Easel) -> Easel?) -> Bool {
        let shown = canvases(for: id)
        guard !deleted.contains(id), !shown.isEmpty else { return false }
        for each in shown {
            // Deleted on the other Mac (nil for every canvas): the closing canvases write nothing back;
            // their tabs close with `closeTabs`.
            guard let new = change(each.document) else { delete(id); return true }
            if new != each.document { each.replace(with: new) }
        }
        return true
    }

    /// After sync changed the easels: Library lists them again, and one deleted here that a bundle
    /// brought back (Import) saves again, its canvases still loaded (a Favorite) showing Import's copy.
    static func synced() {
        let back = deleted.filter { FileManager.default.fileExists(atPath: store($0).url.path) }
        deleted.subtract(back)
        for id in back {
            let easel = load(id)
            for canvas in canvases(for: id) { canvas.replace(with: easel) }
        }
        listChanged()
    }

    /// Easels deleted this session: a tab still closing must not write one back.
    static var deleted: Set<UUID> = []

    /// Runs the removal a second after a delete; a test runs it when it chooses.
    static var afterDelete: (@escaping @MainActor @Sendable () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: $0)
    }

    /// Deleting from Library ▸ Easels: the easel's file and its pictures.
    static func delete(_ id: UUID) {
        deleted.insert(id)
        EaselFolder.remove(id, in: folder)
        // An edit made just before is written 0.4 s later (JSONStore.save): remove what it writes too, unless Import or
        // a drawing brought the easel back since.
        afterDelete { if deleted.contains(id) { EaselFolder.remove(id, in: folder) } }
        listChanged()
    }

    /// An easel going (Library ▸ Easels ▸ Delete, or deleted on another Mac): every tab showing it
    /// closes through `close`, and none writes it back.
    static func closeTabs(of id: UUID, in store: SidebarStore, close: (UUID) -> Void) {
        deleted.insert(id)
        let url = Easel(id: id).url
        for tab in store.allTabs() where tab.tab?.url == url { close(tab.id) }
    }

    /// Arc's capture menu ▸ Send To…: the capture added below what the easel holds. With `source`
    /// (the page it came from) it is a capture that can go live, else a plain picture.
    static func add(picture png: Data, to id: UUID, source: Easel.Capture? = nil) -> Bool {
        var easel = current(id)
        let bottom = easel.items.map { $0.frame.y + $0.frame.height }.max() ?? 160
        guard let item = captureItem(png, easel: id, source: source, at: .init(120, bottom + 40)) else { return false }
        defer { listChanged() }
        // Open in a tab: onto its canvas, which shows it at once and saves it. Written to the file
        // behind the canvas's back, the picture was gone as soon as the canvas saved again.
        if let canvas = canvas(for: id) {
            canvas.sheetView.insert(item)
            return true
        }
        easel.items.append(item)
        store(id).saveNow(easel)
        return true
    }

    /// File ▸ New Easel: an empty easel, on disk before its tab opens (a canvas writes none), so Library ▸ Easels lists it.
    static func create() -> Easel {
        let easel = Easel()
        store(easel.id).saveNow(easel)
        listChanged()
        return easel
    }

    /// Arc's capture menu ▸ New Easel: an easel with the capture on it, under the title.
    static func create(withPicture png: Data, source: Easel.Capture? = nil) -> Easel? {
        var easel = Easel()
        guard let item = captureItem(png, easel: easel.id, source: source, at: .init(120, 160)) else { return nil }
        easel.items = [item]
        store(easel.id).saveNow(easel)
        listChanged()
        return easel
    }

    private static func captureItem(_ png: Data, easel id: UUID, source: Easel.Capture?, at p: Easel.Point) -> Easel.Item? {
        guard let image = NSImage(data: png) else { return nil }
        let name = UUID().uuidString + ".png"
        guard (try? png.write(to: pictures(id).appendingPathComponent(name))) != nil else { return nil }
        // The capture's size on the page, at most 640 pt across.
        let size = source?.area.map { NSSize(width: $0.width, height: $0.height) } ?? image.size
        let scale = min(1, 640 / max(size.width, size.height, 1))
        let frame = Easel.Rect(x: p.x, y: p.y, width: size.width * scale, height: size.height * scale)
        guard var capture = source else { return Easel.Item(kind: .image(file: name), frame: frame) }
        capture.image = name
        return Easel.Item(kind: .capture(capture), frame: frame)
    }

    /// Every easel on disk, newest edit first, for Library ▸ Easels.
    static func all() -> [(id: UUID, title: String, edited: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let decoder = JSONDecoder()
        var listed = files.filter { $0.pathExtension == "json" }.compactMap { url -> (id: UUID, title: String, edited: Date)? in
            guard let data = try? Data(contentsOf: url), let e = try? decoder.decode(Easel.self, from: data) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            // An easel open in a tab has the name on its canvas; its file gets it a moment later.
            return (e.id, canvas(for: e.id)?.document.title ?? e.title, date)
        }
        for id in open.keys where !deleted.contains(id) && !listed.contains(where: { $0.id == id }) {
            if let canvas = canvas(for: id) { listed.append((id, canvas.document.title, Date())) }
        }
        return listed.sorted { $0.edited > $1.edited }
    }
    static func pictures(_ id: UUID) -> URL {
        let u = folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
