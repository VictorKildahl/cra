import Foundation

/// Arc's Filter on Library ▸ Archived Tabs and Downloads (Arc 1.172.1, 8 Nov 2026): a panel in place
/// of the search with chips. Archived Tabs: "How was the tab closed?" Auto-Closed / Manually Closed,
/// "Where was the tab?" Little Arc and each space. Downloads: "Profiles". Chips in one group widen
/// the match within it (either picked passes); groups narrow each other; nothing picked shows all.
public struct ArchiveFilter: Equatable, Sendable {
    public enum Closed: Hashable, Sendable { case auto, manual }
    public enum Place: Hashable, Sendable { case littleWindow, space(UUID) }

    public var closed: Set<Closed> = []
    public var places: Set<Place> = []
    public init() {}

    public var isEmpty: Bool { closed.isEmpty && places.isEmpty }

    public func shows(_ e: ArchivedItem) -> Bool {
        if !closed.isEmpty {
            // Arc's Auto-Closed is the archiving timer; a Clear or a deleted space counts as by hand.
            let how: Closed = e.reason == .auto ? .auto : .manual
            guard closed.contains(how) else { return false }
        }
        if !places.isEmpty {
            let place: Place? = e.fromLittleWindow == true ? .littleWindow : e.sourceSpaceID.map { .space($0) }
            guard let place, places.contains(place) else { return false }
        }
        return true
    }
}

public struct DownloadFilter: Equatable, Sendable {
    /// Picked profile ids ("" is the default profile).
    public var profiles: Set<String> = []
    public init() {}
    public var isEmpty: Bool { profiles.isEmpty }
    public func shows(profile: String?) -> Bool { profiles.isEmpty || profiles.contains(profile ?? "") }
}
