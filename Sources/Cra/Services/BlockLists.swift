import CraCEF
import Foundation
import Observation

/// Settings ▸ Privacy ▸ Block lists (#507): lists added on top of the one Cra ships. Each is
/// fetched (or read, for a file), kept in the data folder's Blocklists folder and fetched again
/// once it's old (CustomBlocklist.isDue). The engine gets Cra's own list and every added list's
/// domains as one set, which the Block ads and trackers switch turns on and off.
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
    @ObservationIgnored private let styles = NSCache<NSString, NSString>()
    @ObservationIgnored private var personal = ""
    private(set) var personalSummary: String?

    nonisolated(unsafe) private static var lastDomains: [String]? // only accessed on queue

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
        if let value = styles.object(forKey: host as NSString) { return value as String }
        let value = hiding.css(host: host)
        styles.setObject(value as NSString, forKey: host as NSString, cost: value.utf8.count)
        return value
    }

    static var folder: URL {
        let url = AppPaths.supportDir.appendingPathComponent("Blocklists", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cacheURL(_ address: String) -> URL {
        folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: address))
    }

    /// The bundled list (resources/blocklist), read once on `queue`.
    nonisolated(unsafe) private static var bundled: [String]?

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

    /// Fetches the lists that are old, or that have no copy yet.
    private func refreshDue(atLaunch: Bool) {
        CustomBlocklist.due(addresses, fetched: cached.mapValues(\.fetched), now: clock.now, atLaunch: atLaunch).forEach { fetch($0) }
    }

    /// Fetches (or reads) one list now. A failure keeps the copy it had.
    func fetch(_ address: String) {
        guard !fetching.contains(address), let url = URL(string: address) else { return }
        fetching.insert(address)
        let fetchedAt = clock.now
        Task { [weak self] in
            let outcome = await Self.load(url)
            let result: Result<CachedBlocklist, BlockListError> = await Task.detached(priority: .utility) {
                outcome.flatMap { text in
                    let list = DesktopHidingRules.read(text, address: address, fetched: fetchedAt)
                    guard !list.domains.isEmpty || !list.hidingRules.isEmpty else { return .failure(.noDomains) }
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
        let key = [personal] + CustomBlocklist.engineKey(addresses, fetched: cached.mapValues(\.fetched))
        guard key != publishedKey else { return }
        publishedKey = key
        let lists = addresses.compactMap { cached[$0] }
        let personalText = personal
        queue.async {
            if Self.bundled == nil {
                let path = Bundle.main.path(forResource: "domains", ofType: "txt", inDirectory: "blocklist")
                Self.bundled = path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map { ParsedBlocklist(text: $0).domains } ?? []
            }
            let user = DesktopHidingRules.read(personalText, address: "", fetched: .distantPast)
            let domains = CustomBlocklist.merged([Self.bundled ?? [], user.domains] + lists.map(\.domains))
            let hiding = DesktopHidingRules(lines: lists.flatMap(\.hidingRules) + user.hidingRules)
            DispatchQueue.main.async { [self] in
                guard publishedKey == key else { return }
                self.hiding = hiding
                styles.removeAllObjects()
                personalSummary = personalText.isEmpty ? nil : user.desktopSummary
                hidingChanged?()
            }
            if domains != Self.lastDomains {
                CraCEFRuntime.setBlockedDomains(domains)
                Self.lastDomains = domains
            }
            CraLog.note("block lists: \(domains.count) domains, \(lists.count) added \(lists.count == 1 ? "list" : "lists")")
        }
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
        case .noDomains: return "Cra found no supported domain or element-hiding rules in this list."
        }
    }
}
