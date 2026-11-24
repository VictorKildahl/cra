import AppKit
import CryptoKit
import Foundation

// Importers read Arc's and Dia's on-disk stores (see docs/arc-reverse-engineering.md)
// into a neutral ImportPlan that the store applies.

struct ImportedItem {
    var customTitle: String?
    var pageTitle: String = ""
    var url: String?
    var isFolder = false
    var children: [ImportedItem] = []
    var createdAt = Date()
    /// Cached favicon file in the source browser, if any.
    var faviconPath: String?
    /// A live folder's source and filter (Arc's GitHub live folder, #215): it keeps refreshing.
    var liveFolder: LiveFolderData?
    /// The live item a tab in a live folder stands for (Arc: `liveItemID.url`).
    var liveItemURL: String?
    /// The source's list a favorite came from, when it isn't its space's (Arc: the Top Apps
    /// container a space shows or borrows). The favorites tile counts each list once.
    var favoritesList: String?
}

struct ImportedSpace {
    var title: String
    var emoji: String
    /// An SF Symbol shown instead of `emoji` (then empty): Arc's Icon-tab glyphs.
    var symbol: String? = nil
    var theme: SpaceTheme?
    /// The space's own favorites (Arc: the top apps of the space's profile).
    var favorites: [ImportedItem] = []
    var pinned: [ImportedItem] = []
    var today: [ImportedItem] = []
    /// The source browser's profile the space was on, when it is not Default (Arc, GitHub #131).
    var profile: ImportedProfile?
    /// The source's list `favorites` is, when spaces share it (Zen's Essentials, Yab's shared tiles);
    /// nil for the space's own. A favorite's own `favoritesList` comes first.
    var favoritesList: String?
    /// What the importer left out of this space, listed after the import.
    var skipped: [ImportSkip] = []
}

/// A Chromium profile of the source browser: its folder under `User Data` and the name it shows.
struct ImportedProfile: Hashable {
    var folder: String
    var name: String
}

struct ImportedArchiveEntry {
    var customTitle: String?
    var pageTitle: String
    var url: String
    var archivedAt: Date
    var reason: ArchiveReason
    var spaceTitle: String?
    /// Cached favicon file in the source browser, if any.
    var faviconPath: String? = nil
}

/// Air Traffic Control destinations name spaces by title; ids differ between browsers.
enum ImportedLinkDestination {
    case mostRecentSpace
    case space(title: String)
    case littleWindow(spaceTitle: String?)
}

struct ImportedLinkRoute {
    var match: LinkMatchStyle
    var text: String
    var destination: ImportedLinkDestination
}

/// The profile folder picked for a site in a Little Arc.
struct ImportedSiteProfile: Equatable {
    var site: String
    var folder: String
}

struct ImportedSettings {
    var autoArchive: AutoArchiveThreshold?
    var sidebarWidth: Double?
    var showToolbar: Bool?
    var toolbarShowsFullURL: Bool?
    var linkRoutes: [ImportedLinkRoute] = []
    var defaultLinkDestination: ImportedLinkDestination?
    /// Arc's domainToProfilePreferences, by site, so two reads of one file are equal.
    var siteProfiles: [ImportedSiteProfile] = []

    var isEmpty: Bool {
        autoArchive == nil && sidebarWidth == nil && showToolbar == nil && toolbarShowsFullURL == nil && linkRoutes.isEmpty && defaultLinkDestination == nil
            && siteProfiles.isEmpty
    }
}

struct ImportPlan {
    var source: String
    var spaces: [ImportedSpace] = []
    /// Favorites that belong to no imported space; they go to the focused space.
    var favorites: [ImportedItem] = []
    var archive: [ImportedArchiveEntry] = []
    var settings = ImportedSettings()
    /// What the importer left out that belongs to no space it brings, listed after the import.
    var skipped: [ImportSkip] = []
    /// Archived tabs the importer left out, listed when the archive comes over.
    var archiveSkipped: [ImportSkip] = []

    var tabCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
    }
    var folderCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? 1 + count($1.children) : 0) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
    }

    /// The plan restricted to what the user picked.
    func selecting(spaces: Set<Int>, favorites: Bool) -> ImportPlan {
        var p = self
        p.spaces = spaces.sorted().compactMap { $0 < self.spaces.count ? self.spaces[$0] : nil }
        if !favorites {
            p.favorites = []
            // What was left out of the favorites of no space goes with them.
            p.skipped.removeAll { $0.kind == .favorites }
        }
        return p
    }

    /// What the import counts and lists, a tile each: the spaces' pinned and Today tabs, the
    /// favorites, the archive when it comes over, and the skips that go with them. Favorites of no
    /// space are a list of their own ("").
    func report(includeArchive: Bool) -> ImportReports {
        func urls(_ items: [ImportedItem]) -> [String] { items.flatMap { $0.isFolder ? urls($0.children) : [$0.url].compactMap { $0 } } }
        let lists = spaces.enumerated().map { i, sp in sp.favoritesList.map { "list " + $0 } ?? "space \(i)" }
        let favorites = urls(favorites).map { (list: "", url: $0) } + spaces.indices.flatMap { i in
            spaces[i].favorites.flatMap { item in urls([item]).map { (list: item.favoritesList.map { "list " + $0 } ?? lists[i], url: $0) } }
        }
        let skips = spaces.indices.flatMap { i in spaces[i].skipped.map { (list: $0.favoritesList.map { "list " + $0 } ?? lists[i], skip: $0) } }
            + (skipped + (includeArchive ? archiveSkipped : [])).map { (list: "", skip: $0) }
        return ImportReports(tabs: spaces.reduce(0) { $0 + $1.itemCount }, favorites: favorites, archive: includeArchive ? archive.count : 0, skipped: skips)
    }
}

