import AppKit
import CraCEF
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Arc Max's Instant Links (#407) on the Mac's own Apple Intelligence model: Shift-Return on a
/// search in ⌘T turns the typed phrase into a plan (CraCore InstantLinks), searches Google in a
/// page nobody sees and opens the top results as tabs, a split or a folder. The sidebar shows a row
/// at the top of Today meanwhile. Only the queries leave the Mac, to the search engine.
@MainActor @Observable
final class InstantLinksService {
    static let shared = InstantLinksService()
    private init() {}

    /// A row at the top of a space's Today: "Searching the web for you…", or the error.
    struct Pending: Equatable, Identifiable {
        let id: UUID
        let space: UUID
        var failed = false
        /// The run started from ⌘T's new-tab bar: Arc draws the row as the open one, as it does the New Tab row.
        var current = false
    }

    /// The rows now showing, newest first. Transient: never saved.
    private(set) var pending: [Pending] = []

    func pending(in space: UUID) -> [Pending] { pending.filter { $0.space == space } }

    /// What the window offers a run: its id, and how to start a page that isn't selected.
    struct Host {
        var windowID: UUID?
        var load: (UUID) -> Void
    }

    // MARK: Test hooks

    /// A URL template with `{searchTerms}` (scenarios). While set, every search loads it in the hidden
    /// page and reads the results with Google's script, as if it were Google.
    static let searchTemplate = ProcessInfo.processInfo.environment["CRA_INSTANT_LINKS_SEARCH"].flatMap { $0.contains("{searchTerms}") ? $0 : nil }

    /// CRA_INSTANT_LINKS_MODEL_FAIL=1 makes the test model throw, so the plain plan runs instead.
    /// `cra://debug?instantLinksFail=none|plan|model` changes it while Cra runs.
    static var modelFailsOnPurpose = ProcessInfo.processInfo.environment["CRA_INSTANT_LINKS_MODEL_FAIL"] == "1"

    /// CRA_INSTANT_LINKS_FAIL=1 makes the model and the fallback both give no plan, so the row shows
    /// its error. Changed by the same `cra://debug` key.
    static var failsOnPurpose = ProcessInfo.processInfo.environment["CRA_INSTANT_LINKS_FAIL"] == "1"

    /// Settings ▸ Max ▸ Instant Links is on, and Apple Intelligence can answer.
    func isAvailable(_ store: SidebarStore) -> Bool {
        store.settings.instantLinks && (TidyTabsService.fakeModel || TidyTabsService.shared.modelAvailable)
    }

    // MARK: Run

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var watchdogs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private weak var storeInUse: SidebarStore?

    /// What the last run did, for `cra://debug?instantLinks=`.
    @ObservationIgnored private var lastPlan: InstantLinks.Plan?
    @ObservationIgnored private var lastOpenings: [InstantLinks.Search] = []
    @ObservationIgnored private var lastOpened: Int?
    @ObservationIgnored private var lastFellBack = false

