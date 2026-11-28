import CraCEF
import Foundation
import Observation

/// Settings ▸ Privacy ▸ Block lists (#507): lists added on top of the one Cra ships. Each is
/// fetched (or read, for a file), kept in the data folder's Blocklists folder and fetched again
/// once it's old (CustomBlocklist.isDue). The engine gets Cra's own list and every added list's
/// domains as one set. Each source can be switched independently.
@MainActor
@Observable
final class BlockLists {
    static let shared = BlockLists()

    /// Fetched copies, by address.
    private(set) var cached: [String: CachedBlocklist] = [:]
    /// Addresses being fetched now.
    private(set) var fetching: Set<String> = []
    /// Why the last fetch of an address failed; a good fetch clears it.
    private(set) var failures: [String: String] = [:]

    @ObservationIgnored private var addresses: [String] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loaded = false
    private(set) var networkFailure: String?
    /// The rules in use and how many lists they come from (Settings ▸ Privacy ▸ Block lists); nil until
    /// the first set is built, and while a selection over Chromium's limit leaves the previous one active.
    private(set) var inUse: (rules: Int, lists: Int)?
    /// Each built-in list's rules ("adaway", "anudeep"), switched on or not.
    private(set) var builtInCounts: [String: BlockListCount] = [:]
    @ObservationIgnored private var refreshTimer: ScheduledWork?
    @ObservationIgnored private var clock: Scheduler = LiveScheduler.shared
    /// What the engine was last given: each address with its fetch date.
    @ObservationIgnored private var publishedKey: [String]?
    /// Reads and writes the folder and builds the engine's set, one job at a time.
    @ObservationIgnored private let queue = DispatchQueue(label: "dk.kildahl.cra.blocklists", qos: .utility)

    /// A list bigger than this isn't a block list.
    private static let maxBytes = 64 << 20

    @ObservationIgnored var hidingChanged: (() -> Void)?
    @ObservationIgnored private var hiding = DesktopHidingRules(lines: [])
    /// The lists' procedural hiding (#845), by host; their scriptlets go to FilterPageScripts.
    @ObservationIgnored private var procedural = ProceduralTable()
    @ObservationIgnored private let styles = NSCache<NSString, NSString>()
    @ObservationIgnored private var personal = ""
    @ObservationIgnored private var bundledSources: [String] = []

    nonisolated(unsafe) private static var lastDomains: [String]? // only accessed on queue

    nonisolated(unsafe) private static var chromiumOwnsDomains = false // accessed on queue

    @ObservationIgnored private var pausedHosts: Set<String> = []

    /// The last accepted inputs survive a restart with an oversized pending selection.
    private struct AcceptedFilters: Codable {
        let domains: [String]
        let hiding: [String]
        let rules: [DesktopNetworkRules.Rule]
    }

    nonisolated private static var acceptedURL: URL {
        ChromiumFilterLists.directory.appendingPathComponent("accepted-filters.json")
    }

    func setPausedHosts(_ hosts: Set<String>) {
        guard hosts != pausedHosts else { return }
        pausedHosts = hosts
        if CraCEFRuntime.responds(to: NSSelectorFromString("setContentBlockingPausedHosts:")) {
            CraCEFRuntime.setContentBlockingPausedHosts(hosts.sorted())
        }
        hidingChanged?()
        publish()
    }

    func isPaused(url: String) -> Bool {
        guard let host = AppSettings.filterHost(url) else { return false }
        return pausedHosts.contains(host)
    }

    private init() {
        styles.totalCostLimit = 4 << 20
        styles.countLimit = 32
    }

    func setPersonal(_ text: String?) {
        let next = text ?? ""
        guard next != personal else { return }
        personal = next
        publish()
    }

    func style(for host: String) -> String {
        if pausedHosts.contains(host.lowercased()) { return "" }
        if let value = styles.object(forKey: host as NSString) { return value as String }
        let value = hiding.css(host: host)
        styles.setObject(value as NSString, forKey: host as NSString, cost: value.utf8.count)
        return value
    }

    /// The procedural selectors a page on `host` runs (#845): none while the site is paused.
    func procedural(for host: String) -> [String] {
        if pausedHosts.contains(host.lowercased()) { return [] }
        return procedural.selectors(for: host)
    }

    nonisolated static var folder: URL {
        let url = AppPaths.supportDir.appendingPathComponent("Blocklists", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cacheURL(_ address: String) -> URL {
        folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: address))
    }

    /// The bundled list (resources/blocklist), read once on `queue`.
    nonisolated(unsafe) private static var bundled: [String: [String]] = [:]

