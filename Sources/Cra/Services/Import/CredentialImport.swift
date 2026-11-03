import CommonCrypto
import CryptoKit
import Foundation
import Security
import SQLite3

// Passwords and cookies from other browsers (Dia's "Unlock your data for import"
// and ImportPasswordsAndCookiesResultView). Sources decrypt with their own key;
// rows are re-encrypted for Cra's Chromium profile and staged in a file, then
// written into Cookies / Login Data on the next launch before Chromium opens
// them (Chromium keeps both databases locked while it runs). Rows from an Arc
// profile go to the Cra profile its spaces were put on (GitHub #131).

struct ImportedCookie: Codable {
    var host: String            // host_key: ".example.com" for domain cookies
    var name: String
    var value: String
    var path: String
    /// Chromium time (µs since 1601); 0 for a session cookie.
    var expires: Int64
    var created: Int64
    var lastAccess: Int64
    var secure: Bool
    var httpOnly: Bool
    /// Chromium CookieSameSite: -1 unspecified, 0 none, 1 lax, 2 strict.
    var sameSite: Int
    /// The source browser's profile folder it was read from.
    var sourceProfile: String?
}

struct ImportedLogin: Codable {
    var originURL: String
    var actionURL: String = ""
    var usernameElement: String = ""
    var username: String
    var passwordElement: String = ""
    var password: String
    var signonRealm: String
    var created: Int64
    /// The source browser's profile folder it was read from.
    var sourceProfile: String?

    /// A login from a CSV or Firefox: the realm is the page's origin.
    init?(url: String, username: String, password: String, created: Int64 = ChromiumTime.now) {
        guard let u = URL(string: url), let scheme = u.scheme, let host = u.host, !password.isEmpty else { return nil }
        let origin = "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")"
        originURL = origin + "/"
        signonRealm = origin + "/"
        self.username = username
        self.password = password
        self.created = created
    }

    init(originURL: String, actionURL: String, usernameElement: String, username: String, passwordElement: String,
         password: String, signonRealm: String, created: Int64) {
        self.originURL = originURL; self.actionURL = actionURL; self.usernameElement = usernameElement
        self.username = username; self.passwordElement = passwordElement; self.password = password
        self.signonRealm = signonRealm; self.created = created
    }
}

struct ImportedCredentials {
    var cookies: [ImportedCookie] = []
    var logins: [ImportedLogin] = []
    var isEmpty: Bool { cookies.isEmpty && logins.isEmpty }
}

enum CredentialImportError: LocalizedError {
    case keychainDenied(String)
    case unreadable(String)
    case primaryPassword(String)
    var errorDescription: String? {
        switch self {
        case .keychainDenied(let s): return "macOS did not unlock \(s)'s data."
        case .unreadable(let s): return "Could not read \(s)'s passwords and cookies."
        case .primaryPassword(let s): return "\(s) is protected by a primary password; turn it off in \(s) to import passwords."
        }
    }
}

enum ChromiumTime {
    /// Seconds between 1601-01-01 and 1970-01-01.
    static let epochDelta: Int64 = 11_644_473_600
    static var now: Int64 { from(Date()) }
    static func from(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 + Double(epochDelta)) * 1_000_000) }
    static func fromUnix(seconds s: Double) -> Int64 { Int64((s + Double(epochDelta)) * 1_000_000) }
}

// MARK: - Chromium crypto (macOS: v10 = AES-128-CBC, key PBKDF2-SHA1 of the Keychain secret)

