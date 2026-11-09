import AppKit
import Observation

/// Keeps live folders current on Dia's schedule (its LiveFolderRefreshTrigger: periodicRefresh,
/// windowFocus, manualRefresh, configChanged, externalTrigger): every two minutes while a Cra window
/// is active, when a window takes focus, when the user asks, and when a folder's plugin asks after a
/// page moved (GitHub: a pull request created or reviewed in a tab). The requests and their reading
/// are the plugins' (resources/live-folder-plugins, docs/live-folder-plugins.md); tabs, timing and
/// what a failure leaves in place are Cra's. See docs/live-folders.md, "Dia's refresh timing".
@MainActor
@Observable
final class LiveFolderManager {
    static let shared = LiveFolderManager()
    @ObservationIgnored private weak var store: SidebarStore?
    /// Folders with a refresh in flight; their refresh button spins.
    private(set) var refreshing: Set<UUID> = []
    /// Groups (repositories, projects) in each folder's last results plus the hidden ones: the folder
    /// menu's list (Arc: "This list is generated based on your currently active pull requests.").
    private(set) var repositories: [UUID: [String]] = [:]
    /// Why each folder's last plugin call failed, also written to cra.log (and so to Export Diagnostics).
    private(set) var diagnostics: [UUID: String] = [:]
    /// Folders whose filters, profile or server changed while a refresh was out: they refresh again
    /// once it's back (its answer is for the old settings and is dropped).
    @ObservationIgnored private var pendingRefresh: Set<UUID> = []
    @ObservationIgnored private var timer: ScheduledWork?
    /// The last address each tab reported, to tell what a page came from.
    @ObservationIgnored private var lastURL: [UUID: String] = [:]
    /// A page on a folder's service loaded while it waits for a sign-in: refresh once pages have settled.
    @ObservationIgnored private var signInChecks: [UUID: DispatchWorkItem] = [:]

