import AppKit
import CraCEF
import CryptoKit
import Observation

/// Unpacked Chrome extensions, one folder each, loaded at start-up with
/// --load-extension by the Chrome-style page windows, plus the ones Chrome installed
/// into Cra's profile itself (Chrome Web Store, chrome://extensions "Load unpacked").
@MainActor
@Observable
final class ExtensionStore {
    struct Entry: Identifiable, Hashable {
        let id: String          // folder name
        let name: String
        let version: String
        let description: String
        let url: URL
        /// Chromium's extension ID (from the manifest key, else the folder path).
        var extensionID: String = ""
        /// The action's manifest icon at 16 pt, with the files for 1x and 2x screens: its
        /// default_icon, else the extension's icons, as Chrome's toolbar picks it.
        var icon: NSImage?
        /// action / browser_action / page_action default_popup, relative to the folder.
        var popupPath: String?
        /// options_ui.page or options_page, relative to the folder.
        var optionsPath: String?
        /// Installed by Chrome into the profile (Web Store); Chrome owns the folder and
        /// loads changes at once, so removing goes through chrome://extensions.
        var managedByChrome = false
        /// Chromium profile folders ("Default", "Profile <id>") it is installed in; nil for an
        /// --load-extension one that loads into every profile (extension-profiles.json, GitHub #131).
        var profiles: Set<String>?
        /// Profile folders where it is turned off in chrome://extensions. Chromium keeps it off
        /// there across launches, also when --load-extension loads the folder again.
        var disabledProfiles: Set<String> = []

        func isInstalled(inProfile name: String) -> Bool { profiles?.contains(name) ?? true }
        func isEnabled(inProfile name: String) -> Bool { isInstalled(inProfile: name) && !disabledProfiles.contains(name) }
    }

    /// The menu bar's Extensions menu and the toolbar read this one.
    static let shared: ExtensionStore = {
        let store = ExtensionStore()
        // An install, switch or removal in chrome://extensions or the Web Store (main queue).
        CraCEFRuntime.setExtensionSettingsChangeHandler { [weak store] in
            MainActor.assumeIsolated { store?.reload() }
        }
        return store
    }()

    /// CraCEF loads the same folder (it also honours CRA_DATA_DIR).
    nonisolated static var directory: URL { AppPaths.supportDir.appendingPathComponent("Extensions", isDirectory: true) }

    /// The folders --load-extension loads at start-up, in name order, and the switch that says
    /// which profiles load each (CraCEFRuntime.setExtensionPaths).
    nonisolated static func loadList(profileIsFree: Bool = true) -> (paths: [String], profiles: String?) {
        let fm = FileManager.default
        // Before Chromium starts: a copy the store already installed in a profile must not load
        // there again, or --load-extension would put the copy back over the store's install.
        let profiles = chromiumProfiles()
        if profileIsFree {
            let settings = { (profile: String) in
                ExtensionImporter.settings(inProfile: AppPaths.chromiumCache.appendingPathComponent(profile, isDirectory: true))
            }
            dropWebStoreCopies(profiles: profiles, settings: settings)
            dropUnpackedCopies(profiles: profiles, settings: settings)
        }
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
            .filter { fm.fileExists(atPath: directory.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }
        return (names.map { directory.appendingPathComponent($0, isDirectory: true).path }, loadProfiles().commandLineValue(forFolders: names))
    }

    nonisolated static func isInstalled(id: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(id).appendingPathComponent("manifest.json").path)
    }

    /// Copies an extension imported from Arc or Dia in as Extensions/<id>,
    /// replacing an older copy of the same extension. It loads in `profiles` (nil: every
    /// profile) from the next launch.
    nonisolated static func importExtension(_ ext: ImportableExtension, profiles: Set<String>?) throws {
        let existed = isInstalled(id: ext.id)
        try importExtension(ext)
        var scopes = loadProfiles()
        scopes.add(folder: ext.id, profiles: profiles, folderExisted: existed)
        try saveProfiles(scopes)
    }

    /// Rebuild from Arc (#131): an extension an older import left loading everywhere gets the
    /// profiles that had it. One that already has its own list keeps it.
    nonisolated static func scopeImported(folder: String, profiles: Set<String>?) {
        var scopes = loadProfiles()
        guard scopes.profiles(ofFolder: folder) == nil, let profiles else { return }
        scopes.add(folder: folder, profiles: profiles, folderExisted: false)
        try? saveProfiles(scopes)
    }