    /// `settings.customBlocklists` now. The first call (at launch) reads the kept copies, gives the
    /// engine its set and fetches what's old; later ones forget removed lists and fetch added ones.
    func set(addresses new: [String], clock: Scheduler) {
        guard started else {
            started = true
            self.clock = clock
            addresses = new
            queue.async {
                let kept = new.compactMap { address in
                    (try? String(contentsOf: Self.cacheURL(address), encoding: .utf8)).flatMap(CachedBlocklist.init(text:))
                }
                DispatchQueue.main.async { [self] in
                    loaded = true
                    for list in kept where addresses.contains(list.url) { cached[list.url] = list }
                    publish()
                    refreshDue(atLaunch: true)
                }
            }
            refreshTimer = clock.every(6 * 3600) { [weak self] in self?.refreshDue(atLaunch: false) }
            return
        }
        let (removed, added) = CustomBlocklist.changes(from: addresses, to: new)
        addresses = new
        for address in removed {
            cached[address] = nil
            failures[address] = nil
            queue.async { try? FileManager.default.removeItem(at: Self.cacheURL(address)) }
            CraLog.note("block list \(Self.logName(address)) removed")
        }
        publish()
        added.forEach { fetch($0) }
    }

    func setBundledSources(_ sources: [String]) {
        guard bundledSources != sources else { return }
        bundledSources = sources
        publish()
    }

    /// A fetched list's rules, as it applies on this engine; nil without a copy yet.
    func count(_ address: String) -> BlockListCount? {
        cached[address].map { BlockListCount($0, networkRules: ChromiumFilterLists.available) }
    }

    /// The person's own filters: what Cra reads in them.
    func personalCount(_ text: String?) -> BlockListCount {
        BlockListCount(DesktopHidingRules.read(text ?? "", address: "", fetched: .distantPast), networkRules: ChromiumFilterLists.available)
    }

    /// Fetches the lists that are old, or that have no copy yet.
    private func refreshDue(atLaunch: Bool) {
        CustomBlocklist.due(addresses, fetched: cached.filter { $0.value.hasNetworkSource }.mapValues(\.fetched), now: clock.now, atLaunch: atLaunch).forEach { fetch($0) }
    }

    /// Fetches (or reads) one list now. A failure keeps the copy it had.
    func fetch(_ address: String) {
        guard addresses.contains(address), !fetching.contains(address), let url = URL(string: address) else { return }
        fetching.insert(address)
        let fetchedAt = clock.now
        Task { [weak self] in
            let outcome = await Self.load(url)
            let result: Result<CachedBlocklist, BlockListError> = await Task.detached(priority: .utility) {
                outcome.flatMap { text in
                    let list = DesktopHidingRules.read(text, address: address, fetched: fetchedAt)
                    guard !list.domains.isEmpty || !list.hidingRules.isEmpty || !list.networkRules.isEmpty else { return .failure(.noDomains) }
                    return .success(list)
                }
            }.value
            self?.finish(address, result)
        }
    }

    private func finish(_ address: String, _ result: Result<CachedBlocklist, BlockListError>) {
        fetching.remove(address)
        guard addresses.contains(address) else { return }  // removed while it loaded
        switch result {
        case .success(let list):
            cached[address] = list
            failures[address] = nil
            let text = list.text
            queue.async { try? text.write(to: Self.cacheURL(address), atomically: true, encoding: .utf8) }
            publish()
        case .failure(let error):
            failures[address] = error.message
            CraLog.note("block list \(Self.logName(address)) not fetched: \(error.message)")
        }
    }

