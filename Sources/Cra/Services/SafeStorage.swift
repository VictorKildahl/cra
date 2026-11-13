import Foundation
import Security
import SQLite3

/// Chromium encrypts cookies, saved passwords, card numbers and search engine hashes
/// ("v10" values, see ChromiumCrypto) with a key derived from the secret in the login
/// Keychain item "Cra Safe Storage" (account "Chromium"). Stock Chromium calls it
/// "Chromium Safe Storage", like every Chromium-based app without its own name; CEF is
/// built with scripts/cef-patches/keychain-service-name.patch (or patched by
/// scripts/fetch-cef.sh) so Cra's secret is its own.
///
/// Cra used to start Chromium with --use-mock-keychain, whose secret is the public
/// constant "mock_password": anyone who could read the profile could decrypt it. The
/// first launch of a signed Cra re-encrypts such a profile with the Keychain secret
/// before Chromium opens it. Unsigned dev builds keep the mock keychain on profiles that
/// never used the Keychain: macOS ties the item to the app's signature, which changes
/// with every ad-hoc rebuild, and would ask for the login password each time.
enum SafeStorage {
    static let service = "Cra Safe Storage"
    /// Chromium's default, left alone: the 156 framework builds it from instruction
    /// immediates rather than a string the patch could change.
    static let account = "Chromium"

    /// Whether Chromium reads the Keychain item (false: --use-mock-keychain).
    private(set) static var usesKeychain = false
    /// The key Cra's profile is encrypted with, for the importer. nil when the Keychain
    /// did not hand out the secret.
    private(set) static var key: Data?

    private static let mockKey = ChromiumCrypto.key(fromSecret: "mock_password")
    /// Present once the profile is encrypted with the Keychain secret.
    private static var marker: URL { AppPaths.chromiumCache.appendingPathComponent("Cra Safe Storage") }
    private static let metaKey = "cra_safe_storage"
    private static let databases = ["Cookies", "Extension Cookies", "Safe Browsing Cookies", "Login Data",
                                    "Login Data For Account", "Web Data", "Account Web Data"]

    /// Called from main.swift before Chromium starts. Only migrates when `profileIsFree`
    /// (no other Cra has the databases open).
    static func prepare(profileIsFree: Bool) {
        if FileManager.default.fileExists(atPath: marker.path) {
            usesKeychain = true
            key = keychainSecret().map(ChromiumCrypto.key(fromSecret:))
            if key == nil { NSLog("Cra: no secret from the \(service) Keychain item") }
            return
        }
        key = mockKey
        guard profileIsFree, isSignedByTeam, frameworkUsesCraItem, let secret = keychainSecret() else { return }
        let newKey = ChromiumCrypto.key(fromSecret: secret)
        guard migrate(to: newKey) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.chromiumCache, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: marker.path, contents: Data()) else { return }
        usesKeychain = true
        key = newKey
    }

    /// The item's secret, made the way Chromium makes one (16 random bytes, base64) when
    /// there is none yet. Cra creates it, so macOS lets Cra read it without asking.
    private static func keychainSecret() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return String(data: data, encoding: .utf8) }
        guard status == errSecItemNotFound else {
            NSLog("Cra: reading the \(service) Keychain item failed (\(status))")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let secret = Data(bytes).base64EncodedString()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecAttrLabel as String: service,
                                   kSecValueData as String: Data(secret.utf8)]
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            NSLog("Cra: creating the \(service) Keychain item failed (\(added))")
            return nil
        }
        return secret
    }

    /// Signed with a Developer ID (a team), so the Keychain keeps trusting Cra across updates.
    private static var isSignedByTeam: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return false }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] is String
    }

    /// A framework that still looks for "Chromium Safe Storage" would make its own secret
    /// and lose everything this migration re-encrypts.
    private static var frameworkUsesCraItem: Bool {
        guard let url = EngineFramework.binaryURL,
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return false }
        let name = Array("\(service)\0".utf8)
        let found = data.withUnsafeBytes { memmem($0.baseAddress, $0.count, name, name.count) != nil }
        if !found { NSLog("Cra: \(url.lastPathComponent) does not use \(service); run scripts/fetch-cef.sh") }
        return found
    }

    /// Re-encrypts every mock-keychain value in every profile and the import's staged
    /// rows. All databases commit together or none does. Each one notes it in its meta
    /// table in the same transaction, so a later run never encrypts a value twice (a
    /// wrong key "decrypts" about once in 256, which tells nothing).
    private static func migrate(to newKey: Data) -> Bool {
        let fm = FileManager.default
        let root = AppPaths.chromiumCache
        let profiles = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        var open: [OpaquePointer] = []
        defer { open.forEach { sqlite3_close($0) } }
        var count = 0
        for profile in profiles {
            for name in databases {
                let path = root.appendingPathComponent(profile).appendingPathComponent(name).path
                guard fm.fileExists(atPath: path) else { continue }
                var db: OpaquePointer?
                guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
                    sqlite3_close(db)
                    NSLog("Cra: could not open \(profile)/\(name) to re-encrypt it")
                    return false
                }
                sqlite3_busy_timeout(db, 500)
                let hasMeta = !SQLite.rows(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'meta'").isEmpty
                if hasMeta, !SQLite.rows(db, "SELECT 1 FROM meta WHERE key = '\(metaKey)'").isEmpty {
                    sqlite3_close(db)
                    continue
                }
                open.append(db)
                guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK,
                      let n = reencrypt(db, from: mockKey, to: newKey),
                      !hasMeta || sqlite3_exec(db, "INSERT INTO meta (key, value) VALUES ('\(metaKey)', 'keychain')", nil, nil, nil) == SQLITE_OK else {
                    NSLog("Cra: could not re-encrypt \(profile)/\(name)")
                    open.forEach { sqlite3_exec($0, "ROLLBACK", nil, nil, nil) }
                    return false
                }
                count += n
            }
        }
        guard CredentialImport.reencryptPending(from: mockKey, to: newKey) else {
            open.forEach { sqlite3_exec($0, "ROLLBACK", nil, nil, nil) }
            return false
        }
        for db in open where sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            NSLog("Cra: committing re-encrypted values failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        NSLog("Cra: moved \(count) encrypted values to the \(service) Keychain item")
        return true
    }

    /// Every BLOB that decrypts with `old`, in every table. Returns the number changed.
    private static func reencrypt(_ db: OpaquePointer, from old: Data, to new: Data) -> Int? {
        var changed = 0
        let tables = SQLite.rows(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
            .compactMap { $0["name"] as? String }
        for table in tables {
            let columns = SQLite.rows(db, "SELECT name FROM pragma_table_info('\(table)')").compactMap { $0["name"] as? String }
            for column in columns {
                // WITHOUT ROWID tables have no rowid; Chromium keeps no encrypted values in those.
                let rows = SQLite.rows(db, "SELECT rowid AS r, \"\(column)\" AS v FROM \"\(table)\" WHERE typeof(\"\(column)\") = 'blob' AND substr(\"\(column)\", 1, 3) = X'763130'")
                for row in rows {
                    guard let rowid = row["r"] as? Int64, let blob = row["v"] as? Data,
                          let plain = ChromiumCrypto.decrypt(blob, key: old) else { continue }
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, "UPDATE \"\(table)\" SET \"\(column)\" = ? WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
                    SQLite.bind(stmt, [ChromiumCrypto.encrypt(plain, key: new), rowid])
                    let done = sqlite3_step(stmt) == SQLITE_DONE
                    sqlite3_finalize(stmt)
                    guard done else { return nil }
                    changed += 1
                }
            }
        }
        return changed
    }
}
