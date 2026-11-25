import Foundation

/// One profile's "Archive tabs after" (Settings ▸ Profiles): a timer, or never.
public enum AutoArchiveChoice: Equatable, Hashable, Sendable {
    case after(AutoArchiveThreshold)
    case never

    /// As AppSettings.profileAutoArchive holds it: "never" or the threshold's name.
    var stored: String {
        switch self {
        case .never: "never"
        case .after(let t): t.rawValue
        }
    }

    /// A name from a newer Cra is the longest timer this one knows: never sooner than asked.
    init(stored: String) {
        self = stored == "never" ? .never : .after(AutoArchiveThreshold(rawValue: stored) ?? AutoArchiveThreshold.allCases.last!)
    }
}

public extension AppSettings {
    /// Arc's per-profile "Archive tabs after" (GitHub #693). Default's is `autoArchive` and
    /// `autoArchiveEnabled`, the setting every Cra had and older ones still read; another profile has
    /// its own in `profileAutoArchive`, and one never set archives as Default does.
    func autoArchive(profileID: UUID?) -> AutoArchiveChoice {
        if let profileID, let stored = profileAutoArchive[DownloadLocation.key(profileID: profileID)] {
            return AutoArchiveChoice(stored: stored)
        }
        return autoArchiveEnabled ? .after(autoArchive) : .never
    }

    /// Sets one profile's timer. Changing Default's first gives `otherProfiles` that were following
    /// it the timer they had, so a change on one profile never moves another's.
    mutating func setAutoArchive(_ choice: AutoArchiveChoice, profileID: UUID?, otherProfiles: [UUID]) {
        guard let profileID else {
            let before = autoArchive(profileID: nil)
            for p in otherProfiles where profileAutoArchive[DownloadLocation.key(profileID: p)] == nil {
                profileAutoArchive[DownloadLocation.key(profileID: p)] = before.stored
            }
            switch choice {
            case .never: autoArchiveEnabled = false
            case .after(let t): autoArchiveEnabled = true; autoArchive = t
            }
            return
        }
        profileAutoArchive[DownloadLocation.key(profileID: profileID)] = choice.stored
    }
}

/// Which Today tabs the archive clock takes (Arc: ArchiveState+AutoArchive, autoArchiveTimeThreshold),
/// each space by its profile's timer (#693).
public enum AutoArchive {
    public struct Tab: Equatable, Sendable {
        public var id: UUID
        /// When it was last shown, or made if never.
        public var lastActive: Date

        public init(id: UUID, lastActive: Date) {
            self.id = id
            self.lastActive = lastActive
        }
    }

    /// The tabs idle longer than `choice`'s timer, in order; a tab selected in a window stays.
    public static func due(_ tabs: [Tab], selected: Set<UUID>, choice: AutoArchiveChoice, now: Date) -> [UUID] {
        guard case .after(let threshold) = choice else { return [] }
        let cutoff = now.addingTimeInterval(-threshold.seconds)
        return tabs.filter { !selected.contains($0.id) && $0.lastActive < cutoff }.map(\.id)
    }
}

/// Arc's toast after an archive pass, "Auto archived %d tabs" (Toasts, "Toast indicating that tabs were
/// archived"). A pass mostly runs while nobody is looking, overnight or at the launch an automatic update
/// makes, and the sidebar is just emptier in the morning (X, 25 Nov 2026). So the count waits for someone at
/// Cra to read it, adding up over passes, and is said once.
public struct AutoArchiveNotice: Equatable, Sendable {
    /// Tabs archived since the toast last showed.
    public private(set) var pending: Int

    public init(pending: Int = 0) {
        self.pending = max(0, pending)
    }

    /// Input this recent, with Cra the active app, means someone is at it.
    public static let presenceWindow: TimeInterval = 60

    public static func userPresent(appActive: Bool, idleSeconds: TimeInterval) -> Bool {
        appActive && idleSeconds < presenceWindow
    }

    /// Arc's words; one tab is "1 tab", where Arc's single format says "1 tabs".
    public static func text(count: Int) -> String {
        count == 1 ? "Auto archived 1 tab" : "Auto archived \(count) tabs"
    }

    public mutating func archived(_ count: Int) {
        pending += max(0, count)
    }

    /// The toast's words when someone is there and tabs wait, which clears the count; otherwise nil and
    /// the count keeps waiting.
    public mutating func take(userPresent: Bool) -> String? {
        guard userPresent, pending > 0 else { return nil }
        defer { pending = 0 }
        return Self.text(count: pending)
    }
}