    /// Gives the engine Cra's list with every added one, when that changed.
    private func publish() {
        guard loaded else { return }
        let pauses = pausedHosts.sorted()
        let key = [personal, bundledSources.joined(separator: ","), pauses.joined(separator: ",")] + CustomBlocklist.engineKey(addresses, fetched: cached.mapValues(\.fetched))
        guard key != publishedKey else { return }
        publishedKey = key
        let lists = addresses.compactMap { cached[$0] }
        let personalText = personal
        let selected = bundledSources
        queue.async {
            for source in selected where Self.bundled[source] == nil {
                Self.bundled[source] = Self.readBundled(source)
            }
            if Self.builtInCounts == nil {
                let counts = Dictionary(uniqueKeysWithValues: Self.builtInSources.map { source in
                    (source, BlockListCount(applied: (Self.bundled[source] ?? Self.readBundled(source)).count))
                })
                Self.builtInCounts = counts
                DispatchQueue.main.async { [self] in builtInCounts = counts }
            }
            // Hide explicitly marked ad regions when built-in ad blocking is enabled.
            // Use normal cosmetic rules so personal exceptions still apply.
            let adRegions = selected.isEmpty ? [] : [
                #"##[data-component="ad-slot"]"#,
                "##.ad-container",
                "##.dfp-slot",
                "##[data-ad][data-ad-unit]:empty",
                #"##[id^="div-gpt-ad"]"#,
                #"##[class~="adContainer"][aria-label="Advertisement"]"#,
            ]
            let base = selected.flatMap { Self.bundled[$0] ?? [] }
            let user = DesktopHidingRules.read(personalText, address: "", fetched: .distantPast)
            let sources = lists + [user]
            let lines = sources.flatMap(\.networkRules)
            let useNetwork = ChromiumFilterLists.available && !lines.isEmpty
            let hosts = useNetwork ? CustomBlocklist.merged([base] + sources.map(\.plainDomains)) : []
            let candidate = AcceptedFilters(domains: CustomBlocklist.merged([base] + sources.map(\.domains)),
                                            hiding: adRegions + sources.flatMap(\.hidingRules),
                                            rules: useNetwork ? DesktopNetworkRules.compile(domains: hosts, lines: lines) : [])
            // WebKit pages get the same network rules as content-blocker lists (WebKitContentBlocking). Chromium's
            // limit of 30,000 isn't WebKit's, so they get the whole selection, on the CEF engine too.
            let webKitLists = WebKitContentRules.build(from: useNetwork ? candidate.rules : DesktopNetworkRules.compile(
                domains: lines.isEmpty ? candidate.domains : CustomBlocklist.merged([base] + sources.map(\.plainDomains)), lines: lines))
            var active = candidate
            var notice: String?
            let count = candidate.rules.count
            if count > DesktopNetworkRules.dynamicRuleLimit {
                let prior = (try? Data(contentsOf: Self.acceptedURL)).flatMap { try? JSONDecoder().decode(AcceptedFilters.self, from: $0) }
                active = prior ?? AcceptedFilters(domains: base, hiding: [], rules: [])
                let kept = prior == nil ? "Only the selected built-in lists are active." : "Your previous filters remain active."
                notice = "Selection needs \(count) network rules. Chromium allows \(DesktopNetworkRules.dynamicRuleLimit). " + kept
            }
            let limitNotice = notice
            let personalRules = BlockListCount(user, networkRules: useNetwork).applied
            let total = BlockListCount.total(builtIn: selected.map { Self.bundled[$0] ?? [] }, builtInHiding: adRegions,
                                             lists: sources, networkRules: useNetwork)
            let listsInUse = selected.filter { !(Self.bundled[$0] ?? []).isEmpty }.count
                + lists.filter { BlockListCount($0, networkRules: useNetwork).applied > 0 }.count + (personalRules > 0 ? 1 : 0)
            let usage: (rules: Int, lists: Int)? = notice == nil ? (total, listsInUse) : nil
            let domains = active.domains
            let hiding = DesktopHidingRules(lines: active.hiding)
            // Scriptlets and procedural hiding (#845), each list with its own trust (`trusted-` scriptlets and
            // `:style()` only from uBlock Origin's lists and My filters).
            var scriptlets = ScriptletTable()
            var procedural = ProceduralTable()
            for list in lists {
                let trusted = Scriptlets.isTrusted(source: list.url)
                scriptlets.add(lines: list.hidingRules, trusted: trusted)
                procedural.add(lines: list.hidingRules, trusted: trusted)
            }
            scriptlets.add(lines: user.hidingRules, trusted: true)
            procedural.add(lines: user.hidingRules, trusted: true)
            let scriptletTable = scriptlets.json(paused: pauses)
            let pageRuleCounts = (scriptlets.count, procedural.count)
            DispatchQueue.main.async { [self] in
                guard publishedKey == key else { return }
                inUse = usage
                self.hiding = hiding
                self.procedural = procedural
                styles.removeAllObjects()
                FilterPageScripts.install(table: scriptletTable)
                WebKitContentBlocking.shared.set(webKitLists.lists, rules: webKitLists.rules)
                hidingChanged?()
            }
            let rules = active.rules
            if !ChromiumFilterLists.available || rules.isEmpty || !Self.chromiumOwnsDomains {
                Self.setNativeDomains(domains)
            }
            if ChromiumFilterLists.available {
                let hasRules = !rules.isEmpty
                do {
                    let exceptions = hasRules ? DesktopNetworkRules.siteExceptions(for: pauses, after: 0) : []
                    let revision = try ChromiumFilterLists.publish(rules, siteExceptions: exceptions)
                    DispatchQueue.main.async { [self] in
                        guard publishedKey == key else { return }
                        confirm(revision, key: key, hasNetworkRules: hasRules, filters: candidate, fallback: domains, notice: limitNotice)
                    }
                } catch {
                    ChromiumFilterLists.expectNetworkRules(false)
                    Self.setNativeDomains(domains)
                    Self.chromiumOwnsDomains = false
                    DispatchQueue.main.async { [self] in
                        if publishedKey == key { networkFailure = "Couldn’t save the network filters on this Mac." }
                    }
                }
            }
            CraLog.note("block lists: \(domains.count) domains, \(lists.count) added \(lists.count == 1 ? "list" : "lists")"
                + (usage.map { ", \($0.rules) rules in use from \($0.lists)" } ?? "")
                + ", \(pageRuleCounts.0) scriptlets, \(pageRuleCounts.1) procedural")
        }
    }

