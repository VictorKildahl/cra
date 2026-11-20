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
