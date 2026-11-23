import AppKit

/// Sidebar items in arrival order, with folders created where their first tab appears: for
/// browsers that store each tab with the folders it sits in (Zen, Ardia, Yab) rather than a tree.
/// A folder is known by its id; the same URL twice in one folder comes over once.
final class ImportTree {
    private final class Node {
        var item: ImportedItem
        var kids: [Node] = []
        var folders: [String: Node] = [:]
        init(_ item: ImportedItem) { self.item = item }
        var built: ImportedItem { var it = item; if it.isFolder { it.children = kids.map(\.built) }; return it }
    }
    private let root = Node(ImportedItem(url: nil, isFolder: true))

    /// `path` runs from the outermost folder to the one the item is in.
    func insert(_ item: ImportedItem, path: [(id: String, name: String)]) {
        var n = root
        for (id, name) in path {
            if let f = n.folders[id] { n = f; continue }
            let f = Node(ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true))
            n.kids.append(f)
            n.folders[id] = f
            n = f
        }
        if !n.kids.contains(where: { !$0.item.isFolder && $0.item.url == item.url }) { n.kids.append(Node(item)) }
    }

    var items: [ImportedItem] { root.kids.map(\.built) }
}

enum ImportFavicons {
    /// Each item's favicon: one it has, else the file `own` finds for its URL in the browser's store, else its
    /// host's from `icons` (by lowercased host), written as PNGs of at most 64 px in a new folder under `folder`.
    static func attach(to plan: inout ImportPlan, folder: String, own: (String) -> URL? = { _ in nil },
                       icons: ([String]) -> [String: NSImage]) {
        func visit(_ body: (String, inout String?) -> Void) {
            func walk(_ items: inout [ImportedItem]) {
                for i in items.indices {
                    walk(&items[i].children)
                    if let url = items[i].url { body(url, &items[i].faviconPath) }
                }
            }
            walk(&plan.favorites)
            for s in plan.spaces.indices { walk(&plan.spaces[s].favorites); walk(&plan.spaces[s].pinned); walk(&plan.spaces[s].today) }
            for a in plan.archive.indices { body(plan.archive[a].url, &plan.archive[a].faviconPath) }
        }
        // Each plan writes its own files: the import preview caches icons by path.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(folder)/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [String: String] = [:]
        func write(_ image: NSImage?, as source: String) -> String? {
            if let path = written[source] { return path }
            guard let image, let png = ZenImporter.faviconPNG(image) else { return nil }
            let file = dir.appendingPathComponent("\(written.count).png")
            guard (try? png.write(to: file, options: .atomic)) != nil else { return nil }
            written[source] = file.path
            return file.path
        }

        var missing = Set<String>()
        visit { url, path in
            guard path == nil else { return }
            if let file = own(url) { path = write(NSImage(contentsOf: file), as: file.path) }
            if path == nil, let h = host(url) { missing.insert(h) }
        }
        guard !missing.isEmpty else { return }
        let found = icons(Array(missing))
        visit { url, path in
            guard path == nil, let h = host(url), let image = found[h] else { return }
            path = write(image, as: "host " + h)
        }
    }

    /// FaviconCache's key: the lowercased host.
    static func host(_ url: String) -> String? {
        URL(string: url)?.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    /// The hosts whose pages give `host` its icon: itself, and with `www.` added or dropped. A sibling
    /// subdomain never does.
    static func names(of host: String) -> [String] {
        [host, host.hasPrefix("www.") ? String(host.dropFirst(4)) : "www." + host]
    }

    /// A page's lowercased host when it is an http or https page, whatever its port.
    static func webHost(_ page: String) -> String? {
        guard let url = URL(string: page), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    /// An SQL condition on a page address `column` that holds for the pages of `host`'s `names`, under
    /// http or https and on any port.
    static func pages(of host: String, column: String) -> String {
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
        // A range per prefix rather than LIKE, so Chromium's index on page_url serves it: "0" and ";"
        // sort right after "/" and ":", the characters that can end a host.
        return names(of: host).flatMap { name in
            ["http", "https"].flatMap { scheme in
                [("/", "0"), (":", ";")].map { end, next in
                    "(\(column) >= \(quoted("\(scheme)://\(name)\(end)")) AND \(column) < \(quoted("\(scheme)://\(name)\(next)")))"
                }
            }
        }.joined(separator: " OR ")
    }
}