extension ImportedSpace {
    var itemCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return count(pinned) + count(today)
    }
}

enum ImportError: LocalizedError {
    case notFound(String)
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let s): return "\(s) data was not found on this Mac."
        case .unreadable(let s): return "Could not read \(s)."
        }
    }
}

private func refDate(_ v: Any?) -> Date {
    if let d = v as? Double { return Date(timeIntervalSinceReferenceDate: d) }
    return Date()
}

/// Arc stores `[id, object, id, object…]` for ordered dictionaries.
private func pairs(_ list: Any?) -> [(String, [String: Any])] {
    guard let arr = list as? [Any] else { return [] }
    var out: [(String, [String: Any])] = []
    var i = 0
    while i + 1 < arr.count {
        if let id = arr[i] as? String, let obj = arr[i + 1] as? [String: Any] { out.append((id, obj)); i += 2 }
        else { i += 1 }
    }
    return out
}

/// Arc wraps an enum case's value as `{case: {_0: value}}`.
private func tagged<T>(_ value: Any?, _ key: String) -> T? {
    ((value as? [String: Any])?[key] as? [String: Any])?["_0"] as? T
}

// MARK: - Arc

enum ArcImporter {
    /// CRA_ARC_DIR points a test instance at a made-up profile (Tests/Fixtures/Arc).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_ARC_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Arc", isDirectory: true)

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableSidebar.json").path) }

    /// Arc's Chromium profiles: Default and "Profile <n>", one per profile a space can be on.
    static var userData: URL { supportDir.appendingPathComponent("User Data", isDirectory: true) }

    /// Arc's View ▸ Show Toolbar (topBarURLEnabled, off by default); nil when Arc never stored it.
    static var showsToolbar: Bool? {
        UserDefaults(suiteName: "company.thebrowser.Browser")?.object(forKey: "topBarURLEnabled") as? Bool
    }

    /// Arc's "Show Full URL" on the toolbar address (off by default); nil when Arc never stored it.
    static var showsFullURL: Bool? {
        UserDefaults(suiteName: "company.thebrowser.Browser")?.object(forKey: "toolbarShowFullURLsEnabledPreference") as? Bool
    }

    /// Arc's domainToProfilePreferences: site → profile folder ("Default", "Profile 1"), written when a
    /// profile is picked in a Little Arc. Under CRA_ARC_DIR it is the fixture's
    /// company.thebrowser.Browser.plist, so a test never reads this Mac's Arc.
    static var siteProfileFolders: [String: String] {
        let key = "domainToProfilePreferences"
        if ProcessInfo.processInfo.environment["CRA_ARC_DIR"] != nil {
            return NSDictionary(contentsOf: supportDir.appendingPathComponent("company.thebrowser.Browser.plist"))?[key] as? [String: String] ?? [:]
        }
        return UserDefaults(suiteName: "company.thebrowser.Browser")?.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// With `favicons` (a User Data folder, for an import), a tab Arc's caches have no icon for takes its
    /// host's from the Favicons databases there. Rebuild from Arc reads only the spaces and skips them.
    static func plan(favicons userData: URL? = nil) throws -> ImportPlan {
        let url = supportDir.appendingPathComponent("StorableSidebar.json")
        guard let data = try? Data(contentsOf: url) else { throw ImportError.notFound("Arc") }
        var plan = try plan(sidebar: data)
        if let userData { ImportFavicons.attach(to: &plan, folder: "cra-arc-favicons", from: ImportSource.Kind.arc.iconStores(dataDir: userData)) }
        return plan
    }

    /// The plan from a StorableSidebar.json's contents and a StorableArchiveItems.json's (favicons
    /// and profiles still come from `supportDir`).
    static func plan(sidebar data: Data,
                     archive: Data? = try? Data(contentsOf: supportDir.appendingPathComponent("StorableArchiveItems.json"))) throws -> ImportPlan {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]] else { throw ImportError.unreadable("Arc's sidebar") }
        var plan = ImportPlan(source: "Arc")
        // A file can hold an older spaces container ahead of the real one, one untitled space with an
        // empty Today (#749): take the one holding the most items, the first of equals.
        guard let main = containers.filter({ $0["spaces"] != nil })
            .max(by: { pairs($0["items"]).count < pairs($1["items"]).count }) else { return plan }
        // A damaged file can list an id twice: the later entry wins, as when Arc decodes it.
        let items = Dictionary(pairs(main["items"]), uniquingKeysWith: { _, later in later })
        var spaceTitleByID: [String: String] = [:]
        // What `convert` leaves out, taken by the list being converted.
        var refused: [ImportSkip] = []

