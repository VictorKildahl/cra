import Foundation
import Observation

/// Every Boost (Arc's per-site restyles), in boosts.json in the data folder.
@MainActor
@Observable
final class BoostStore {
    static let shared = BoostStore()
    @ObservationIgnored private let file = JSONStore<[Boost]>("boosts.json")
    private(set) var boosts: [Boost]

    private init() { boosts = file.load(or: { [] }) }

    func boost(_ id: UUID) -> Boost? { boosts.first { $0.id == id } }
    func boost(forHost host: String) -> Boost? { boosts.first { $0.host == Boost.siteHost(host) } }

    /// The site's boost, made when it has none (Arc's New Boost opens the one a site has).
    func boostForSite(of url: String) -> Boost? {
        guard let host = URL(string: url)?.host, url.hasPrefix("http") else { return nil }
        if let b = boost(forHost: host) { return b }
        let b = Boost(host: host)
        boosts.append(b)
        file.save(boosts)
        return b
    }

    func update(_ boost: Boost) {
        guard let i = boosts.firstIndex(where: { $0.id == boost.id }) else { return }
        boosts[i] = boost
        file.save(boosts)
        BoostStore.changed?(boost.host)
    }

    /// A boost from a link or the gallery (BoostInstall): added, or put in place of the one with its id.
    func add(_ boost: Boost) {
        if let i = boosts.firstIndex(where: { $0.id == boost.id }) { boosts[i] = boost } else { boosts.append(boost) }
        file.save(boosts)
        BoostStore.changed?(boost.host)
    }

    func delete(_ id: UUID) {
        let host = boost(id)?.host
        boosts.removeAll { $0.id == id }
        file.save(boosts)
        if let host { BoostStore.changed?(host) }
    }

    /// The pages on a host get their boost again (set by the app: BrowserManager re-applies).
    @ObservationIgnored static var changed: ((String) -> Void)?
}
