import AppKit

// Yab (folder "Fast" before Oct 2026) lists its spaces in <support>/spaces.json and keeps each
// space's tabs in a file of its own: session.json for the first space, session-<space id>.json for
// the others, and session-…0A11.json for the pinned tiles every space shares when "pins in every
// space" is on. Each entry is one tab, in sidebar order: a tile (`pin`, Arc's favorite), then kept
// tabs (`kept`, Arc's pinned), then today's. A kept tab names its folder (`folder`, `folderName`)
// and the folders that one is in (`folderPath`, from the top down).
//
// Its Chromium profiles are <support>/Chromium/space-<id>: the shared one for spaces that use the
// first space's sign-ins, and one per space with sign-ins of its own, found through the receipts
// in <support>/ChromiumProfiles. Its saved passwords are Keychain items of its own, not Chromium's.

enum YabImporter {
    /// CRA_YAB_DIR points a test instance at a made-up profile (Tests/Fixtures/Yab).
    static var supportDir: URL {
        if let dir = ProcessInfo.processInfo.environment["CRA_YAB_DIR"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dirs = ["Yab", "Fast"].map { support.appendingPathComponent($0, isDirectory: true) }
        return dirs.first(where: hasSidebar) ?? dirs[0]
    }
    static var userData: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }

    static var isAvailable: Bool { hasSidebar(supportDir) }