        func convert(_ id: String) -> ImportedItem? {
            guard let it = items[id], let dataDict = it["data"] as? [String: Any] else { return nil }
            let custom = it["title"] as? String
            let created = refDate(it["createdAt"])
            let childIDs = it["childrenIds"] as? [String] ?? []
            if let tab = dataDict["tab"] as? [String: Any] {
                guard let u = tab["savedURL"] as? String, ImportedAddress.keeps(u) else {
                    ImportSkip.leftOut(tab["savedURL"] as? String, title: custom ?? tab["savedTitle"] as? String ?? "").map { refused.append($0) }
                    return nil
                }
                return ImportedItem(customTitle: custom, pageTitle: tab["savedTitle"] as? String ?? "", url: u, createdAt: created,
                                    faviconPath: faviconFile(forItemID: id), liveItemURL: tagged(tab["liveItemID"], "url"))
            }
            if let list = dataDict["list"] as? [String: Any] {
                return ImportedItem(customTitle: custom, pageTitle: custom ?? "Folder", url: nil, isFolder: true,
                                    children: childIDs.compactMap(convert), createdAt: created,
                                    liveFolder: liveFolder(list["automaticLiveFolderData"]))
            }
            if dataDict["splitView"] != nil || dataDict["tabGroup"] != nil {
                // Flatten split views into their tabs.
                let kids = childIDs.compactMap(convert)
                return kids.count == 1 ? kids[0] : ImportedItem(customTitle: custom ?? "Split", pageTitle: "", url: nil, isFolder: true, children: kids, createdAt: created)
            }
            return nil
        }

        // Each space is on a Chromium profile in User Data, named as Arc's space menu shows it.
        let profileNames = ChromiumImporter.profileNames(userData: userData)

        // Favorites (topApps): one container per profile, shared by that profile's spaces.
        var favoritesByProfile: [(profile: NSDictionary, id: String, items: [ImportedItem])] = []
        var allFavorites: [ImportedItem] = [], favoritesSkipped: [String: [ImportSkip]] = [:]
        for (id, it) in items {
            guard let d = it["data"] as? [String: Any], let c = d["itemContainer"] as? [String: Any],
                  let type = c["containerType"] as? [String: Any], let top = type["topApps"] as? [String: Any] else { continue }
            let favs = (it["childrenIds"] as? [String] ?? []).compactMap(convert).map { var f = $0; f.favoritesList = id; return f }
            // A favorite left out goes with every space that shows its list, and is listed once.
            favoritesSkipped[id] = refused.map { var s = $0; s.kind = .favorites; s.favoritesList = id; return s }
            refused = []
            allFavorites += favs
            if let profile = top["_0"] as? NSDictionary { favoritesByProfile.append((profile, id, favs)) }
        }

