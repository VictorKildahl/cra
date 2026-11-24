import Foundation

/// The import window's tiles that count what came over, each with its own report.
public enum ImportKind: Hashable, Sendable, CaseIterable {
    /// Pinned and Today tabs, and bookmarks.
    case tabs
    case favorites
    case archive

    /// "42 of 42 tabs", "12 of 12 favorites"; the archive tile counts tabs too, as it does before
    /// the import, and "1500 of 1501 archived" doesn't fit the tile.
    func summary(copied: Int, total: Int) -> String {
        let noun = self == .favorites ? "favorite" : "tab"
        return total == 0 ? "No \(noun)s" : "\(copied) of \(total) \(noun)\(total == 1 ? "" : "s")"
    }
}

/// Why an import left an item of the source browser out.
public enum ImportSkipReason: Equatable, Sendable {
    /// An address that isn't a web page, where an importer still takes web pages only (Dia's archive).
    case notAWebPage
    /// Past the newest `limit` archived tabs, all Cra takes of the source's archive.
    case olderArchive(limit: Int)
    /// A tab in a live folder that stands for none of its items: the folder fills itself.
    case notALiveItem
    /// A whole file of the source (an encrypted session, a damaged one) that could not be read.
    case unreadable
    /// Cra's own cra: address, which an import leaves behind (ImportedAddress.keeps).
    case craAddress
    /// A blob: or Firefox's place: query, which only the browser that made it can open.
    case onlyInItsBrowser

    public var text: String {
        switch self {
        case .notAWebPage: return "Not a web page"
        case .olderArchive(let limit): return "Older than the newest \(limit) archived tabs"
        case .notALiveItem: return "Not one of the live folder's items"
        case .unreadable: return "Could not be read"
        case .craAddress: return "Cra's own address"
        case .onlyInItsBrowser: return "Only works in the browser it came from"
        }
    }
}

/// One row of a tile's skipped list.
public struct ImportSkip: Equatable, Sendable {
    public var title: String
    /// The item's address, or the path of a file that could not be read.
    public var url: String
    public var reason: ImportSkipReason
    /// The tile that lists it.
    public var kind: ImportKind
    /// The source's list a left-out favorite is on, when it isn't its space's (Arc: its Top Apps
    /// container): spaces showing that list each carry the row, which is listed once.
    public var favoritesList: String?

    public init(title: String, url: String, reason: ImportSkipReason, kind: ImportKind = .tabs, favoritesList: String? = nil) {
        self.title = title
        self.url = url
        self.reason = reason
        self.kind = kind
        self.favoritesList = favoritesList
    }

    /// A page an importer refuses for not being a web page (Dia's archive), listed as the address rule
    /// lists it (`leftOut`): nil for no address or a blank or new tab page, which was never a tab.
    public static func notAWebPage(_ url: String?, title: String, kind: ImportKind = .tabs) -> ImportSkip? {
        guard let url, !url.isEmpty else { return nil }
        if let skip = leftOut(url, title: title, kind: kind) { return skip }
        return ImportedAddress.keeps(url) ? ImportSkip(title: title, url: url, reason: .notAWebPage, kind: kind) : nil
    }

    /// A tab or bookmark an import leaves behind for its address (ImportedAddress.leftOut); nil when
    /// it comes over or, as a blank or new tab page, was never a tab.
    public static func leftOut(_ url: String?, title: String, kind: ImportKind = .tabs) -> ImportSkip? {
        guard let url, let reason = ImportedAddress.leftOut(url) else { return nil }
        return ImportSkip(title: title, url: url, reason: reason, kind: kind)
    }

    /// A file that could not be read ("Open tabs", "Bookmarks"): one row on the tabs tile, since
    /// how many items it held is unknown.
    public static func unreadable(_ what: String, file: String) -> ImportSkip {
        ImportSkip(title: what, url: file, reason: .unreadable)
    }
}

/// What one import copied of one kind of item, and what it left out: a tile's "N of M" and its list.
public struct ImportReport: Equatable, Sendable {
    public var kind: ImportKind
    /// Items now in Cra, counting those it already had from an earlier import.
    public var copied: Int
    public var skipped: [ImportSkip]

    public init(_ kind: ImportKind, copied: Int = 0, skipped: [ImportSkip] = []) {
        self.kind = kind
        self.copied = copied
        self.skipped = skipped
    }

    /// Every item with an address the import read; an unreadable file adds none.
    public var total: Int { copied + skipped.filter { $0.reason != .unreadable }.count }

    public var summary: String { kind.summary(copied: copied, total: total) }

    /// `summary` without its noun ("1500 of 1501"), for a tile too narrow for the whole line.
    public var shortSummary: String { total == 0 ? summary : "\(copied) of \(total)" }

    /// The tile shows when it has anything to count or to list.
    public var isShown: Bool { total > 0 || !skipped.isEmpty }

    /// The skipped list for the pasteboard: a line an item, title, address and reason apart by tabs.
    public var plainText: String {
        skipped.map { [$0.title, $0.url, $0.reason.text].joined(separator: "\t") }.joined(separator: "\n")
    }
}

/// One import's reports, a tile each.
public struct ImportReports: Equatable, Sendable {
    private var reports: [ImportKind: ImportReport]

    /// `favorites` are the addresses of the favorites that came over, each with the source's list it
    /// is on, and `skipped` pairs each skip with its list. A list several spaces show (an Arc Top Apps
    /// container, Zen's Essentials, Yab's shared tiles) counts, and lists a left-out favorite, once per address.
    public init(tabs: Int, favorites: [(list: String, url: String)], archive: Int, skipped: [(list: String, skip: ImportSkip)]) {
        var listed = Set<[String]>()
        let rows = skipped.filter { $0.skip.kind != .favorites || listed.insert([$0.list, $0.skip.url]).inserted }.map(\.skip)
        let copied: [ImportKind: Int] = [.tabs: tabs, .favorites: Set(favorites.map { [$0.list, $0.url] }).count, .archive: archive]
        reports = Dictionary(uniqueKeysWithValues: ImportKind.allCases.map { kind in
            (kind, ImportReport(kind, copied: copied[kind] ?? 0, skipped: rows.filter { $0.kind == kind }))
        })
    }

    public subscript(kind: ImportKind) -> ImportReport {
        get { reports[kind] ?? ImportReport(kind) }
        set { reports[kind] = newValue }
    }
}
