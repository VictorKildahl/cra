import Foundation

/// The Mac's sidebar as the iPhone shows it: Arc Search's Spaces view lists each Space's pinned
/// tabs and folders, then its Today tabs, one Space per page. Read from the `sidebar.json` the
/// Mac app syncs (`SettingsSync`); the phone opens things from it and does not write it.
public enum MobileSpaces {
    public struct Row: Equatable, Identifiable {
        public enum Kind: Equatable {
            case tab(url: String)
            case folder
            /// The line between the pinned part and Today.
            case todayHeader
        }

        public var id: UUID
        public var kind: Kind
        public var title: String
        /// How deep inside folders the row sits.
        public var depth: Int
    }

    public struct SpaceView: Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// The Space's emoji, or empty when it uses a symbol.
        public var emoji: String
        public var symbol: String?
        /// The theme's colours as "#RRGGBB".
        public var colors: [String]
        public var rows: [Row]
    }

    /// Every Space in the Mac's order, with its favorites and pinned items (folders opened out
    /// unless listed in `closedFolders`), then its Today tabs. Blank-window spaces are left out.
    public static func spaces(in document: SidebarDocument, closedFolders: Set<UUID> = []) -> [SpaceView] {
        let items = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(document.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = document.spaceOrder.compactMap { byID[$0] } + document.spaces.filter { !document.spaceOrder.contains($0.id) }

        func rows(under parent: UUID, depth: Int) -> [Row] {
            guard let container = items[parent] else { return [] }
            return container.children.flatMap { id -> [Row] in
                guard let item = items[id] else { return [] }
                switch item.data {
                case .tab(let tab):
                    let title = item.title ?? (tab.savedTitle.isEmpty ? (URL(string: tab.url)?.host ?? tab.url) : tab.savedTitle)
                    return [Row(id: id, kind: .tab(url: tab.url), title: title, depth: depth)]
                case .folder:
                    let folder = Row(id: id, kind: .folder, title: item.title ?? "Folder", depth: depth)
                    return [folder] + (closedFolders.contains(id) ? [] : rows(under: id, depth: depth + 1))
                case .split, .container:
                    // A split's tabs are its children: listed one by one.
                    return rows(under: id, depth: depth)
                }
            }
        }

        return ordered.filter { $0.standaloneWindowID == nil }.map { space in
            let pinned = rows(under: space.favoritesContainerID, depth: 0) + rows(under: space.pinnedContainerID, depth: 0)
            let today = rows(under: space.todayContainerID, depth: 0)
            let header = today.isEmpty ? [] : [Row(id: space.todayContainerID, kind: .todayHeader, title: "Today", depth: 0)]
            return SpaceView(id: space.id, title: space.title, emoji: space.emoji, symbol: space.symbol,
                             colors: space.theme.colors, rows: pinned + header + today)
        }
    }

    /// Reads a synced `sidebar.json`.
    public static func document(from data: Data) -> SidebarDocument? {
        try? JSONDecoder().decode(SidebarDocument.self, from: data)
    }
}

extension MobileSpaces {
    /// The Spaces sheet's colour and its text: the Space's first colour softened a third of the
    /// way to white, and white text where that comes out dark enough (Arc Search's purple Space,
    /// #a687c8 in TidBITS' screenshot, has white text).
    public struct SheetStyle: Equatable {
        public var fill: String
        public var lightText: Bool

        public init(fill: String, lightText: Bool) {
            self.fill = fill
            self.lightText = lightText
        }
    }

    public static func sheetStyle(colors: [String]) -> SheetStyle? {
        guard let first = colors.first, let c = HexColor.components(first) else { return nil }
        func softened(_ v: Double) -> Double { v + (1 - v) * 0.35 }
        let (r, g, b) = (softened(c.r), softened(c.g), softened(c.b))
        let fill = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        return SheetStyle(fill: fill, lightText: (HexColor.luminance(fill) ?? 1) < 0.62)
    }
}

/// "Favorite in App": the sites the phone keeps under the empty search field. `favorites.json`.
public struct MobileFavorites: Codable, Equatable {
    public struct Site: Codable, Equatable, Identifiable {
        public var url: String
        public var title: String
        public var id: String { url }

        public init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    public var sites: [Site] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
    }

    private enum CodingKeys: String, CodingKey { case sites }

    /// A page counts as the favorite of its address without tracking parameters or fragment.
    static func key(_ url: String) -> String {
        var clean = CleanURL.withoutTrackers(url)
        if let hash = clean.firstIndex(of: "#") { clean = String(clean[..<hash]) }
        return clean.hasSuffix("/") ? String(clean.dropLast()) : clean
    }

    public func contains(_ url: String) -> Bool {
        sites.contains { Self.key($0.url) == Self.key(url) }
    }

    /// Adds the page, or removes it when it is already a favorite. Returns whether it is one now.
    @discardableResult
    public mutating func toggle(url: String, title: String) -> Bool {
        if contains(url) {
            sites.removeAll { Self.key($0.url) == Self.key(url) }
            return false
        }
        sites.append(Site(url: url, title: title.isEmpty ? (URL(string: url)?.host ?? url) : title))
        return true
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard sites.indices.contains(source), (0..<sites.count).contains(destination) else { return }
        sites.insert(sites.remove(at: source), at: destination)
    }

    /// What shows under the empty search field: the first four, as in Arc Search.
    public func shown(limit: Int = MobileSearchSheet.visibleRows) -> [Site] {
        Array(sites.prefix(limit))
    }
}