        for (sid, space) in pairs(main["spaces"]) {
            let title = space["title"] as? String ?? "Space"
            spaceTitleByID[sid] = title
            // An emoji, an Icon-tab glyph as Cra's symbol in that slot, or no icon (a dot, #252).
            let icon = ArcSpaceIcon.icon((space["customInfo"] as? [String: Any])?["iconType"] as? [String: Any],
                                         symbolExists: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
            var pinnedID: String?, todayID: String?
            if let ids = space["containerIDs"] as? [Any] {
                var i = 0
                while i + 1 < ids.count {
                    if let k = ids[i] as? String, let v = ids[i + 1] as? String {
                        if k == "pinned" { pinnedID = v } else if k == "unpinned" { todayID = v }
                    }
                    i += 2
                }
            }
            // A space without a theme is Arc's default dark purple, close to Ink. Not the next
            // preset: that shifted every later space onto another colour (issue #30).
            var sp = ImportedSpace(title: title, emoji: icon.emoji, symbol: icon.symbol, theme: ArcThemeImport.theme(from: space) ?? SpaceTheme.presets[0])
            let profile = space["profile"] as? NSDictionary
            let own = favoritesByProfile.first { $0.profile.isEqual(profile) }
            sp.favorites = own?.items ?? allFavorites
            sp.skipped = own.map { favoritesSkipped[$0.id] ?? [] } ?? favoritesSkipped.keys.sorted().flatMap { favoritesSkipped[$0] ?? [] }
            sp.profile = ImportProfileMap.arcProfileFolder(space["profile"]).map { ImportedProfile(folder: $0, name: profileNames[$0] ?? $0) }
            if let p = pinnedID, let c = items[p] { sp.pinned = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            if let t = todayID, let c = items[t] { sp.today = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            sp.skipped += refused
            refused = []
            plan.spaces.append(sp)
        }

        // Archive
        if let adata = archive,
           let aroot = try? JSONSerialization.jsonObject(with: adata) as? [String: Any],
           let aitems = aroot["items"] as? [Any] {
            for case let e as [String: Any] in aitems {
                guard let si = e["sidebarItem"] as? [String: Any], let d = si["data"] as? [String: Any],
                      let tab = d["tab"] as? [String: Any] else { continue }
                guard let u = tab["savedURL"] as? String, ImportedAddress.keeps(u) else {
                    let title = si["title"] as? String ?? tab["savedTitle"] as? String ?? ""
                    ImportSkip.leftOut(tab["savedURL"] as? String, title: title, kind: .archive).map { plan.archiveSkipped.append($0) }
                    continue
                }
                let reason = (e["reason"] as? String) == "auto" ? ArchiveReason.auto : .manual
                var spaceTitle: String?
                if let src = e["source"] as? [String: Any], let sp = src["space"] as? [String: Any], let id = sp["_0"] as? String { spaceTitle = spaceTitleByID[id] }
                plan.archive.append(ImportedArchiveEntry(customTitle: si["title"] as? String, pageTitle: tab["savedTitle"] as? String ?? "",
                                                         url: u, archivedAt: refDate(e["archivedAt"]), reason: reason, spaceTitle: spaceTitle,
                                                         faviconPath: (si["id"] as? String).flatMap { faviconFile(forItemID: $0, in: "ArchiveItemsFaviconCache") }))
            }
            plan.archive.sort { $0.archivedAt > $1.archivedAt }
            if plan.archive.count > 1500 {
                plan.archiveSkipped += plan.archive[1500...].map {
                    ImportSkip(title: $0.customTitle ?? $0.pageTitle, url: $0.url, reason: .olderArchive(limit: 1500), kind: .archive)
                }
                plan.archive.removeLast(plan.archive.count - 1500)
            }
        }

        // Settings
        if let wdata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableWindows.json")),
           let wroot = try? JSONSerialization.jsonObject(with: wdata) as? [String: Any],
           let prefs = wroot["sidebarViewPreferences"] as? [String: Any], let w = prefs["sidebarWidth"] as? Double {
            plan.settings.sidebarWidth = w
        }
        if let threshold = UserDefaults(suiteName: "company.thebrowser.Browser")?.string(forKey: "autoArchiveTimeThreshold") {
            plan.settings.autoArchive = AutoArchiveThreshold(rawValue: threshold)
        }
        plan.settings.showToolbar = showsToolbar
        plan.settings.toolbarShowsFullURL = showsFullURL
        plan.settings.siteProfiles = siteProfileFolders.sorted { $0.key < $1.key }.map { ImportedSiteProfile(site: $0.key, folder: $0.value) }
        if let ldata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableLinkRouting.json")),
           let lroot = try? JSONSerialization.jsonObject(with: ldata) as? [String: Any] {
            plan.settings.defaultLinkDestination = linkDestination(lroot["defaultDestination"], spaceTitles: spaceTitleByID)
            plan.settings.linkRoutes = (lroot["rules"] as? [[String: Any]] ?? []).compactMap { linkRoute($0, spaceTitles: spaceTitleByID) }
        }
        return plan
    }

    /// Arc's `automaticLiveFolderData` for a GitHub folder: `dataSource {github: {}}`, `filter
    /// {github: {_0: {attributes, hiddenRepositories [{owner, name}]}}}`, `hiddenItems [{url: {_0}}]`.
    /// Its `lastFetch` stays behind, so the folder refreshes as soon as Cra runs (#215).
    static func liveFolder(_ value: Any?) -> LiveFolderData? {
        guard let data = value as? [String: Any], (data["dataSource"] as? [String: Any])?["github"] != nil else { return nil }
        var live = LiveFolderData()
        if let filter: [String: Any] = tagged(data["filter"], "github") {
            if let bits = filter["attributes"] as? Int { live.filter.attributes = GitHubLiveFilter.Attributes(rawValue: bits).intersection(.all) }
            live.filter.hiddenRepositories = (filter["hiddenRepositories"] as? [[String: Any]] ?? []).compactMap { r in
                guard let owner = r["owner"] as? String, let name = r["name"] as? String else { return nil }
                return "\(owner)/\(name)"
            }
        }
        live.hiddenItems = (data["hiddenItems"] as? [Any] ?? []).compactMap { tagged($0, "url") }
        return live
    }

    /// One Air Traffic Control rule: `sourceComponents[0].componentType.urlMatch` is
    /// `{_0: {contains: {}} | {matches: {}}, _1: text}`.
    private static func linkRoute(_ rule: [String: Any], spaceTitles: [String: String]) -> ImportedLinkRoute? {
        guard let dest = linkDestination(rule["destination"], spaceTitles: spaceTitles),
              let component = (rule["sourceComponents"] as? [[String: Any]])?.first,
              let type = component["componentType"] as? [String: Any],
              let urlMatch = type["urlMatch"] as? [String: Any],
              let text = urlMatch["_1"] as? String else { return nil }
        let style: LinkMatchStyle = (urlMatch["_0"] as? [String: Any])?["matches"] != nil ? .equals : .contains
        return ImportedLinkRoute(match: style, text: text, destination: dest)
    }

    /// `{littleArc: {_0: <profile>}}` or `{space: {_0: {mostRecent: {}}}}`; a specific
    /// space is recognised by its id anywhere inside either. Arc's editor never wrote a
    /// Little Arc with a space, but one written by hand loaded in that space's profile;
    /// Cra's Little Window route can name the space (#258).
    private static func linkDestination(_ value: Any?, spaceTitles: [String: String]) -> ImportedLinkDestination? {
        guard let d = value as? [String: Any] else { return nil }
        func title(_ v: Any) -> String? {
            if let s = v as? String { return spaceTitles[s] }
            if let o = v as? [String: Any] { return o.values.lazy.compactMap(title).first }
            if let a = v as? [Any] { return a.lazy.compactMap(title).first }
            return nil
        }
        if let little = d["littleArc"] { return .littleWindow(spaceTitle: title(little)) }
        guard let space = d["space"] else { return nil }
        return title(space).map { .space(title: $0) } ?? .mostRecentSpace
    }

    /// Arc caches favicons as 32x32 PNGs named md5(item id): the sidebar's in SidebarItemsFaviconCache,
    /// archived tabs' in ArchiveItemsFaviconCache.
    static func faviconFile(forItemID id: String, in cache: String = "SidebarItemsFaviconCache") -> String? {
        let digest = Insecure.MD5.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let path = supportDir.appendingPathComponent("\(cache)/\(digest)").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

// MARK: - Dia

enum DiaImporter {
    /// CRA_DIA_DIR points a test instance at a made-up profile (Tests/Fixtures/Dia).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_DIA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dia", isDirectory: true)
    static var userData: URL { supportDir.appendingPathComponent("User Data", isDirectory: true) }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableProfileContainers.json").path) || hasEncryptedSidebar
    }

    /// Dia 1.55 and later: the sidebar is in encrypted tabs.db files, read with the Keychain secret.
    static var hasEncryptedSidebar: Bool { hasEncryptedSidebar(userData: userData) }
    static func hasEncryptedSidebar(userData: URL) -> Bool { !DiaSidebar.databases(userData: userData).isEmpty }

    /// With the "Dia Safe Storage" secret the spaces come from Dia's sidebar database; without
    /// it (or from an older Dia) from the files Dia kept before 1.55, which no longer follow
    /// the sidebar: the open tabs as of then and the bookmarks bar. A secret that opens no
    /// sidebar database throws rather than fall back to those stale files. The sidebar database and
    /// favicons come from `userData`, the older files and the archive from `dir`.
    static func plan(secret: String? = nil, supportDir dir: URL = DiaImporter.supportDir, userData: URL = DiaImporter.userData) throws -> ImportPlan {
        guard isAvailable else { throw ImportError.notFound("Dia") }
        var plan = ImportPlan(source: "Dia")
        if let secret, hasEncryptedSidebar(userData: userData) {
            plan.spaces = DiaSidebar.spaces(userData: userData, rootKey: ChromiumCrypto.key(fromSecret: secret))
            if plan.spaces.isEmpty { throw ImportError.unreadable("Dia's spaces and tabs") }
        } else {
            addLegacySidebar(to: &plan, supportDir: dir, userData: userData)
        }
        addArchive(to: &plan, supportDir: dir)
        ImportFavicons.attach(to: &plan, folder: "cra-dia-favicons", from: ImportSource.Kind.dia.iconStores(dataDir: userData))
        return plan
    }

    private static func addLegacySidebar(to plan: inout ImportPlan, supportDir: URL, userData: URL) {
        // Open tabs and the favorites container.
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableProfileContainers.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            var openTabs: [ImportedItem] = [], openSkipped: [ImportSkip] = []
            for c in containers {
                let idInfo = c["id"] as? [String: Any]
                let kind = idInfo?["container"] as? [String: Any]
                let isFavorites = kind?["favorites"] != nil
                for tab in c["tabs"] as? [[String: Any]] ?? [] {
                    guard let contents = tab["contents"] as? [[String: Any]] else { continue }
                    for content in contents {
                        guard let variant = content["variant"] as? [String: Any], let web = variant["webContent"] as? [String: Any],
                              let w = web["_0"] as? [String: Any], let url = w["url"] as? String else { continue }
                        guard ImportedAddress.keeps(url) else {
                            let skip = ImportSkip.leftOut(url, title: w["title"] as? String ?? "", kind: isFavorites ? .favorites : .tabs)
                            if isFavorites { plan.skipped += [skip].compactMap { $0 } } else { openSkipped += [skip].compactMap { $0 } }
                            continue
                        }
                        let item = ImportedItem(pageTitle: w["title"] as? String ?? "", url: url, createdAt: refDate(tab["creationDate"]))
                        if isFavorites { plan.favorites.append(item) } else { openTabs.append(item) }
                    }
                }
            }
            if !openTabs.isEmpty { plan.spaces.append(ImportedSpace(title: "Dia", emoji: "🌀", theme: nil, today: openTabs, skipped: openSkipped)) }
            else { plan.skipped += openSkipped }
        }

        // Bookmarks: Dia keeps imported Arc spaces as folders on the bookmarks bar.
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        for prof in profiles where prof == "Default" || prof.hasPrefix("Profile ") {
            let bm = supportDir.appendingPathComponent("User Data/\(prof)/Bookmarks")
            guard let data = try? Data(contentsOf: bm), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let roots = root["roots"] as? [String: Any], let bar = roots["bookmark_bar"] as? [String: Any] else { continue }
            // The tile a bookmark left out is listed on: favorites for the bar's own and its Favorites folder's.
            var kind = ImportKind.tabs, refused: [ImportSkip] = []
            func convert(_ node: [String: Any]) -> ImportedItem? {
                let name = node["name"] as? String ?? ""
                if node["type"] as? String == "url", let u = node["url"] as? String, ImportedAddress.keeps(u) {
                    return ImportedItem(customTitle: name.isEmpty ? nil : name, pageTitle: name, url: u)
                }
                if node["type"] as? String == "url" { ImportSkip.leftOut(node["url"] as? String, title: name, kind: kind).map { refused.append($0) } }
                if node["type"] as? String == "folder" {
                    let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                    return ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids)
                }
                return nil
            }
            // A row goes with the space its bookmark's folder becomes, else with the plan.
            func file(_ skips: [ImportSkip], in space: String?) {
                if let i = space.flatMap({ t in plan.spaces.firstIndex { $0.title == t } }) { plan.spaces[i].skipped += skips } else { plan.skipped += skips }
            }
            for child in bar["children"] as? [[String: Any]] ?? [] {
                kind = child["type"] as? String == "url" || (child["name"] as? String)?.lowercased() == "favorites" ? .favorites : .tabs
                refused = []
                guard let item = convert(child) else { file(refused, in: nil); continue }
                if item.isFolder {
                    if item.pageTitle.lowercased() == "favorites" { plan.favorites.append(contentsOf: item.children.filter { !$0.isFolder }) }
                    else if !item.children.isEmpty {
                        if let i = plan.spaces.firstIndex(where: { $0.title == item.pageTitle }) { plan.spaces[i].pinned.append(contentsOf: item.children) }
                        else { plan.spaces.append(ImportedSpace(title: item.pageTitle, emoji: "📁", theme: nil, pinned: item.children)) }
                    }
                    file(refused, in: kind == .favorites || item.children.isEmpty ? nil : item.pageTitle)
                } else {
                    plan.favorites.append(item)
                    file(refused, in: nil)
                }
            }
            kind = .tabs
            refused = []
            if let other = roots["other"] as? [String: Any], let kids = (other["children"] as? [[String: Any]])?.compactMap(convert), !kids.isEmpty {
                plan.spaces.append(ImportedSpace(title: "Other Bookmarks", emoji: "🔖", theme: nil, pinned: kids))
                file(refused, in: "Other Bookmarks")
            } else {
                file(refused, in: nil)
            }
        }
    }

    private static func addArchive(to plan: inout ImportPlan, supportDir: URL) {
        // Auto-archive store (best effort; shape varies between Dia versions).
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableAutoArchive.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            for c in containers {
                for t in c["archivedTabs"] as? [[String: Any]] ?? [] {
                    if let (url, title) = firstURL(in: t) {
                        plan.archive.append(ImportedArchiveEntry(customTitle: nil, pageTitle: title, url: url,
                                                                 archivedAt: refDate(t["archivedAt"] ?? t["archiveDate"] ?? t["date"]), reason: .auto, spaceTitle: "Dia"))
                    } else if let (url, title) = anyURL(in: t), let skip = ImportSkip.notAWebPage(url, title: title, kind: .archive) {
                        plan.archiveSkipped.append(skip)
                    }
                }
            }
        }
    }

