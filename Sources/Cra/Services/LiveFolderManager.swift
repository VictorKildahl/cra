import AppKit
import Observation

@MainActor
@Observable
final class LiveFolderManager {
    static let shared = LiveFolderManager()
    @ObservationIgnored private weak var store: SidebarStore?
    private(set) var refreshing: Set<UUID> = []
    private(set) var repositories: [UUID: [String]] = [:]
    private(set) var diagnostics: [UUID: String] = [:]
    @ObservationIgnored private var pendingRefresh: Set<UUID> = []
    @ObservationIgnored private var timer: ScheduledWork?
    @ObservationIgnored private var lastURL: [UUID: String] = [:]
    nonisolated static let refreshInterval: TimeInterval = 120
    nonisolated static let retention: TimeInterval = 120
    static let minimumInterval: TimeInterval = 10
    nonisolated static let retryInterval: TimeInterval = 30

    func start(store: SidebarStore) {
        self.store = store
        store.liveFolderChanged = { [weak self] id in
            self?.repositories[id] = nil
            self?.refresh(id, force: true)
        }
        timer = store.clock.every(15) { [weak self] in
            self?.store?.expireLiveItems(olderThan: Self.retention)
            self?.refreshStale()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshStale() }
        }
        Task {
            await LiveFolderPluginStore.shared.reload()
            await migrateFolders()
            refreshStale()
        }
    }

    func refreshStale(olderThan age: TimeInterval = refreshInterval) {
        guard NSApp.isActive, LiveFolderPluginStore.shared.loaded, let store else { return }
        for folder in store.liveFolders {
            let last = folder.liveFolder?.lastFetch ?? .distantPast
            let failing = folder.liveFolder.map { $0.lastError != nil || Self.needsSignIn($0) } ?? false
            if store.clock.now.timeIntervalSince(last) >= (failing ? min(age, Self.retryInterval) : age) { refresh(folder.id) }
        }
    }

    nonisolated static func needsSignIn(_ live: LiveFolderData) -> Bool {
        live.lastError == .notSignedIn || live.plugin?.snapshot?.warning != nil
    }

    private struct Migration: Decodable {
        var settings: [String: String]
        var filters: [String]
        var state: [String: String]
    }

    func migrateFolders() async {
        guard let store else { return }
        let registry = LiveFolderPluginStore.shared
        for folder in store.liveFolders {
            guard let live = folder.liveFolder, live.plugin == nil,
                  let entry = registry.entries.values.first(where: { $0.package.manifest.legacySource == live.source.rawValue &&
                      $0.package.directory.path.hasPrefix(Bundle.main.resourceURL!.path + "/") }) else { continue }
            do {
                let result = try await registry.invoke(entry.package, method: "migrate", input: JSONEncoder().encode(live), origins: [], profile: nil)
                let migrated = try JSONDecoder().decode(Migration.self, from: result)
                var configuration = try Self.configuration(entry: entry, settings: migrated.settings, filters: migrated.filters, state: migrated.state)
                configuration.snapshot = LiveFolderPluginSnapshot(items: store.tabs(under: folder.id).compactMap { item in
                    guard let tab = item.tab, let url = tab.liveItemURL else { return nil }
                    return LiveFolderPluginItem(id: url, url: url, title: item.displayTitle, subtitle: tab.liveSubtitle,
                                                group: live.repository(for: url), createdAt: item.createdAt)
                })
                try await updateSignIn(&configuration, entry: entry)
                guard store.item(folder.id)?.liveFolder == live else { continue }
                store.updateLiveFolder(folder.id) { $0.plugin = configuration }
            } catch { diagnostics[folder.id] = error.localizedDescription }
        }
    }

    static func configuration(entry: LiveFolderPluginStore.Entry, settings: [String: String], filters: [String],
                              state: [String: String] = [:]) throws -> LiveFolderPluginConfiguration {
        var origins = entry.package.manifest.sessionOrigins
        if let key = entry.package.manifest.sessionSetting {
            guard let value = settings[key], var url = URLComponents(string: value), url.user == nil, url.password == nil else {
                throw LiveFolderPluginError.invalidManifest("Missing session address")
            }
            url.path = ""; url.query = nil; url.fragment = nil
            guard let origin = url.string else { throw LiveFolderPluginError.invalidManifest("Invalid session address") }
            _ = try LiveFolderSessionOrigin(origin)
            origins.append(origin)
        }
        return LiveFolderPluginConfiguration(id: entry.package.manifest.id, settings: settings, filters: filters,
                                             state: state, sessionOrigins: origins)
    }

    func updateSignIn(_ configuration: inout LiveFolderPluginConfiguration, entry: LiveFolderPluginStore.Entry) async throws {
        struct SignIn: Decodable {
            var title: String; var url: String; var warning: String
            var emptyText: String?; var failureText: String?; var failureURL: String?
            var instanceLabel: String?; var detailLabel: String?
        }
        let data = try await LiveFolderPluginStore.shared.invoke(entry.package, method: "signIn", input: JSONEncoder().encode(configuration), origins: [], profile: nil)
        let result = try JSONDecoder().decode(SignIn.self, from: data)
        try LiveFolderPluginItem(id: result.title, url: result.url, title: result.title).validate()
        if let url = result.failureURL { try LiveFolderPluginItem(id: "failure", url: url, title: "failure").validate() }
        configuration.signIn = .init(title: result.title, url: result.url)
        configuration.signInWarning = result.warning
        configuration.emptyText = result.emptyText
        configuration.failureText = result.failureText
        configuration.failureURL = result.failureURL
        configuration.instanceLabel = result.instanceLabel
        configuration.detailLabel = result.detailLabel
    }

    func refresh(_ id: UUID, force: Bool = false) {
        if store?.item(id)?.liveFolder?.plugin == nil, LiveFolderPluginStore.shared.loaded {
            Task {
                await migrateFolders()
                if store?.item(id)?.liveFolder?.plugin != nil { refresh(id, force: force) }
            }
            return
        }
        guard let store, let live = store.item(id)?.liveFolder, let configuration = live.plugin,
              LiveFolderPluginStore.shared.isEnabled(configuration.id),
              let entry = LiveFolderPluginStore.shared.entries[configuration.id], let context = store.liveRequestContext(id) else { return }
        if refreshing.contains(id) { if force { pendingRefresh.insert(id) }; return }
        if !force, let last = live.lastFetch, store.clock.now.timeIntervalSince(last) < Self.minimumInterval, live.lastError == nil { return }
        refreshing.insert(id)
        let profile = store.profilePath(item: id)
        Task {
            defer {
                refreshing.remove(id)
                if pendingRefresh.remove(id) != nil { refresh(id, force: true) }
            }
            do {
                var metadata = configuration
                try await updateSignIn(&metadata, entry: entry)
                guard acceptsResponse(id, context: context) else { return }
                store.updateLiveFolder(id) { current in
                    current.plugin?.signIn = metadata.signIn
                    current.plugin?.signInWarning = metadata.signInWarning
                    current.plugin?.emptyText = metadata.emptyText
                    current.plugin?.failureText = metadata.failureText
                    current.plugin?.failureURL = metadata.failureURL
                    current.plugin?.instanceLabel = metadata.instanceLabel
                    current.plugin?.detailLabel = metadata.detailLabel
                }
                var input = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as! [String: Any]
                input["groups"] = store.liveRepositories(id)
                let data = try await LiveFolderPluginStore.shared.invoke(entry.package, method: "refresh",
                    input: JSONSerialization.data(withJSONObject: input),
                    origins: configuration.sessionOrigins.map { try LiveFolderSessionOrigin($0) }, profile: profile,
                    isCurrent: { store.liveRequestContext(id) == context })
                guard acceptsResponse(id, context: context) else { return }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let snapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: data)
                try snapshot.validate()
                repositories[id] = store.liveRepositories(id, fetched: snapshot.items.compactMap(\.group))
                diagnostics[id] = nil
                store.applyPluginResults(snapshot, to: id, context: context)
            } catch {
                guard acceptsResponse(id, context: context) else { return }
                diagnostics[id] = error.localizedDescription
                let code = error.localizedDescription.replacingOccurrences(of: "Error: ", with: "")
                store.applyLiveFailure(LiveFolderError(rawValue: code) ?? .unexpectedPage, to: id, context: context)
                if case LiveFolderPluginError.pluginFailed(_, let state) = error, !state.isEmpty, state != configuration.state {
                    var updated = configuration
                    updated.state = state
                    do {
                        try await updateSignIn(&updated, entry: entry)
                        guard store.liveRequestContext(id) == context else { return }
                        store.updateLiveFolder(id) { $0.plugin?.state = state; $0.plugin?.signIn = updated.signIn }
                    } catch { diagnostics[id] = error.localizedDescription }
                }
            }
        }
    }

    private func acceptsResponse(_ id: UUID, context: SidebarStore.LiveRequestContext) -> Bool {
        guard let current = store?.liveRequestContext(id) else { return false }
        if let plugin = current.plugin, !LiveFolderPluginStore.shared.isEnabled(plugin.id) || LiveFolderPluginStore.shared.entries[plugin.id] == nil { return false }
        guard current == context else { pendingRefresh.insert(id); return false }
        return true
    }

    func pageChanged(tab: UUID, to url: String) {
        let previous = lastURL[tab]
        lastURL[tab] = url
        if lastURL.count > 500 { lastURL = [tab: url] }
        guard previous != url, let store else { return }
        struct Change: Decodable { var state: [String: String]; var refreshAfter: [Double]; var checkSignIn: Bool }
        for folder in store.liveFolders {
            guard let live = folder.liveFolder, var configuration = live.plugin,
                  let entry = LiveFolderPluginStore.shared.entries[configuration.id],
                  let context = store.liveRequestContext(folder.id),
                  store.profilePath(item: tab) == store.profilePath(item: folder.id) else { continue }
            let id = folder.id
            Task {
                do {
                    let input: [String: Any] = ["url": url, "previousURL": previous ?? "", "state": configuration.state, "settings": configuration.settings]
                    let data = try await LiveFolderPluginStore.shared.invoke(entry.package, method: "pageChanged",
                        input: JSONSerialization.data(withJSONObject: input), origins: [], profile: nil)
                    let change = try JSONDecoder().decode(Change.self, from: data)
                    guard store.liveRequestContext(id) == context else { return }
                    if configuration.state != change.state {
                        configuration.state = change.state
                        try await updateSignIn(&configuration, entry: entry)
                        guard store.liveRequestContext(id) == context else { return }
                        store.updateLiveFolder(id) { $0.plugin?.state = configuration.state; $0.plugin?.signIn = configuration.signIn }
                    }
                    var delays = change.refreshAfter.filter { $0.isFinite && $0 >= 0 && $0 <= 300 }.prefix(5).map { $0 }
                    if change.checkSignIn && Self.needsSignIn(live) { delays.append(2) }
                    for delay in delays {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.refresh(id, force: true) }
                    }
                } catch { diagnostics[id] = error.localizedDescription }
            }
        }
    }
}