    /// Dia's github-live-folder-min-refresh-interval-seconds (120 in its flag cache, 27 Oct 2026).
    nonisolated static let refreshInterval: TimeInterval = 120
    /// Dia's github-live-folder-post-merge/-post-review-retention-seconds (120 each): an item
    /// that left the results stays this long before its tab goes.
    nonisolated static let retention: TimeInterval = 120
    /// Arc's requestedTooSoon: clicks on refresh closer together than this do nothing.
    static let minimumInterval: TimeInterval = 10
    /// A folder that failed or waits for a sign-in tries again this often (a Mac waking up has no
    /// network for a moment; an SSO session renews as soon as a GitHub page is opened).
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
        // Dia's windowFocus trigger. App activation makes a window key too.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshStale() }
        }
        Task {
            await LiveFolderPluginStore.shared.reload()
            await migrateFolders()
            refreshStale()
        }
    }

    /// Dia waits for an active window (LiveDataRefreshSkipReason.waitingForActiveWindow): nothing
    /// is fetched while Cra is in the background.
    func refreshStale(olderThan age: TimeInterval = refreshInterval) {
        guard NSApp.isActive, LiveFolderPluginStore.shared.loaded, let store else { return }
        for folder in store.liveFolders {
            let last = folder.liveFolder?.lastFetch ?? .distantPast
            let failing = folder.liveFolder.map { $0.lastError != nil || Self.needsSignIn($0) } ?? false
            if store.clock.now.timeIntervalSince(last) >= (failing ? min(age, Self.retryInterval) : age) { refresh(folder.id) }
        }
    }

    /// The service asked for a sign-in, or the plugin's last answer holds some items back until one
    /// (GitHub: SSO for an organization).
    nonisolated static func needsSignIn(_ live: LiveFolderData) -> Bool {
        live.lastError == .notSignedIn || live.plugin?.snapshot?.warning != nil
    }

    private struct Migration: Decodable {
        var settings: [String: String]
        var filters: [String]
        var state: [String: String]
    }

    /// GitHub and GitLab folders saved before plugins become the bundled plugin's folders: the
    /// plugin turns the old filter bits and instance into its settings, and the tabs already in the
    /// folder seed its snapshot so nothing reloads or moves. Only bundled plugins may claim them.
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
            } catch { note(error, folder: folder.id) }
        }
    }

    /// A new folder's configuration: the plugin's own origins, plus the address its setup asked for.
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

    /// The plugin's sign-in action and the folder's instance-specific text, for its current settings and state.
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

    /// `force` skips the gap between refreshes: the folder's filters just changed.
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
                note(error, folder: id)
                let code = error.localizedDescription.replacingOccurrences(of: "Error: ", with: "")
                store.applyLiveFailure(LiveFolderError(rawValue: code) ?? .unexpectedPage, to: id, context: context)
                if case LiveFolderPluginError.pluginFailed(_, let state) = error, !state.isEmpty, state != configuration.state {
                    var updated = configuration
                    updated.state = state
                    do {
                        try await updateSignIn(&updated, entry: entry)
                        guard store.liveRequestContext(id) == context else { return }
                        store.updateLiveFolder(id) { $0.plugin?.state = state; $0.plugin?.signIn = updated.signIn }
                    } catch { note(error, folder: id) }
                }
            }
        }
    }

    private func note(_ error: Error, folder: UUID) {
        let message = error.localizedDescription
        diagnostics[folder] = message
        CraLog.note("live folder \(folder.uuidString.prefix(8)): \(message)")
    }

    private func acceptsResponse(_ id: UUID, context: SidebarStore.LiveRequestContext) -> Bool {
        guard let current = store?.liveRequestContext(id) else { return false }
        if let plugin = current.plugin, !LiveFolderPluginStore.shared.isEnabled(plugin.id) || LiveFolderPluginStore.shared.entries[plugin.id] == nil { return false }
        guard current == context else { pendingRefresh.insert(id); return false }
        return true
    }

    /// A page in a tab moved (BrowserManager). A folder's plugin hears about pages on its own session
    /// origins only, in the folder's profile: any other address would start a helper process per folder
    /// for nothing. GitHub's plugin refreshes after a pull request is created (compare page → pull page)
    /// or reviewed (#pullrequestreview- anchor), like Dia's edit/review creation triggers, and learns an
    /// enterprise's SSO from where a tab lands.
    func pageChanged(tab: UUID, to url: String) {
        let previous = lastURL[tab]
        lastURL[tab] = url
        if lastURL.count > 500 { lastURL = [tab: url] }
        guard previous != url, let store, !store.liveFolders.isEmpty else { return }
        let page = URL(string: url), before = previous.flatMap { URL(string: $0) }
        struct Change: Decodable { var state: [String: String]; var refreshAfter: [Double]; var checkSignIn: Bool }
        for folder in store.liveFolders {
            guard let live = folder.liveFolder, var configuration = live.plugin,
                  configuration.sessionOrigins.contains(where: { origin in
                      guard let origin = try? LiveFolderSessionOrigin(origin) else { return false }
                      return page.map(origin.permits) == true || before.map(origin.permits) == true
                  }),
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
                    for delay in change.refreshAfter.filter({ $0.isFinite && $0 >= 0 && $0 <= 300 }).prefix(5) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.refresh(id, force: true) }
                    }
                    if change.checkSignIn { checkSignIn(id) }
                } catch { note(error, folder: id) }
            }
        }
    }

    /// Signing in ends on the service's own pages, and so does an SSO session that renews by itself
    /// (an identity provider that signs in without asking, like JYSK's ADFS): a folder waiting for a
    /// sign-in tries again a moment after those pages stop loading, instead of waiting for the next retry.
    private func checkSignIn(_ id: UUID) {
        guard let live = store?.item(id)?.liveFolder, Self.needsSignIn(live) else { return }
        signInChecks[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let store = self.store else { return }
            self.signInChecks[id] = nil
            guard let live = store.item(id)?.liveFolder, Self.needsSignIn(live),
                  store.clock.now.timeIntervalSince(live.lastFetch ?? .distantPast) >= Self.minimumInterval else { return }
            self.refresh(id, force: true)
        }
        signInChecks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