    private static func firstURL(in obj: Any) -> (String, String)? {
        if let d = obj as? [String: Any] {
            if let u = d["url"] as? String, u.hasPrefix("http") { return (u, d["title"] as? String ?? "") }
            for v in d.values { if let r = firstURL(in: v) { return r } }
        } else if let a = obj as? [Any] {
            for v in a { if let r = firstURL(in: v) { return r } }
        }
        return nil
    }

    /// The first address of any scheme, for an archived tab `firstURL` finds none in.
    private static func anyURL(in obj: Any) -> (String, String)? {
        if let d = obj as? [String: Any] {
            if let u = d["url"] as? String { return (u, d["title"] as? String ?? "") }
            return d.values.lazy.compactMap(anyURL).first
        }
        return (obj as? [Any])?.lazy.compactMap(anyURL).first
    }
}

// MARK: - Applying

extension SidebarStore {
    struct ImportResult {
        var spaces = 0; var tabs = 0; var folders = 0; var archived = 0; var spaceIDs: [UUID] = []
        /// The Cra profile each source profile of an imported space landed in.
        var profiles = ImportProfileMap()
        /// How much of the plan is in Cra, and what was left out, a tile each.
        var report = ImportReports(tabs: 0, favorites: [], archive: 0, skipped: [])
    }

