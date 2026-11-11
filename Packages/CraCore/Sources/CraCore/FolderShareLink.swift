import Foundation

/// Share Folder… on a sidebar folder (GitHub #357). Arc saved the folder on arc.net, copied an
/// `arc.net/folder/…` link and said "Copied Folder URL"; whoever opened it saw the folder's tabs on
/// a web page, with or without Arc. Cra has no server, so the folder travels in the link itself:
/// its names and addresses as JSON, deflated, base64url'd, after the `#` of
/// `crabrowser.app/folder#…`. Browsers never send the part after `#` to a server, so the site only
/// serves a static page that unpacks it in the reader's browser (cra-website `src/app/folder`), and
/// nothing about the folder is stored anywhere.
///
/// The format is a promise: links people have already sent must keep opening. A change adds a new
/// `v`, it never changes what version 1 means.
///
///     {"v":1,"t":"Trip","i":[{"t":"Flights","u":"https://…"},{"t":"Hotels","i":[…]}]}
public enum FolderShareLink {
    public static let prefix = Sharing.base + "/folder#"
    public static let version = 1
    /// Names past this are cut, so one long page title doesn't make the link longer than it needs.
    public static let titleLimit = 120

    public indirect enum Node: Equatable, Sendable {
        case link(title: String, url: String)
        case folder(title: String, items: [Node])
    }

    public struct Folder: Equatable, Sendable {
        public var title: String
        public var items: [Node]

        public init(title: String, items: [Node]) {
            self.title = title
            self.items = items
        }

        /// How many links the folder holds, subfolders included.
        public var linkCount: Int { Self.count(items) }

        private static func count(_ nodes: [Node]) -> Int {
            nodes.reduce(0) { n, node in
                switch node {
                case .link: n + 1
                case .folder(_, let items): n + count(items)
                }
            }
        }
    }

    // MARK: From the sidebar

    /// The folder as it is shared: its tabs in sidebar order, a split's tabs in its place, a
    /// subfolder (or tab group) as a folder of its own. Only web pages go in (cra://, file:// and
    /// the like mean nothing to someone else), and a subfolder with none is left out.
    public static func folder(_ item: SidebarItem, children: (UUID) -> [SidebarItem]) -> Folder {
        Folder(title: clip(item.title ?? "") ?? "Folder", items: nodes(under: item.id, children: children))
    }

    private static func nodes(under id: UUID, children: (UUID) -> [SidebarItem]) -> [Node] {
        children(id).flatMap { child -> [Node] in
            if child.isSplit { return nodes(under: child.id, children: children) }
            if child.isFolder {
                let inner = nodes(under: child.id, children: children)
                return inner.isEmpty ? [] : [.folder(title: clip(child.title ?? "") ?? "Folder", items: inner)]
            }
            guard let tab = child.tab, let url = webURL(tab.liveItemURL ?? (tab.savedURL.isEmpty ? tab.url : tab.savedURL)) else { return [] }
            return [.link(title: title(of: child, tab: tab, url: url), url: url)]
        }
    }

    /// A folder tab is pinned, so it shares its pinned page under that page's name: the name the
    /// user gave it, else the title its page reported, else the host.
    private static func title(of item: SidebarItem, tab: TabData, url: String) -> String {
        let page = tab.url == tab.savedURL ? tab.savedTitle : (tab.homeTitle ?? "")
        return clip(item.title ?? "") ?? clip(page) ?? URL(string: url)?.host ?? url
    }

    /// Share N Items… on tabs picked in the sidebar (#356). Arc made an arc.net link for the
    /// selection ("Copied Shared URL"); Cra puts the picks in a folder link of their own, titled
    /// "N Tabs", so the site's page opens it as it opens a shared folder. Each pick shares the page
    /// it is on now, as Copy URLs does (without trackers), under the name the sidebar shows; a pick
    /// that isn't a web page is left out.
    public static func picked(_ items: [SidebarItem]) -> Folder {
        let links: [Node] = items.compactMap { item in
            guard let tab = item.tab, let url = webURL(CleanURL.withoutTrackers(tab.liveItemURL ?? tab.url)) else { return nil }
            return .link(title: clip(item.displayTitle) ?? URL(string: url)?.host ?? url, url: url)
        }
        return Folder(title: "\(links.count) Tabs", items: links)
    }

    // MARK: The link

    /// The link to copy, or nil for a folder with no web pages in it.
    public static func url(for folder: Folder) -> String? {
        guard folder.linkCount > 0 else { return nil }
        let wire = Wire(v: version, t: folder.title, u: nil, i: folder.items.map(Wire.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(wire),
              let deflated = try? (json as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return prefix + base64URL(deflated)
    }

    /// Reads a shared link back, as the site's page does. Anything that isn't a version-1 folder
    /// link is nil, and a link that isn't a web page is dropped, whoever made the link.
    public static func folder(from link: String) -> Folder? {
        guard link.hasPrefix(prefix),
              let data = data(base64URL: String(link.dropFirst(prefix.count))),
              let json = try? (data as NSData).decompressed(using: .zlib) as Data,
              let wire = try? JSONDecoder().decode(Wire.self, from: json), wire.v == version
        else { return nil }
        let folder = Folder(title: clip(wire.t) ?? "Folder", items: (wire.i ?? []).compactMap(node))
        return folder.linkCount > 0 ? folder : nil
    }

    private static func node(_ wire: Wire) -> Node? {
        if let items = wire.i {
            let inner = items.compactMap(node)
            return inner.isEmpty ? nil : .folder(title: clip(wire.t) ?? "Folder", items: inner)
        }
        guard let url = wire.u.flatMap(webURL) else { return nil }
        return .link(title: clip(wire.t) ?? URL(string: url)?.host ?? url, url: url)
    }

    // MARK: Helpers

    /// The key names are one letter each: they are in every link.
    private struct Wire: Codable {
        var v: Int?
        var t: String
        var u: String?
        var i: [Wire]?

        init(v: Int?, t: String, u: String?, i: [Wire]?) {
            self.v = v
            self.t = t
            self.u = u
            self.i = i
        }

        init(_ node: Node) {
            switch node {
            case .link(let title, let url): self.init(v: nil, t: title, u: url, i: nil)
            case .folder(let title, let items): self.init(v: nil, t: title, u: nil, i: items.map(Wire.init))
            }
        }
    }

    static func webURL(_ string: String) -> String? {
        guard let parts = URLComponents(string: string), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http", parts.host?.isEmpty == false
        else { return nil }
        return string
    }

    static func clip(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > titleLimit ? String(trimmed.prefix(titleLimit - 1)) + "…" : trimmed
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}
