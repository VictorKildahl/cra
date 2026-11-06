import AppKit
import CraCEF
import Observation

/// Keeps live folders current on Dia's schedule (its LiveFolderRefreshTrigger: periodicRefresh,
/// windowFocus, manualRefresh, configChanged, externalTrigger): every two minutes while a Cra window
/// is active, when a window takes focus, when the user asks, and right after a pull request is
/// created or reviewed in a tab. See docs/live-folders.md, "Dia's refresh timing".
@MainActor
@Observable
final class LiveFolderManager {
    static let shared = LiveFolderManager()
    @ObservationIgnored private weak var store: SidebarStore?
    /// Folders with a refresh in flight; their refresh button spins.
    private(set) var refreshing: Set<UUID> = []
    /// Repositories in each folder's last results plus the hidden ones: the folder menu's list
    /// (Arc: "This list is generated based on your currently active pull requests.").
    private(set) var repositories: [UUID: [String]] = [:]
    @ObservationIgnored private var timer: ScheduledWork?
    /// The last address each tab reported, to tell what a page came from.
    @ObservationIgnored private var lastURL: [UUID: String] = [:]

    /// Dia's github-live-folder-min-refresh-interval-seconds (120 in its flag cache, 27 Oct 2026).
    nonisolated static let refreshInterval: TimeInterval = 120
    /// Dia's github-live-folder-post-merge/-post-review-retention-seconds (120 each): a pull request
    /// that left the results stays this long before its tab goes.
    nonisolated static let retention: TimeInterval = 120
    /// After a pull request is created or reviewed, refreshes this long after (GitHub's search
    /// catches up within seconds, sometimes later).
    static let triggerDelays: [TimeInterval] = [5, 45]
    /// Arc's requestedTooSoon: clicks on refresh closer together than this do nothing.
    static let minimumInterval: TimeInterval = 10
    /// A folder that failed or waits for a sign-in tries again this often (a Mac waking up has no
    /// network for a moment; an SSO session renews as soon as a GitHub page is opened).
    nonisolated static let retryInterval: TimeInterval = 30
    /// A GitHub page loaded while a folder waits for a sign-in: refresh once the page has settled.
    @ObservationIgnored private var signInCheck: DispatchWorkItem?
    /// CRA_LIVE_FOLDER_DEBUG=1 writes every GitHub response to <data dir>/live-folder-debug/.
    private static let debug = ProcessInfo.processInfo.environment["CRA_LIVE_FOLDER_DEBUG"] == "1"

