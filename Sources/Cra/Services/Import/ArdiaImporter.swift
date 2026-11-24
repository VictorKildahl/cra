import AppKit

// Ardia keeps its whole sidebar in one JSON file, <support>/session.json (version 10–11 as of
// Nov 2026), and runs Chromium under <support>/Chromium. Its profiles are its spaces: each has a
// name, a colour and an icon, and its own Chromium profile, "Default" for the first one and
// "Profile <id>" for the rest (profiles made to share sign-ins name the one they use in `dataId`).
//
// A tab's `pin` is {as: "tile"} for a Top App (Arc's favorite) or {as: "row"} for a pinned tab;
// pinned folders are `groups` with pinned true, nested through `parentId`, each listing its own
// and its subfolders' tabs. Pins are mirrored into every window; a profile without a window keeps
// them in `parkedPins`.

enum ArdiaImporter {
    /// CRA_ARDIA_DIR points a test instance at a made-up profile (Tests/Fixtures/Ardia).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_ARDIA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.ardia.browser", isDirectory: true)
    static var userData: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static var sessionFile: URL { supportDir.appendingPathComponent("session.json") }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: sessionFile.path) }

    static func plan() throws -> ImportPlan {
        guard let data = try? Data(contentsOf: sessionFile) else { throw ImportError.notFound("Ardia") }
        var plan = try plan(session: data)
        ImportFavicons.attach(to: &plan, folder: "cra-ardia-favicons", from: ImportSource.Kind.ardia.iconStores(dataDir: userData))
        return plan
    }

    /// The Ardia swatches a profile's `color` names (Ardia's tokens.ts).
    static let swatches: [String: String] = [
        "plum": "#C07A98", "blue": "#4691C3", "purple": "#7873AF", "pink": "#D37B8B", "red": "#C1575C",
        "orange": "#D87249", "yellow": "#E3AC38", "green": "#3EB489", "neutral": "#8E8E93",
    ]

    static func plan(session data: Data) throws -> ImportPlan {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [String: [String: Any]] else { throw ImportError.unreadable("Ardia's spaces") }
        var plan = ImportPlan(source: "Ardia")

        let order = (root["profileOrder"] as? [String] ?? []).filter { profiles[$0] != nil }
        let profileIDs = order + profiles.keys.filter { !order.contains($0) }.sorted()
        let tabs = Dictionary((root["tabs"] as? [[String: Any]] ?? []).compactMap { t in (t["id"] as? String).map { ($0, t) } },
                              uniquingKeysWith: { a, _ in a })
        let windows = Dictionary((root["windows"] as? [[String: Any]] ?? []).compactMap { w in (w["id"] as? String).map { ($0, w) } },
                                 uniquingKeysWith: { a, _ in a })
        // The focused window first: it holds the order the person last saw.
        var windowIDs = root["windowOrder"] as? [String] ?? []
        windowIDs += windows.keys.filter { !windowIDs.contains($0) }.sorted()
        if let focused = root["focusedWindowId"] as? String, windows[focused] != nil {
            windowIDs.removeAll { $0 == focused }
            windowIDs.insert(focused, at: 0)
        }
        let groups = Dictionary((root["groups"] as? [[String: Any]] ?? []).compactMap { g in (g["id"] as? String).map { ($0, g) } },
                                uniquingKeysWith: { a, _ in a })
        // A tab's folder is the deepest pinned group listing it (a group lists its subfolders' tabs too).
        var groupOfTab: [String: String] = [:]
        for (gid, g) in groups where (g["pinned"] as? Bool) == true {
            for tid in g["tabIds"] as? [String] ?? [] {
                if let other = groupOfTab[tid], depth(other, groups) >= depth(gid, groups) { continue }
                groupOfTab[tid] = gid
            }
        }
        let parked = root["parkedPins"] as? [String: [String: Any]] ?? [:]

        for pid in profileIDs {
            guard let profile = profiles[pid] else { continue }
            var seen = Set<String>()
            var favorites: [ImportedItem] = []
            let pinned = ImportTree()
            var today: [ImportedItem] = []
            var skipped: [ImportSkip] = []

            func take(_ t: [String: Any], folder: String?, folders: [String: [String: Any]]) {
                let pin = t["pin"] as? [String: Any]
                let pinnedFolder = folder.flatMap { folders[$0] }
                let isPinned = pin != nil || pinnedFolder != nil
                let key = (t["pinKey"] as? String) ?? (t["id"] as? String) ?? UUID().uuidString
                // A Top App left out is listed on the favorites tile.
                let isTile = pin?["as"] as? String == "tile"
                guard seen.insert(key).inserted,
                      let item = item(t, pinned: isPinned, skip: { var s = $0; if isTile { s.kind = .favorites }; skipped.append(s) }) else { return }
                if isTile {
                    // Cra's favorites have no folders: a Top Apps folder's tiles come over in its place.
                    favorites.append(item)
                } else if isPinned {
                    pinned.insert(item, path: chain(folder, folders))
                } else {
                    today.append(item)
                }
            }

            for wid in windowIDs {
                for tid in windows[wid]?["tabIds"] as? [String] ?? [] {
                    guard let t = tabs[tid], t["profileId"] as? String == pid else { continue }
                    take(t, folder: groupOfTab[tid], folders: groups)
                }
            }
            // A profile with no window open keeps its pins parked.
            if favorites.isEmpty && pinned.items.isEmpty, let park = parked[pid] {
                let parkedGroups = Dictionary((park["groups"] as? [[String: Any]] ?? []).compactMap { g in (g["id"] as? String).map { ($0, g) } },
                                              uniquingKeysWith: { a, _ in a })
                for t in park["tabs"] as? [[String: Any]] ?? [] {
                    take(t, folder: t["groupId"] as? String, folders: parkedGroups)
                }
            }

            let name = (profile["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space"
            let icon = icon(profile["icon"] as? String)
            var space = ImportedSpace(title: name, emoji: icon.emoji, symbol: icon.symbol, theme: theme(profile))
            space.favorites = favorites
            space.pinned = pinned.items
            space.today = today
            space.skipped = skipped
            // Every profile but the first signs in on a Chromium profile of its own.
            let dataID = (profile["dataId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? pid
            if dataID != "default" {
                let owner = (profiles[dataID]?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
                space.profile = ImportedProfile(folder: "Profile \(dataID)", name: owner)
            }
            plan.spaces.append(space)
        }
        return plan
    }

    /// The names Ardia shows for its Chromium profile folders: the profile (space) each belongs to.
    static func profileNames() -> [String: String] {
        guard let data = try? Data(contentsOf: sessionFile), let plan = try? plan(session: data) else { return [:] }
        var names: [String: String] = [:]
        if let first = plan.spaces.first(where: { $0.profile == nil }) { names["Default"] = first.title }
        for sp in plan.spaces { if let p = sp.profile, names[p.folder] == nil { names[p.folder] = p.name } }
        return names
    }

    private static func depth(_ gid: String, _ groups: [String: [String: Any]]) -> Int {
        var n = 0, id: String? = gid, seen = Set<String>()
        while let g = id, seen.insert(g).inserted, let group = groups[g] { n += 1; id = group["parentId"] as? String }
        return n
    }

    /// The folders from the outermost down to `gid`.
    private static func chain(_ gid: String?, _ groups: [String: [String: Any]]) -> [(id: String, name: String)] {
        var out: [(id: String, name: String)] = [], id = gid, seen = Set<String>()
        while let g = id, seen.insert(g).inserted, let group = groups[g] {
            let name = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Folder"
            out.insert((g, name), at: 0)
            id = group["parentId"] as? String
        }
        return out
    }

    /// A pinned tab or Top App keeps the page it was pinned with, not where it navigated, unless that
    /// page can't be imported: then it comes at the page it shows. `skip` hears of a tab left out.
    private static func item(_ t: [String: Any], pinned: Bool, skip: (ImportSkip) -> Void) -> ImportedItem? {
        let home = pinned ? t["pinnedUrl"] as? String : nil
        let custom = (t["customTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let pages = [home, t["url"] as? String].compactMap { $0 }
        guard let url = pages.first(where: ImportedAddress.keeps) else {
            ImportSkip.leftOut(pages.first { ImportedAddress.leftOut($0) != nil }, title: custom ?? t["title"] as? String ?? "").map(skip)
            return nil
        }
        let created = (t["createdAt"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil } ?? Date()
        return ImportedItem(customTitle: custom, pageTitle: t["title"] as? String ?? "", url: url, createdAt: created)
    }

    /// An emoji, "symbol:<SF Symbol>", or nothing (a dot).
    static func icon(_ raw: String?) -> (emoji: String, symbol: String?) {
        guard let raw, !raw.isEmpty else { return ("", nil) }
        if raw.hasPrefix("symbol:") {
            let name = String(raw.dropFirst("symbol:".count))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? ("", name) : ("🗂️", nil)
        }
        return (raw, nil)
    }

    /// A custom theme's gradient stops (RGBA, 0…1), else the profile's swatch.
    static func theme(_ profile: [String: Any]) -> SpaceTheme? {
        if let theme = profile["theme"] as? [String: Any], let stops = theme["stops"] as? [[String: Any]] {
            let colors: [String] = stops.compactMap { s in
                guard let c = s["color"] as? [String: Any], let r = c["r"] as? Double, let g = c["g"] as? Double, let b = c["b"] as? Double else { return nil }
                func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
                return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
            }
            if let first = colors.first {
                let mode = theme["mode"] as? String
                return SpaceTheme(colors: Array((colors + [first]).prefix(2)), intensity: max(0.3, min(1, theme["intensity"] as? Double ?? 0.75)),
                                  noise: max(0, min(1, theme["grain"] as? Double ?? 0)),
                                  appearance: mode == "light" || mode == "dark" ? mode! : "auto", accent: first)
            }
        }
        guard let hex = (profile["color"] as? String).flatMap({ swatches[$0] }) else { return nil }
        return SpaceTheme(colors: [hex, hex], intensity: 0.75, noise: 0, appearance: "auto", accent: hex)
    }
}
