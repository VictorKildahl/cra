import AppKit

// Phi (Phinomenon's open-source browser, github.com/phibrowser/phibrowser-mac) runs Chromium straight
// in its Application Support folder, com.phibrowser.Mac ("Default", "Profile <n>", "Phi Safe Storage"),
// and keeps its sidebar in a SwiftData store of its own beside it:
// Phi/users/<account>/localDB/LocalStore.sqlite (store format 14 as of Nov 2026, Core Data's tables).
//
// ZSPACEMODEL holds the spaces, each on one Chromium profile (`profileId`) and with a bookmark tree
// (`bookmarkRoot`), which is its pinned section: bookmarks (type 2) and folders (type 3) in
// ZTABDATAMODEL, nested through `parent`, ordered by `index`. Pinned tabs (type 1) are Arc's
// favorites; whose they are follows the store's Pinned Tab Scope: a space's (`spaceId` set), a
// profile's (only `profileId`), or every space's (neither). Rows of the other scopes are Phi's
// backups from the last scope change and stay behind. Open tabs (type 0) live in Chromium's session.

enum PhiImporter {
    /// CRA_PHI_DIR points a test instance at a made-up profile (Tests/Fixtures/Phi).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_PHI_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.phibrowser.Mac", isDirectory: true)
    static var userData: URL { supportDir }

    /// The store of the account Phi used last: each account (and the signed-out one) has its own.
    static var storeFile: URL? {
        let users = supportDir.appendingPathComponent("Phi/users", isDirectory: true)
        let fm = FileManager.default
        func modified(_ url: URL) -> Date {
            ["", "-wal"].compactMap { (try? fm.attributesOfItem(atPath: url.path + $0))?[.modificationDate] as? Date }.max() ?? .distantPast
        }
        return ((try? fm.contentsOfDirectory(atPath: users.path)) ?? [])
            .map { users.appendingPathComponent($0, isDirectory: true).appendingPathComponent("localDB/LocalStore.sqlite") }
            .filter { fm.fileExists(atPath: $0.path) }
            .max { modified($0) < modified($1) }
    }

    static var isAvailable: Bool { storeFile != nil }

    static func plan() throws -> ImportPlan {
        guard let store = storeFile else { throw ImportError.notFound("Phi") }
        var plan = try plan(store: store)
        ImportFavicons.attach(to: &plan, folder: "cra-phi-favicons", from: ImportSource.Kind.phi.iconStores(dataDir: userData))
        return plan
    }

    /// Phi's agent spaces (AgentSpaceManager): the robot icon in grey with an "R<n>" name, or in
    /// purple for one that outlives its task. They are an agent's scratch space, not the person's.
    static func isAgentSpace(name: String, icon: String, color: String) -> Bool {
        guard icon == "emoji:1F916" else { return false }
        let ordinal = name.hasPrefix("R") && name.count > 1 && name.dropFirst().allSatisfy(\.isNumber)
        return (ordinal && color == "#8E8E93") || color == "#5856D6"
    }