    /// Add a plan to the sidebar. Like Dia, every imported space is a new one (importing
    /// twice gives two of each), so people pick what to keep; a taken title gets a number
    /// ("JYSK 2"). Favorites on the current space skip URLs it already has. `replacing`
    /// spaces (a fresh install's empty one) are deleted afterwards and don't take titles.
    @discardableResult
    func apply(_ plan: ImportPlan, includeArchive: Bool, includeSettings: Bool, replacing: [UUID] = []) -> ImportResult {
        var result = ImportResult()
        // A tab or favorite Cra already has (an earlier import, the same address twice here) counts as copied.
        result.report = plan.report(includeArchive: includeArchive)

        // A pinned tab that has navigated still counts as present via its home URL.
        func existingURLs(under container: UUID) -> Set<String> {
            Set(tabs(under: container).flatMap { [$0.tab?.url, $0.tab?.savedURL].compactMap { $0 } })
        }

        // Each host's favicon first, for every item (also ones skipped as duplicates): what
        // suggestions and a tab imported with no icon show.
        func file(_ key: String) -> URL { AppPaths.favicons.appendingPathComponent(FaviconCache.fileName(key)) }
        func copyFavicon(_ src: String?, url: String?) {
            guard let src, let key = url.flatMap(FaviconKey.key(for:)) else { return }
            let dst = file(key)
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(atPath: src, toPath: dst.path)
            }
        }
        func copyFavicons(_ items: [ImportedItem]) {
            for it in items {
                if it.isFolder { copyFavicons(it.children) } else { copyFavicon(it.faviconPath, url: it.url) }
            }
        }
        copyFavicons(plan.favorites)
        for sp in plan.spaces { copyFavicons(sp.favorites); copyFavicons(sp.pinned); copyFavicons(sp.today) }
        if includeArchive { for e in plan.archive { copyFavicon(e.faviconPath, url: e.url) } }

