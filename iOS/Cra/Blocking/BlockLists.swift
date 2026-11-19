import CraCore
import Foundation

/// Default Site Settings ▸ Block Lists (#507): lists added on top of Cra's own, as on the Mac.
/// Each is fetched, kept in the data folder's Blocklists folder and fetched again when it's a day
/// old (CustomBlocklist.isDue); ContentBlocker compiles them for pages with Block Ads on.
///
/// A list with more than domains (EasyList, AdGuard Base) applies all its rules (#570): its text is
/// kept in `<hash>.rules.txt` beside #507's `<hash>.txt`, which is written as before so an older Cra
/// still reads the domains. A kept list without its rules file blocks its domains until the next fetch.
@MainActor
final class BlockLists: ObservableObject {
    static let shared = BlockLists()

    /// Fetched copies, by address.
    @Published private(set) var cached: [String: CachedBlocklist] = [:]
    /// What each list applies, for its row; a list with a rules file has none until it's read.
    @Published private(set) var rules: [String: BlocklistRules] = [:]
    @Published private(set) var fetching: Set<String> = []
    /// Why the last fetch of an address failed; a good fetch clears it.
    @Published private(set) var failures: [String: String] = [:]

    /// The kept rules files that belong to the kept copies, by address.
    private var rulesFiles: [String: CachedBlocklistRules] = [:]
    private var addresses: [String] = []
    private var started = false
    nonisolated private static let maxBytes = 64 << 20

    private init() {}

    nonisolated private static var folder: URL {
        let url = LaunchOptions.dataDirectory.appendingPathComponent("Blocklists", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private static func cacheURL(_ address: String) -> URL {
        folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: address))
    }

    nonisolated private static func rulesURL(_ address: String) -> URL {
        folder.appendingPathComponent(CachedBlocklistRules.fileName(for: address))
    }

    /// Whether a list applies its full rules (it has a rules file) rather than its domains.
    func hasFullRules(_ address: String) -> Bool { rulesFiles[address] != nil }

    /// `settings.customBlocklists` now. The first call (at launch) reads the kept copies; later
    /// ones forget removed lists and fetch added ones.
    func set(addresses new: [String]) {
        if !started {
            started = true
            addresses = new
            ContentBlocker.shared.launched(addresses: new, first: true)
            Task.detached(priority: .utility) {
                let kept = new.compactMap { address -> (CachedBlocklist, CachedBlocklistRules?)? in
                    guard let list = (try? String(contentsOf: Self.cacheURL(address), encoding: .utf8)).flatMap(CachedBlocklist.init(text:))
                    else { return nil }
                    // A rules file from another fetch (an older Cra fetched the list since) isn't used.
                    let file = (try? String(contentsOf: Self.rulesURL(address), encoding: .utf8))
                        .flatMap(CachedBlocklistRules.init(text:)).flatMap { $0.belongs(to: list) ? $0 : nil }
                    return (list, file)
                }
                await MainActor.run {
                    for (list, file) in kept where self.addresses.contains(list.url) {
                        self.cached[list.url] = list
                        if let file {
                            self.rulesFiles[list.url] = file
                        } else {
                            self.rules[list.url] = BlocklistRules.loading(kept: list, rulesFile: nil)
                        }
                    }
                    self.publish()
                    self.readRulesFiles()
                    self.refreshDue()
                }
            }
            return
        }
        let (removed, added) = CustomBlocklist.changes(from: addresses, to: new)
        addresses = new
        for address in removed {
            cached[address] = nil
            rules[address] = nil
            rulesFiles[address] = nil
            failures[address] = nil
            try? FileManager.default.removeItem(at: Self.cacheURL(address))
            try? FileManager.default.removeItem(at: Self.rulesURL(address))
        }
        publish()
        added.forEach { fetch($0) }
    }