    func start(store: SidebarStore) {
        self.store = store
        timer = store.clock.every(15) { [weak self] in
            self?.store?.expireLiveItems(olderThan: Self.retention)
            self?.refreshStale()
        }
        // Dia's windowFocus trigger. App activation makes a window key too.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshStale() }
        }
        // Chromium's profiles load first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refreshStale() }
    }

    /// Dia waits for an active window (LiveDataRefreshSkipReason.waitingForActiveWindow): nothing
    /// is fetched while Cra is in the background.
    func refreshStale(olderThan age: TimeInterval = refreshInterval) {
        guard NSApp.isActive, let store else { return }
        for f in store.liveFolders {
            let last = f.liveFolder?.lastFetch ?? .distantPast
            let failing = f.liveFolder.map { $0.lastError != nil || Self.needsSignIn($0) } ?? false
            if store.clock.now.timeIntervalSince(last) >= (failing ? min(age, Self.retryInterval) : age) { refresh(f.id) }
        }
    }

    /// GitHub asked for a sign-in: to github.com, or SSO for an organization whose pull requests it held back.
    nonisolated static func needsSignIn(_ live: LiveFolderData) -> Bool {
        live.lastError == .notSignedIn || (live.lastError == nil && !live.ssoOrganizations.isEmpty)
    }

    /// `force` skips the gap between refreshes: the folder's filters just changed.
    func refresh(_ id: UUID, force: Bool = false) {
        guard let store, let live = store.item(id)?.liveFolder, !refreshing.contains(id) else { return }
        if !force, let last = live.lastFetch, store.clock.now.timeIntervalSince(last) < Self.minimumInterval, live.lastError == nil { return }
        let attributes: [GitHubLiveFilter.Attributes] = [.authored, .reviewRequests, .teamReviewRequests]
            .filter { live.filter.attributes.contains($0) }
        refreshing.insert(id)
        let profile = store.profilePath(item: id)
        Task { @MainActor in
            var pages: [(GitHubLiveFilter.Attributes, GitHubLiveClient.Page)] = []
            var failure: GitHubLiveClient.Failure?
            for a in attributes {
                switch await fetch(GitHubLiveClient.query(for: a), profile: profile, label: "\(a.rawValue)") {
                case .success(let page): pages.append((a, page))
                case .failure(let f): failure = failure == .notSignedIn ? failure : f
                }
            }
            refreshing.remove(id)
            guard let store = self.store, store.item(id)?.isLiveFolder == true else { return }
            // A partial update would empty the folder of whatever the failed search found.
            if let failure {
                store.applyLiveFailure(failure.asLiveFolderError, to: id)
                return
            }
            let prs = Self.merge(pages)
            let hidden = store.item(id)?.liveFolder?.filter.hiddenRepositories ?? []
            repositories[id] = Array(Set(prs.map(\.repository) + hidden)).sorted { $0.lowercased() < $1.lowercased() }
            let sso = Array(Set(pages.flatMap { $0.1.ssoOrganizations })).sorted()
            store.applyLiveResults(prs, to: id, ssoOrganizations: sso)
        }
    }

    /// A page in a tab moved (BrowserManager). Creating a pull request (compare page → pull page)
    /// and submitting a review (#pullrequestreview- anchor) refresh the folders straight away, like
    /// Dia's edit/review creation triggers; the next refresh moves a new pull request's tab into the folder.
    func pageChanged(tab: UUID, to url: String) {
        let old = lastURL[tab]
        lastURL[tab] = url
        if lastURL.count > 500 { lastURL = [tab: url] }
        guard old != url, let store, !store.liveFolders.isEmpty else { return }
        let folders = store.liveFolders
        guard let page = URL(string: url), page.host == "github.com" else { return }
        learnEnterprise(from: url)
        if folders.contains(where: { $0.liveFolder.map(Self.needsSignIn) ?? false }) { checkSignIn() }
        guard let pr = GitHubLiveClient.pullPath(url) else { return }
        let oldPath = old.flatMap { URL(string: $0)?.path } ?? ""
        let created = oldPath.hasPrefix("/\(pr.owner)/\(pr.repo)/compare")
        let reviewed = url.contains("#pullrequestreview-") && !(old ?? "").contains("#pullrequestreview-")
        guard created || reviewed else { return }
        for delay in Self.triggerDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                for f in self?.store?.liveFolders ?? [] { self?.refresh(f.id, force: true) }
            }
        }
    }

    /// GitHub sends a signed-out Enterprise Managed User to /enterprises/<slug>/sso (JYSK, 29 Oct
    /// 2026), a tab and the folder's own requests alike: the folder's sign-in goes there too.
    private func learnEnterprise(from url: String) {
        guard let slug = GitHubLiveClient.enterprise(inSSO: url), let store else { return }
        for f in store.liveFolders where f.liveFolder?.enterprise != slug { store.updateLiveFolder(f.id) { $0.enterprise = slug } }
    }

    /// Signing in ends on a GitHub page, and so does an SSO session that renews by itself (an
    /// identity provider that signs in without asking, like JYSK's ADFS): the folder tries again a
    /// moment after GitHub pages stop loading, instead of waiting for the next retry.
    private func checkSignIn() {
        signInCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let store = self?.store else { return }
            for f in store.liveFolders where f.liveFolder.map(Self.needsSignIn) ?? false {
                let last = f.liveFolder?.lastFetch ?? .distantPast
                if store.clock.now.timeIntervalSince(last) >= Self.minimumInterval { self?.refresh(f.id, force: true) }
            }
        }
        signInCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// One search: the pulls page first (what Arc and Dia read), then GitHub's search page
    /// when that comes back with nothing it can read.
    private func fetch(_ query: String, profile: String?, label: String) async -> Result<GitHubLiveClient.Page, GitHubLiveClient.Failure> {
        let pulls = await get(GitHubLiveClient.pullsURL(query: query), profile: profile, label: "pulls-\(label)")
        if case .success(let page) = pulls, !page.pullRequests.isEmpty { return pulls }
        if case .failure(let f) = pulls, f != .unexpectedPage { return pulls }
        let search = await get(GitHubLiveClient.searchURL(query: query), profile: profile, label: "search-\(label)")
        if case .success = search { return search }
        return pulls
    }

    private func get(_ url: String, profile: String?, label: String) async -> Result<GitHubLiveClient.Page, GitHubLiveClient.Failure> {
        await withCheckedContinuation { continuation in
            CraCEFRuntime.fetchURL(url, headers: GitHubLiveClient.jsonHeaders, profilePath: profile) { [weak self] status, finalURL, mime, body in
                if Self.debug { Self.dump(label: label, url: url, status: status, finalURL: finalURL, mime: mime, body: body) }
                MainActor.assumeIsolated { self?.learnEnterprise(from: finalURL) }
                continuation.resume(returning: GitHubLiveClient.read(status: status, finalURL: finalURL, body: body))
            }
        }
    }

    /// One list from the folder's searches: who made it and who's asked come from the search
    /// it was found by, and from the author when the page names the signed-in user.
    static func merge(_ pages: [(GitHubLiveFilter.Attributes, GitHubLiveClient.Page)]) -> [LivePullRequest] {
        let viewerLogin = pages.lazy.compactMap { $0.1.viewer }.first { !$0.isEmpty }
        let viewer = viewerLogin?.lowercased()
        var byURL: [String: LivePullRequest] = [:]
        var order: [String] = []
        for (attribute, page) in pages {
            for var pr in page.pullRequests {
                if attribute == .authored { pr.createdByMe = true } else { pr.isAwaitingMyReview = true }
                if let viewer, pr.author?.lowercased() == viewer { pr.createdByMe = true }
                // Your own pull requests are named after you even when the page leaves the author out.
                if pr.author == nil, attribute == .authored { pr.author = viewerLogin }
                if var seen = byURL[pr.url] {
                    seen.createdByMe = seen.createdByMe || pr.createdByMe
                    seen.isAwaitingMyReview = seen.isAwaitingMyReview || pr.isAwaitingMyReview
                    seen.author = seen.author ?? pr.author
                    seen.createdAt = seen.createdAt ?? pr.createdAt
                    seen.updatedAt = seen.updatedAt ?? pr.updatedAt
                    byURL[pr.url] = seen
                } else {
                    byURL[pr.url] = pr
                    order.append(pr.url)
                }
            }
        }
        // Newest first, like Arc's folder (its tabs carry the pull request's creation date).
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order.compactMap { byURL[$0] }.sorted {
            let a = $0.createdAt ?? $0.updatedAt, b = $1.createdAt ?? $1.updatedAt
            if let a, let b, a != b { return a > b }
            return rank[$0.url]! < rank[$1.url]!
        }
    }

    private static func dump(label: String, url: String, status: Int, finalURL: String, mime: String, body: String) {
        let dir = AppPaths.file("live-folder-debug")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "GET \(url)\nstatus \(status)\nfinal \(finalURL)\nmime \(mime)\n\n\(body)"
        let file = dir.appendingPathComponent("\(label).txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
