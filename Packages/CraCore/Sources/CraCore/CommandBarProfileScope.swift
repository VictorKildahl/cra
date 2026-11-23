import Foundation

/// What the command bar suggests from the archive and from history: only what was browsed on the
/// profile of the space the bar is in, the way a space's history is its profile's (Chromium keeps
/// one per profile, and so did Arc). Before, a space on one profile was offered the other profiles'
/// archived tabs and visited pages (#609). Open tabs stay across spaces, as in Arc, and Library ▸
/// Archived Tabs keeps every space's, as Arc's archive (with its "Where was the tab?" filter) does.
public enum CommandBarProfileScope {
    /// A profile as history records it: its id, or "default" for the Default profile (nil).
    public static func key(_ profile: UUID?) -> String { profile?.uuidString ?? "default" }

    /// Whether a history entry is suggested in a bar on `profile`: one visited there, or one saved
    /// before Cra kept profiles (it can't tell whose it was).
    public static func suggests(_ entry: HistoryEntry, on profile: UUID?) -> Bool {
        entry.profiles.map { $0.contains(key(profile)) } ?? true
    }

    /// Whether an archived tab is suggested in a bar on `profile`. `source` is the profile of the
    /// space it was closed in, nil when it has none (closed in a Little Window): that one is suggested
    /// everywhere, as before.
    public static func suggests(archivedFrom source: UUID??, on profile: UUID?) -> Bool {
        guard let source else { return true }
        return source == profile
    }
}

public extension HistoryEntry {
    /// The entry after a visit in `profile`.
    mutating func visited(in profile: UUID?) {
        let k = CommandBarProfileScope.key(profile)
        var known = profiles ?? []
        if !known.contains(k) { known.append(k) }
        profiles = known
    }
}

public extension CommandBarProfileScope {
    /// History saved before #609 has no profiles, so every profile's bar suggested it (#729). The
    /// profiles' own Chromium histories know whose each page was: `chromiumURLs` holds, per profile
    /// (`key`), the addresses its `History` has. An entry with no profiles gets those that have its
    /// page; one that none has (older than Chromium's 90 days) gets every profile there is, which is
    /// what it was suggested on before. Entries that have profiles are left as they are. Returns the
    /// entries that changed.
    static func attributing(_ entries: [HistoryEntry], chromiumURLs: [String: Set<String>]) -> [HistoryEntry] {
        let everyone = chromiumURLs.keys.sorted { ($0 == key(nil) ? 0 : 1, $0) < ($1 == key(nil) ? 0 : 1, $1) }
        guard !everyone.isEmpty else { return [] }
        return entries.compactMap { e in
            guard e.profiles == nil else { return nil }
            var out = e
            let found = everyone.filter { chromiumURLs[$0]?.contains(e.url) == true }
            out.profiles = found.isEmpty ? everyone : found
            return out
        }
    }
}