    /// Reads the kept lists' full rules, after their compiled rule lists were looked up, for their
    /// rows and for counting what they stop.
    private func readRulesFiles() {
        let files = rulesFiles.filter { rules[$0.key] == nil }
        guard !files.isEmpty else { return }
        Task.detached(priority: .utility) {
            let read = files.mapValues { BlocklistRules(text: $0.listText) }
            await MainActor.run {
                for (address, list) in read where self.rulesFiles[address] == files[address] { self.rules[address] = list }
                self.publishFilters()
            }
        }
    }

    /// Fetches the lists that are a day old, or that have no copy yet (at launch and on coming back).
    func refreshDue() {
        guard started else { return }
        CustomBlocklist.due(addresses, fetched: cached.mapValues(\.fetched), now: Date(), atLaunch: true).forEach { fetch($0) }
    }

    private struct Fetched {
        var list: CachedBlocklist
        var rules: BlocklistRules
        var file: CachedBlocklistRules?
    }

    func fetch(_ address: String) {
        guard !fetching.contains(address), let url = URL(string: address), !url.isFileURL else { return }
        fetching.insert(address)
        let fetchedAt = Date()
        Task {
            let result: Result<Fetched, BlockListError> = await Task.detached(priority: .utility) {
                await Self.load(url).flatMap { text in
                    let list = CachedBlocklist(url: address, list: ParsedBlocklist(text: text), fetched: fetchedAt)
                    let rules = BlocklistRules(text: text)
                    guard !list.domains.isEmpty || rules.hasFilterRules else { return .failure(.noRules) }
                    let file = BlocklistRules.keepsRulesFile(rules) ? CachedBlocklistRules(url: address, fetched: fetchedAt, listText: text) : nil
                    return .success(Fetched(list: list, rules: rules, file: file))
                }
            }.value
            finish(address, result)
        }
    }

    private func finish(_ address: String, _ result: Result<Fetched, BlockListError>) {
        fetching.remove(address)
        guard addresses.contains(address) else { return }
        switch result {
        case .success(let fetched):
            cached[address] = fetched.list
            rules[address] = fetched.rules
            rulesFiles[address] = fetched.file
            failures[address] = nil
            // #507's file as before; the rules file beside it only for a list with more than domains.
            try? fetched.list.text.write(to: Self.cacheURL(address), atomically: true, encoding: .utf8)
            if let file = fetched.file {
                try? file.text.write(to: Self.rulesURL(address), atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: Self.rulesURL(address))
            }
            publish()
        case .failure(let error):
            failures[address] = error.message
        }
    }

    /// Hands the blocker the lists: domain lists merged, lists with full rules each on its own.
    private func publish() {
        var domainLists: [[String]] = []
        var full: [ContentBlocker.AddedList] = []
        for address in addresses {
            guard let list = cached[address] else { continue }
            if let file = rulesFiles[address] {
                let parsed = rules[address]
                full.append(ContentBlocker.AddedList(key: file.ruleListKey) { parsed ?? BlocklistRules(text: file.listText) })
            } else {
                domainLists.append(list.domains)
            }
        }
        ContentBlocker.shared.setAdded(CustomBlocklist.merged(domainLists), lists: full)
        publishFilters()
    }

    /// The full rules read so far, for counting what they stop.
    private func publishFilters() {
        ContentBlocker.shared.setAddedFilters(addresses.compactMap { address in
            rulesFiles[address] == nil ? nil : rules[address]?.filters
        })
    }

    nonisolated private static func load(_ url: URL) async -> Result<String, BlockListError> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return .failure(.status(http.statusCode)) }
            guard data.count <= maxBytes else { return .failure(.tooBig) }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return .failure(.unreadable) }
            return .success(text)
        } catch {
            return .failure(.network)
        }
    }
}

enum BlockListError: Error {
    case network, status(Int), unreadable, tooBig, noRules

    var message: String {
        switch self {
        case .network: return "Couldn’t reach the list. Cra tries again later."
        case .status(let code): return "The server answered \(code). Cra tries again later."
        case .unreadable: return "Cra couldn’t read the list."
        case .tooBig: return "The list is bigger than 64 MB."
        case .noRules: return "Cra found no rules it can use in this list."
        }
    }
}
