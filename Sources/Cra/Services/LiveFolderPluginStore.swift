import AppKit
import CraCEF
import Observation

@MainActor
@Observable
final class LiveFolderPluginStore {
    struct Entry {
        let package: LiveFolderPluginPackage
        let presentation: LiveFolderPluginPresentation
        let icon: NSImage
    }

    static let shared = LiveFolderPluginStore()
    private(set) var entries: [String: Entry] = [:]
    private(set) var packages: [LiveFolderPluginPackage] = []
    private(set) var failures: [String] = []
    private(set) var loaded = false
    private(set) var reloading = false
    private(set) var disabled: Set<String>
    @ObservationIgnored private let disabledFile = JSONStore<[String]>("disabled-live-folder-plugins.json")

    private init() { disabled = Set(disabledFile.load(or: { [] })) }

    func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }

    func isBundled(_ package: LiveFolderPluginPackage) -> Bool {
        package.isInside(Bundle.main.resourceURL!)
    }

    func setEnabled(_ enabled: Bool, id: String) async {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        disabledFile.saveNow(disabled.sorted())
        await reload()
        await LiveFolderManager.shared.migrateFolders()
        LiveFolderManager.shared.refreshStale()
    }

    func install(_ directory: URL) async throws {
        let package = try LiveFolderPluginPackage(directory: directory)
        guard !packages.contains(where: { $0.manifest.id == package.manifest.id }) else {
            throw LiveFolderPluginError.invalidManifest("A plugin with this ID is already installed")
        }
        guard package.manifest.legacySource == nil, package.manifest.legacyCommand == nil else {
            throw LiveFolderPluginError.invalidManifest("Legacy migration metadata is reserved for bundled plugins")
        }
        let data = try await invoke(package, method: "describe", input: Data("{}".utf8), origins: [], profile: nil)
        let presentation = try JSONDecoder().decode(LiveFolderPluginPresentation.self, from: data)
        try presentation.validate()
        guard NSImage(contentsOf: try package.resource(presentation.icon)) != nil else {
            throw LiveFolderPluginError.invalidManifest("Invalid plugin icon")
        }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let staging = Self.directory.appendingPathComponent(".install-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: directory, to: staging)
        try FileManager.default.moveItem(at: staging, to: Self.directory.appendingPathComponent(package.manifest.id, isDirectory: true))
        await reload()
    }

    func remove(_ package: LiveFolderPluginPackage) async throws {
        guard !isBundled(package), package.directory.deletingLastPathComponent() == Self.directory.resolvingSymlinksInPath().standardizedFileURL else {
            throw LiveFolderPluginError.invalidManifest("Only installed user plugins can be removed")
        }
        try FileManager.default.trashItem(at: package.directory, resultingItemURL: nil)
        await reload()
    }

    static var directory: URL { AppPaths.supportDir.appendingPathComponent("LiveFolderPlugins", isDirectory: true) }

    func entry(for live: LiveFolderData) -> Entry? {
        if let id = live.plugin?.id { return entries[id] }
        return entries.values.first { $0.package.manifest.legacySource == live.source.rawValue }
    }

    func entry(forCommand id: String) -> Entry? {
        entries.values.first { isEnabled($0.package.manifest.id) && Self.commandID($0) == id }
    }

    static func commandID(_ entry: Entry) -> String {
        entry.package.manifest.legacyCommand ?? "liveFolderPlugin:" + entry.package.manifest.id
    }

    private static var executable: URL {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("CraPluginHost")
    }

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var reloadAgain = false

    /// Reads both plugin folders again. A call while one runs waits for a second pass that starts
    /// after it, so an install or a toggle never returns before its plugin is (or isn't) loaded.
    func reload() async {
        if let running = reloadTask {
            reloadAgain = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            reloading = true
            repeat {
                reloadAgain = false
                await loadPackages()
            } while reloadAgain
            reloading = false
        }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    private func loadPackages() async {
        let builtin = Bundle.main.resourceURL!.appendingPathComponent("live-folder-plugins", isDirectory: true)
        let roots = [builtin, Self.directory]
        var directories: [URL] = []
        var errors: [String] = []
        for root in roots {
            do {
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                directories += try FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch { errors.append(error.localizedDescription) }
        }
        let catalog = LiveFolderPluginCatalog(directories: directories)
        packages = catalog.packages
        errors += catalog.failures.map { "\($0.directory.lastPathComponent): \($0.message)" }
        var loadedEntries: [String: Entry] = [:]
        for package in catalog.packages {
            do {
                if !package.isInside(builtin),
                   package.manifest.legacySource != nil || package.manifest.legacyCommand != nil {
                    throw LiveFolderPluginError.invalidManifest("Legacy migration metadata is reserved for bundled plugins")
                }
                guard isEnabled(package.manifest.id) else { continue }
                let data = try await invoke(package, method: "describe", input: Data("{}".utf8), origins: [], profile: nil)
                let presentation = try JSONDecoder().decode(LiveFolderPluginPresentation.self, from: data)
                try presentation.validate()
                let iconURL = try package.resource(presentation.icon)
                guard let icon = NSImage(contentsOf: iconURL) else {
                    throw LiveFolderPluginError.invalidManifest("Invalid plugin icon")
                }
                icon.isTemplate = true
                loadedEntries[package.manifest.id] = Entry(package: package, presentation: presentation, icon: icon)
            } catch { errors.append("\(package.manifest.id): \(error.localizedDescription)") }
        }
        entries = loadedEntries
        KeyBindingRegistry.shared.setPluginActions(loadedEntries.values.sorted { $0.package.manifest.name < $1.package.manifest.name }.map { entry in
            let manifest = entry.package.manifest
            return KeyAction(id: Self.commandID(entry), name: manifest.command?.title ?? "Add \(manifest.name) Live Folder",
                             section: .file, shortcuts: [], triggers: manifest.command?.triggers ?? [manifest.name])
        })
        failures = errors
        loaded = true
    }

    func invoke(_ package: LiveFolderPluginPackage, method: String, input: Data,
                origins: [LiveFolderSessionOrigin], profile: String?,
                isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Data {
        let executable = Self.executable
        let id = package.manifest.id
        // The helper's pipe and each session request block their thread until the answer comes (up
        // to the 30 s deadline): a queue of their own, not Swift's cooperative pool, which has a
        // thread per core and stalls every other task in Cra while they are all waiting.
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result {
                    try LiveFolderPluginProcess.invoke(executable: executable, script: package.script, method: method,
                        input: input, origins: origins) { request in
                            try Self.fetch(request, origins: origins, profile: profile, pluginID: id, isCurrent: isCurrent)
                        }
                })
            }
        }
    }

    nonisolated private static let queue = DispatchQueue(label: "cra.live-folder-plugins", qos: .utility, attributes: .concurrent)
    /// CRA_LIVE_FOLDER_DEBUG=1 writes every session response a plugin gets to <data dir>/live-folder-debug/.
    nonisolated private static let debug = ProcessInfo.processInfo.environment["CRA_LIVE_FOLDER_DEBUG"] == "1"

    nonisolated private static func dump(_ request: String, _ response: LiveFolderPluginResponse, pluginID: String) {
        let dir = AppPaths.file("live-folder-debug")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "GET \(request)\nstatus \(response.status)\nfinal \(response.url)\n\n\(response.body)"
        let file = dir.appendingPathComponent("\(pluginID)-\(Int(Date().timeIntervalSince1970 * 1000)).txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    nonisolated private static func fetch(_ request: LiveFolderPluginRequest,
                                          origins: [LiveFolderSessionOrigin], profile: String?, pluginID: String,
                                          isCurrent: @escaping @MainActor @Sendable () -> Bool) throws -> LiveFolderPluginResponse {
        var address = request.url
        for _ in 0..<10 {
            guard let url = URL(string: address), origins.contains(where: { $0.permits(url) }) else {
                return LiveFolderPluginResponse(status: 401, url: request.url, body: "")
            }
            let pending = PluginSessionResponse()
            let target = address
            DispatchQueue.main.async {
                guard isCurrent(), LiveFolderPluginStore.shared.isEnabled(pluginID),
                      LiveFolderPluginStore.shared.packages.contains(where: { $0.manifest.id == pluginID }) else {
                    pending.resolve(LiveFolderPluginResponse(status: 0, url: target, body: ""))
                    return
                }
                CraCEFRuntime.fetchPluginURL(target, headers: request.headers, profilePath: profile) { status, finalURL, _, body in
                    pending.resolve(LiveFolderPluginResponse(status: Int(status), url: finalURL, body: body))
                }
            }
            let response = try pending.wait()
            if debug { dump(target, response, pluginID: pluginID) }
            if (300..<400).contains(response.status) {
                address = response.url
                continue
            }
            return response
        }
        throw LiveFolderPluginError.executionFailed("Too many session redirects")
    }
}

private final class PluginSessionResponse: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var response: LiveFolderPluginResponse?

    func resolve(_ value: LiveFolderPluginResponse) {
        lock.lock()
        response = value
        lock.unlock()
        ready.signal()
    }

    func wait() throws -> LiveFolderPluginResponse {
        guard ready.wait(timeout: .now() + 40) == .success else {
            throw LiveFolderPluginError.executionFailed("Session request timed out")
        }
        lock.lock()
        defer { lock.unlock() }
        guard let response else { throw LiveFolderPluginError.executionFailed("Missing session response") }
        return response
    }
}