        // The icon the other browser had for this very tab, under the tab's own key (FaviconKey, #211).
        // Arc keeps one per sidebar item, so a Google Doc and a Sheet come with different ones; under
        // the host alone they all showed one icon, and that of whichever page there loaded last (#673).
        func ownIconKey(_ src: String?, url: String?, tabID: UUID) -> String? {
            guard let src, let site = url.flatMap(FaviconKey.key(for:)) else { return nil }
            let key = FaviconKey.key(site: site, tabID: tabID)
            let dst = file(key)
            return (try? FileManager.default.copyItem(atPath: src, toPath: dst.path)) != nil ? key : nil
        }

        func insert(_ items: [ImportedItem], into parent: UUID, skip: Set<String>, pinned: Bool) {
            var skip = skip
            for it in items {
                if let live = it.liveFolder {
                    insertLiveFolder(it, live, into: parent, pinned: pinned)
                } else if it.isFolder {
                    let name = it.customTitle ?? it.pageTitle
                    // Re-importing must not duplicate folders: reuse one with the same name.
                    let folder: SidebarItem
                    if let existing = children(of: parent).first(where: { $0.isFolder && ($0.title ?? "") == name }) {
                        folder = existing
                    } else {
                        folder = createFolder(named: name, in: parent)
                        setExpanded(folder.id, false)
                        result.folders += 1
                    }
                    insert(it.children, into: folder.id, skip: existingURLs(under: folder.id), pinned: pinned)
                } else if let url = it.url, !skip.contains(url) {
                    skip.insert(url)
                    var tab = SidebarItem.tab(url, title: it.pageTitle, parent: parent)
                    tab.title = it.customTitle
                    tab.createdAt = it.createdAt
                    // An open tab was alive in the other browser: auto-archive counts from the import,
                    // not from when the tab was made (Dia keeps tabs for weeks with auto-clean off).
                    if var t = tab.tab {
                        t.timeLastActiveAt = pinned ? it.createdAt : clock.now
                        if self.items[parent]?.isLiveFolder == true { t.liveItemURL = it.liveItemURL }
                        if let key = ownIconKey(it.faviconPath, url: it.url, tabID: tab.id) { t.faviconKey = key }
                        tab.data = .tab(t)
                    }
                    insertItem(tab, into: parent, at: nil)
                    result.tabs += 1
                }
            }
        }

        // A space has one GitHub live folder: importing again fills the one it has.
        func insertLiveFolder(_ it: ImportedItem, _ live: LiveFolderData, into parent: UUID, pinned: Bool) {
            guard let sid = self.spaceID(ofItem: parent), !isIncognito(space: sid) else { return }
            let folder: SidebarItem
            if let existing = self.liveFolder(live.source, inSpace: sid) {
                folder = existing
            } else {
                folder = createFolder(named: it.customTitle ?? it.pageTitle, in: parent)
                self.items[folder.id]?.liveFolder = live
                setExpanded(folder.id, false)
                result.folders += 1
            }
            // A child that stands for no live item stays out, a folder with every tab in it.
            func tabs(_ item: ImportedItem) -> [ImportedItem] { item.isFolder ? item.children.flatMap(tabs) : [item] }
            for tab in it.children.filter({ $0.liveItemURL == nil }).flatMap(tabs) {
                result.report[.tabs].copied -= 1
                if let url = tab.url { result.report[.tabs].skipped.append(ImportSkip(title: tab.customTitle ?? tab.pageTitle, url: url, reason: .notALiveItem)) }
            }
            insert(it.children.filter { $0.liveItemURL != nil }, into: folder.id, skip: existingURLs(under: folder.id), pinned: pinned)
        }

        let current = focusedSpace.favoritesContainerID
        insert(plan.favorites, into: current, skip: existingURLs(under: current), pinned: true)

        // Archive entries and link routes name spaces by title: point them at this import's spaces.
        var imported: [String: UUID] = [:]
        func spaceID(titled title: String) -> UUID? {
            imported[title.lowercased()] ?? orderedSpaces.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id
        }
        func freeTitle(_ title: String) -> String {
            let taken = Set(orderedSpaces.filter { !replacing.contains($0.id) }.map { $0.title.lowercased() })
            guard taken.contains(title.lowercased()) else { return title }
            var n = 2
            while taken.contains("\(title) \(n)".lowercased()) { n += 1 }
            return "\(title) \(n)"
        }