    /// Keep native host protection during startup and compilation. An acknowledgement means
    /// Chromium has swapped rules atomically. A superseded acknowledgement cannot change the engine.
    private func confirm(_ revision: String, key: [String], hasNetworkRules: Bool, filters: AcceptedFilters, fallback: [String], notice: String?) {
        networkFailure = notice
        if !hasNetworkRules && CraCEFRuntime.responds(to: NSSelectorFromString("synchronizeBundledNetworkFilter")) {
            CraCEFRuntime.synchronizeBundledNetworkFilter()
            queue.async {
                guard ChromiumFilterLists.isCurrent(revision) else { return }
                Self.chromiumOwnsDomains = false
                if notice == nil { Self.keep(filters) }
                Self.setNativeDomains(fallback)
                CraLog.note("native domain filters active: " + revision)
            }
            return
        }
        Task { [weak self] in
            for _ in 0..<100 {
                guard let self, publishedKey == key else { return }
                let folder = ChromiumFilterLists.directory
                if (try? String(contentsOf: folder.appendingPathComponent("applied"), encoding: .utf8)) == revision {
                    queue.async {
                        guard ChromiumFilterLists.isCurrent(revision) else { return }
                        if notice == nil { Self.keep(filters) }
                        if hasNetworkRules {
                            Self.setNativeDomains([])
                            Self.chromiumOwnsDomains = true
                        } else {
                            Self.chromiumOwnsDomains = false
                        }
                        CraLog.note("network filter revision active: " + revision)
                    }
                    return
                }
                if (try? String(contentsOf: folder.appendingPathComponent("failed"), encoding: .utf8)) == revision { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard let self, publishedKey == key else { return }
            queue.async {
                guard ChromiumFilterLists.isCurrent(revision) else { return }
                ChromiumFilterLists.expectNetworkRules(false)
                Self.setNativeDomains(fallback)
                Self.chromiumOwnsDomains = false
            }
            networkFailure = "Chromium couldn’t apply these network filters. The domain blocker is active. Try fewer lists and update again."
        }
    }

    nonisolated private static func keep(_ filters: AcceptedFilters) {
        do {
            try JSONEncoder().encode(filters).write(to: acceptedURL, options: .atomic)
        } catch {
            CraLog.note("Could not save the accepted filters for restart: " + error.localizedDescription)
        }
    }

    /// Cra's own lists in resources/blocklist, which the Privacy pane switches one by one.
    nonisolated static let builtInSources = ["adaway", "anudeep"]
    nonisolated(unsafe) private static var builtInCounts: [String: BlockListCount]? // only accessed on queue

    /// A built-in list's domains. Only called on the publication queue.
    nonisolated private static func readBundled(_ source: String) -> [String] {
        let path = Bundle.main.path(forResource: source, ofType: "txt", inDirectory: "blocklist")
        return path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ParsedBlocklist(text: $0).domains } ?? []
    }

    /// Only called on the publication queue.
    nonisolated private static func setNativeDomains(_ domains: [String]) {
        guard domains != lastDomains else { return }
        CraCEFRuntime.setBlockedDomains(domains)
        lastDomains = domains
    }

    /// A list as cra.log names it: its host, never the whole address (CraLog).
    private static func logName(_ address: String) -> String {
        URL(string: address).flatMap { $0.isFileURL ? "file" : $0.host } ?? "?"
    }

    private static func load(_ url: URL) async -> Result<String, BlockListError> {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            return text(data)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpShouldHandleCookies = false
        request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.status(http.statusCode))
            }
            return text(data)
        } catch {
            return .failure(.network)
        }
    }

    private static func text(_ data: Data) -> Result<String, BlockListError> {
        guard data.count <= maxBytes else { return .failure(.tooBig) }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return .failure(.unreadable) }
        return .success(text)
    }
}

enum BlockListError: Error {
    case network, status(Int), unreadable, tooBig, noDomains

    var message: String {
        switch self {
        case .network: return "Couldn’t reach the list. Cra tries again later."
        case .status(let code): return "The server answered \(code). Cra tries again later."
        case .unreadable: return "Cra couldn’t read the file."
        case .tooBig: return "The list is bigger than 64 MB."
        case .noDomains: return "Cra found no supported domain, network or element-hiding rules in this list."
        }
    }
}
