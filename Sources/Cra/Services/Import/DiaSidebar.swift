import CommonCrypto
import CryptoKit
import Foundation

// Dia 1.55 keeps its sidebar (spaces, per-space favorites, pinned tabs and folders, open tabs)
// in User Data/<profile>/tabs.db, a SQLCipher 4 database with a raw key derived from the
// "Dia Safe Storage" secret (see docs/arc-reverse-engineering.md, "Dia 1.55 sidebar store").
// StorableProfileContainers.json and the bookmarks bar stopped following the sidebar then.

enum DiaSidebar {
    /// The HMAC key of Dia's DatabaseEncryptionKeyDerivationFunction, from its binary.
    private static let saltKey = Data(base64Encoded: "iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=")!
    /// SQLCipher 4 defaults: 4096-byte pages ending in a 16-byte IV and a 64-byte HMAC-SHA512.
    private static let pageSize = 4096, reserve = 80

    /// The profiles' tabs.db files, in profile folder order.
    static func databases(userData: URL) -> [(profile: String, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        return names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted().compactMap { name in
            let url = userData.appendingPathComponent(name).appendingPathComponent("tabs.db")
            return FileManager.default.fileExists(atPath: url.path) ? (name, url) : nil
        }
    }

    /// HKDF-SHA256 of Chromium's Safe Storage key, salted with HMAC-SHA256(saltKey, label);
    /// the label is "profile/<profile folder>/<database name>" (Dia's DatabaseController).
    static func key(rootKey: Data, label: String) -> Data {
        let info = Data(label.utf8)
        let salt = Data(HMAC<SHA256>.authenticationCode(for: info, using: SymmetricKey(data: saltKey)))
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: rootKey), salt: salt, info: info, outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    /// The database as plain SQLite, with the committed frames of its -wal folded in (Dia
    /// keeps the file open, so recent edits are often only there). Nil for a wrong key.
    static func decrypt(_ url: URL, key: Data) -> Data? {
        guard let file = try? Data(contentsOf: url), file.count >= pageSize, file.count % pageSize == 0 else { return nil }
        var pages: [Int: Data] = [:]
        var count = file.count / pageSize
        for i in 0..<count { pages[i + 1] = file.subdata(in: i * pageSize..<(i + 1) * pageSize) }
        if let wal = try? Data(contentsOf: URL(fileURLWithPath: url.path + "-wal")), wal.count > 32, be32(wal, 8) == pageSize {
            // Frames from an older generation of the log carry another salt; frames after
            // the last commit belong to an unfinished transaction.
            let salt = wal.subdata(in: 16..<24)
            var pending: [Int: Data] = [:]
            var off = 32
            while off + 24 + pageSize <= wal.count, wal.subdata(in: off + 8..<off + 16) == salt {
                pending[be32(wal, off)] = wal.subdata(in: off + 24..<off + 24 + pageSize)
                let commit = be32(wal, off + 4)
                if commit > 0 { pages.merge(pending) { $1 }; pending = [:]; count = commit }
                off += 24 + pageSize
            }
        }
        // A damaged log can claim more pages than exist.
        guard count >= 1, count <= pages.count else { return nil }
        var out = Data(capacity: count * pageSize)
        for n in 1...count {
            guard let page = pages[n], let plain = decryptPage(page, first: n == 1, key: key) else { return nil }
            out.append(plain)
        }
        // A right key turns page 1 into SQLite's header: page size 4096, payload fractions 64/32/32.
        guard out[16] == 0x10, out[17] == 0, out[21] == 64, out[22] == 32, out[23] == 32 else { return nil }
        return out
    }

    private static func decryptPage(_ page: Data, first: Bool, key: Data) -> Data? {
        let start = first ? 16 : 0  // page 1 begins with the KDF salt instead of "SQLite format 3"
        let body = page.subdata(in: start..<pageSize - reserve), iv = page.subdata(in: pageSize - reserve..<pageSize - reserve + 16)
        var plain = Data(count: body.count)
        var moved = 0
        let status = plain.withUnsafeMutableBytes { out in body.withUnsafeBytes { inp in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0, k.baseAddress, key.count, v.baseAddress,
                    inp.baseAddress, body.count, out.baseAddress, body.count, &moved)
        } } } }
        guard status == kCCSuccess, moved == body.count else { return nil }
        return (first ? Data("SQLite format 3\0".utf8) : Data()) + plain + Data(count: reserve)
    }

    private static func be32(_ d: Data, _ i: Int) -> Int {
        d.subdata(in: i..<i + 4).reduce(0) { $0 << 8 | Int($1) }
    }

    // MARK: Reading the sidebar

    /// Every profile's spaces; empty when no database opens with the key.
    static func spaces(userData: URL, rootKey: Data) -> [ImportedSpace] {
        databases(userData: userData).flatMap { db -> [ImportedSpace] in
            guard let plain = decrypt(db.url, key: key(rootKey: rootKey, label: "profile/\(db.profile)/tabs")) else {
                CraLog.note("Dia import: \(db.profile)/tabs.db did not decrypt")
                return []
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cra-dia-\(UUID().uuidString).db")
            defer { try? FileManager.default.removeItem(at: tmp) }
            // Readable by the user only while it exists: it holds the decrypted tab list.
            guard FileManager.default.createFile(atPath: tmp.path, contents: plain, attributes: [.posixPermissions: 0o600]),
                  let snapshot = SQLiteSnapshot(copying: tmp) else {
                CraLog.note("Dia import: \(db.profile)/tabs.db could not be opened")
                return []
            }
            let found = spaces(in: snapshot)
            CraLog.note("Dia import: \(db.profile)/tabs.db has \(found.count) spaces")
            return found
        }
    }

    /// `nodes` is the tree: per space a `favorites` and a `pinned_container` node and one
    /// `window` node per window (its open tabs). A `tab` holds one `content_pane` (two or
    /// more in a split), a `group` is a folder.
    static func spaces(in db: SQLiteSnapshot) -> [ImportedSpace] {
        let nodes = db.rows("SELECT id, kind, entity_id, parent_id, space_id FROM nodes WHERE deleted_at IS NULL ORDER BY \"order\"")
        var children: [Int64: [[String: Any]]] = [:]
        for n in nodes { if let p = n["parent_id"] as? Int64 { children[p, default: []].append(n) } }
        func byID(_ sql: String) -> [String: [String: Any]] {
            Dictionary(db.rows(sql).compactMap { r in (r["id"] as? String).map { ($0, r) } }) { a, _ in a }
        }
        let groups = byID("SELECT id, title FROM tab_groups")
        let tabs = byID("SELECT id, creation_date FROM tabs")
        let panes = byID("SELECT p.id, p.custom_title, w.url, w.title FROM content_panes p JOIN web_contents w ON w.content_pane_id = p.id")

        func items(_ node: [String: Any], created: Date) -> [ImportedItem] {
            let id = node["entity_id"] as? String ?? ""
            let kids = (node["id"] as? Int64).flatMap { children[$0] } ?? []
            switch node["kind"] as? String {
            case "tab":
                let created = date(tabs[id]?["creation_date"]) ?? created
                return kids.flatMap { items($0, created: created) }
            case "content_pane":
                guard let p = panes[id], let url = p["url"] as? String, !url.isEmpty else { return [] }
                let custom = (p["custom_title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return [ImportedItem(customTitle: custom, pageTitle: p["title"] as? String ?? "", url: url, createdAt: created)]
            case "group":
                let title = groups[id]?["title"] as? String ?? "Folder"
                return [ImportedItem(customTitle: title, pageTitle: title, url: nil, isFolder: true,
                                     children: kids.flatMap { items($0, created: created) }, createdAt: created)]
            default:
                return []
            }
        }
        func contents(of kind: String, in space: String) -> [ImportedItem] {
            nodes.filter { $0["kind"] as? String == kind && $0["space_id"] as? String == space }.flatMap { container in
                ((container["id"] as? Int64).flatMap { children[$0] } ?? []).flatMap { items($0, created: Date()) }
            }
        }

        return db.rows("SELECT id, title, theme FROM spaces ORDER BY creation_date").map { row in
            let id = row["id"] as? String ?? ""
            var space = ImportedSpace(title: row["title"] as? String ?? "Space", emoji: "🗂️", theme: theme(row["theme"] as? String))
            space.favorites = contents(of: "favorites", in: id)
            space.pinned = contents(of: "pinned_container", in: id)
            space.today = contents(of: "window", in: id)
            return space
        }
    }

    /// GRDB's text dates: "2026-10-14 07:32:24.443", UTC.
    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Dia's space colours are names (neutral, red, orange, yellow, green, blue, pink, purple);
    /// neutral is Cra's default theme.
    static func theme(_ name: String?) -> SpaceTheme? {
        let colors: [String: [String]] = [
            "red": ["#F25C54", "#F7A399"], "orange": ["#F5913E", "#F9C48F"], "yellow": ["#F8D558", "#FBE79E"],
            "green": ["#5DBB63", "#A8DCA0"], "blue": ["#4A90E2", "#9CC3F0"], "pink": ["#F27BAA", "#F8B8D0"],
            "purple": ["#9B6FE0", "#C9B0F0"],
        ]
        guard let name, let pair = colors[name] else { return nil }
        return SpaceTheme(colors: pair, intensity: 0.5, noise: 0.15, appearance: "light", accent: pair[0])
    }
}
