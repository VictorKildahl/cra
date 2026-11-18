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
    /// Each tab's favicon from the source browser's own store (`icons` by lowercased host), written
    /// as small PNGs under a temporary `folder` where the plan's copy step picks them up.
    static func attach(to spaces: inout [ImportedSpace], folder: String, icons: ([String]) -> [String: NSImage]) {
        func hosts(_ items: [ImportedItem]) -> [String] { items.flatMap { $0.isFolder ? hosts($0.children) : [$0.url.flatMap(host)].compactMap { $0 } } }
        let allHosts = Set(spaces.flatMap { hosts($0.favorites) + hosts($0.pinned) + hosts($0.today) })
        guard !allHosts.isEmpty else { return }
        let found = icons(Array(allHosts))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        for (host, img) in found {
            guard let png = ZenImporter.faviconPNG(img) else { continue }
            let file = dir.appendingPathComponent("\(files.count).png")
            if (try? png.write(to: file, options: .atomic)) != nil { files[host] = file.path }
        }
        func withIcons(_ items: [ImportedItem]) -> [ImportedItem] {
            items.map { var it = $0; it.children = withIcons(it.children); it.faviconPath = it.url.flatMap(host).flatMap { files[$0] } ?? it.faviconPath; return it }
        }
        for i in spaces.indices {
            spaces[i].favorites = withIcons(spaces[i].favorites)
            spaces[i].pinned = withIcons(spaces[i].pinned)
            spaces[i].today = withIcons(spaces[i].today)
        }
    }

    /// FaviconCache's key: the lowercased host.
    static func host(_ url: String) -> String? {
        URL(string: url)?.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }
}