    private nonisolated static func importExtension(_ ext: ImportableExtension) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(ext.id, isDirectory: true)
        let staging = directory.appendingPathComponent(".\(ext.id).importing", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: ext.folder, to: staging)
        // Web Store verification hashes (_metadata) do not apply to an unpacked copy.
        try? fm.removeItem(at: staging.appendingPathComponent("_metadata"))
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: staging, to: dest)
    }

    /// Cra's Chromium profile folders ("Default", "Profile <id>"), sorted.
    nonisolated static func chromiumProfiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: AppPaths.chromiumCache.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
    }

    // MARK: Web Store installs (GitHub #203)

    /// The folders in Extensions/ that hold a Web Store extension (an import from Arc, Dia or
    /// Chrome), with their manifest.
    nonisolated static func webStoreCopies() -> [(folder: String, manifest: [String: Any])] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        return names.compactMap { name in
            let dir = directory.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  WebStoreInstalls.isWebStoreCopy(folder: name, extensionID: chromiumID(key: m["key"] as? String, folder: dir),
                                                  updateURL: m["update_url"] as? String) else { return nil }
            return (name, m)
        }
    }

    /// Each profile where the store has installed a copy's extension stops loading the copy;
    /// a copy no profile loads any more is deleted. True when anything changed.
    @discardableResult
    nonisolated private static func dropWebStoreCopies(profiles: [String], settings: (String) -> [String: Any]) -> Bool {
        var scopes = loadProfiles()
        var changed = false
        for copy in webStoreCopies() {
            for profile in profiles where scopes.loads(folder: copy.folder, inProfile: profile)
                && hasStoreInstall(copy.folder, inProfile: profile, settings: settings(profile)) {
                var next = scopes
                let removeCopy = next.movedToWebStore(folder: copy.folder, profile: profile, allProfiles: Set(profiles))
                if removeCopy {
                    do { try FileManager.default.removeItem(at: directory.appendingPathComponent(copy.folder, isDirectory: true)) }
                    catch {
                        CraLog.note("extension \(copy.folder): could not remove its migrated copy (\(error.localizedDescription))")
                        continue
                    }
                }
                scopes = next
                changed = true
                CraLog.note("extension \(copy.folder) is the Web Store's install in \(profile) now")
                if removeCopy { break }
            }
        }
        if changed {
            do { try saveProfiles(scopes) }
            catch { CraLog.note("extension migration: could not save profile scopes (\(error.localizedDescription))") }
        }
        return changed
    }

    // MARK: Copies of extensions loaded in place (GitHub #299)

    /// A copy in Extensions/ stops loading in each profile that loads its original folder with
    /// chrome://extensions' "Load unpacked", or chrome://extensions lists both; a copy no profile
    /// loads any more is deleted. Before Chromium starts, as dropWebStoreCopies.
    nonisolated private static func dropUnpackedCopies(profiles: [String], settings: (String) -> [String: Any]) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        var scopes = loadProfiles()
        var changed = false
        for folder in names where !folder.hasPrefix(".") {
            for profile in profiles where scopes.loads(folder: folder, inProfile: profile)
                && isLoadedInPlace(folder: folder, settings: settings(profile)) {
                var next = scopes
                let removeCopy = next.stopsLoading(folder: folder, inProfile: profile, allProfiles: Set(profiles))
                if removeCopy {
                    do { try FileManager.default.removeItem(at: directory.appendingPathComponent(folder, isDirectory: true)) }
                    catch {
                        CraLog.note("extension \(folder): could not remove its copy (\(error.localizedDescription))")
                        continue
                    }
                }
                scopes = next
                changed = true
                CraLog.note("extension \(folder) is loaded unpacked from its own folder in \(profile); its copy stops loading there")
                if removeCopy { break }
            }
        }
        if changed {
            do { try saveProfiles(scopes) }
            catch { CraLog.note("extension copies: could not save profile scopes (\(error.localizedDescription))") }
        }
    }

    /// Whether a profile with these extensions.settings loads Extensions/<folder>'s extension
    /// from the folder it was copied from (UnpackedCopies).
    nonisolated private static func isLoadedInPlace(folder: String, settings: [String: Any]) -> Bool {
        let dir = directory.appendingPathComponent(folder, isDirectory: true)
        guard let manifest = manifest(in: dir) else { return false }
        return UnpackedCopies.isLoadedInPlace(copyFolder: folder, copyPath: dir.resolvingSymlinksInPath().path,
                                              copyExtensionID: chromiumID(key: manifest["key"] as? String, folder: dir),
                                              copyName: manifest["name"] as? String, settings: settings) { path in
            Self.manifest(in: URL(fileURLWithPath: path, isDirectory: true))?["name"] as? String
        }
    }

    nonisolated private static func manifest(in folder: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    nonisolated private static func hasStoreInstall(_ id: String, inProfile profile: String, settings: [String: Any]) -> Bool {
        let profileDirectory = AppPaths.chromiumCache.appendingPathComponent(profile, isDirectory: true).resolvingSymlinksInPath()
        guard let installed = WebStoreInstalls.storeInstallDirectory(settings: settings[id] as? [String: Any], extensionID: id,
                                                                    profileDirectory: profileDirectory)?.resolvingSymlinksInPath(),
              installed.deletingLastPathComponent() == profileDirectory.appendingPathComponent("Extensions/\(id)", isDirectory: true),
              let data = try? Data(contentsOf: installed.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = manifest["version"] as? String, !version.isEmpty,
              manifest["manifest_version"] is Int else { return false }
        return true
    }

    /// Web Store copies whose store install was live this session ("<profile>/<id>"). The copy
    /// keeps its folder until the next launch, when the store install is on disk.
    @ObservationIgnored private var liveStoreInstalls: Set<String> = []

    /// A store install seen this session that has left its profile's live settings was removed
    /// (chrome://extensions deletes an INTERNAL extension's entry), so its copy stops loading
    /// there, or the next launch would bring the extension back. The copy goes once no profile
    /// loads it; Chromium stopped reading it when the store install replaced it.
    private func dropRemovedStoreInstalls(profiles: [String], live: [String: [String: Any]]) {
        var scopes = Self.loadProfiles()
        var changed = false
        for copy in Self.webStoreCopies() {
            for profile in profiles where scopes.loads(folder: copy.folder, inProfile: profile) {
                guard let settings = live[profile] else { continue }
                let key = "\(profile)/\(copy.folder)"
                if Self.hasStoreInstall(copy.folder, inProfile: profile, settings: settings) {
                    liveStoreInstalls.insert(key)
                    continue
                }
                guard liveStoreInstalls.contains(key), settings[copy.folder] == nil else { continue }
                var next = scopes
                if next.movedToWebStore(folder: copy.folder, profile: profile, allProfiles: Set(profiles)) {
                    do { try FileManager.default.removeItem(at: Self.directory.appendingPathComponent(copy.folder, isDirectory: true)) }
                    catch {
                        CraLog.note("extension \(copy.folder): could not remove its copy (\(error.localizedDescription))")
                        continue
                    }
                }
                liveStoreInstalls.remove(key)
                scopes = next
                changed = true
                CraLog.note("extension \(copy.folder) was removed from \(profile) after its Web Store install; its copy stops loading there")
            }
        }
        if changed {
            do { try Self.saveProfiles(scopes) }
            catch { CraLog.note("extension migration: could not save profile scopes (\(error.localizedDescription))") }
        }
    }

    /// Extension IDs asked of the store in a profile this session ("<profile>/<id>"), each once.
    @ObservationIgnored private var webStoreAsked: Set<String> = []

    /// A page in `profile` has loaded, so the profile's extensions are up: its Web Store copies
    /// are installed from the store there (Cra.installFromWebStore, the store's own install).
    /// The store's version may not ask for more permissions than the copy the person picked.
    func installFromWebStore(using browser: CraBrowser, profile: String) {
        let scopes = Self.loadProfiles()
        let live = Self.extensionSettings(inProfile: profile)
        for copy in Self.webStoreCopies() where !webStoreAsked.contains("\(profile)/\(copy.folder)") {
            guard !WebStoreInstalls.pendingProfiles(folder: copy.folder, extensionID: copy.folder, scopes: scopes,
                                                    profiles: [profile], settings: { _ in live }).isEmpty,
                  let params = try? JSONSerialization.data(withJSONObject: ["id": copy.folder, "manifest": copy.manifest]) else { continue }
            webStoreAsked.insert("\(profile)/\(copy.folder)")
            CraLog.note("extension \(copy.folder): installing from the Web Store in \(profile)")
            browser.sendDevToolsMethod("Cra.installFromWebStore", params: String(decoding: params, as: UTF8.self)) { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error { CraLog.note("extension \(copy.folder): Web Store install in \(profile) failed (\(error)); it keeps loading from its folder") }
                    self?.reload()
                }
            }
        }
    }

    // MARK: Profiles of the Extensions/ folders (GitHub #131)

    nonisolated private static var profilesFile: URL { AppPaths.file("extension-profiles.json") }

    nonisolated static func loadProfiles() -> ExtensionProfiles {
        guard let data = try? Data(contentsOf: profilesFile) else { return ExtensionProfiles() }
        return (try? JSONDecoder().decode(ExtensionProfiles.self, from: data)) ?? ExtensionProfiles()
    }

    nonisolated private static func saveProfiles(_ profiles: ExtensionProfiles) throws {
        if profiles.folders.isEmpty {
            if FileManager.default.fileExists(atPath: profilesFile.path) { try FileManager.default.removeItem(at: profilesFile) }
        } else {
            try JSONEncoder().encode(profiles).write(to: profilesFile, options: .atomic)
        }
    }

    private(set) var entries: [Entry] = []
    /// Set once the folder changed in this session; a restart loads the change.
    private(set) var needsRestart = false

    init() {
        reload()
        // Keep what was taken over from another browser, so it is only read once.
        if !FileManager.default.fileExists(atPath: Self.pinnedFile.path), !pinned.shared.isEmpty { savePinned() }
    }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: ExtensionStore.directory, withIntermediateDirectories: true)
        let root = AppPaths.chromiumCache
        let profiles = Self.chromiumProfiles()
        let live = Dictionary(uniqueKeysWithValues: profiles.compactMap { p in Self.liveExtensionSettings(inProfile: p).map { (p, $0) } })
        let settings = Dictionary(uniqueKeysWithValues: profiles.map {
            ($0, live[$0] ?? ExtensionImporter.settings(inProfile: root.appendingPathComponent($0, isDirectory: true)))
        })
        dropRemovedStoreInstalls(profiles: profiles, live: live)
        let names = (try? fm.contentsOfDirectory(atPath: ExtensionStore.directory.path)) ?? []
        let disabled = settings.mapValues(ExtensionImporter.disabledIDs(settings:))
        let scopes = Self.loadProfiles()
        var list = names.sorted().compactMap { name -> Entry? in
            guard var entry = Self.entry(id: name, folder: ExtensionStore.directory.appendingPathComponent(name, isDirectory: true),
                                         extensionID: nil) else { return nil }
            entry.profiles = scopes.profiles(ofFolder: name)
            // The store's install, or the folder it copies loaded in place (#299), stands in for it there.
            let migrated = Set(profiles.filter {
                scopes.loads(folder: name, inProfile: $0)
                    && (Self.hasStoreInstall(entry.extensionID, inProfile: $0, settings: settings[$0] ?? [:])
                        || Self.isLoadedInPlace(folder: name, settings: settings[$0] ?? [:]))
            })
            if !migrated.isEmpty {
                entry.profiles = (entry.profiles ?? Set(profiles)).subtracting(migrated)
                if entry.profiles?.isEmpty == true { return nil }
            }
            entry.disabledProfiles = Set(profiles.filter { disabled[$0]?.contains(entry.extensionID) == true })
            return entry
        }
        let loaded = Set(list.map(\.extensionID))
        // Each profile has its own Web Store extensions: note which profiles hold each one.
        var managed: [Entry] = []
        for profile in profiles {
            // Turned-off ones stay listed (as off) so their pins come back with them.
            for e in ExtensionImporter.extensions(settings: settings[profile] ?? [:], inProfile: root.appendingPathComponent(profile, isDirectory: true)) {
                // The store's install of a copy that still loads from its folder in other profiles.
                if loaded.contains(e.id) {
                    guard let i = list.firstIndex(where: { $0.extensionID == e.id }), list[i].profiles?.contains(profile) == false else { continue }
                    list[i].profiles?.insert(profile)
                    if !e.isEnabled { list[i].disabledProfiles.insert(profile) }
                    continue
                }
                var i = managed.firstIndex(where: { $0.extensionID == e.id })
                if i == nil, var entry = Self.entry(id: e.id, folder: e.folder, extensionID: e.id) {
                    entry.managedByChrome = true
                    entry.profiles = []
                    managed.append(entry)
                    i = managed.count - 1
                }
                guard let i else { continue }
                managed[i].profiles?.insert(profile)
                if !e.isEnabled { managed[i].disabledProfiles.insert(profile) }
            }
        }
        let next = list + managed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // chrome://extensions switches, in the log: a report of a click on a turned-off extension
        // shows when Cra learned about it.
        for e in next {
            guard let old = entries.first(where: { $0.extensionID == e.extensionID }) else { continue }
            for p in e.disabledProfiles.subtracting(old.disabledProfiles).sorted() { CraLog.note("extension \(e.extensionID) turned off in \(p)") }
            for p in old.disabledProfiles.subtracting(e.disabledProfiles).sorted() { CraLog.note("extension \(e.extensionID) turned on in \(p)") }
        }
        entries = next
        pinned.removeAll { id in !entries.contains { $0.extensionID == id } }
        noteProxyControllers(settings: settings)
    }

    // MARK: Proxy (GitHub #107)

    /// Per profile folder, the turned-on extensions that set the proxy, the one Chromium applies
    /// first. Two of them collide quietly: the others get "controlled_by_other_extensions",
    /// which only the extensions themselves show, so the log and diagnostics name them.
    private(set) var proxyControllers: [String: [ExtensionProxyControl.Controller]] = [:]

    private func noteProxyControllers(settings: [String: [String: Any]]) {
        var next: [String: [ExtensionProxyControl.Controller]] = [:]
        for (profile, s) in settings {
            let on = Set(entries(inProfile: profile).map(\.extensionID))
            let c = ExtensionProxyControl.controllers(settings: s, enabled: on)
            if !c.isEmpty { next[profile] = c }
        }
        // By what the line says: --load-extension reinstalls (new times) on every launch.
        for profile in Set(next.keys).union(proxyControllers.keys).sorted() {
            let line = Self.proxyLine(next[profile] ?? [])
            if line != Self.proxyLine(proxyControllers[profile] ?? []) { CraLog.note("proxy in \(profile): " + line) }
        }
        proxyControllers = next
    }

    /// The line for one profile folder, as a page's failed load in cra.log names it.
    func proxyLine(inProfile name: String) -> String { Self.proxyLine(proxyControllers[name] ?? []) }

    /// "set by <id> (<config>), overriding <id>, <id>", or "not set by an extension".
    static func proxyLine(_ controllers: [ExtensionProxyControl.Controller]) -> String {
        guard let first = controllers.first else { return "not set by an extension" }
        let others = controllers.dropFirst().map(\.extensionID)
        return "set by \(first.extensionID) (\(first.config))" + (others.isEmpty ? "" : ", overriding " + others.joined(separator: ", "))
    }

    /// The extensions a page in this Chromium profile folder can run; running another
    /// profile's extension there, or one turned off there, crashes Chromium. Arc's toolbar and
    /// Site Control Center leave turned-off extensions out (Chrome's toolbar model).
    func entries(inProfile name: String) -> [Entry] { entries.filter { $0.isEnabled(inProfile: name) } }

    // MARK: Installed, turned on and off in chrome://extensions (GitHub #41, #43)

    /// A profile's extensions.settings. Chromium writes its prefs to disk ~10 s after an install
    /// or a switch, so a profile that has loaded answers from memory (and says when it changes);
    /// the files only for one no space has opened yet, where nothing can have changed.
    private static func extensionSettings(inProfile name: String) -> [String: Any] {
        liveExtensionSettings(inProfile: name)
            ?? ExtensionImporter.settings(inProfile: AppPaths.chromiumCache.appendingPathComponent(name, isDirectory: true))
    }

    /// A loaded profile's extensions.settings from Chromium's memory; nil before it loads or
    /// once it has shut down.
    private static func liveExtensionSettings(inProfile name: String) -> [String: Any]? {
        let dir = AppPaths.chromiumCache.appendingPathComponent(name, isDirectory: true)
        guard let json = CraCEFRuntime.extensionSettings(forProfile: name == "Default" ? nil : dir.path) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }

    /// The extension whose options page `url` is (its options_ui/options_page, or Chrome's
    /// chrome://extensions page for it). Chrome keeps one such tab and opening it again selects it.
    func optionsPageOwner(_ url: String) -> String? {
        guard let u = URLComponents(string: url) else { return nil }
        if u.scheme == "chrome", u.host == "extensions" {
            return u.queryItems?.first(where: { $0.name == "options" || $0.name == "id" })?.value
        }
        guard u.scheme == "chrome-extension", let id = u.host,
              let options = entries.first(where: { $0.extensionID == id })?.optionsPath else { return nil }
        let path = options.split(separator: "?", maxSplits: 1).first.map(String.init) ?? options
        return u.path == "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ? id : nil
    }

    private static func entry(id: String, folder dir: URL, extensionID: String?) -> Entry? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ k: String) -> String { (m[k] as? String) ?? "" }
        var title = ExtensionImporter.localized(str("name"), manifest: m, folder: dir)
        if title.hasPrefix("__MSG_") { title = id }
        let action = (m["action"] ?? m["browser_action"] ?? m["page_action"]) as? [String: Any]
        let options = (m["options_ui"] as? [String: Any])?["page"] as? String ?? m["options_page"] as? String
        // A path or {size: path} (React DevTools' grey "disabled" icon until a page uses React).
        let actionIcons = action?["default_icon"] as? [String: String] ?? (action?["default_icon"] as? String).map { ["16": $0] }
        let description = ExtensionImporter.localizedDescription(manifest: m, folder: dir)
        return Entry(id: id, name: title.isEmpty ? id : title, version: str("version"), description: description, url: dir,
                     extensionID: extensionID ?? chromiumID(key: m["key"] as? String, folder: dir),
                     icon: actionIcons.flatMap { ExtensionImporter.icon(manifest: ["icons": $0], folder: dir, points: 16) }
                        ?? ExtensionImporter.icon(manifest: m, folder: dir, points: 16),
                     popupPath: (action?["default_popup"] as? String).flatMap { $0.isEmpty ? nil : $0 }, optionsPath: options)
    }

    /// Chromium's ID: the first 128 bits of SHA-256 over the manifest key (or the
    /// unpacked folder's path), each hex digit mapped 0-f → a-p.
    nonisolated static func chromiumID(key: String?, folder: URL) -> String {
        let input = key.flatMap { Data(base64Encoded: $0) } ?? Data(folder.path.utf8)
        let digest = SHA256.hash(data: input).prefix(16)
        let a = UInt8(ascii: "a")
        return String(decoding: digest.flatMap { [a + ($0 >> 4), a + ($0 & 0xF)] }, as: UTF8.self)
    }

    // MARK: Pinned extensions (Dia's Extensions ▸ Pin Extensions…; toolbar buttons)

    private static var pinnedFile: URL { AppPaths.file("pinned-extensions.json") }

    /// Each profile's pins, like Arc's (GitHub #107).
    private(set) var pinned = ExtensionStore.loadPinned()

    /// Before Cra has a list of its own, the browser it replaces supplies one: Arc keeps its
    /// pinned extensions in Chromium's `extensions.pinned_extensions` pref, as do Dia and Chrome.
    private static func loadPinned() -> PinnedExtensions {
        if let data = try? Data(contentsOf: pinnedFile) { return (try? JSONDecoder().decode(PinnedExtensions.self, from: data)) ?? PinnedExtensions() }
        for source in [ImportSource.arc, .dia] + ImportSource.allCases.filter({ $0.id == "chrome" }) {
            guard let ids = ExtensionImporter.pinnedIDs(inProfile: source.dataDir.appendingPathComponent("Default", isDirectory: true)),
                  !ids.isEmpty else { continue }
            return PinnedExtensions(shared: ids)
        }
        return PinnedExtensions()
    }

    /// Chromium extension IDs in toolbar order, for spaces on this profile folder.
    func pinnedIDs(inProfile profile: String) -> [String] { pinned.ids(inProfile: profile) }

    func isPinned(_ id: String, inProfile profile: String) -> Bool { pinned.isPinned(id, inProfile: profile) }

    func setPinned(_ id: String, _ isPinned: Bool, inProfile profile: String) {
        let before = pinned
        pinned.setPinned(id, isPinned, inProfile: profile)
        if pinned != before { savePinned() }
    }

    /// The pins a profile had in the browser the import came from (GitHub #131): a profile the
    /// import made gets them as its own. Default's become everyone's list while Cra has none
    /// saved yet, as they would at the first launch after the import (loadPinned).
    func seedPinned(_ ids: [String], inProfile profile: String) {
        let before = pinned
        if profile == "Default" {
            guard !FileManager.default.fileExists(atPath: Self.pinnedFile.path), pinned.shared.isEmpty else { return }
            pinned.shared = ids
        } else {
            pinned.seed(ids, inProfile: profile)
        }
        if pinned != before { savePinned() }
    }

    func movePinned(_ id: String, to index: Int, inProfile profile: String) {
        let before = pinned
        pinned.move(id, to: index, inProfile: profile)
        if pinned != before { savePinned() }
    }

    private func savePinned() {
        try? JSONEncoder().encode(pinned).write(to: Self.pinnedFile, options: .atomic)
        NotificationCenter.default.post(name: .craPinnedExtensionsChanged, object: self)
    }

    // MARK: Toolbar icons (GitHub #9: a pinned extension's button in Cra's monochrome ink)

    /// How a pinned extension's button draws, keyed by Chromium extension ID, so it survives
    /// restarts and extension updates. The extension's own icon is untouched elsewhere.
    struct IconStyle: Codable, Equatable {
        /// Drawn as a template in the toolbar's ink instead of the extension's colours.
        var monochrome = false
        /// An SF Symbol in place of the extension's icon (always monochrome).
        var symbol: String?
        /// An image the user picked, copied into "Extension Icons".
        var imageFile: String?
    }

    /// Symbols offered in place of an extension's icon.
    static let iconSymbols = ["shield.lefthalf.filled", "lock.shield", "key", "lock", "person.badge.key",
                              "eye.slash", "hand.raised", "checkmark.shield", "bolt", "star", "bookmark",
                              "doc.text", "paintbrush", "globe", "puzzlepiece.extension"]

    private static var iconStylesFile: URL { AppPaths.file("extension-icons.json") }
    private static var customIconsDir: URL { AppPaths.supportDir.appendingPathComponent("Extension Icons", isDirectory: true) }

    private(set) var iconStyles: [String: IconStyle] = {
        guard let data = try? Data(contentsOf: ExtensionStore.iconStylesFile) else { return [:] }
        return (try? JSONDecoder().decode([String: IconStyle].self, from: data)) ?? [:]
    }()
    /// One image per extension, so the toolbar sees the same object until the style or the
    /// image it was made from changes.
    @ObservationIgnored private var toolbarIcons: [String: (base: NSImage?, image: NSImage?)] = [:]

    func iconStyle(_ id: String) -> IconStyle { iconStyles[id] ?? IconStyle() }

    func setIconStyle(_ id: String, _ style: IconStyle) {
        let old = iconStyle(id)
        guard style != old else { return }
        if let file = old.imageFile, file != style.imageFile {
            try? FileManager.default.removeItem(at: Self.customIconsDir.appendingPathComponent(file))
        }
        iconStyles[id] = style == IconStyle() ? nil : style
        toolbarIcons[id] = nil
        try? JSONEncoder().encode(iconStyles).write(to: Self.iconStylesFile, options: .atomic)
    }

    /// Copies `url` in as the extension's toolbar icon.
    func setCustomIcon(_ id: String, from url: URL) throws {
        guard NSImage(contentsOf: url) != nil else {
            throw NSError(domain: "Cra", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file is not an image."])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.customIconsDir, withIntermediateDirectories: true)
        // A new name each time: the old file is removed once the style no longer points at it.
        let name = "\(id)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        try fm.copyItem(at: url, to: Self.customIconsDir.appendingPathComponent(name))
        var style = iconStyle(id)
        style.symbol = nil
        style.imageFile = name
        setIconStyle(id, style)
    }

    /// The pinned button's image: the extension's icon as it is now on `tab`, the user's
    /// replacement, or either as a template image (the button tints templates with the toolbar's
    /// ink). A monochrome icon follows the extension's own changes.
    func toolbarIcon(for e: Entry, profile: String, tab: UUID?) -> NSImage? {
        // Read before the early return, so every caller's observation sees the extension's changes.
        let live = liveIcon(for: e, profile: profile, tab: tab)
        let style = iconStyle(e.extensionID)
        if style == IconStyle() { return live }
        let set = live === e.icon ? nil : live
        if let cached = toolbarIcons[e.extensionID], cached.base === set { return cached.image }
        var image: NSImage?
        if let symbol = style.symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: e.name)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            image?.isTemplate = true
        } else {
            if let file = style.imageFile {
                image = NSImage(contentsOf: Self.customIconsDir.appendingPathComponent(file)) ?? live
            } else if style.monochrome, set == nil {
                // From the largest icon: in the 16 px one a plate's edge and the mark blur together.
                let manifest = (try? Data(contentsOf: e.url.appendingPathComponent("manifest.json")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                image = manifest.flatMap { ExtensionImporter.icon(manifest: $0, folder: e.url, minPixels: 128) } ?? e.icon
            } else {
                image = live
            }
            if style.monochrome { image = image.flatMap(Self.monochrome) }
        }
        toolbarIcons[e.extensionID] = (set, image)
        return image
    }

    // MARK: Live actions (GitHub #106: chrome.action.setIcon, setTitle)

    /// What extensions set on their toolbar actions while running, from Chromium
    /// (ExtensionActions forwards Extensions.actionUpdated).
    private(set) var actions = ExtensionActionStates()
    /// Decoded icons by their PNG bytes, so a redraw sees the same image until the icon changes.
    @ObservationIgnored private var actionIcons: [Data: NSImage] = [:]

    func applyActionUpdate(_ update: ExtensionActionUpdate, tab: UUID?) {
        var next = actions
        next.apply(update, tab: tab)
        guard next != actions else { return }
        actions = next
    }

    /// Drops the values extensions set for a tab whose page is gone (closed or asleep).
    func forgetActionTab(_ tab: UUID) {
        var next = actions
        next.removeTab(tab)
        guard next != actions else { return }
        actions = next
    }

    /// The icon the extension shows on `tab` (any tab when nil): the one it set there, else
    /// the one it set for every tab, else its manifest's.
    func liveIcon(for e: Entry, profile: String, tab: UUID?) -> NSImage? {
        guard let png = actions.state(extensionID: e.extensionID, profile: profile, tab: tab).icon else { return e.icon }
        if let image = actionIcons[png] { return image }
        guard let image = NSImage(data: png), image.size.width > 0 else { return e.icon }
        // Action icons are 16 pt; Chromium sends the largest scale it has (32 px on Retina).
        image.size = NSSize(width: 16, height: 16 * image.size.height / image.size.width)
        if actionIcons.count > 64 { actionIcons.removeAll() }
        actionIcons[png] = image
        return image
    }

    /// The badge the extension shows on `tab` (chrome.action.setBadgeText), laid out as Arc does.
    func badge(for e: Entry, profile: String, tab: UUID?) -> ExtensionBadge? {
        let font = Self.badgeFont(size: ExtensionBadge.measuringFontSize)
        return ExtensionBadge(state: actions.state(extensionID: e.extensionID, profile: profile, tab: tab),
                              defaultBackground: Self.badgeDefaultBackground) { text in
            Double((text as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    /// The badge's colour when the extension set none: Chromium's neutral container (kColorRefNeutral15
    /// dark, 94 light). Arc's dark one measures the same (1.171); light mode not seen in Arc.
    static var badgeDefaultBackground: ExtensionBadge.RGBA {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ExtensionBadge.RGBA(hex: dark ? "#282828" : "#EFEDED")!
    }

    /// The badge's bold system font at SF's optical size 24, between its text and display designs:
    /// with it "7", "42" and "1234" take Arc's widths exactly (CoreText's own choice at 9 pt is wider,
    /// the display design narrower; measured 2 Nov 2026).
    static func badgeFont(size: Double) -> NSFont {
        let opticalSize = 0x6F70737A // 'opsz'
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [opticalSize: 24],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Recent badged icons, so a redraw sees the same image until icon, badge or ink change.
    @ObservationIgnored private var badgedIcons: [(icon: NSImage, badge: ExtensionBadge, tint: NSColor, image: NSImage)] = []

    /// `icon` with `badge` drawn into it the way Chromium does (IconWithBadgeImageSource): a ring
    /// cut out of the icon, then the badge. The buttons draw the result as is, so a template icon
    /// takes `tint` first and the badge keeps its own colours.
    func badged(_ icon: NSImage?, _ badge: ExtensionBadge?, tint: NSColor) -> NSImage? {
        guard let icon, let badge else { return icon }
        if let hit = badgedIcons.first(where: { $0.icon === icon && $0.badge == badge && $0.tint == tint }) { return hit.image }
        let side = 16.0
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let fit = min(side / max(icon.size.width, 1), side / max(icon.size.height, 1))
            let w = icon.size.width * fit, h = icon.size.height * fit
            let box = NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
            icon.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if icon.isTemplate {
                tint.setFill()
                box.fill(using: .sourceAtop)
            }
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: badge.cutout, xRadius: badge.cutoutCornerRadius, yRadius: badge.cutoutCornerRadius).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.background.color.setFill()
            NSBezierPath(roundedRect: badge.frame, xRadius: badge.cornerRadius, yRadius: badge.cornerRadius).fill()
            let font = Self.badgeFont(size: ExtensionBadge.fontSize)
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            centred.lineBreakMode = .byClipping
            let line = font.ascender - font.descender
            (badge.text as NSString).draw(in: NSRect(x: badge.frame.minX, y: badge.frame.midY - line / 2, width: badge.frame.width, height: line),
                                          withAttributes: [.font: font, .foregroundColor: badge.textColor.color, .paragraphStyle: centred])
            return true
        }
        badgedIcons.append((icon, badge, tint, image))
        if badgedIcons.count > 32 { badgedIcons.removeFirst() }
        return image
    }

    /// An icon as a one-ink template, the way Arc's own toolbar glyphs read. An icon drawn on a
    /// plate (one colour covering most of it: Bitwarden's blue square, Vercel's black disc) keeps
    /// what stands out from the plate, so Bitwarden becomes its shield. Without a plate, colour
    /// reads as ink and white as none, so a white badge keeps only its mark. Ink is scaled so the
    /// strongest is solid; a one-colour glyph (nothing stands out) keeps its silhouette.
    static func monochrome(_ source: NSImage) -> NSImage? {
        let n = 64
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        source.draw(in: NSRect(x: 0, y: 0, width: n, height: n), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let count = n * n
        // Premultiplied: divide the alpha back out before judging the colour.
        func rgb(_ i: Int) -> (Double, Double, Double) {
            let a = Double(data[i * 4 + 3]) / 255
            return (Double(data[i * 4]) / 255 / a, Double(data[i * 4 + 1]) / 255 / a, Double(data[i * 4 + 2]) / 255 / a)
        }
        // The plate: the most common opaque colour (16 levels a channel), if it covers 40 % of the icon.
        var buckets: [Int: (n: Int, r: Double, g: Double, b: Double)] = [:]
        var visible = 0
        for i in 0..<count where data[i * 4 + 3] > 12 {
            visible += 1
            guard data[i * 4 + 3] > 240 else { continue }
            let (r, g, b) = rgb(i)
            let key = Int(r * 15.99) << 8 | Int(g * 15.99) << 4 | Int(b * 15.99)
            let o = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (o.n + 1, o.r + r, o.g + g, o.b + b)
        }
        let top = buckets.values.max { $0.n < $1.n }
        let plate = top.flatMap { t in Double(t.n) >= Double(visible) * 0.4 ? (t.r / Double(t.n), t.g / Double(t.n), t.b / Double(t.n)) : nil }
        var ink = [Double](repeating: 0, count: count)
        var inkMax = 0.0
        for i in 0..<count {
            let a = Double(data[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            let (r, g, b) = rgb(i)
            if let p = plate {
                ink[i] = a * min(1, ((r - p.0) * (r - p.0) + (g - p.1) * (g - p.1) + (b - p.2) * (b - p.2)).squareRoot() / 0.5)
            } else {
                ink[i] = a * max(0, 1 - (0.2126 * r + 0.7152 * g + 0.0722 * b))
            }
            inkMax = max(inkMax, ink[i])
        }
        let silhouette = inkMax < 0.08
        for i in 0..<count {
            let a = Double(data[i * 4 + 3]) / 255
            let v = silhouette ? a : min(max((ink[i] / inkMax - 0.1) / 0.5, 0), 1)
            let byte = UInt8((v * 255).rounded())
            data[i * 4] = 0; data[i * 4 + 1] = 0; data[i * 4 + 2] = 0; data[i * 4 + 3] = byte
        }
        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    /// Copies an unpacked extension folder (one that holds manifest.json) in.
    func add(folder: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) else {
            throw NSError(domain: "Cra", code: 1, userInfo: [NSLocalizedDescriptionKey: "That folder has no manifest.json."])
        }
        var dest = ExtensionStore.directory.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = ExtensionStore.directory.appendingPathComponent("\(folder.lastPathComponent)-\(n)", isDirectory: true)
            n += 1
        }
        try fm.copyItem(at: folder, to: dest)
        needsRestart = true
        reload()
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        if !entry.managedByChrome {
            var scopes = Self.loadProfiles()
            scopes.remove(folder: entry.id)
            try? Self.saveProfiles(scopes)
        }
        needsRestart = true
        reload()
    }
}

extension Notification.Name {
    static let craPinnedExtensionsChanged = Notification.Name("craPinnedExtensionsChanged")
}

extension ExtensionBadge.RGBA {
    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}
