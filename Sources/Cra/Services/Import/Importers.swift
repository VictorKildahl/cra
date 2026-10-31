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
}

struct ImportedSpace {
    var title: String
    var emoji: String
    var theme: SpaceTheme?
    /// The space's own favorites (Arc: the top apps of the space's profile).
    var favorites: [ImportedItem] = []
    var pinned: [ImportedItem] = []
    var today: [ImportedItem] = []
}

struct ImportedArchiveEntry {
    var customTitle: String?
    var pageTitle: String
    var url: String
    var archivedAt: Date
    var reason: ArchiveReason
    var spaceTitle: String?
}

/// Air Traffic Control destinations name spaces by title; ids differ between browsers.
enum ImportedLinkDestination {
    case mostRecentSpace
    case space(title: String)
    case littleWindow
}

struct ImportedLinkRoute {
    var match: LinkMatchStyle
    var text: String
    var destination: ImportedLinkDestination
}

struct ImportedSettings {
    var autoArchive: AutoArchiveThreshold?
    var sidebarWidth: Double?
    var showToolbar: Bool?
    var linkRoutes: [ImportedLinkRoute] = []
    var defaultLinkDestination: ImportedLinkDestination?

    var isEmpty: Bool {
        autoArchive == nil && sidebarWidth == nil && showToolbar == nil && linkRoutes.isEmpty && defaultLinkDestination == nil
    }
}

struct ImportPlan {
    var source: String
    var spaces: [ImportedSpace] = []
    /// Favorites that belong to no imported space; they go to the focused space.
    var favorites: [ImportedItem] = []
    var archive: [ImportedArchiveEntry] = []
    var settings = ImportedSettings()

    var tabCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
    }
    var folderCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? 1 + count($1.children) : 0) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
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

// MARK: - Arc

enum ArcImporter {
    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableSidebar.json").path) }

    /// Arc's View ▸ Show Toolbar (topBarURLEnabled, off by default); nil when Arc never stored it.
    static var showsToolbar: Bool? {
        UserDefaults(suiteName: "company.thebrowser.Browser")?.object(forKey: "topBarURLEnabled") as? Bool
    }

    static func plan() throws -> ImportPlan {
        let url = supportDir.appendingPathComponent("StorableSidebar.json")
        guard let data = try? Data(contentsOf: url) else { throw ImportError.notFound("Arc") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]] else { throw ImportError.unreadable("Arc's sidebar") }
        var plan = ImportPlan(source: "Arc")
        guard let main = containers.first(where: { $0["spaces"] != nil }) else { return plan }
        let items = Dictionary(uniqueKeysWithValues: pairs(main["items"]).map { ($0.0, $0.1) })
        var spaceTitleByID: [String: String] = [:]

        func convert(_ id: String) -> ImportedItem? {
            guard let it = items[id], let dataDict = it["data"] as? [String: Any] else { return nil }
            let custom = it["title"] as? String
            let created = refDate(it["createdAt"])
            let childIDs = it["childrenIds"] as? [String] ?? []
            if let tab = dataDict["tab"] as? [String: Any] {
                guard let u = tab["savedURL"] as? String, !u.isEmpty else { return nil }
                return ImportedItem(customTitle: custom, pageTitle: tab["savedTitle"] as? String ?? "", url: u, createdAt: created,
                                    faviconPath: faviconFile(forItemID: id))
            }
            if dataDict["list"] != nil {
                return ImportedItem(customTitle: custom, pageTitle: custom ?? "Folder", url: nil, isFolder: true,
                                    children: childIDs.compactMap(convert), createdAt: created)
            }
            if dataDict["splitView"] != nil || dataDict["tabGroup"] != nil {
                // Flatten split views into their tabs.
                let kids = childIDs.compactMap(convert)
                return kids.count == 1 ? kids[0] : ImportedItem(customTitle: custom ?? "Split", pageTitle: "", url: nil, isFolder: true, children: kids, createdAt: created)
            }
            return nil
        }

        // Favorites (topApps): one container per profile, shared by that profile's spaces.
        var favoritesByProfile: [(profile: NSDictionary, items: [ImportedItem])] = []
        var allFavorites: [ImportedItem] = []
        for (_, it) in items {
            guard let d = it["data"] as? [String: Any], let c = d["itemContainer"] as? [String: Any],
                  let type = c["containerType"] as? [String: Any], let top = type["topApps"] as? [String: Any] else { continue }
            let favs = (it["childrenIds"] as? [String] ?? []).compactMap(convert)
            allFavorites += favs
            if let profile = top["_0"] as? NSDictionary { favoritesByProfile.append((profile, favs)) }
        }

