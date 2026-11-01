import AppKit

// Chrome, Brave, Edge, Vivaldi, Opera, Chromium and Helium (and Arc's and Dia's own
// Chromium profiles for passwords and cookies). Dia's import lists the same
// browsers; each profile becomes a space with its bookmarks bar pinned and its
// last session's tabs in Today.

struct ChromiumProfile: Identifiable, Hashable {
    let id: String      // folder name: "Default", "Profile 1"
    let name: String    // shown name from Local State
    let dir: URL
}

enum ChromiumImporter {
    /// Profile folders under a "User Data" root, named as the browser shows them.
    /// Opera keeps its single profile in the root itself.
    static func profiles(userData: URL) -> [ChromiumProfile] {
        let fm = FileManager.default
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: userData.appendingPathComponent("Local State")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            for (dir, info) in cache { if let n = (info as? [String: Any])?["name"] as? String { names[dir] = n } }
        }
        let dirs = ((try? fm.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { $0 == "Default" ? true : ($1 == "Default" ? false : $0.localizedStandardCompare($1) == .orderedAscending) }
        var out = dirs.compactMap { d -> ChromiumProfile? in
            let dir = userData.appendingPathComponent(d, isDirectory: true)
            guard hasData(dir) else { return nil }
            return ChromiumProfile(id: d, name: names[d] ?? (d == "Default" ? "Default" : d), dir: dir)
        }
        if out.isEmpty && hasData(userData) { out = [ChromiumProfile(id: "Default", name: "Default", dir: userData)] }
        return out
    }

    private static func hasData(_ dir: URL) -> Bool {
        ["Bookmarks", "History", "Cookies", "Login Data"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    // MARK: Plan

    static func plan(browser: String, userData: URL) throws -> ImportPlan {
        let profiles = profiles(userData: userData)
        guard !profiles.isEmpty else { throw ImportError.notFound(browser) }
        var plan = ImportPlan(source: browser)
        for p in profiles {
            let title = profiles.count == 1 ? browser : "\(browser) · \(p.name)"
            var space = ImportedSpace(title: title, emoji: "🌐", theme: nil)
            let bm = bookmarks(profile: p.dir)
            space.pinned = bm.bar + (bm.other.isEmpty ? [] : [ImportedItem(customTitle: "Other Bookmarks", pageTitle: "Other Bookmarks", url: nil, isFolder: true, children: bm.other)])
            space.today = openTabs(profile: p.dir)
            if !space.pinned.isEmpty || !space.today.isEmpty { plan.spaces.append(space) }
        }
        return plan
    }

    static func bookmarks(profile dir: URL) -> (bar: [ImportedItem], other: [ImportedItem]) {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("Bookmarks")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return ([], []) }
        func convert(_ node: [String: Any]) -> ImportedItem? {
            let name = node["name"] as? String ?? ""
            let created = (node["date_added"] as? String).flatMap(Int64.init).map(date) ?? Date()
            if node["type"] as? String == "url", let u = node["url"] as? String, u.hasPrefix("http") {
                return ImportedItem(customTitle: name.isEmpty ? nil : name, pageTitle: name, url: u, createdAt: created)
            }
            if node["type"] as? String == "folder" {
                let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                return kids.isEmpty ? nil : ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids, createdAt: created)
            }
            return nil
        }
        func children(_ key: String) -> [ImportedItem] {
            ((roots[key] as? [String: Any])?["children"] as? [[String: Any]] ?? []).compactMap(convert)
        }
        return (children("bookmark_bar"), children("other") + children("synced"))
    }

    static func date(_ chromiumMicros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(chromiumMicros) / 1_000_000 - Double(ChromiumTime.epochDelta))
    }

    // MARK: Session (SNSS)