    private static func hasSidebar(_ dir: URL) -> Bool {
        ["spaces.json", "session.json"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    static let firstID = "00000000-0000-0000-0000-000000000001"
    static let sharedPinsID = "00000000-0000-0000-0000-000000000A11"

    static func plan() throws -> ImportPlan {
        guard isAvailable else { throw ImportError.notFound("Yab") }
        // Yab's Settings › Tabs "Pins in every space"; without it, a space with no tiles of its own
        // shows the shared ones.
        let everySpace = UserDefaults(suiteName: "dev.serafim.fast")?.object(forKey: "pins.everySpace") as? Bool
        var plan = try plan(supportDir: supportDir, pinsInEverySpace: everySpace)
        ImportFavicons.attach(to: &plan.spaces, folder: "cra-yab-favicons") { ChromiumImporter.favicons(userData: userData, hosts: $0) }
        return plan
    }

    static func plan(supportDir dir: URL, pinsInEverySpace: Bool?) throws -> ImportPlan {
        var spaces: [[String: Any]] = [["id": firstID, "name": "Personal", "icon": "🏠", "ownSignIns": false]]
        if let data = try? Data(contentsOf: dir.appendingPathComponent("spaces.json")) {
            guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ImportError.unreadable("Yab's spaces") }
            if !list.isEmpty { spaces = list }
        }
        let shared = entries(dir.appendingPathComponent("session-\(sharedPinsID).json"))
        var plan = ImportPlan(source: "Yab")

        for s in spaces {
            guard let id = s["id"] as? String else { continue }
            let file = id.uppercased() == firstID ? "session.json" : "session-\(id.uppercased()).json"
            var rows = entries(dir.appendingPathComponent(file))
            let ownTiles = rows.contains { isTile($0) }
            if pinsInEverySpace == true || (pinsInEverySpace == nil && !ownTiles) {
                rows = shared.filter(isTile) + rows.filter { !isTile($0) }
            }

            var favorites: [ImportedItem] = []
            let kept = ImportTree()
            var today: [ImportedItem] = []
            for e in rows {
                let pinned = isTile(e) || e["kept"] as? Bool == true
                guard let item = item(e, pinned: pinned) else { continue }
                if isTile(e) {
                    if !favorites.contains(where: { $0.url == item.url }) { favorites.append(item) }
                } else if pinned {
                    kept.insert(item, path: folderChain(e))
                } else {
                    today.append(item)
                }
            }

            let name = (s["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space"
            let icon = icon(s["icon"] as? String)
            var space = ImportedSpace(title: name, emoji: icon.emoji, symbol: icon.symbol, theme: theme(s["paint"] as? [String: Any]))
            space.favorites = favorites
            space.pinned = kept.items
            space.today = today
            space.profile = profile(of: s, among: spaces, supportDir: dir)
            plan.spaces.append(space)
        }
        return plan
    }

    private static func entries(_ file: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: file),
              let shape = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return shape["tabs"] as? [[String: Any]] ?? []
    }

    private static func isTile(_ e: [String: Any]) -> Bool { (e["pin"] as? String).map { !$0.isEmpty } ?? false }

    /// A tile or kept tab keeps the page it was pinned with (`home`), not where it navigated.
    private static func item(_ e: [String: Any], pinned: Bool) -> ImportedItem? {
        let home = pinned ? (e["home"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
        guard let url = home ?? e["url"] as? String, url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
        let title = (home != nil ? e["homeTitle"] as? String : nil).flatMap { $0.isEmpty ? nil : $0 } ?? e["title"] as? String ?? ""
        let custom = (e["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ImportedItem(customTitle: custom, pageTitle: title, url: url)
    }

    private static func folderChain(_ e: [String: Any]) -> [(id: String, name: String)] {
        guard let folder = e["folder"] as? String, !folder.isEmpty else { return [] }
        func named(_ s: Any?) -> String { (s as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Folder" }
        let parents = (e["folderPath"] as? [[String: Any]] ?? []).compactMap { step in (step["id"] as? String).map { ($0, named(step["name"])) } }
        return parents + [(folder, named(e["folderName"]))]
    }

    /// An emoji or the name of an SF Symbol from Yab's Icon tab.
    static func icon(_ raw: String?) -> (emoji: String, symbol: String?) {
        guard let raw, !raw.isEmpty else { return ("", nil) }
        let isName = raw.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == ".") }
        guard isName else { return (raw, nil) }
        return NSImage(systemSymbolName: raw, accessibilityDescription: nil) != nil ? ("", raw) : ("🗂️", nil)
    }

    /// Yab's swatches in a light window (its Design.swift); "custom" uses the space's own colour.
    static let swatches: [String: String] = [
        "gray": "#E3E3E5", "paper": "#ECEAE4", "coral": "#F2837C", "peach": "#F5BB8C", "sage": "#A8C3A0",
        "sky": "#8DB6E6", "lavender": "#B6A6E6", "rose": "#EEA2C4", "graphite": "#3B3B3E", "plain": "#FFFFFF",
    ]

    static func theme(_ paint: [String: Any]?) -> SpaceTheme? {
        guard let paint else { return nil }
        let own = (paint["colors"] as? [String] ?? []).compactMap(hex)
        let swatch = paint["swatch"] as? String ?? "custom"
        guard let first = own.first ?? (swatch == "custom" ? (paint["color"] as? String).flatMap(hex) : swatches[swatch]) else { return nil }
        let grain = paint["grainAmount"] as? Double ?? ((paint["grain"] as? Bool) == true ? 0.3 : 0)
        let mode = paint["mode"] as? String
        return SpaceTheme(colors: Array((own.isEmpty ? [first, first] : own + [first]).prefix(2)), intensity: 0.75,
                          noise: max(0, min(1, grain)), appearance: mode == "light" || mode == "dark" ? mode! : "auto", accent: first)
    }

    private static func hex(_ s: String) -> String? {
        let h = s.hasPrefix("#") ? s : "#" + s
        return HexColor.components(h) != nil ? h.uppercased() : nil
    }

    /// The Chromium profile folder a space signs in with, for a space with sign-ins of its own;
    /// nil for the spaces sharing the first space's.
    private static func profile(of s: [String: Any], among spaces: [[String: Any]], supportDir dir: URL) -> ImportedProfile? {
        guard s["ownSignIns"] as? Bool == true, let id = s["id"] as? String else { return nil }
        let logical = ((s["signInWith"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id).uppercased()
        let chromium = dir.appendingPathComponent("Chromium", isDirectory: true)
        let receipt = dir.appendingPathComponent("ChromiumProfiles/\(logical)-named.json")
        let physical = (try? Data(contentsOf: receipt)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["physical"] as? String
        guard let folder = [physical, logical].compactMap({ $0.map { "space-\($0.uppercased())" } })
            .first(where: { FileManager.default.fileExists(atPath: chromium.appendingPathComponent($0).path) }) else { return nil }
        let owner = spaces.first { ($0["id"] as? String)?.uppercased() == logical }
        let name = (owner?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (s["name"] as? String) ?? "Yab"
        return ImportedProfile(folder: folder, name: name)
    }

    /// The names Yab shows for its Chromium profile folders: the space whose sign-ins each holds,
    /// or "Shared" for the one the other spaces use.
    static func profileNames(supportDir dir: URL) -> [String: String] {
        guard let plan = try? plan(supportDir: dir, pinsInEverySpace: false) else { return [:] }
        var names: [String: String] = [:]
        let receipt = dir.appendingPathComponent("ChromiumProfiles/\(firstID)-shared.json")
        let shared = (try? Data(contentsOf: receipt)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["physical"] as? String
        names["space-\((shared ?? firstID).uppercased())"] = "Shared"
        for sp in plan.spaces { if let p = sp.profile { names[p.folder] = p.name } }
        return names
    }
}