        // A source profile's spaces go on the Cra profile of its name; the rest stay on Default.
        for sp in plan.spaces {
            let space = createSpace(title: freeTitle(sp.title), emoji: sp.emoji, symbol: sp.symbol, theme: sp.theme, focus: false)
            if let source = sp.profile {
                let folder = result.profiles.folders[source.folder] ?? importedProfile(named: source.name).directoryName
                result.profiles.folders[source.folder] = folder
                if let p = profiles.first(where: { $0.directoryName == folder }) { setProfile(p.id, forSpace: space.id) }
            } else {
                result.profiles.folders["Default"] = "Default"
            }
            result.spaces += 1
            result.spaceIDs.append(space.id)
            if imported[sp.title.lowercased()] == nil { imported[sp.title.lowercased()] = space.id }
            // With shared favorites (#154) the profile picks which list the space shows.
            let favorites = self.space(space.id)?.favoritesContainerID ?? space.favoritesContainerID
            insert(sp.favorites, into: favorites, skip: existingURLs(under: favorites), pinned: true)
            insert(sp.pinned, into: space.pinnedContainerID, skip: existingURLs(under: space.pinnedContainerID), pinned: true)
            insert(sp.today, into: space.todayContainerID, skip: existingURLs(under: space.todayContainerID), pinned: false)
        }
        for id in replacing { deleteSpace(id) }

        if includeArchive {
            let known = Set(archive.compactMap { $0.item.tab?.url })
            for e in plan.archive where !known.contains(e.url) {
                var item = SidebarItem.tab(e.url, title: e.pageTitle, parent: nil)
                item.title = e.customTitle
                if var t = item.tab, let key = ownIconKey(e.faviconPath, url: e.url, tabID: item.id) {
                    t.faviconKey = key
                    item.data = .tab(t)
                }
                let sid = e.spaceTitle.flatMap(spaceID(titled:))
                appendArchived(ArchivedItem(archivedAt: e.archivedAt, reason: e.reason, sourceSpaceID: sid, wasPinned: false, item: item))
                result.archived += 1
            }
        }

        if includeSettings {
            if let a = plan.settings.autoArchive { settings.autoArchive = a }
            if let w = plan.settings.sidebarWidth { prefs.sidebarWidth = SidebarWidth.clamped(w) }
            if let t = plan.settings.showToolbar { settings.showToolbar = t }
            if let f = plan.settings.toolbarShowsFullURL { settings.toolbarShowsFullURL = f }
            // Air Traffic Control, pointed at the spaces of the same name.
            func destination(_ d: ImportedLinkDestination) -> LinkDestination {
                switch d {
                case .mostRecentSpace: return .mostRecentSpace
                case .littleWindow(let title): return .littleWindow(space: title.flatMap(spaceID(titled:)))
                case .space(let title):
                    return spaceID(titled: title).map { .space($0) } ?? .mostRecentSpace
                }
            }
            if let d = plan.settings.defaultLinkDestination { settings.defaultLinkDestination = destination(d) }
            for r in plan.settings.linkRoutes where !settings.linkRoutes.contains(where: { $0.match == r.match && $0.text == r.text }) {
                settings.linkRoutes.append(LinkRoute(match: r.match, text: r.text, destination: destination(r.destination)))
            }
            // Little Arc's profile per site, on the Cra profile its folder became; a folder no imported
            // space is on has no Cra profile, and its sites follow the window used last.
            func profile(folder: String) -> RememberedProfile? {
                if folder == "Default" { return RememberedProfile(id: nil) }
                return result.profiles.folders[folder].flatMap { dir in profiles.first { $0.directoryName == dir } }.map { RememberedProfile(id: $0.id) }
            }
            prefs.siteProfiles.adopt(Dictionary(plan.settings.siteProfiles.compactMap { pick in profile(folder: pick.folder).map { (pick.site, $0) } },
                                                uniquingKeysWith: { a, _ in a }))
        }
        touchAfterImport()
        return result
    }

    /// The Cra profile a source profile becomes: one already there of the same name is reused, so
    /// importing again (or rebuilding from Arc) doesn't add "Work" twice.
    private func importedProfile(named name: String) -> BrowserProfile {
        profiles.first { $0.name == name } ?? createProfile(name: name)
    }

    // MARK: Rebuild from Arc (GitHub #131)

    /// Spaces an import from before Cra kept Arc's profiles left on Default, that Arc has on a
    /// profile of their own (matched by name).
    func arcProfileMoves(_ plan: ImportPlan) -> [ArcProfileRebuild.Move] {
        let cra = orderedSpaces.map { ArcProfileRebuild.CraSpace(id: $0.id, title: $0.title, movable: $0.profileID == nil && !isIncognito(space: $0.id)) }
        let arc = plan.spaces.map { ArcProfileRebuild.ArcSpace(title: $0.title, folder: $0.profile?.folder, name: $0.profile?.name ?? "Default") }
        return ArcProfileRebuild.moves(cra: cra, arc: arc)
    }

    /// Puts each space on the Cra profile its Arc profile becomes; what Arc's profiles map to.
    @discardableResult
    func applyArcProfileMoves(_ moves: [ArcProfileRebuild.Move]) -> ImportProfileMap {
        var map = ImportProfileMap(folders: ["Default": "Default"])
        for m in moves where spaces[m.spaceID] != nil {
            let profile = map.folders[m.folder].flatMap { f in profiles.first { $0.directoryName == f } } ?? importedProfile(named: m.profileName)
            map.folders[m.folder] = profile.directoryName
            setProfile(profile.id, forSpace: m.spaceID)
        }
        return map
    }
}