        for (sid, space) in pairs(main["spaces"]) {
            let title = space["title"] as? String ?? "Space"
            spaceTitleByID[sid] = title
            var emoji = "🗂️"
            if let info = space["customInfo"] as? [String: Any], let icon = info["iconType"] as? [String: Any] {
                if let e = icon["emoji_v2"] as? String { emoji = e }
                else if let code = icon["emoji"] as? Int, let scalar = UnicodeScalar(code) { emoji = String(Character(scalar)) }
            }
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
            var sp = ImportedSpace(title: title, emoji: emoji, theme: theme(from: space) ?? SpaceTheme.presets[0])
            let profile = space["profile"] as? NSDictionary
            sp.favorites = favoritesByProfile.first { $0.profile.isEqual(profile) }?.items ?? allFavorites
            if let p = pinnedID, let c = items[p] { sp.pinned = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            if let t = todayID, let c = items[t] { sp.today = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            plan.spaces.append(sp)
        }

        // Archive
        if let adata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableArchiveItems.json")),
           let aroot = try? JSONSerialization.jsonObject(with: adata) as? [String: Any],
           let aitems = aroot["items"] as? [Any] {
            for case let e as [String: Any] in aitems {
                guard let si = e["sidebarItem"] as? [String: Any], let d = si["data"] as? [String: Any],
                      let tab = d["tab"] as? [String: Any], let u = tab["savedURL"] as? String, !u.isEmpty else { continue }
                let reason = (e["reason"] as? String) == "auto" ? ArchiveReason.auto : .manual
                var spaceTitle: String?
                if let src = e["source"] as? [String: Any], let sp = src["space"] as? [String: Any], let id = sp["_0"] as? String { spaceTitle = spaceTitleByID[id] }
                plan.archive.append(ImportedArchiveEntry(customTitle: si["title"] as? String, pageTitle: tab["savedTitle"] as? String ?? "",
                                                         url: u, archivedAt: refDate(e["archivedAt"]), reason: reason, spaceTitle: spaceTitle))
            }
            plan.archive.sort { $0.archivedAt > $1.archivedAt }
            if plan.archive.count > 1500 { plan.archive.removeLast(plan.archive.count - 1500) }
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
        if let ldata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableLinkRouting.json")),
           let lroot = try? JSONSerialization.jsonObject(with: ldata) as? [String: Any] {
            plan.settings.defaultLinkDestination = linkDestination(lroot["defaultDestination"], spaceTitles: spaceTitleByID)
            plan.settings.linkRoutes = (lroot["rules"] as? [[String: Any]] ?? []).compactMap { linkRoute($0, spaceTitles: spaceTitleByID) }
        }
        return plan
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
    /// space is recognised by its id anywhere inside `space`.
    private static func linkDestination(_ value: Any?, spaceTitles: [String: String]) -> ImportedLinkDestination? {
        guard let d = value as? [String: Any] else { return nil }
        if d["littleArc"] != nil { return .littleWindow }
        guard let space = d["space"] else { return nil }
        func title(_ v: Any) -> String? {
            if let s = v as? String { return spaceTitles[s] }
            if let o = v as? [String: Any] { return o.values.lazy.compactMap(title).first }
            if let a = v as? [Any] { return a.lazy.compactMap(title).first }
            return nil
        }
        return title(space).map { .space(title: $0) } ?? .mostRecentSpace
    }

    /// Arc caches sidebar favicons as 32x32 PNGs named md5(item id).
    static func faviconFile(forItemID id: String) -> String? {
        let digest = Insecure.MD5.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let path = supportDir.appendingPathComponent("SidebarItemsFaviconCache/\(digest)").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Arc's blendedGradient → SpaceTheme. Prefers the dark variant when one exists.
    private static func theme(from space: [String: Any]) -> SpaceTheme? {
        guard let info = space["customInfo"] as? [String: Any], let wt = info["windowTheme"] as? [String: Any],
              let bg = wt["background"] as? [String: Any] else { return nil }
        var variant: [String: Any]?
        var appearance = "auto"
        if let ab = bg["appearanceBased"] as? [String: Any] {
            variant = (ab["dark"] as? [String: Any]) ?? (ab["light"] as? [String: Any])
            appearance = ab["dark"] != nil ? "dark" : "light"
        } else if let single = bg["single"] as? [String: Any] {
            variant = single["_0"] as? [String: Any]
        }
        guard let v = variant else { return nil }
        if let a = v["contentOverBackgroundAppearance"] as? String { appearance = a }
        let vibrant = v["isVibrant"] as? Bool ?? false
        func comp(_ c: [String: Any], _ k: String) -> Double { max(0, min(1, c[k] as? Double ?? 0)) }
        func hexOf(_ c: [String: Any]) -> String {
            String(format: "#%02X%02X%02X", Int((comp(c, "red") * 255).rounded()),
                   Int((comp(c, "green") * 255).rounded()), Int((comp(c, "blue") * 255).rounded()))
        }
        let c0 = ((v["style"] as? [String: Any])?["color"] as? [String: Any])?["_0"] as? [String: Any]
        // A solid colour (Arc's colour picker with one dot) is `blendedSingleColor`. Themes
        // Cra can't read still carry Arc's derived palette, whose mid tone keeps the hue.
        if let s = (c0?["blendedSingleColor"] as? [String: Any])?["_0"] as? [String: Any], let c = s["color"] as? [String: Any] {
            let mods = s["modifiers"] as? [String: Any]
            return solidTheme(hexOf(c), intensity: mods?["intensityFactor"] as? Double ?? 1,
                              noise: mods?["noiseFactor"] as? Double ?? 0, appearance: appearance)
        }
        guard let bg2 = c0?["blendedGradient"] as? [String: Any], let g = bg2["_0"] as? [String: Any],
              let base = g["baseColors"] as? [[String: Any]], !base.isEmpty else {
            guard let mid = (wt["primaryColorPalette"] as? [String: Any])?["midTone"] as? [String: Any] else { return nil }
            return solidTheme(hexOf(mid), intensity: 1, noise: 0, appearance: appearance)
        }
        let overlays = g["overlayColors"] as? [[String: Any]] ?? []
        // Arc blends an overlay gradient onto the base gradient and the wheel
        // mixes the two base colours; bake both into our two stops (fitted to
        // Arc's rendering: top stop leans toward the second base colour).
        func hex(_ i: Int) -> String {
            let b = base[min(i, base.count - 1)]
            let other = base[min(i == 0 ? 1 : 0, base.count - 1)]
            var r = comp(b, "red"), gg = comp(b, "green"), bl = comp(b, "blue")
            if i == 0 {
                r += (comp(other, "red") - r) * 0.1; gg += (comp(other, "green") - gg) * 0.1; bl += (comp(other, "blue") - bl) * 0.1
            }
            if i < overlays.count {
                let o = overlays[i]
                let a = comp(o, "alpha") * 0.85
                r += (comp(o, "red") - r) * a; gg += (comp(o, "green") - gg) * a; bl += (comp(o, "blue") - bl) * a
            }
            return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((gg * 255).rounded()), Int((bl * 255).rounded()))
        }
        var colors = [hex(0), hex(1)]
        let mods = g["modifiers"] as? [String: Any]
        var intensity = mods?["intensityFactor"] as? Double ?? 0.5
        if vibrant && appearance != "dark" {
            // Fitted to Arc over white and black backdrops: the top stop is the
            // first base colour nudged toward the second and 30% toward white;
            // the bottom stop is the base colour pulled 30% toward the overlay's
            // end colour (or the second base colour) and 20% toward white.
            // Opacity ramps 0.45 → 0.59 (see SpacePalette).
            func rgb(_ c: [String: Any]) -> (Double, Double, Double) { (comp(c, "red"), comp(c, "green"), comp(c, "blue")) }
            func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
                (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            }
            func hexOf(_ c: (Double, Double, Double)) -> String {
                String(format: "#%02X%02X%02X", Int((c.0 * 255).rounded()), Int((c.1 * 255).rounded()), Int((c.2 * 255).rounded()))
            }
            let b0 = rgb(base[0]), b1 = rgb(base[min(1, base.count - 1)])
            let end = overlays.last(where: { comp($0, "alpha") > 0 }).map(rgb) ?? b1
            let white = (1.0, 1.0, 1.0)
            colors = [hexOf(mix(mix(b0, b1, 0.15), white, 0.30)), hexOf(mix(mix(b0, end, 0.30), white, 0.20))]
        }
        let accent = String(format: "#%02X%02X%02X", Int((comp(base[0], "red") * 255).rounded()),
                            Int((comp(base[0], "green") * 255).rounded()), Int((comp(base[0], "blue") * 255).rounded()))
        if appearance == "dark" && !vibrant {
            // Measured from Arc: dark themes show ~27% of the colour over a
            // slightly purple dark grey (#2B2632).
            colors = colors.map { c in
                let k = HexColor.components(c) ?? (0, 0, 0)
                func ch(_ v: Double, _ base: Double) -> Int { Int((v * 255 * 0.27 + base).rounded()) }
                return String(format: "#%02X%02X%02X", ch(k.r, 43), ch(k.g, 38), ch(k.b, 50))
            }
            intensity = 1
        }
        return SpaceTheme(colors: colors, intensity: intensity,
                          noise: mods?["noiseFactor"] as? Double ?? 0.15, appearance: appearance, vibrant: vibrant, accent: accent)
    }

    /// One flat colour (SpaceTheme.solid). Arc draws it the same whether or not it is
    /// marked vibrant, so only the colour, intensity and text appearance carry over.
    private static func solidTheme(_ hex: String, intensity: Double, noise: Double, appearance: String) -> SpaceTheme {
        SpaceTheme(colors: [hex, hex], intensity: intensity, noise: noise, appearance: appearance, accent: hex, solid: true)
    }
}

// MARK: - Dia

enum DiaImporter {
    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dia", isDirectory: true)

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableProfileContainers.json").path) }

    static func plan() throws -> ImportPlan {
        guard isAvailable else { throw ImportError.notFound("Dia") }
        var plan = ImportPlan(source: "Dia")

        // Open tabs and the favorites container.
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableProfileContainers.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            var openTabs: [ImportedItem] = []
            for c in containers {
                let idInfo = c["id"] as? [String: Any]
                let kind = idInfo?["container"] as? [String: Any]
                let isFavorites = kind?["favorites"] != nil
                for tab in c["tabs"] as? [[String: Any]] ?? [] {
                    guard let contents = tab["contents"] as? [[String: Any]] else { continue }
                    for content in contents {
                        guard let variant = content["variant"] as? [String: Any], let web = variant["webContent"] as? [String: Any],
                              let w = web["_0"] as? [String: Any], let url = w["url"] as? String else { continue }
                        let item = ImportedItem(pageTitle: w["title"] as? String ?? "", url: url, createdAt: refDate(tab["creationDate"]))
                        if isFavorites { plan.favorites.append(item) } else { openTabs.append(item) }
                    }
                }
            }
            if !openTabs.isEmpty { plan.spaces.append(ImportedSpace(title: "Dia", emoji: "🌀", theme: nil, today: openTabs)) }
        }

        // Bookmarks: Dia keeps imported Arc spaces as folders on the bookmarks bar.
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: supportDir.appendingPathComponent("User Data").path)) ?? []
        for prof in profiles where prof == "Default" || prof.hasPrefix("Profile ") {
            let bm = supportDir.appendingPathComponent("User Data/\(prof)/Bookmarks")
            guard let data = try? Data(contentsOf: bm), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let roots = root["roots"] as? [String: Any], let bar = roots["bookmark_bar"] as? [String: Any] else { continue }
            func convert(_ node: [String: Any]) -> ImportedItem? {
                let name = node["name"] as? String ?? ""
                if node["type"] as? String == "url", let u = node["url"] as? String {
                    return ImportedItem(customTitle: name.isEmpty ? nil : name, pageTitle: name, url: u)
                }
                if node["type"] as? String == "folder" {
                    let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                    return ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids)
                }
                return nil
            }
            for child in bar["children"] as? [[String: Any]] ?? [] {
                guard let item = convert(child) else { continue }
                if item.isFolder {
                    if item.pageTitle.lowercased() == "favorites" { plan.favorites.append(contentsOf: item.children.filter { !$0.isFolder }) }
                    else if !item.children.isEmpty {
                        if let i = plan.spaces.firstIndex(where: { $0.title == item.pageTitle }) { plan.spaces[i].pinned.append(contentsOf: item.children) }
                        else { plan.spaces.append(ImportedSpace(title: item.pageTitle, emoji: "📁", theme: nil, pinned: item.children)) }
                    }
                } else {
                    plan.favorites.append(item)
                }
            }
            if let other = roots["other"] as? [String: Any], let kids = (other["children"] as? [[String: Any]])?.compactMap(convert), !kids.isEmpty {
                plan.spaces.append(ImportedSpace(title: "Other Bookmarks", emoji: "🔖", theme: nil, pinned: kids))
            }
        }

