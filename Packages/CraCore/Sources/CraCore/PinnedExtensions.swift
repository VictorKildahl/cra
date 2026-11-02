import Foundation

/// pinned-extensions.json: the extensions pinned to the toolbar, in toolbar order, for each
/// Chromium profile. Arc keeps them per profile: its `arc::BrowserContext` (one per profile)
/// reads and writes Chromium's `extensions.pinned_extensions` pref, so a space shows the pins of
/// the profile it is bound to (GitHub #107). Cra kept one list for every profile before that, a
/// plain array. That list still serves each profile that has not pinned or unpinned anything
/// itself, so an update changes no toolbar, and a file with no list of a profile's own is still
/// written as that array.
public struct PinnedExtensions: Codable, Equatable, Sendable {
    /// The pins of every profile without a list of its own.
    public var shared: [String]
    /// Lists of profiles whose pins changed, by profile folder ("Default", "Profile <id>").
    public var profiles: [String: [String]]

    public init(shared: [String] = [], profiles: [String: [String]] = [:]) {
        self.shared = shared
        self.profiles = profiles
    }

    /// Chromium extension IDs in toolbar order.
    public func ids(inProfile profile: String) -> [String] { profiles[profile] ?? shared }

    public func isPinned(_ id: String, inProfile profile: String) -> Bool { ids(inProfile: profile).contains(id) }

    /// Pins or unpins in one profile only; the others keep what they show.
    public mutating func setPinned(_ id: String, _ pinned: Bool, inProfile profile: String) {
        guard pinned != isPinned(id, inProfile: profile) else { return }
        var list = ids(inProfile: profile)
        if pinned { list.append(id) } else { list.removeAll { $0 == id } }
        profiles[profile] = list
    }

    public mutating func move(_ id: String, to index: Int, inProfile profile: String) {
        var list = ids(inProfile: profile)
        guard let from = list.firstIndex(of: id) else { return }
        list.remove(at: from)
        list.insert(id, at: min(max(0, index), list.count))
        profiles[profile] = list
    }

    /// Drops the extensions `isGone` says are no longer installed, from every list.
    public mutating func removeAll(where isGone: (String) -> Bool) {
        shared.removeAll(where: isGone)
        for key in profiles.keys { profiles[key]?.removeAll(where: isGone) }
    }

    private enum CodingKeys: String, CodingKey { case shared, profiles }

    public init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([String].self) {
            self.init(shared: list)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(shared: try c.decodeIfPresent([String].self, forKey: .shared) ?? [],
                  profiles: try c.decodeIfPresent([String: [String]].self, forKey: .profiles) ?? [:])
    }

    public func encode(to encoder: Encoder) throws {
        if profiles.isEmpty {
            var c = encoder.singleValueContainer()
            try c.encode(shared)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shared, forKey: .shared)
        try c.encode(profiles, forKey: .profiles)
    }
}