enum ChromiumCrypto {
    static func key(fromSecret secret: String) -> Data {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        _ = key.withUnsafeMutableBytes { k in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), secret, secret.utf8.count, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                 k.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
        }
        return key
    }

    private static let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)

    /// nil for a wrong key too: CommonCrypto strips PKCS#7 padding without checking it,
    /// so the padding is checked here (a wrong key passes about once in 256).
    static func decrypt(_ blob: Data, key: Data) -> Data? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8), (blob.count - 3) % kCCBlockSizeAES128 == 0,
              let padded = crypt(CCOperation(kCCDecrypt), Data(blob.dropFirst(3)), key: key, options: 0),
              let n = padded.last.map(Int.init), (1...kCCBlockSizeAES128).contains(n), padded.count >= n,
              padded.suffix(n).allSatisfy({ Int($0) == n }) else { return nil }
        return Data(padded.dropLast(n))
    }

    static func encrypt(_ plain: Data, key: Data) -> Data {
        Data("v10".utf8) + (crypt(CCOperation(kCCEncrypt), plain, key: key, options: CCOptions(kCCOptionPKCS7Padding)) ?? Data())
    }

    private static func crypt(_ op: CCOperation, _ input: Data, key: Data, options: CCOptions) -> Data? {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in input.withUnsafeBytes { i in key.withUnsafeBytes { k in
            CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), options, k.baseAddress, key.count, iv,
                    i.baseAddress, input.count, o.baseAddress, o.count, &moved)
        } } }
        return status == kCCSuccess ? out.prefix(moved) : nil
    }

    /// Cookies databases from version 24 prefix the value with SHA-256 of the host.
    static func hostDigest(_ host: String) -> Data { Data(SHA256.hash(data: Data(host.utf8))) }

    /// The browser's "<Name> Safe Storage" secret. macOS asks for the login
    /// password (Dia: "macOS will ask for your computer password"), so call
    /// this off the main thread.
    static func keychainSecret(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - SQLite

/// A read-only snapshot of a database another app may hold open: the file and
/// its -wal/-shm are copied to a temporary folder first, so the read never
/// touches (or waits on) the original.
final class SQLiteSnapshot {
    private var db: OpaquePointer?
    private let dir: URL

    init?(copying url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        dir = fm.temporaryDirectory.appendingPathComponent("cra-import-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm", "-journal"] where fm.fileExists(atPath: url.path + suffix) {
                try fm.copyItem(atPath: url.path + suffix, toPath: dir.appendingPathComponent(url.lastPathComponent + suffix).path)
            }
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
        guard sqlite3_open_v2(dir.appendingPathComponent(url.lastPathComponent).path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            try? fm.removeItem(at: dir)
            return nil
        }
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: dir)
    }

    func columns(of table: String) -> Set<String> {
        Set(rows("SELECT name FROM pragma_table_info('\(table)')").compactMap { $0["name"] as? String })
    }

    func scalar(_ sql: String) -> Any? { rows(sql).first?.values.first }

    /// Rows as [column: Int64 | Double | String | Data].
    func rows(_ sql: String) -> [[String: Any]] { SQLite.rows(db, sql) }
}

enum SQLite {
    static func rows(_ db: OpaquePointer?, _ sql: String) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, i))
                    row[name] = n > 0 ? Data(bytes: sqlite3_column_blob(stmt, i), count: n) : Data()
                default: break
                }
            }
            out.append(row)
        }
        return out
    }

    /// Binds Int64, Int, Bool, Double, String and Data; anything else is NULL.
    static func bind(_ stmt: OpaquePointer?, _ values: [Any?]) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case let x as Int64: sqlite3_bind_int64(stmt, idx, x)
            case let x as Int: sqlite3_bind_int64(stmt, idx, Int64(x))
            case let x as Bool: sqlite3_bind_int64(stmt, idx, x ? 1 : 0)
            case let x as Double: sqlite3_bind_double(stmt, idx, x)
            case let x as String: sqlite3_bind_text(stmt, idx, x, -1, transient)
            case let x as Data: _ = x.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(x.count), transient) }
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }
}

// MARK: - Staging and applying

enum CredentialImport {
    /// Staged rows, already encrypted for Cra's profile (SafeStorage.key), so the
    /// file is no easier to read than the databases it feeds.
    private struct Pending: Codable {
        /// `profile`: the Cra profile folder it goes to; nil (files from before #131) is Default.
        struct Cookie: Codable { var c: ImportedCookie; var encrypted: Data; var profile: String? }
        struct Login: Codable { var l: ImportedLogin; var encrypted: Data; var profile: String? }
        var cookies: [Cookie] = []
        var logins: [Login] = []
    }