    /// The model's first answer after launch took 7.7 s, a warm one 2.1: the bar opening loads it. The
    /// session is kept until the next run uses it.
    func prewarm(_ store: SidebarStore) {
        guard isAvailable(store), !TidyTabsService.fakeModel else { return }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), warmSession == nil {
            let session = LanguageModelSession(instructions: InstantLinks.instructions)
            session.prewarm()
            warmSession = session
        }
        #endif
    }

    @ObservationIgnored private var warmSession: Any?

    /// Shift-Return on `phrase`: the row appears, the plan is made, the searches run, the results open
    /// in `space` and the row goes. `engine` is the one the bar searched with.
    func run(phrase: String, space: UUID, engine: ChromiumSearchEngine, store: SidebarStore, host: Host, asNewTab: Bool = false) {
        // Only the newest row is drawn as the open one.
        for i in pending.indices { pending[i].current = false }
        let row = Pending(id: UUID(), space: space, current: asNewTab)
        pending.insert(row, at: 0)
        let selectedAtStart = store.selectedTabID(in: space, window: host.windowID)
        storeInUse = store
        lastPlan = nil
        lastOpenings = []
        lastOpened = nil
        lastFellBack = false
        let started = Date()
        tasks[row.id] = Task { [weak self] in
            await self?.perform(row.id, phrase: phrase, space: space, engine: engine, store: store, host: host, selectedAtStart: selectedAtStart, started: started)
        }
        // A model or a page that never answers must not leave the row spinning for good.
        watchdogs[row.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, let self, self.tasks[row.id] != nil else { return }
            self.tasks[row.id]?.cancel()
            CraLog.note("Instant Links: gave up after 75 s")
            self.fail(row.id)
        }
    }

    /// The error row's ✕.
    func dismiss(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        watchdogs.removeValue(forKey: id)?.cancel()
        pending.removeAll { $0.id == id }
    }

    /// The run is over, however it ended: its watchdog has nothing left to watch.
    private func endRun(_ id: UUID) {
        tasks[id] = nil
        watchdogs.removeValue(forKey: id)?.cancel()
    }

    private func fail(_ id: UUID) {
        endRun(id)
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].failed = true
    }

    private func perform(_ id: UUID, phrase: String, space: UUID, engine: ChromiumSearchEngine, store: SidebarStore, host: Host, selectedAtStart: UUID?, started: Date) async {
        guard let plan = await makePlan(for: phrase, store: store) else {
            CraLog.note("Instant Links: no plan after \(Self.seconds(since: started)) s")
            if !Task.isCancelled { fail(id) }
            return
        }
        let openings = InstantLinks.openings(for: plan)
        guard !openings.isEmpty, !Task.isCancelled else { fail(id); return }
        lastPlan = plan
        lastOpenings = openings
        let planned = Date()

        let incognito = store.isIncognito(space: space)
        let profile = store.profilePath(space: space)
        var found = [[URL]](repeating: [], count: openings.count)
        await withTaskGroup(of: (Int, [URL]).self) { group in
            for (i, search) in openings.enumerated() {
                group.addTask { @MainActor in
                    (i, await Self.links(for: search, engine: engine, profilePath: profile, incognito: incognito))
                }
            }
            for await (i, urls) in group { found[i] = urls }
        }
        guard !Task.isCancelled else { return }
        // createTab falls back to the focused space when this one is gone: the results would land elsewhere.
        guard store.space(space) != nil else {
            CraLog.note("Instant Links: the space was closed before the results came; opened nothing")
            pending.removeAll { $0.id == id }
            endRun(id)
            return
        }

        var seen = Set<String>()
        let urls = found.flatMap { $0 }.filter { seen.insert($0.absoluteString).inserted }
        guard !urls.isEmpty else { fail(id); return }
        // A late result must not take the window from a tab the user has gone to since.
        let takesSelection = pending.first { $0.id == id }?.current == true
            || store.selectedTabID(in: space, window: host.windowID) == selectedAtStart
        pending.removeAll { $0.id == id }
        endRun(id)
        lastOpened = Self.open(urls, as: plan.format, title: plan.title, space: space, store: store, host: host, select: takesSelection)
        CraLog.note("Instant Links: \(plan.format.rawValue) of \(lastOpened ?? 0) pages from \(openings.count) searches "
                    + "(counts \(openings.map { String($0.count) }.joined(separator: ","))), plan \(Self.seconds(since: started, to: planned)) s, "
                    + "search \(Self.seconds(since: planned)) s")
    }

    private static func seconds(since a: Date, to b: Date = Date()) -> String { String(format: "%.1f", b.timeIntervalSince(a)) }

    // MARK: The plan

    /// The model's plan for what was typed, after CraCore's rules; nil when it can't answer.
    private func makePlan(for phrase: String, store: SidebarStore) async -> InstantLinks.Plan? {
        // CRA_INSTANT_LINKS_FAIL=1 fails the model and the fallback alike, so the error row stays testable.
        if Self.failsOnPurpose {
            if TidyTabsService.fakeModel { try? await Task.sleep(for: .seconds(1.6)) }
            return nil
        }
        if TidyTabsService.fakeModel {
            try? await Task.sleep(for: .seconds(1.6))
            if Self.modelFailsOnPurpose { return fallbackPlan(for: phrase, failure: "test") }
            return InstantLinks.plainPlan(for: phrase)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = (warmSession as? LanguageModelSession) ?? LanguageModelSession(instructions: InstantLinks.instructions)
            warmSession = nil
            do {
                let answer = try await session.respond(to: phrase, generating: InstantLinksAnswer.self,
                                                       options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 300))
                let a = answer.content
                let format: InstantLinks.Format = switch a.format {
                case .tab: .tab
                case .folder: .folder
                case .split: .split
                }
                let searches = a.searches.map { InstantLinks.Search(query: $0.query, count: $0.count) }
                return InstantLinks.plan(title: a.title, format: format, searches: searches, phrase: phrase)
            } catch {
                if Task.isCancelled { return nil }
                // Whatever the model throws (a guardrail's false positive, the context window, an unsupported
                // language, no model), the phrase is searched as it stands. Only the kind is logged.
                return fallbackPlan(for: phrase, failure: Self.failureKind(error))
            }
        }
        #endif
        return nil
    }

    /// The plan without the model; the phrase as one search (CraCore InstantLinks.plainPlan).
    private func fallbackPlan(for phrase: String, failure: String) -> InstantLinks.Plan {
        CraLog.note("Instant Links: the model failed (\(failure)); searching the phrase as typed")
        lastFellBack = true
        return InstantLinks.plainPlan(for: phrase)
    }

    private static func failureKind(_ error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let e = error as? LanguageModelSession.GenerationError {
            return switch e {
            case .guardrailViolation: "guardrail"
            case .exceededContextWindowSize: "context window"
            case .unsupportedLanguageOrLocale: "language"
            case .assetsUnavailable: "unavailable"
            case .rateLimited: "rate limited"
            case .concurrentRequests: "busy"
            case .decodingFailure: "decoding"
            case .unsupportedGuide: "guide"
            case .refusal: "refusal"
            @unknown default: "other"
            }
        }
        #endif
        return "other"
    }

    // MARK: The searches

    /// The pages one search opens: Google's top results read from a hidden page. When Google's page
    /// can't be read (a captcha, `/sorry`, nothing in time) Google's results page opens, one tab
    /// whatever the count. When the engine isn't Google (Arc reads Google's only) or the space is
    /// incognito, the engine's own results page opens, one per search whatever the count.
    private static func links(for search: InstantLinks.Search, engine: ChromiumSearchEngine, profilePath: String?, incognito: Bool) async -> [URL] {
        let enginePage = URL(string: engine.searchURL(search.query))
        if let template = searchTemplate {
            let encoded = search.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search.query
            let url = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
            let read = await readResults(of: url, limit: search.count, profilePath: profilePath)
            return read.isEmpty ? [InstantLinks.googleURL(for: search.query)] : read
        }
        guard !incognito, InstantLinks.readsResults(of: engine) else { return enginePage.map { [$0] } ?? [] }
        let read = await readResults(of: InstantLinks.googleURL(for: search.query).absoluteString, limit: search.count, profilePath: profilePath)
        return read.isEmpty ? [InstantLinks.googleURL(for: search.query)] : read
    }

    private static func readResults(of url: String, limit: Int, profilePath: String?) async -> [URL] {
        let started = Date()
        let json = await InstantLinksPage.evaluate(InstantLinks.resultsScript(limit: limit), at: url, profilePath: profilePath, timeout: 10)
        let results = json.map { InstantLinks.results(fromJSON: $0, limit: limit) } ?? InstantLinks.Results(links: [], blocked: false)
        CraLog.note("Instant Links: a search read \(results.links.count) links in \(seconds(since: started)) s"
                    + (results.blocked ? " (blocked)" : json == nil ? " (no answer)" : ""))
        return results.links
    }

    // MARK: Opening

    /// The results in `space`, in result order from the top of Today; the first is selected when `select`
    /// and the window still shows that space. Returns how many tabs were opened.
    private static func open(_ urls: [URL], as format: InstantLinks.Format, title: String, space: UUID, store: SidebarStore, host: Host, select: Bool) -> Int {
        var ids: [UUID] = []
        for (i, url) in urls.enumerated() {
            let tab = store.createTab(url: url.absoluteString, in: space, select: false, index: i, window: host.windowID)
            store.markUnread(tab.id, false)
            ids.append(tab.id)
        }
        var first = ids[0]
        switch format {
        case .split where ids.count > 1:
            if let split = store.createSplit(with: ids, at: ids[0]) { first = store.paneID(for: ids[0], in: split) ?? ids[0] }
        case .folder where !store.isBlank(space: space):
            if let pinned = store.space(space)?.pinnedContainerID {
                let folder = store.createFolder(named: title, in: pinned)
                store.moveItems(ids, to: folder.id, index: nil)
            }
        default:
            break
        }
        let shown = select && store.focusedSpaceID(window: host.windowID) == space
        if shown { store.selectTab(first, window: host.windowID) }
        for id in ids where !(shown && id == first) { host.load(id) }
        return ids.count
    }

    // MARK: Debug

    /// `cra://debug?instantLinks=<label>`.
    func readout(_ label: String, store: SidebarStore, space: UUID) -> String {
        let rows = pending(in: space)
        let status = rows.isEmpty ? "-" : rows.contains { !$0.failed } ? "loading" : "error"
        let plan = lastPlan.map { "\($0.format.rawValue)/\($0.searches.count)/" + (lastOpenings.isEmpty ? "-" : lastOpenings.map { String($0.count) }.joined(separator: ",")) } ?? "-"
        let sp = store.space(space)
        let selected = store.selectedTabID(in: sp?.id ?? UUID(), window: nil)
        return "instant links \(label): available=\(isAvailable(store)) rows=\(rows.count) status=\(status) current=\(rows.contains { $0.current } ? 1 : 0) "
            + "plan=\(plan) opened=\(lastOpened.map(String.init) ?? "-") fellback=\(lastFellBack ? 1 : 0) "
            + "today=[\(sp.map { layout(of: $0.todayContainerID, store: store, selected: selected) } ?? "")] "
            + "pinned=[\(sp.map { layout(of: $0.pinnedContainerID, store: store, selected: selected) } ?? "")]"
    }

    /// A container's items in order, a page as its result number (the fixture's `result=N`, "x" for any
    /// other), a split as `a+b`, a folder as `"title"{…}`; the selected tab has a `*`.
    private func layout(of id: UUID, store: SidebarStore, selected: UUID?) -> String {
        store.children(of: id).map { item -> String in
            if let tab = item.tab { return Self.token(tab.url) + (item.id == selected ? "*" : "") }
            if item.isSplit { return store.children(of: item.id).map { Self.token($0.tab?.url ?? "") + ($0.id == selected ? "*" : "") }.joined(separator: "+") }
            if item.isFolder { return "\"\(item.title ?? "")\"{" + layout(of: item.id, store: store, selected: selected) + "}" }
            return "?"
        }.joined(separator: ",")
    }

    private static func token(_ url: String) -> String {
        URLComponents(string: url)?.queryItems?.first { $0.name == "result" }?.value ?? "x"
    }

    /// `cra://debug?instantLinksDismiss=1`: the error row's ✕ (Cra ignores synthetic clicks).
    func dismissFailed() {
        for row in pending where row.failed { dismiss(row.id) }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
enum InstantLinksFormat {
    case tab, folder, split
}

@available(macOS 26.0, *)
@Generable
struct InstantLinksAnswer {
    @Guide(description: "A short name for the results, in Title Case")
    var title: String
    @Guide(description: "split only if asked for a split or left and right, folder only if asked for a folder, otherwise tab")
    var format: InstantLinksFormat
    @Guide(description: "The Google searches; usually one", .maximumCount(4))
    var searches: [InstantLinksSearch]
}

@available(macOS 26.0, *)
@Generable
struct InstantLinksSearch {
    @Guide(description: "The search words, short, in the user's language")
    var query: String
    @Guide(description: "How many results to open: the number the user asks for, otherwise 1", .range(1...10))
    var count: Int
}
#endif

/// A windowless page (as MCP's agent pages and the easel's live cards): loads `url` in the space's
/// profile, runs `script` once it has committed and answers with the string the script returns.
/// Closed afterwards; nil when the page never loads, the script fails or `timeout` passes.
@MainActor
final class InstantLinksPage {
    private var browser: CraBrowser?
    private var timer: Timer?
    private var done: ((String?) -> Void)?

    private var cancelled = false

    /// Cancelling the task (the ✕, the watchdog) answers nil and closes the page at once.
    static func evaluate(_ script: String, at url: String, profilePath: String?, timeout: TimeInterval) async -> String? {
        let page = InstantLinksPage()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
                page.start(script, url: url, profilePath: profilePath, timeout: timeout) { value in
                    page.close()
                    c.resume(returning: value)
                }
            }
        } onCancel: {
            Task { @MainActor in page.cancel() }
        }
    }

    private func cancel() {
        cancelled = true
        finish(nil)
    }

    private func start(_ script: String, url: String, profilePath: String?, timeout: TimeInterval, done: @escaping (String?) -> Void) {
        if cancelled { done(nil); return }
        self.done = done
        let b = CraBrowser(agentURL: url, profilePath: profilePath)
        b.setAudioMuted(true)
        browser = b
        let started = Date()
        var inFlight = false
        var retryAfter = Date.distantPast
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let b = self.browser else { return }
                if Date().timeIntervalSince(started) > timeout { self.finish(nil); return }
                // Wait for the load to finish: Google's page reloads itself (adding &sei=) right after the
                // first commit, and an evaluation started before that loses its page and never answers.
                guard !inFlight, Date() >= retryAfter, b.isCreated, b.hasCommittedLoad, !b.isLoading else { return }
                inFlight = true
                let body = try? JSONSerialization.data(withJSONObject: ["expression": script, "awaitPromise": true, "returnByValue": true])
                b.sendDevToolsMethod("Runtime.evaluate", params: body.flatMap { String(data: $0, encoding: .utf8) } ?? "{}") { result, _ in
                    let value = result.flatMap { r -> String? in
                        guard let json = try? JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any], json["exceptionDetails"] == nil else { return nil }
                        return (json["result"] as? [String: Any])?["value"] as? String
                    }
                    DispatchQueue.main.async {
                        // No answer (the page navigated under the script): try again while there's time.
                        if let value { self.finish(value) } else { inFlight = false; retryAfter = Date().addingTimeInterval(0.3) }
                    }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func finish(_ value: String?) {
        timer?.invalidate()
        timer = nil
        let d = done
        done = nil
        d?(value)
    }

    private func close() {
        timer?.invalidate()
        timer = nil
        browser?.close()
        browser = nil
    }
}