    static func plan(store: URL) throws -> ImportPlan {
        guard let db = SQLiteSnapshot(copying: store) else { throw ImportError.notFound("Phi") }
        guard !db.columns(of: "ZSPACEMODEL").isEmpty, !db.columns(of: "ZTABDATAMODEL").isEmpty else {
            throw ImportError.unreadable("Phi's spaces")
        }
        var plan = ImportPlan(source: "Phi")
        let rows = db.rows("SELECT * FROM ZTABDATAMODEL")
        var byID: [Int64: [String: Any]] = [:]
        var children: [Int64: [[String: Any]]] = [:]
        for r in rows {
            guard let id = r["Z_PK"] as? Int64 else { continue }
            byID[id] = r
            if let parent = r["ZPARENT"] as? Int64 { children[parent, default: []].append(r) }
        }
        func ordered(_ rs: [[String: Any]]) -> [[String: Any]] {
            rs.sorted { (int($0["ZINDEX"]), int($0["Z_PK"])) < (int($1["ZINDEX"]), int($1["Z_PK"])) }
        }

        // Profile names: Phi's own, else Chromium's.
        var profileNames = ChromiumImporter.profileNames(userData: userData)
        for p in db.rows("SELECT ZPROFILEID, ZDISPLAYNAME FROM ZPROFILEMODEL") {
            if let id = p["ZPROFILEID"] as? String, let name = text(p["ZDISPLAYNAME"]) { profileNames[id] = name }
        }

        // Pinned tabs in the store's scope; Phi's own default is the profile.
        let scope = db.rows("SELECT ZPINNEDTABSCOPERAWVALUE AS s FROM ZBROWSERDATASETTINGSMODEL").first?["s"] as? String ?? "profile"
        let pins = ordered(rows.filter { int($0["ZTYPE"]) == 1 && int($0["ZISPINNEDTABDORMANT"]) == 0 }).filter { r in
            let space = text(r["ZSPACEID"]), profile = text(r["ZPROFILEID"])
            switch scope {
            case "space": return space != nil && profile != nil
            case "app": return space == nil && profile == nil
            default: return space == nil && profile != nil
            }
        }

        let spaceRows = db.rows("SELECT * FROM ZSPACEMODEL").sorted {
            (int($0["ZSORTORDER"]), int($0["Z_PK"])) < (int($1["ZSORTORDER"]), int($1["Z_PK"]))
        }
        for s in spaceRows {
            let name = text(s["ZNAME"]) ?? "Space", iconName = s["ZICONNAME"] as? String ?? "", color = s["ZCOLORHEX"] as? String ?? ""
            guard let spaceID = text(s["ZSPACEID"]), !isAgentSpace(name: name, icon: iconName, color: color) else { continue }
            let profileID = text(s["ZPROFILEID"]) ?? "Default"
            var skipped: [ImportSkip] = []

            // The pinned section: the space's bookmark tree, without its root.
            func convert(_ r: [String: Any]) -> [ImportedItem] {
                let created = (r["ZCREATEDDATE"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
                switch int(r["ZTYPE"]) {
                case 3:
                    let title = text(r["ZTITLE"]) ?? "Folder"
                    let kids = ordered(children[int(r["Z_PK"])] ?? []).flatMap(convert)
                    return [ImportedItem(customTitle: title, pageTitle: title, url: nil, isFolder: true, children: kids, createdAt: created)]
                case 2:
                    return pages(of: r).compactMap { page in
                        guard ImportedAddress.keeps(page.url) else {
                            ImportSkip.leftOut(page.url, title: page.custom ?? page.title).map { skipped.append($0) }
                            return nil
                        }
                        return ImportedItem(customTitle: page.custom, pageTitle: page.title, url: page.url, createdAt: created)
                    }
                default: return []
                }
            }
            let root = (s["ZBOOKMARKROOT"] as? Int64)
                ?? rows.first { int($0["ZTYPE"]) == 3 && $0["ZPARENT"] == nil && text($0["ZSPACEID"]) == spaceID }?["Z_PK"] as? Int64
            let pinned = root.map { ordered(children[$0] ?? []).flatMap(convert) } ?? []

            // Favorites: the space's own pinned tabs, or the ones it shares with its profile or every space.
            let mine: [[String: Any]]
            var list: String?
            switch scope {
            case "space": mine = pins.filter { text($0["ZSPACEID"]) == spaceID }
            case "app": mine = pins; list = "app"
            default: mine = pins.filter { text($0["ZPROFILEID"]) == profileID }; list = "profile \(profileID)"
            }
            var favorites: [ImportedItem] = []
            for r in mine {
                let created = (r["ZCREATEDDATE"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
                guard let page = pages(of: r).first else { continue }
                guard ImportedAddress.keeps(page.url) else {
                    ImportSkip.leftOut(page.url, title: page.custom ?? page.title, kind: .favorites).map { skipped.append($0) }
                    continue
                }
                if !favorites.contains(where: { $0.url == page.url }) {
                    favorites.append(ImportedItem(customTitle: page.custom, pageTitle: page.title, url: page.url, createdAt: created))
                }
            }

            let icon = icon(iconName)
            var space = ImportedSpace(title: name, emoji: icon, theme: theme(color))
            space.favorites = favorites
            space.favoritesList = list
            space.pinned = pinned
            space.skipped = skipped
            if profileID != "Default" {
                space.profile = ImportedProfile(folder: profileID, name: profileNames[profileID] ?? name)
            }
            plan.spaces.append(space)
        }
        return plan
    }

    /// A bookmark's or pinned tab's pages: its own, then a split's second page and any after it.
    private static func pages(of r: [String: Any]) -> [(url: String, title: String, custom: String?)] {
        var out: [(url: String, title: String, custom: String?)] = []
        if let url = text(r["ZURL"]) { out.append((url, r["ZTITLE"] as? String ?? "", text(r["ZOVERRIDETITLE"]))) }
        if let url = text(r["ZSECONDARYURL"]) { out.append((url, r["ZSECONDARYTITLE"] as? String ?? "", nil)) }
        if let extra = text(r["ZSPLITEXTRAPANES"])?.data(using: .utf8),
           let panes = try? JSONSerialization.jsonObject(with: extra) as? [[String: Any]] {
            for p in panes { if let url = text(p["url"]) { out.append((url, p["title"] as? String ?? "", nil)) } }
        }
        return out
    }

    /// "emoji:<code points in hex>" is that emoji; Phi's own artwork ("phi:…") has no Cra match and is a dot.
    static func icon(_ raw: String) -> String {
        guard raw.hasPrefix("emoji:") else { return "" }
        var scalars = String.UnicodeScalarView()
        for part in raw.dropFirst("emoji:".count).split(separator: "-") {
            guard let v = UInt32(part, radix: 16), let s = Unicode.Scalar(v) else { return "" }
            scalars.append(s)
        }
        return String(scalars)
    }

    /// The space's colour (#RRGGBB) as a one-colour theme.
    static func theme(_ hex: String) -> SpaceTheme? {
        let h = hex.uppercased()
        guard h.count == 7, h.hasPrefix("#"), h.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return SpaceTheme(colors: [h, h], intensity: 0.75, noise: 0, appearance: "auto", accent: h)
    }

    private static func int(_ v: Any?) -> Int64 { v as? Int64 ?? 0 }
    private static func text(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
}