        // Auto-archive store (best effort; shape varies between Dia versions).
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableAutoArchive.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            for c in containers {
                for t in c["archivedTabs"] as? [[String: Any]] ?? [] {
                    if let (url, title) = firstURL(in: t) {
                        plan.archive.append(ImportedArchiveEntry(customTitle: nil, pageTitle: title, url: url,
                                                                 archivedAt: refDate(t["archivedAt"] ?? t["archiveDate"] ?? t["date"]), reason: .auto, spaceTitle: "Dia"))
                    }
                }
            }
        }
        return plan
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
}

// MARK: - Applying

extension SidebarStore {
    struct ImportResult { var spaces = 0; var tabs = 0; var folders = 0; var archived = 0; var spaceIDs: [UUID] = [] }

    /// Add a plan to the sidebar. Like Dia, every imported space is a new one (importing
    /// twice gives two of each), so people pick what to keep; a taken title gets a number
    /// ("JYSK 2"). Favorites on the current space skip URLs it already has. `replacing`
    /// spaces (a fresh install's empty one) are deleted afterwards and don't take titles.
    @discardableResult
    func apply(_ plan: ImportPlan, includeArchive: Bool, includeSettings: Bool, replacing: [UUID] = []) -> ImportResult {
        var result = ImportResult()

        // A pinned tab that has navigated still counts as present via its home URL.
        func existingURLs(under container: UUID) -> Set<String> {
            Set(tabs(under: container).flatMap { [$0.tab?.url, $0.tab?.savedURL].compactMap { $0 } })
        }

        // Favicons first, for every item (also ones skipped as duplicates).
        func copyFavicons(_ items: [ImportedItem]) {
            for it in items {
                if it.isFolder { copyFavicons(it.children); continue }
                guard let src = it.faviconPath, let url = it.url, let key = FaviconCache.key(for: url) else { continue }
                let dst = AppPaths.favicons.appendingPathComponent(FaviconCache.fileName(key))
                if !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(atPath: src, toPath: dst.path)
                }
            }
        }
        copyFavicons(plan.favorites)
        for sp in plan.spaces { copyFavicons(sp.favorites); copyFavicons(sp.pinned); copyFavicons(sp.today) }

