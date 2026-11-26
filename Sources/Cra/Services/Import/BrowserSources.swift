import AppKit

/// A browser the import can read: Dia's list (Arc, Brave, Chrome, Edge,
/// Firefox, Opera, Opera GX, Safari) plus Dia itself, Vivaldi, Chromium, Helium, Yab, Ardia, Phi, Crest and Zen.
struct ImportSource: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Arc and Dia: their own sidebar stores, and a Chromium profile for passwords and cookies.
        case arc, dia
        /// Yab and Ardia: Arc-style spaces in their own files, Chromium profiles for passwords and cookies.
        case yab, ardia
        /// Phi: spaces in its own SwiftData store, Chromium profiles right in its folder.
        case phi
        /// Crest: spaces in its own SQLite session file, a Chromium profile for each space.
        case crest
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
    /// The browser's own folder under Application Support, when `dataDir` sits inside it (Arc's
    /// "User Data", Yab's and Ardia's "Chromium"). The import list looks at this folder only (#757).
    var ownFolder: URL? = nil

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
                                  keychainService: "Arc Safe Storage", keychainAccount: "Arc", ownFolder: ArcImporter.supportDir)
    static let dia = ImportSource(id: "dia", name: "Dia", bundleID: "company.thebrowser.dia", kind: .dia,
                                  dataDir: DiaImporter.userData,
                                  keychainService: "Dia Safe Storage", keychainAccount: "Dia", ownFolder: DiaImporter.supportDir)

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
                     keychainService: "Yab Safe Storage", keychainAccount: "Yab", ownFolder: YabImporter.supportDir),
        ImportSource(id: "ardia", name: "Ardia", bundleID: "com.ardia.browser", kind: .ardia, dataDir: ArdiaImporter.userData,
                     keychainService: "Ardia Safe Storage", keychainAccount: "Ardia", ownFolder: ArdiaImporter.supportDir),
        ImportSource(id: "phi", name: "Phi", bundleID: "com.phibrowser.Mac", kind: .phi, dataDir: PhiImporter.userData,
                     keychainService: "Phi Safe Storage", keychainAccount: "Phi"),
        ImportSource(id: "crest", name: "Crest", bundleID: "com.pauldavis.crest", kind: .crest, dataDir: CrestImporter.userData,
                     keychainService: "Crest Safe Storage", keychainAccount: "com.pauldavis.crest", ownFolder: CrestImporter.supportDir),
        ImportSource(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox", kind: .firefox,
                     dataDir: support.appendingPathComponent("Firefox", isDirectory: true)),
        ImportSource(id: "zen", name: "Zen", bundleID: "app.zen-browser.zen", kind: .zen,
                     dataDir: support.appendingPathComponent("zen", isDirectory: true)),
        ImportSource(id: "safari", name: "Safari", bundleID: "com.apple.Safari", kind: .safari,
                     dataDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari", isDirectory: true)),
    ]

    /// Offered in the import list: its own folder is there. A browser someone already deleted is
    /// still offered while its folder is; Safari always is. Whether the folder holds a profile, and
    /// whether macOS lets Cra read it (Full Disk Access), shows once the browser is picked: reading
    /// inside it before that made macOS show "Data Access Blocked … tried to access your data from
    /// other apps" on Cra's first launch (#757).
    var isAvailable: Bool {
        !OtherBrowserData.offered([otherBrowser]) { FileManager.default.fileExists(atPath: $0) }.isEmpty
    }

    /// This browser as OtherBrowserData sees it: its own folder and its native messaging manifests.
    var otherBrowser: OtherBrowserData.Browser {
        let manifests = [.chromium, .arc, .dia, .phi].contains(kind) ? dataDir.appendingPathComponent("NativeMessagingHosts", isDirectory: true).path : nil
        return OtherBrowserData.Browser(id: id, folder: (ownFolder ?? dataDir).path, nativeMessagingHosts: manifests,
                                        alwaysOffered: kind == .safari)
    }

    /// The picked browser's folder is there but macOS refuses to list it. Asked only about the
    /// browser the person picked: asking reads inside its folder (#757).
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

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// Safari's data arrives as an exported file instead of a plan read from disk.
    var needsExportedFile: Bool { kind == .safari }

    func plan() throws -> ImportPlan {
        switch kind {
        case .arc: return try ArcImporter.plan(favicons: dataDir)
        case .dia: return try DiaImporter.plan()
        case .yab: return try YabImporter.plan()
        case .ardia: return try ArdiaImporter.plan()
        case .phi: return try PhiImporter.plan()
        case .crest: return try CrestImporter.plan()
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
        // Yab, Ardia and Crest name their Chromium folders by an id, shown here by the space's name;
        // Yab never uses Default. Crest browses each space in its own "Crest-<id>": its Default and
        // any folder no space uses hold none of the person's sign-ins.
        let names: [String: String]
        switch kind {
        case .yab: names = YabImporter.profileNames(supportDir: dataDir.deletingLastPathComponent())
        case .ardia: names = ArdiaImporter.profileNames()
        case .crest: names = CrestImporter.profileNames()
        default: return profiles
        }
        let unused: (ChromiumProfile) -> Bool = { p in
            switch kind {
            case .yab: return p.id == "Default"
            case .crest: return !names.isEmpty && names[p.id] == nil
            default: return false
            }
        }
        return profiles.filter { !unused($0) }.map { ChromiumProfile(id: $0.id, name: names[$0.id] ?? $0.name, dir: $0.dir) }
    }

    func topSites(limit: Int) -> [TopSite] {
        switch kind {
        case .arc, .dia, .yab, .ardia, .phi, .crest, .chromium: return ChromiumImporter.topSites(userData: dataDir, limit: limit)
        case .firefox, .zen: return FirefoxImporter.topSites(root: dataDir, limit: limit)
        case .safari: return []
        }
    }

    /// Each host's icon, from the same stores the import reads.
    func favicons(hosts: [String]) -> [String: NSImage] {
        kind.iconStores(dataDir: dataDir).icons(hosts: hosts).compactMapValues { FaviconCache.png($0).flatMap(NSImage.init(data:)) }
    }

    func extensions() -> [ImportableExtension] {
        switch kind {
        case .arc, .dia, .yab, .ardia, .phi, .crest, .chromium: return ExtensionImporter.extensions(inUserData: dataDir)
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

extension ImportSource.Kind {
    /// Where this browser keeps tab icons under `dataDir` (its ImportSource's): Yab's own icons/ folder,
    /// then each browser's favicon databases. Arc's per-item caches are read with its sidebar, by item id.
    func iconStores(dataDir: URL) -> ImportFavicons.Stores {
        switch self {
        case .yab:
            return ImportFavicons.Stores(own: YabImporter.ownIcons(supportDir: dataDir.deletingLastPathComponent()),
                                         databases: { ChromiumImporter.favicons(userData: dataDir, hosts: $0) })
        case .arc, .dia, .ardia, .phi, .crest, .chromium: return ImportFavicons.Stores(databases: { ChromiumImporter.favicons(userData: dataDir, hosts: $0) })
        case .firefox, .zen: return ImportFavicons.Stores(databases: { FirefoxImporter.favicons(root: dataDir, hosts: $0) })
        case .safari: return ImportFavicons.Stores()
        }
    }
}