    static var pendingFile: URL { AppPaths.file("pending-credentials.json") }
    static var hasPending: Bool { FileManager.default.fileExists(atPath: pendingFile.path) }

    /// Adds to whatever is already staged, each row for the Cra profile `profiles` maps its
    /// source profile to; returns false when nothing could be written.
    @discardableResult
    static func stage(_ creds: ImportedCredentials, profiles: ImportProfileMap = ImportProfileMap()) -> Bool {
        guard !creds.isEmpty else { return true }
        guard let key = SafeStorage.key else { return false }
        var pending = (try? Data(contentsOf: pendingFile)).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } ?? Pending()
        for var c in creds.cookies {
            let encrypted = ChromiumCrypto.encrypt(Data(c.value.utf8), key: key)
            c.value = ""
            pending.cookies.append(.init(c: c, encrypted: encrypted, profile: profiles.craFolder(forSource: c.sourceProfile)))
        }
        for var l in creds.logins {
            let encrypted = ChromiumCrypto.encrypt(Data(l.password.utf8), key: key)
            l.password = ""
            pending.logins.append(.init(l: l, encrypted: encrypted, profile: profiles.craFolder(forSource: l.sourceProfile)))
        }
        return write(pending)
    }

    private static func write(_ pending: Pending) -> Bool {
        guard let data = try? JSONEncoder().encode(pending) else { return false }
        do {
            try data.write(to: pendingFile, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pendingFile.path)
            return true
        } catch {
            return false
        }
    }

    /// Rows staged before the profile moved to the Keychain secret (SafeStorage). Rows
    /// that don't decrypt with `old` (already moved by a run that failed later) stay.
    static func reencryptPending(from old: Data, to new: Data) -> Bool {
        guard let data = try? Data(contentsOf: pendingFile) else { return true }
        guard var pending = try? JSONDecoder().decode(Pending.self, from: data) else { return false }
        for i in pending.cookies.indices {
            if let plain = ChromiumCrypto.decrypt(pending.cookies[i].encrypted, key: old) {
                pending.cookies[i].encrypted = ChromiumCrypto.encrypt(plain, key: new)
            }
        }
        for i in pending.logins.indices {
            if let plain = ChromiumCrypto.decrypt(pending.logins[i].encrypted, key: old) {
                pending.logins[i].encrypted = ChromiumCrypto.encrypt(plain, key: new)
            }
        }
        return write(pending)
    }

    /// Called from main.swift before Chromium starts, with the folder that holds the profiles.
    /// A profile Chromium has not made yet gets its databases from Default's schema, so its spaces
    /// are signed in from their first page. Rows stay in the file while their profile's databases
    /// are missing (no first run yet) or busy.
    static func applyPending(root: URL) {
        guard let data = try? Data(contentsOf: pendingFile),
              var pending = try? JSONDecoder().decode(Pending.self, from: data),
              let key = SafeStorage.key else { return }
        let template = root.appendingPathComponent("Default", isDirectory: true)
        let folders = Set(pending.cookies.map { $0.profile ?? "Default" } + pending.logins.map { $0.profile ?? "Default" })
        for folder in folders.sorted() {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            let cookies = pending.cookies.filter { ($0.profile ?? "Default") == folder }
            let logins = pending.logins.filter { ($0.profile ?? "Default") == folder }
            let cookiesDB = dir.appendingPathComponent("Cookies"), loginsDB = dir.appendingPathComponent("Login Data")
            if folder != "Default" {
                if !cookies.isEmpty { createDatabase(cookiesDB, like: template.appendingPathComponent("Cookies")) }
                if !logins.isEmpty { createDatabase(loginsDB, like: template.appendingPathComponent("Login Data")) }
            }
            let cookiesOK = cookies.isEmpty || insertCookies(cookies, into: cookiesDB, key: key)
            let loginsOK = logins.isEmpty || insertLogins(logins, into: loginsDB)
            if cookiesOK { pending.cookies.removeAll { ($0.profile ?? "Default") == folder } }
            if loginsOK { pending.logins.removeAll { ($0.profile ?? "Default") == folder } }
            if !cookiesOK || !loginsOK { NSLog("Cra: imported passwords/cookies for \(folder) stay pending (cookies \(cookiesOK), logins \(loginsOK))") }
        }
        if pending.cookies.isEmpty && pending.logins.isEmpty {
            try? FileManager.default.removeItem(at: pendingFile)
        } else {
            _ = write(pending)
        }
    }

    /// An empty database with `template`'s tables, indexes and meta rows (Chromium's schema
    /// version), for a profile Chromium has not opened yet. Nothing when `url` exists.
    static func createDatabase(_ url: URL, like template: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: template.path) else { return }
        var source: OpaquePointer?
        guard sqlite3_open_v2(template.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(source); return }
        let schema = SQLite.rows(source, "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type = 'table' DESC, rowid")
            .compactMap { $0["sql"] as? String }
        let meta = SQLite.rows(source, "SELECT key, value FROM meta")
        sqlite3_close(source)
        guard !schema.isEmpty, !meta.isEmpty else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).creating")
        try? fm.removeItem(at: staging)
        var db: OpaquePointer?
        guard sqlite3_open_v2(staging.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { sqlite3_close(db); return }
        let ok = transaction(db) {
            for sql in schema where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { return false }
            for row in meta {
                guard let k = row["key"] as? String else { return false }
                if !insert(db, table: "meta", values: ["key": k, "value": row["value"] ?? ""], orIgnore: false) { return false }
            }
            return true
        }
        sqlite3_close(db)
        if ok { try? fm.moveItem(at: staging, to: url) } else { try? fm.removeItem(at: staging) }
    }

    private static func open(_ url: URL) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 500)
        return db
    }

    /// Fills every NOT NULL column the row does not name with 0 or "", so the
    /// insert keeps working across Chromium schema versions.
    private static func insert(_ db: OpaquePointer?, table: String, values: [String: Any], orIgnore: Bool) -> Bool {
        var row = values
        for col in SQLite.rows(db, "SELECT name, type, \"notnull\" AS nn, dflt_value FROM pragma_table_info('\(table)')") {
            guard let name = col["name"] as? String, row[name] == nil, (col["nn"] as? Int64) == 1, col["dflt_value"] == nil else { continue }
            let type = (col["type"] as? String ?? "").uppercased()
            row[name] = type.contains("INT") ? Int64(0) : (type.contains("BLOB") ? Data() : "")
        }
        let known = Set(SQLite.rows(db, "SELECT name FROM pragma_table_info('\(table)')").compactMap { $0["name"] as? String })
        let cols = row.keys.filter(known.contains).sorted()
        let sql = "INSERT \(orIgnore ? "OR IGNORE " : "")INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(cols.map { _ in "?" }.joined(separator: ",")))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        SQLite.bind(stmt, cols.map { row[$0] })
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private static func transaction(_ db: OpaquePointer?, _ body: () -> Bool) -> Bool {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }
        if body() { return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK }
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        return false
    }

    private static func insertCookies(_ cookies: [Pending.Cookie], into url: URL, key: Data) -> Bool {
        guard let db = open(url) else { return false }
        defer { sqlite3_close(db) }
        let version = Int(SQLite.rows(db, "SELECT value FROM meta WHERE key = 'version'").first?["value"] as? String ?? "") ?? 0
        return transaction(db) {
            for p in cookies {
                let c = p.c
                var encrypted = p.encrypted
                if version >= 24, let plain = ChromiumCrypto.decrypt(encrypted, key: key) {
                    encrypted = ChromiumCrypto.encrypt(ChromiumCrypto.hostDigest(c.host) + plain, key: key)
                }
                let ok = insert(db, table: "cookies", values: [
                    "creation_utc": c.created, "host_key": c.host, "top_frame_site_key": "", "name": c.name, "value": "",
                    "encrypted_value": encrypted, "path": c.path, "expires_utc": c.expires, "is_secure": c.secure,
                    "is_httponly": c.httpOnly, "last_access_utc": c.lastAccess, "has_expires": c.expires > 0,
                    "is_persistent": c.expires > 0, "priority": Int64(1), "samesite": Int64(c.sameSite),
                    "source_scheme": Int64(c.secure ? 2 : 1), "source_port": Int64(c.secure ? 443 : 80),
                    // Chromium stores every unpartitioned cookie with has_cross_site_ancestor = 1 and
                    // matches on it when it updates or deletes one; see repairImportedCookies.
                    "last_update_utc": c.lastAccess, "source_type": Int64(0), "has_cross_site_ancestor": true,
                ], orIgnore: true)
                if !ok { return false }
            }
            return true
        }
    }

    /// Earlier imports wrote unpartitioned cookies with has_cross_site_ancestor = 0.
    /// Chromium's UPDATE and DELETE never match those rows, so a fresh sign-in sat next
    /// to the stale imported cookie, and at the next launch Chromium dropped the stale
    /// duplicate with a DELETE that hit the fresh row instead: signed out after every
    /// restart. Drops imported rows Chromium has since replaced and fixes the rest.
    /// Called from main.swift before Chromium starts.
    static func repairImportedCookies(profileDir: URL) {
        guard let db = open(profileDir.appendingPathComponent("Cookies")) else { return }
        defer { sqlite3_close(db) }
        guard !SQLite.rows(db, "SELECT 1 FROM cookies WHERE top_frame_site_key = '' AND has_cross_site_ancestor = 0 LIMIT 1").isEmpty else { return }
        let ok = transaction(db) {
            sqlite3_exec(db, """
                DELETE FROM cookies WHERE top_frame_site_key = '' AND has_cross_site_ancestor = 0 AND EXISTS (
                    SELECT 1 FROM cookies c WHERE c.top_frame_site_key = '' AND c.has_cross_site_ancestor = 1
                    AND c.host_key = cookies.host_key AND c.name = cookies.name AND c.path = cookies.path
                    AND c.source_scheme = cookies.source_scheme AND c.source_port = cookies.source_port);
                UPDATE cookies SET has_cross_site_ancestor = 1 WHERE top_frame_site_key = '' AND has_cross_site_ancestor = 0;
                """, nil, nil, nil) == SQLITE_OK
        }
        if !ok { NSLog("Cra: could not repair imported cookies") }
    }

    private static func insertLogins(_ logins: [Pending.Login], into url: URL) -> Bool {
        guard let db = open(url) else { return false }
        defer { sqlite3_close(db) }
        return transaction(db) {
            for p in logins {
                let l = p.l
                // A login already saved in Cra for the same site and user wins.
                let exists = SQLite.rows(db, "SELECT 1 FROM logins WHERE signon_realm = '\(l.signonRealm.replacingOccurrences(of: "'", with: "''"))' AND username_value = '\(l.username.replacingOccurrences(of: "'", with: "''"))' LIMIT 1")
                if !exists.isEmpty { continue }
                let ok = insert(db, table: "logins", values: [
                    "origin_url": l.originURL, "action_url": l.actionURL, "username_element": l.usernameElement,
                    "username_value": l.username, "password_element": l.passwordElement, "password_value": p.encrypted,
                    "submit_element": "", "signon_realm": l.signonRealm, "date_created": l.created,
                    "blacklisted_by_user": false, "scheme": Int64(0), "password_type": Int64(0), "times_used": Int64(0),
                    "date_password_modified": l.created, "date_last_used": Int64(0),
                ], orIgnore: true)
                if !ok { return false }
            }
            return true
        }
    }
}