    /// The tabs of the last session, from the newest Sessions/Session_* file
    /// (older Chromium: "Current Session"). Commands are
    /// `uint16 size, uint8 id, payload`; ids from session_service_commands.cc.
    static func openTabs(profile dir: URL) -> [ImportedItem] {
        let fm = FileManager.default
        let sessions = dir.appendingPathComponent("Sessions", isDirectory: true)
        let candidates = ((try? fm.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Session_") }
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast
                > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast }
        let file = candidates.first ?? dir.appendingPathComponent("Current Session")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return parseSession(data)
    }

    static func parseSession(_ data: Data) -> [ImportedItem] {
        let b = [UInt8](data)
        guard b.count > 8, b[0] == 0x53, b[1] == 0x4E, b[2] == 0x53, b[3] == 0x53 else { return [] }
        let version = le32(b, 4)
        guard version == 1 || version == 3 else { return [] }   // 2 and 4 are encrypted
        struct Tab { var window: Int32 = 0; var index: Int32 = 0; var selected: Int32 = -1; var navs: [Int32: (String, String)] = [:] }
        var tabs: [Int32: Tab] = [:], closedTabs = Set<Int32>(), closedWindows = Set<Int32>()
        var p = 8
        while p + 3 <= b.count {
            let size = Int(UInt16(b[p]) | UInt16(b[p + 1]) << 8)
            guard size >= 1, p + 2 + size <= b.count else { break }
            let id = b[p + 2]
            let body = Array(b[(p + 3)..<(p + 2 + size)])
            p += 2 + size
            switch id {
            case 0 where body.count >= 8:   // SetTabWindow {window, tab}
                tabs[le32s(body, 4), default: Tab()].window = le32s(body, 0)
            case 2 where body.count >= 8:   // SetTabIndexInWindow {tab, index}
                tabs[le32s(body, 0), default: Tab()].index = le32s(body, 4)
            case 6:                         // UpdateTabNavigation (pickle)
                var r = PickleReader(body)
                guard let tab = r.int32(), let idx = r.int32(), let url = r.string() else { continue }
                let title = r.string16() ?? ""
                tabs[tab, default: Tab()].navs[idx] = (url, title)
            case 7 where body.count >= 8:   // SetSelectedNavigationIndex {tab, index}
                tabs[le32s(body, 0), default: Tab()].selected = le32s(body, 4)
            case 16 where body.count >= 4:  // TabClosed
                closedTabs.insert(le32s(body, 0))
            case 17 where body.count >= 4:  // WindowClosed
                closedWindows.insert(le32s(body, 0))
            default: break
            }
        }
        return tabs.filter { !closedTabs.contains($0.key) && !closedWindows.contains($0.value.window) }
            .sorted { ($0.value.window, $0.value.index) < ($1.value.window, $1.value.index) }
            .compactMap { _, t -> ImportedItem? in
                guard let nav = t.navs[t.selected] ?? t.navs.max(by: { $0.key < $1.key })?.value, nav.0.hasPrefix("http") else { return nil }
                return ImportedItem(pageTitle: nav.1, url: nav.0)
            }
    }

    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    private static func le32s(_ b: [UInt8], _ i: Int) -> Int32 { Int32(bitPattern: le32(b, i)) }

    /// base::Pickle: uint32 payload size, then 4-byte aligned fields.
    private struct PickleReader {
        let b: [UInt8]
        var p = 4
        init(_ b: [UInt8]) { self.b = b }
        mutating func int32() -> Int32? {
            guard p + 4 <= b.count else { return nil }
            defer { p += 4 }
            return ChromiumImporter.le32s(b, p)
        }
        mutating func string() -> String? {
            guard let n = int32(), n >= 0, p + Int(n) <= b.count else { return nil }
            defer { p += (Int(n) + 3) & ~3 }
            return String(decoding: b[p..<(p + Int(n))], as: UTF8.self)
        }
        mutating func string16() -> String? {
            guard let n = int32(), n >= 0, p + Int(n) * 2 <= b.count else { return nil }
            let units = stride(from: p, to: p + Int(n) * 2, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
            p += (Int(n) * 2 + 3) & ~3
            return String(decoding: units, as: UTF16.self)
        }
    }

    // MARK: Top sites

    /// Most visited sites, one per host, for Dia's pinned-tabs step (rankedTopSitesTask).
    static func topSites(userData: URL, limit: Int) -> [TopSite] {
        var visits: [String: TopSite] = [:]
        for p in profiles(userData: userData) {
            guard let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("History")) else { continue }
            for r in db.rows("SELECT url, title, visit_count FROM urls WHERE hidden = 0 ORDER BY visit_count DESC LIMIT 400") {
                guard let u = r["url"] as? String, let site = TopSite(url: u, title: r["title"] as? String ?? "", visits: Int(r["visit_count"] as? Int64 ?? 0)) else { continue }
                visits[site.host, default: TopSite(host: site.host, url: site.url, title: site.title, visits: 0)].visits += site.visits
            }
        }
        return Array(visits.values.sorted { $0.visits > $1.visits }.prefix(limit))
    }

    /// The largest cached icon for each host, from the profiles' Favicons
    /// databases (Dia imports Chromium favicons the same way).
    static func favicons(userData: URL, hosts: [String]) -> [String: NSImage] {
        var out: [String: NSImage] = [:]
        for p in profiles(userData: userData) {
            guard let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Favicons")) else { continue }
            for host in hosts where out[host] == nil {
                let h = host.replacingOccurrences(of: "'", with: "")
                let rows = db.rows("""
                    SELECT fb.image_data FROM favicon_bitmaps fb JOIN icon_mapping im ON fb.icon_id = im.icon_id
                    WHERE im.page_url LIKE 'https://\(h)/%' OR im.page_url LIKE 'https://www.\(h)/%'
                    ORDER BY fb.width DESC LIMIT 1
                    """)
                if let data = rows.first?["image_data"] as? Data, let img = NSImage(data: data) { out[host] = img }
            }
        }
        return out
    }

    // MARK: Passwords and cookies

    /// Decrypts each picked profile's cookies and saved logins with the
    /// browser's Keychain secret (one macOS password prompt per browser).
    static func credentials(browser: String, profiles: [ChromiumProfile], keychainService: String, keychainAccount: String,
                            cookies: Bool, passwords: Bool) throws -> ImportedCredentials {
        guard let secret = ChromiumCrypto.keychainSecret(service: keychainService, account: keychainAccount) else {
            throw CredentialImportError.keychainDenied(browser)
        }
        return try credentials(browser: browser, profiles: profiles, secret: secret, cookies: cookies, passwords: passwords)
    }

    /// The same with a secret already read (Dia's sidebar needs it too: one prompt for both).
    static func credentials(browser: String, profiles: [ChromiumProfile], secret: String,
                            cookies: Bool, passwords: Bool) throws -> ImportedCredentials {
        let key = ChromiumCrypto.key(fromSecret: secret)
        var out = ImportedCredentials()
        var readAny = false
        for p in profiles {
            if cookies, let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Cookies"))
                ?? SQLiteSnapshot(copying: p.dir.appendingPathComponent("Network/Cookies")) {
                readAny = true
                out.cookies += readCookies(db, key: key)
            }
            if passwords, let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Login Data")) {
                readAny = true
                out.logins += readLogins(db, key: key)
            }
        }
        if !readAny && (cookies || passwords) { throw CredentialImportError.unreadable(browser) }
        return out
    }

