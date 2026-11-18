import AppKit

/// A browser the import can read: Dia's list (Arc, Brave, Chrome, Edge,
/// Firefox, Opera, Opera GX, Safari) plus Dia itself, Vivaldi, Chromium, Helium, Yab, Ardia and Zen.
struct ImportSource: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Arc and Dia: their own sidebar stores, and a Chromium profile for passwords and cookies.
        case arc, dia
        /// Yab and Ardia: Arc-style spaces in their own files, Chromium profiles for passwords and cookies.
        case yab, ardia
        case chromium, firefox
        /// Zen: Firefox underneath, with Arc-style spaces, Essentials and pinned tabs.
        case zen
        /// Safari: only what Safari exports itself.
        case safari
    }

    let id: String
    let name: String
    let bundleID: String
    let kind: Kind
    /// Chromium's "User Data" root, Firefox's profiles root, or Safari's folder.
    let dataDir: URL
    /// "<Name> Safe Storage" in the login Keychain, which encrypts passwords and cookies.
    var keychainService: String?
    var keychainAccount: String?

    var rawValue: String { name }

    private static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static func chromium(_ id: String, _ name: String, _ bundleID: String, _ path: String, account: String,
                                 service: String? = nil) -> ImportSource {
        ImportSource(id: id, name: name, bundleID: bundleID, kind: .chromium, dataDir: support.appendingPathComponent(path, isDirectory: true),
                     keychainService: service ?? "\(account) Safe Storage", keychainAccount: account)
    }

    static let arc = ImportSource(id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser", kind: .arc,
                                  dataDir: ArcImporter.userData,
                                  keychainService: "Arc Safe Storage", keychainAccount: "Arc")
    static let dia = ImportSource(id: "dia", name: "Dia", bundleID: "company.thebrowser.dia", kind: .dia,
                                  dataDir: DiaImporter.userData,
                                  keychainService: "Dia Safe Storage", keychainAccount: "Dia")

    static let allCases: [ImportSource] = [
        arc, dia,
        chromium("chrome", "Chrome", "com.google.Chrome", "Google/Chrome", account: "Chrome"),
        chromium("brave", "Brave", "com.brave.Browser", "BraveSoftware/Brave-Browser", account: "Brave"),
        chromium("edge", "Edge", "com.microsoft.edgemac", "Microsoft Edge", account: "Microsoft Edge"),
        chromium("opera", "Opera", "com.operasoftware.Opera", "com.operasoftware.Opera", account: "Opera"),
        chromium("operagx", "Opera GX", "com.operasoftware.OperaGX", "com.operasoftware.OperaGX", account: "Opera GX"),
        chromium("vivaldi", "Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi", account: "Vivaldi"),
        chromium("chromium", "Chromium", "org.chromium.Chromium", "Chromium", account: "Chromium"),
        // Helium renames its Keychain item instead of using "<Name> Safe Storage".
        chromium("helium", "Helium", "net.imput.helium", "net.imput.helium", account: "Helium", service: "Helium Storage Key"),
        ImportSource(id: "yab", name: "Yab", bundleID: "dev.serafim.fast", kind: .yab, dataDir: YabImporter.userData,
                     keychainService: "Yab Safe Storage", keychainAccount: "Yab"),
        ImportSource(id: "ardia", name: "Ardia", bundleID: "com.ardia.browser", kind: .ardia, dataDir: ArdiaImporter.userData,
                     keychainService: "Ardia Safe Storage", keychainAccount: "Ardia"),
        ImportSource(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox", kind: .firefox,
                     dataDir: support.appendingPathComponent("Firefox", isDirectory: true)),
        ImportSource(id: "zen", name: "Zen", bundleID: "app.zen-browser.zen", kind: .zen,
                     dataDir: support.appendingPathComponent("zen", isDirectory: true)),
        ImportSource(id: "safari", name: "Safari", bundleID: "com.apple.Safari", kind: .safari,
                     dataDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari", isDirectory: true)),
    ]

    /// Has data to bring over. The import reads only the profile on disk, so a browser
    /// someone already deleted is still offered while its data is there; Safari is always there.
    /// A folder macOS won't let Cra read is offered too, asking for Full Disk Access, as Ardia
    /// does: current macOS keeps Chrome's and Brave's data from other apps, and hiding the
    /// browser left a Chrome user with only Opera to pick (X DM, 15 Nov).
    var isAvailable: Bool { hasProfile || needsFullDiskAccess }

    /// The data folder is there but macOS refuses to list it.
    var needsFullDiskAccess: Bool {
        kind != .safari && Self.isAccessDenied(dataDir)
    }

    static func isAccessDenied(_ dir: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            return false
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
            let posix = error.userInfo[NSUnderlyingErrorKey] as? NSError
            return posix?.domain == NSPOSIXErrorDomain && (posix?.code == Int(EPERM) || posix?.code == Int(EACCES))
        }
    }

    private var hasProfile: Bool {
        switch kind {
        case .arc: return ArcImporter.isAvailable
        case .dia: return DiaImporter.isAvailable
        case .yab: return YabImporter.isAvailable
        case .ardia: return ArdiaImporter.isAvailable
        case .safari: return true
        case .chromium: return !ChromiumImporter.profiles(userData: dataDir).isEmpty
        case .firefox, .zen: return FirefoxImporter.defaultProfile(root: dataDir) != nil
        }
    }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// Safari's data arrives as an exported file instead of a plan read from disk.
    var needsExportedFile: Bool { kind == .safari }

    func plan() throws -> ImportPlan {
        switch kind {
        case .arc: return try ArcImporter.plan()
        case .dia: return try DiaImporter.plan()
        case .yab: return try YabImporter.plan()
        case .ardia: return try ArdiaImporter.plan()
        case .chromium: return try ChromiumImporter.plan(browser: name, userData: dataDir)
        case .firefox: return try FirefoxImporter.plan(browser: name, root: dataDir)
        case .zen: return try ZenImporter.plan(root: dataDir)
        case .safari: return ImportPlan(source: name)
        }
    }

    /// Chromium profiles whose passwords and cookies can come over.
    var credentialProfiles: [ChromiumProfile] {
        guard keychainService != nil else { return [] }
        let profiles = ChromiumImporter.profiles(userData: dataDir)
        // Yab and Ardia name their Chromium folders by an id, shown here by the space's name;
        // Yab never uses Default.
        let names: [String: String]
        switch kind {
        case .yab: names = YabImporter.profileNames(supportDir: dataDir.deletingLastPathComponent())
        case .ardia: names = ArdiaImporter.profileNames()
        default: return profiles
        }
        return profiles.filter { kind != .yab || $0.id != "Default" }.map { ChromiumProfile(id: $0.id, name: names[$0.id] ?? $0.name, dir: $0.dir) }
    }

    func topSites(limit: Int) -> [TopSite] {
        switch kind {
        case .arc, .dia, .yab, .ardia, .chromium: return ChromiumImporter.topSites(userData: dataDir, limit: limit)
        case .firefox, .zen: return FirefoxImporter.topSites(root: dataDir, limit: limit)
        case .safari: return []
        }
    }

    func favicons(hosts: [String]) -> [String: NSImage] {
        switch kind {
        case .arc, .dia, .yab, .ardia, .chromium: return ChromiumImporter.favicons(userData: dataDir, hosts: hosts)
        case .firefox, .zen: return FirefoxImporter.favicons(root: dataDir, hosts: hosts)
        case .safari: return [:]
        }
    }

    func extensions() -> [ImportableExtension] {
        switch kind {
        case .arc, .dia, .yab, .ardia, .chromium: return ExtensionImporter.extensions(inUserData: dataDir)
        case .firefox, .zen, .safari: return []
        }
    }

    /// The installed app's own icon, else a logo bundled in resources/browsers for a
    /// browser that may already be deleted (Dia bundles its browser logos).
    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "browsers"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: name) ?? NSImage()
    }
}
