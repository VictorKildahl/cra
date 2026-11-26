import AppKit

// Crest (github.com/pauljoda/Crest, com.pauldavis.crest) keeps its whole sidebar in
// <support>/ControlPlane/session.sqlite: a `checkpoint` table of parts, `core` being the session as
// JSON (CrestCore's StoredSessionCodec, Nov 2026) and `history.<space id>` each Space's history.
// Chromium runs under <support>/Chromium, with a profile of its own for each Space's `profile.id`
// in a folder named "Crest-<id>", and "Crest Safe Storage" (account com.pauldavis.crest) in the Keychain.
//
// A Space's `tabs` are in sidebar order, each with a `placement`: "pinned" is the tile row (Arc's
// favorites), "saved" the pinned section, in `folders` of location "saved" nested through
// `parentID`, and "current" the tabs under it (Arc's Today). A saved tab keeps the page it was
// saved with in `savedURL`. Icons are an SF Symbol name or "crest.emoji:<emoji>"; times are seconds
// since 2001. `archivedTabs` hold {tab, archivedAt, reason}.

enum CrestImporter {
    /// CRA_CREST_DIR points a test instance at a made-up profile (Tests/Fixtures/Crest).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_CREST_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Crest", isDirectory: true)
    static var userData: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static var sessionFile: URL { supportDir.appendingPathComponent("ControlPlane/session.sqlite") }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: sessionFile.path) }

    static func plan() throws -> ImportPlan {
        guard isAvailable else { throw ImportError.notFound("Crest") }
        guard let data = session() else { throw ImportError.unreadable("Crest's spaces") }
        var plan = try plan(session: data, userData: userData)
        ImportFavicons.attach(to: &plan, folder: "cra-crest-favicons", from: ImportSource.Kind.crest.iconStores(dataDir: userData))
        return plan
    }

    /// The `core` part of the session file: the session without its history, as JSON.
    static func session() -> Data? {
        guard let db = SQLiteSnapshot(copying: sessionFile), let core = db.scalar("SELECT data FROM checkpoint WHERE part = 'core'") else { return nil }
        return (core as? Data) ?? (core as? String).map { Data($0.utf8) }
    }

    /// The swatch each of Crest's Space accents stands for (CrestCore's SpaceAccent).
    static let swatches: [String: String] = ["indigo": "#4A4094", "orange": "#D94533", "teal": "#1F7D85", "rose": "#B8406B"]

    /// `userData` is where the Spaces' "Crest-<id>" profile folders are looked for.
    static func plan(session data: Data, userData: URL) throws -> ImportPlan {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let spaces = root["spaces"] as? [[String: Any]] else { throw ImportError.unreadable("Crest's spaces") }
        var plan = ImportPlan(source: "Crest")
        let folders = profileFolders(userData: userData)
        // The first Space signs in on Cra's Default profile; each other Chromium profile gets a Cra profile.
        let firstProfile = spaces.first.flatMap(profileID)

        for s in spaces {
            let name = (s["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space"
            let tree = Dictionary((s["folders"] as? [[String: Any]] ?? []).compactMap { f in id(f["id"]).map { ($0, f) } },
                                  uniquingKeysWith: { a, _ in a })
            var favorites: [ImportedItem] = []
            let pinned = ImportTree()
            var today: [ImportedItem] = []
            var skipped: [ImportSkip] = []

            for t in s["tabs"] as? [[String: Any]] ?? [] {
                let placement = t["placement"] as? String
                let saved = placement == "pinned" || placement == "saved"
                guard let item = item(t, saved: saved, skip: { var k = $0; if placement == "pinned" { k.kind = .favorites }; skipped.append(k) }) else { continue }
                switch placement {
                case "pinned": favorites.append(item)
                case "saved": pinned.insert(item, path: chain(id(t["folderID"]), tree))
                // A folder among the current tabs has no place in Today: its tabs come over on their own.
                default: today.append(item)
                }
            }

            let icon = icon(s["symbol"] as? String)
            var space = ImportedSpace(title: name, emoji: icon.emoji, symbol: icon.symbol, theme: theme(s))
            space.favorites = favorites
            space.pinned = pinned.items
            space.today = today
            space.skipped = skipped
            if let pid = profileID(s), pid != firstProfile, let folder = folders[pid.uppercased()] {
                let owner = spaces.first { profileID($0) == pid }.flatMap { $0["name"] as? String }.flatMap { $0.isEmpty ? nil : $0 } ?? name
                space.profile = ImportedProfile(folder: folder, name: owner)
            }
            plan.spaces.append(space)

            for e in s["archivedTabs"] as? [[String: Any]] ?? [] {
                guard let t = e["tab"] as? [String: Any] else { continue }
                let title = (t["customTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? t["title"] as? String ?? ""
                let pages = [t["url"] as? String, t["savedURL"] as? String].compactMap { $0 }
                guard let url = pages.first(where: ImportedAddress.keeps) else {
                    ImportSkip.leftOut(pages.first, title: title, kind: .archive).map { plan.archiveSkipped.append($0) }
                    continue
                }
                plan.archive.append(ImportedArchiveEntry(customTitle: (t["customTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                                         pageTitle: t["title"] as? String ?? "", url: url, archivedAt: date(e["archivedAt"]),
                                                         reason: e["reason"] as? String == "autoCleanup" ? .auto : .manual, spaceTitle: name))
            }
        }
        plan.archive.sort { $0.archivedAt > $1.archivedAt }
        if plan.archive.count > ArchiveLimit.kept {
            plan.archiveSkipped += plan.archive[ArchiveLimit.kept...].map {
                ImportSkip(title: $0.customTitle ?? $0.pageTitle, url: $0.url, reason: .olderArchive(limit: ArchiveLimit.kept), kind: .archive)
            }
            plan.archive.removeLast(plan.archive.count - ArchiveLimit.kept)
        }
        return plan
    }

    /// The names Crest's Chromium profile folders show: the Space each belongs to.
    static func profileNames() -> [String: String] {
        guard let data = session(), let plan = try? plan(session: data, userData: userData) else { return [:] }
        var names: [String: String] = [:]
        for sp in plan.spaces { if let p = sp.profile, names[p.folder] == nil { names[p.folder] = p.name } }
        // The first Space's folder goes to Cra's Default profile, with that Space.
        let spaces = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["spaces"] as? [[String: Any]]
        if let first = spaces?.first, let pid = profileID(first), let folder = profileFolders(userData: userData)[pid.uppercased()] {
            names[folder] = plan.spaces.first?.title
        }
        return names
    }

    /// Crest's "Crest-<id>" folders under `userData`, by their id in upper case.
    static func profileFolders(userData: URL) -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        return Dictionary(names.filter(isProfileFolder).map { (String($0.dropFirst("Crest-".count)).uppercased(), $0) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// A Crest Space's Chromium profile folder: "Crest-" and an id (Crest's IsCrestProfileName).
    static func isProfileFolder(_ name: String) -> Bool { name.hasPrefix("Crest-") && name.count > "Crest-".count }

    private static func profileID(_ space: [String: Any]) -> String? {
        ((space["profile"] as? [String: Any])?["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Crest's ids are {"rawValue": "<UUID>"}, or the UUID alone.
    private static func id(_ any: Any?) -> String? {
        (any as? String) ?? ((any as? [String: Any])?["rawValue"] as? String)
    }

    private static func date(_ any: Any?) -> Date {
        guard let s = (any as? Double) ?? (any as? Int).map(Double.init), s > 0 else { return Date() }
        return Date(timeIntervalSinceReferenceDate: s)
    }

    /// The folders from the outermost down to `fid`.
    private static func chain(_ fid: String?, _ folders: [String: [String: Any]]) -> [(id: String, name: String)] {
        var out: [(id: String, name: String)] = [], next = fid, seen = Set<String>()
        while let f = next, seen.insert(f).inserted, let folder = folders[f] {
            let name = (folder["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Folder"
            out.insert((f, name), at: 0)
            next = id(folder["parentID"])
        }
        return out
    }

    /// A favorite or pinned tab keeps the page it was saved with, not where it navigated, unless that
    /// page can't be imported: then it comes at the page it shows. `skip` hears of a tab left out;
    /// one with no address at all (Crest's own Settings or Start Page) just stays behind.
    private static func item(_ t: [String: Any], saved: Bool, skip: (ImportSkip) -> Void) -> ImportedItem? {
        let custom = (t["customTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let pages = [saved ? t["savedURL"] as? String : nil, t["url"] as? String].compactMap { $0 }
        guard let url = pages.first(where: ImportedAddress.keeps) else {
            ImportSkip.leftOut(pages.first { ImportedAddress.leftOut($0) != nil }, title: custom ?? t["title"] as? String ?? "").map(skip)
            return nil
        }
        return ImportedItem(customTitle: custom, pageTitle: t["title"] as? String ?? "", url: url, createdAt: date(t["lastActivatedAt"]))
    }

    /// "crest.emoji:<emoji>", an SF Symbol name, or nothing (a dot).
    static func icon(_ raw: String?) -> (emoji: String, symbol: String?) {
        guard let raw, !raw.isEmpty else { return ("", nil) }
        if raw.hasPrefix("crest.emoji:") { return (String(raw.dropFirst("crest.emoji:".count)), nil) }
        return NSImage(systemSymbolName: raw, accessibilityDescription: nil) != nil ? ("", raw) : ("", nil)
    }

    /// The Space's branding colours (its background, then its accent), else its accent's swatch.
    static func theme(_ space: [String: Any]) -> SpaceTheme? {
        let branding = space["branding"] as? [String: Any]
        let colors: [String] = (branding?["colors"] as? [[String: Any]] ?? []).compactMap { c in
            guard let r = c["red"] as? Double, let g = c["green"] as? Double, let b = c["blue"] as? Double else { return nil }
            func byte(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }
        if let first = colors.first {
            let texture = branding?["textureStrength"] as? Double ?? ((branding?["showsTexture"] as? Bool) == true ? 1 : 0)
            return SpaceTheme(colors: Array((colors + [first]).prefix(2)), intensity: 0.75, noise: max(0, min(1, texture)) * 0.5,
                              appearance: "auto", accent: first)
        }
        guard let hex = (space["accent"] as? String).flatMap({ swatches[$0] }) else { return nil }
        return SpaceTheme(colors: [hex, hex], intensity: 0.75, noise: 0, appearance: "auto", accent: hex)
    }
}