    private static func readCookies(_ db: SQLiteSnapshot, key: Data) -> [ImportedCookie] {
        let version = Int(db.scalar("SELECT value FROM meta WHERE key = 'version'") as? String ?? "") ?? 0
        let now = ChromiumTime.now
        let partitioned = db.columns(of: "cookies").contains("top_frame_site_key") ? "AND top_frame_site_key = ''" : ""
        return db.rows("SELECT host_key, name, value, encrypted_value, path, expires_utc, creation_utc, last_access_utc, is_secure, is_httponly, samesite FROM cookies WHERE (expires_utc = 0 OR expires_utc > \(now)) \(partitioned)").compactMap { r in
            guard let host = r["host_key"] as? String, let name = r["name"] as? String else { return nil }
            var value = r["value"] as? String ?? ""
            if value.isEmpty, let blob = r["encrypted_value"] as? Data, !blob.isEmpty {
                guard var plain = ChromiumCrypto.decrypt(blob, key: key) else { return nil }
                if version >= 24 {
                    // A wrong key can still unpad; the host digest proves the key was right.
                    guard plain.count >= 32, plain.prefix(32) == ChromiumCrypto.hostDigest(host) else { return nil }
                    plain = plain.dropFirst(32)
                }
                guard let s = String(data: plain, encoding: .utf8) else { return nil }
                value = s
            }
            return ImportedCookie(host: host, name: name, value: value, path: r["path"] as? String ?? "/",
                                  expires: r["expires_utc"] as? Int64 ?? 0, created: r["creation_utc"] as? Int64 ?? now,
                                  lastAccess: r["last_access_utc"] as? Int64 ?? now, secure: (r["is_secure"] as? Int64 ?? 0) != 0,
                                  httpOnly: (r["is_httponly"] as? Int64 ?? 0) != 0, sameSite: Int(r["samesite"] as? Int64 ?? -1))
        }
    }

    private static func readLogins(_ db: SQLiteSnapshot, key: Data) -> [ImportedLogin] {
        db.rows("SELECT origin_url, action_url, username_element, username_value, password_element, password_value, signon_realm, date_created FROM logins WHERE blacklisted_by_user = 0").compactMap { r in
            guard let blob = r["password_value"] as? Data, let plain = ChromiumCrypto.decrypt(blob, key: key),
                  let password = String(data: plain, encoding: .utf8), !password.isEmpty,
                  let realm = r["signon_realm"] as? String, let origin = r["origin_url"] as? String else { return nil }
            return ImportedLogin(originURL: origin, actionURL: r["action_url"] as? String ?? "",
                                 usernameElement: r["username_element"] as? String ?? "", username: r["username_value"] as? String ?? "",
                                 passwordElement: r["password_element"] as? String ?? "", password: password, signonRealm: realm,
                                 created: r["date_created"] as? Int64 ?? ChromiumTime.now)
        }
    }
}

/// A frequently visited site, for suggestions on the pinned tabs step.
struct TopSite: Hashable {
    var host: String
    var url: String
    var title: String
    var visits: Int

    init(host: String, url: String, title: String, visits: Int) {
        self.host = host; self.url = url; self.title = title; self.visits = visits
    }

    /// Reduced to the site's front page; nil for non-web URLs and search results.
    init?(url: String, title: String, visits: Int) {
        guard let u = URL(string: url), let scheme = u.scheme, scheme.hasPrefix("http"), var host = u.host else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let skip = ["google.", "bing.com", "duckduckgo.com", "localhost", "127.0.0.1", "accounts.", "login.", "auth."]
        if skip.contains(where: { host.hasPrefix($0) }) { return nil }
        self.host = host
        self.url = "https://\(u.host ?? host)/"
        self.title = title
        self.visits = visits
    }
}
