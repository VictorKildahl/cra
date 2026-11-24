import AppKit
import Compression

// Firefox (and Zen's bookmarks and favicons, see ZenImporter): bookmarks from places.sqlite and
// open tabs from the session store (mozLz4). Saved logins come in only through
// Firefox's own export (about:logins ▸ Export Passwords…), read with
// PasswordCSV like Safari's exported Passwords.csv.

enum FirefoxImporter {
    /// The default profile from profiles.ini: the [Install…] section's Default,
    /// else the [Profile…] marked Default=1, else the first.
    static func defaultProfile(root: URL) -> URL? {
        guard let ini = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return nil }
        var sections: [(name: String, values: [String: String])] = []
        for raw in ini.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { sections.append((String(line.dropFirst().dropLast()), [:])) }
            else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1].values[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        func resolve(_ path: String, relative: Bool) -> URL? {
            let u = relative ? root.appendingPathComponent(path, isDirectory: true) : URL(fileURLWithPath: path, isDirectory: true)
            return FileManager.default.fileExists(atPath: u.appendingPathComponent("places.sqlite").path) ? u : nil
        }
        if let install = sections.first(where: { $0.name.hasPrefix("Install") }), let p = install.values["Default"],
           let u = resolve(p, relative: !p.hasPrefix("/")) { return u }
        let profiles = sections.filter { $0.name.hasPrefix("Profile") }
            .sorted { ($0.values["Default"] == "1") && !($1.values["Default"] == "1") }
        for s in profiles {
            if let p = s.values["Path"], let u = resolve(p, relative: s.values["IsRelative"] != "0") { return u }
        }
        return nil
    }

    static func plan(browser: String, root: URL) throws -> ImportPlan {
        guard let profile = defaultProfile(root: root) else { throw ImportError.notFound(browser) }
        var plan = ImportPlan(source: browser)
        var space = ImportedSpace(title: browser, emoji: "🦊", theme: nil)
        var skipped: [ImportSkip] = []
        if let db = SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite")) {
            space.pinned = bookmarks(db, skip: { skipped.append($0) })
        }
        space.today = openTabs(profile: profile, skip: { skipped.append($0) })
        space.skipped = skipped
        if !space.pinned.isEmpty || !space.today.isEmpty { plan.spaces.append(space) } else { plan.skipped = skipped }
        ImportFavicons.attach(to: &plan, folder: "cra-firefox-favicons", from: ImportSource.Kind.firefox.iconStores(dataDir: root))
        return plan
    }

    /// `skip` hears of each bookmark left out.
    static func bookmarks(profile: URL, skip: (ImportSkip) -> Void = { _ in }) -> [ImportedItem] {
        SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite")).map { bookmarks($0, skip: skip) } ?? []
    }

    /// The toolbar's bookmarks, then the menu and unsorted bookmarks as folders.
    private static func bookmarks(_ db: SQLiteSnapshot, skip: (ImportSkip) -> Void) -> [ImportedItem] {
        let rows = db.rows("""
            SELECT b.id, b.type, b.parent, b.title, b.guid, b.dateAdded, p.url, p.title AS ptitle
            FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk = p.id ORDER BY b.parent, b.position
            """)
        var children: [Int64: [[String: Any]]] = [:]
        var idByGUID: [String: Int64] = [:]
        for r in rows {
            guard let id = r["id"] as? Int64 else { continue }
            if let g = r["guid"] as? String { idByGUID[g] = id }
            if let parent = r["parent"] as? Int64 { children[parent, default: []].append(r) }
        }
        func convert(_ r: [String: Any]) -> ImportedItem? {
            let title = r["title"] as? String ?? ""
            // dateAdded is µs since 1970.
            let created = (r["dateAdded"] as? Int64).map { Date(timeIntervalSince1970: Double($0) / 1_000_000) } ?? Date()
            switch r["type"] as? Int64 {
            case 1:
                guard let u = r["url"] as? String, ImportedAddress.keeps(u) else {
                    ImportSkip.leftOut(r["url"] as? String, title: title.isEmpty ? (r["ptitle"] as? String ?? "") : title).map(skip)
                    return nil
                }
                return ImportedItem(customTitle: title.isEmpty ? nil : title, pageTitle: title.isEmpty ? (r["ptitle"] as? String ?? "") : title,
                                    url: u, createdAt: created)
            case 2:
                guard let id = r["id"] as? Int64 else { return nil }
                let kids = (children[id] ?? []).compactMap(convert)
                return kids.isEmpty ? nil : ImportedItem(customTitle: title, pageTitle: title, url: nil, isFolder: true, children: kids, createdAt: created)
            default:
                return nil
            }
        }
        func items(_ guid: String) -> [ImportedItem] { idByGUID[guid].map { (children[$0] ?? []).compactMap(convert) } ?? [] }
        var out = items("toolbar_____")
        for (guid, name) in [("menu________", "Bookmarks Menu"), ("unfiled_____", "Other Bookmarks")] {
            let kids = items(guid)
            if !kids.isEmpty { out.append(ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids)) }
        }
        return out
    }

    /// The current tab of every open window, from recovery.jsonlz4 while
    /// Firefox runs or sessionstore.jsonlz4 after it quit. `skip` hears of each tab left out, or of
    /// a session store that could not be read.
    static func openTabs(profile: URL, skip: (ImportSkip) -> Void = { _ in }) -> [ImportedItem] {
        let candidates = ["sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4", "sessionstore-backups/previous.jsonlz4"]
            .map { profile.appendingPathComponent($0) }
        guard let (file, data) = candidates.lazy.compactMap({ f in (try? Data(contentsOf: f)).map { (f, $0) } }).first else { return [] }
        guard let json = mozLz4(data),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            skip(.unreadable("Open tabs", file: file.path))
            return []
        }
        var out: [ImportedItem] = []
        for w in root["windows"] as? [[String: Any]] ?? [] {
            for t in w["tabs"] as? [[String: Any]] ?? [] {
                guard let entries = t["entries"] as? [[String: Any]], !entries.isEmpty else { continue }
                let index = min(max((t["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)
                guard let u = entries[index]["url"] as? String, ImportedAddress.keeps(u) else {
                    ImportSkip.leftOut(entries[index]["url"] as? String, title: entries[index]["title"] as? String ?? "").map(skip)
                    continue
                }
                out.append(ImportedItem(pageTitle: entries[index]["title"] as? String ?? "", url: u))
            }
        }
        return out
    }

    /// "mozLz40\0", uint32 decompressed size, one raw LZ4 block.
    static func mozLz4(_ data: Data) -> Data? {
        guard data.count > 12, data.prefix(8) == Data("mozLz40\0".utf8) else { return nil }
        let size = data.subdata(in: 8..<12).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        guard size > 0, size < 512 << 20 else { return nil }
        var out = Data(count: size)
        let src = data.subdata(in: 12..<data.count)
        let n = out.withUnsafeMutableBytes { o in src.withUnsafeBytes { s in
            compression_decode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, size, s.bindMemory(to: UInt8.self).baseAddress!, src.count, nil, COMPRESSION_LZ4_RAW)
        } }
        return n == size ? out : nil
    }

    /// The largest icon per host from favicons.sqlite, read in one pass over its pages, which have no
    /// index on page_url.
    static func favicons(root: URL, hosts: [String]) -> [String: Data] {
        guard let profile = defaultProfile(root: root),
              let db = SQLiteSnapshot(copying: profile.appendingPathComponent("favicons.sqlite")) else { return [:] }
        var wanted: [String: [String]] = [:]
        for host in hosts { for name in ImportFavicons.names(of: host) { wanted[name, default: []].append(host) } }
        var best: [String: (icon: Int64, width: Int64)] = [:]
        for r in db.rows("SELECT p.page_url, i.id, i.width FROM moz_pages_w_icons p JOIN moz_icons_to_pages ip ON ip.page_id = p.id JOIN moz_icons i ON i.id = ip.icon_id") {
            guard let page = r["page_url"] as? String, let icon = r["id"] as? Int64, let width = r["width"] as? Int64,
                  let owners = ImportFavicons.webHost(page).flatMap({ wanted[$0] }) else { continue }
            for host in owners where width > best[host]?.width ?? -1 { best[host] = (icon, width) }
        }
        guard !best.isEmpty else { return [:] }
        let ids = Set(best.values.map(\.icon)).map(String.init).joined(separator: ",")
        var images: [Int64: Data] = [:]
        for r in db.rows("SELECT id, data FROM moz_icons WHERE id IN (\(ids))") {
            if let id = r["id"] as? Int64, let data = r["data"] as? Data { images[id] = data }
        }
        return best.compactMapValues { images[$0.icon] }
    }

    static func topSites(root: URL, limit: Int) -> [TopSite] {
        guard let profile = defaultProfile(root: root),
              let db = SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite")) else { return [] }
        var byHost: [String: TopSite] = [:]
        for r in db.rows("SELECT url, title, visit_count FROM moz_places WHERE hidden = 0 AND visit_count > 0 ORDER BY frecency DESC LIMIT 400") {
            guard let u = r["url"] as? String, let site = TopSite(url: u, title: r["title"] as? String ?? "", visits: Int(r["visit_count"] as? Int64 ?? 0)) else { continue }
            byHost[site.host, default: TopSite(host: site.host, url: site.url, title: site.title, visits: 0)].visits += site.visits
        }
        return Array(byHost.values.sorted { $0.visits > $1.visits }.prefix(limit))
    }
}

/// Exported password files: Firefox (url, username, password, …) and Safari
/// (Title, URL, Username, Password, Notes, OTPAuth). Columns are found by name.
enum PasswordCSV {
    static func logins(in text: String) -> [ImportedLogin] {
        var rows = parse(text)
        guard !rows.isEmpty else { return [] }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard let urlCol = header.firstIndex(where: { $0 == "url" || $0 == "origin" }),
              let userCol = header.firstIndex(where: { $0 == "username" || $0 == "login" }),
              let passCol = header.firstIndex(of: "password") else { return [] }
        return rows.compactMap { r in
            guard r.count > max(urlCol, userCol, passCol) else { return nil }
            return ImportedLogin(url: r[urlCol], username: r[userCol], password: r[passCol])
        }
    }

    /// RFC 4180: quoted fields may hold commas, quotes ("") and newlines.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var it = Array(text.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar?
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = n } }
                    else { quoted = false }
                } else { field.unicodeScalars.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r" {
                if c == "\r", let n = it.next(), n != "\n" { pending = n }
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else { field.unicodeScalars.append(c) }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
