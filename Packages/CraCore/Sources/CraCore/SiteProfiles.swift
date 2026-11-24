import Foundation

/// A profile remembered for a site; `id` nil is the Default profile.
public struct RememberedProfile: Equatable, Sendable {
    public let id: UUID?

    public init(id: UUID?) { self.id = id }
}

/// The profile picked for each site in a Little Window: Arc's domainToProfilePreferences.
///
/// Arc 1.173.1 (docs/arc-reverse-engineering.md): picking a profile in a Little Arc's address pill
/// remembers it for the host of the link the window opened, and a later link to that host from
/// another app opens in that profile and names a space on it, whichever window was used last. A host
/// nobody picked a profile for follows the window used last. Kept in windows.json, as Arc keeps it
/// in its own preferences rather than with the synced sidebar.
public struct SiteProfiles: Codable, Equatable, Sendable {
    /// Site → profile, as history keys profiles (CommandBarProfileScope.key).
    private var bySite: [String: String]

    public init() { bySite = [:] }

    /// The site a URL belongs to: its host without case and a leading "www.". Nil without a host.
    public static func site(of url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The profile picked last for `url`'s site, nil when none was.
    public func profile(for url: String) -> RememberedProfile? {
        guard let key = Self.site(of: url).flatMap({ bySite[$0] }) else { return nil }
        if key == CommandBarProfileScope.key(nil) { return RememberedProfile(id: nil) }
        return UUID(uuidString: key).map { RememberedProfile(id: $0) }
    }

    /// `profile` (nil: Default) was picked for `url`'s site.
    public mutating func remember(_ profile: UUID?, for url: String) {
        guard let site = Self.site(of: url) else { return }
        bySite[site] = CommandBarProfileScope.key(profile)
    }

    /// Picks another browser made, by site (an import). A site already picked here keeps its pick.
    public mutating func adopt(_ picks: [String: RememberedProfile]) {
        for (host, picked) in picks {
            guard let site = Self.site(of: "https://\(host)/"), bySite[site] == nil else { continue }
            bySite[site] = CommandBarProfileScope.key(picked.id)
        }
    }

    /// The space a Little Window on `url` opens in instead of `lastUsed`: the first of `spaces` on the
    /// site's profile. Nil when `lastUsed` is on it already, the site has none, or no space uses it any more.
    public func space(for url: String, lastUsed: UUID, in spaces: [Space]) -> UUID? {
        guard let remembered = profile(for: url) else { return nil }
        let onProfile = spaces.filter { $0.profileID == remembered.id }
        return onProfile.contains { $0.id == lastUsed } ? nil : onProfile.first?.id
    }

    public init(from decoder: Decoder) throws {
        bySite = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(bySite)
    }
}
