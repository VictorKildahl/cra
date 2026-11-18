import CraCore
import Foundation

/// Default Site Settings ▸ Block Lists (#507): lists added on top of Cra's own, as on the Mac.
/// Each is fetched, kept in the data folder's Blocklists folder and fetched again when it's a day
/// old (CustomBlocklist.isDue); ContentBlocker compiles their domains for pages with Block Ads on.
@MainActor
final class BlockLists: ObservableObject {
    static let shared = BlockLists()

    /// Fetched copies, by address.
    @Published private(set) var cached: [String: CachedBlocklist] = [:]
    @Published private(set) var fetching: Set<String> = []
    /// Why the last fetch of an address failed; a good fetch clears it.
    @Published private(set) var failures: [String: String] = [:]

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

    /// `settings.customBlocklists` now. The first call (at launch) reads the kept copies; later
    /// ones forget removed lists and fetch added ones.
    func set(addresses new: [String]) {
        if !started {
            started = true
            addresses = new
            ContentBlocker.shared.launched(addresses: new, first: true)
            Task.detached(priority: .utility) {
                let kept = new.compactMap { address in
                    (try? String(contentsOf: Self.cacheURL(address), encoding: .utf8)).flatMap(CachedBlocklist.init(text:))
                }
                await MainActor.run {
                    for list in kept where self.addresses.contains(list.url) { self.cached[list.url] = list }
                    self.publish()
                    self.refreshDue()
                }
            }
            return
        }
        let (removed, added) = CustomBlocklist.changes(from: addresses, to: new)
        addresses = new
        for address in removed {
            cached[address] = nil
            failures[address] = nil
            try? FileManager.default.removeItem(at: Self.cacheURL(address))
        }
        publish()
        added.forEach { fetch($0) }
    }

    /// Fetches the lists that are a day old, or that have no copy yet (at launch and on coming back).
    func refreshDue() {
        guard started else { return }
        CustomBlocklist.due(addresses, fetched: cached.mapValues(\.fetched), now: Date(), atLaunch: true).forEach { fetch($0) }
    }

    func fetch(_ address: String) {
        guard !fetching.contains(address), let url = URL(string: address), !url.isFileURL else { return }
        fetching.insert(address)
        let fetchedAt = Date()
        Task {
            let result: Result<CachedBlocklist, BlockListError> = await Task.detached(priority: .utility) {
                await Self.load(url).flatMap { text in
                    let list = CachedBlocklist(url: address, list: ParsedBlocklist(text: text), fetched: fetchedAt)
                    return list.domains.isEmpty ? .failure(.noDomains) : .success(list)
                }
            }.value
            finish(address, result)
        }
    }

    private func finish(_ address: String, _ result: Result<CachedBlocklist, BlockListError>) {
        fetching.remove(address)
        guard addresses.contains(address) else { return }
        switch result {
        case .success(let list):
            cached[address] = list
            failures[address] = nil
            try? list.text.write(to: Self.cacheURL(address), atomically: true, encoding: .utf8)
            publish()
        case .failure(let error):
            failures[address] = error.message
        }
    }

    private func publish() {
        let lists = addresses.compactMap { cached[$0]?.domains }
        ContentBlocker.shared.setAdded(CustomBlocklist.merged(lists))
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
    case network, status(Int), unreadable, tooBig, noDomains

    var message: String {
        switch self {
        case .network: return "Couldn’t reach the list. Cra tries again later."
        case .status(let code): return "The server answered \(code). Cra tries again later."
        case .unreadable: return "Cra couldn’t read the list."
        case .tooBig: return "The list is bigger than 64 MB."
        case .noDomains: return "Cra found no domain rules it can use in this list."
        }
    }
}