        func insert(_ items: [ImportedItem], into parent: UUID, skip: Set<String>, pinned: Bool) {
            var skip = skip
            for it in items {
                if it.isFolder {
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
                    if var t = tab.tab { t.timeLastActiveAt = it.createdAt; tab.data = .tab(t) }
                    insertItem(tab, into: parent, at: nil)
                    result.tabs += 1
                }
            }
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

        for sp in plan.spaces {
            let space = createSpace(title: freeTitle(sp.title), emoji: sp.emoji, theme: sp.theme, focus: false)
            result.spaces += 1
            result.spaceIDs.append(space.id)
            if imported[sp.title.lowercased()] == nil { imported[sp.title.lowercased()] = space.id }
            insert(sp.favorites, into: space.favoritesContainerID, skip: existingURLs(under: space.favoritesContainerID), pinned: true)
            insert(sp.pinned, into: space.pinnedContainerID, skip: existingURLs(under: space.pinnedContainerID), pinned: true)
            insert(sp.today, into: space.todayContainerID, skip: existingURLs(under: space.todayContainerID), pinned: false)
        }
        for id in replacing { deleteSpace(id) }

        if includeArchive {
            let known = Set(archive.compactMap { $0.item.tab?.url })
            for e in plan.archive where !known.contains(e.url) {
                var item = SidebarItem.tab(e.url, title: e.pageTitle, parent: nil)
                item.title = e.customTitle
                let sid = e.spaceTitle.flatMap(spaceID(titled:))
                appendArchived(ArchivedItem(archivedAt: e.archivedAt, reason: e.reason, sourceSpaceID: sid, wasPinned: false, item: item))
                result.archived += 1
            }
        }

        if includeSettings {
            if let a = plan.settings.autoArchive { settings.autoArchive = a }
            if let w = plan.settings.sidebarWidth { prefs.sidebarWidth = min(max(w, 220), 520) }
            if let t = plan.settings.showToolbar { settings.showToolbar = t }
            // Air Traffic Control, pointed at the spaces of the same name.
            func destination(_ d: ImportedLinkDestination) -> LinkDestination {
                switch d {
                case .mostRecentSpace: return .mostRecentSpace
                case .littleWindow: return .littleWindow
                case .space(let title):
                    return spaceID(titled: title).map { .space($0) } ?? .mostRecentSpace
                }
            }
            if let d = plan.settings.defaultLinkDestination { settings.defaultLinkDestination = destination(d) }
            for r in plan.settings.linkRoutes where !settings.linkRoutes.contains(where: { $0.match == r.match && $0.text == r.text }) {
                settings.linkRoutes.append(LinkRoute(match: r.match, text: r.text, destination: destination(r.destination)))
            }
        }
        touchAfterImport()
        return result
    }
}
