import Foundation

/// Decision logic for restoring the last closed tab (⌘⇧T / ⌘Z, reopenClosedTab), matching Arc.
///
/// In Arc, closing an open pinned tab (⌘W or the close minus) unloads it and keeps it pinned in the sidebar.
/// Pressing ⌘⇧T ("Restore Last Closed Tab") brings back the tab closed last in reverse chronological order:
/// - A closed open pinned tab is restored to the URL and title it had when closed, and re-selected.
/// - An archived Today tab (or a pinned tab archived via ✕) is restored from the archive.
/// - A closed Peek window is reopened over its source tab.
public enum ReopenClosedTab {
    public struct PaneState: Equatable, Sendable {
        public var id: UUID
        public var url: String?
        public var title: String?

        public init(id: UUID, url: String? = nil, title: String? = nil) {
            self.id = id
            self.url = url
            self.title = title
        }
    }

    public struct ClosedPinnedTab: Equatable, Sendable {
        public var id: UUID
        public var url: String?
        public var title: String?
        public var paneStates: [PaneState]
        public var closedAt: Date

        public init(id: UUID, url: String? = nil, title: String? = nil, paneStates: [PaneState] = [], closedAt: Date) {
            self.id = id
            self.url = url
            self.title = title
            self.paneStates = paneStates
            self.closedAt = closedAt
        }
    }

    public struct ClosedPeek: Equatable, Sendable {
        public var url: String
        public var tabID: UUID?
        public var closedAt: Date

        public init(url: String, tabID: UUID?, closedAt: Date) {
            self.url = url
            self.tabID = tabID
            self.closedAt = closedAt
        }
    }

    public struct ArchivedTab: Equatable, Sendable {
        public var id: UUID
        public var archivedAt: Date

        public init(id: UUID, archivedAt: Date) {
            self.id = id
            self.archivedAt = archivedAt
        }
    }

    public enum Restoration: Equatable, Sendable {
        case pinned(id: UUID, url: String?, title: String?, paneStates: [PaneState])
        case peek(url: String, tabID: UUID?)
        case archived(UUID)

        public var tabID: UUID? {
            switch self {
            case .pinned(let id, _, _, _): return id
            case .peek(_, let tabID): return tabID
            case .archived(let id): return id
            }
        }
    }

    public struct Decision: Equatable, Sendable {
        public var restoration: Restoration
        public var remainingPinned: [ClosedPinnedTab]
        public var remainingPeek: ClosedPeek?

        public init(restoration: Restoration, remainingPinned: [ClosedPinnedTab], remainingPeek: ClosedPeek?) {
            self.restoration = restoration
            self.remainingPinned = remainingPinned
            self.remainingPeek = remainingPeek
        }
    }

    /// Determines which closed item to restore and returns the updated state.
    ///
    /// - Parameters:
    ///   - closedPinned: stack of closed pinned tabs, newest first.
    ///   - closedPeek: the last closed Peek, if any.
    ///   - archived: archived tabs, newest first.
    ///   - isPinnedTabAvailable: whether a pinned tab ID still exists in the sidebar.
    ///   - isTabSelected: whether a tab ID is already currently selected in the window.
    public static func next(
        closedPinned: [ClosedPinnedTab],
        closedPeek: ClosedPeek?,
        archived: [ArchivedTab],
        isPinnedTabAvailable: (UUID) -> Bool = { _ in true },
        isTabSelected: (UUID) -> Bool = { _ in false }
    ) -> Decision? {
        var pinned = closedPinned
        // Prune pinned tabs that were removed from the sidebar or are already currently selected.
        while let top = pinned.first {
            if !isPinnedTabAvailable(top.id) || isTabSelected(top.id) {
                pinned.removeFirst()
            } else {
                break
            }
        }

        let pinnedCandidate = pinned.first
        let peekCandidate = closedPeek
        let archivedCandidate = archived.first

        guard pinnedCandidate != nil || peekCandidate != nil || archivedCandidate != nil else {
            return nil
        }

        let pinnedDate = pinnedCandidate?.closedAt ?? .distantPast
        let peekDate = peekCandidate?.closedAt ?? .distantPast
        let archivedDate = archivedCandidate?.archivedAt ?? .distantPast

        if pinnedCandidate != nil && pinnedDate >= peekDate && pinnedDate >= archivedDate {
            let chosen = pinned.removeFirst()
            return Decision(
                restoration: .pinned(id: chosen.id, url: chosen.url, title: chosen.title, paneStates: chosen.paneStates),
                remainingPinned: pinned,
                remainingPeek: closedPeek
            )
        } else if let peek = peekCandidate, peekDate >= archivedDate {
            return Decision(restoration: .peek(url: peek.url, tabID: peek.tabID), remainingPinned: pinned, remainingPeek: nil)
        } else if let arch = archivedCandidate {
            return Decision(restoration: .archived(arch.id), remainingPinned: pinned, remainingPeek: closedPeek)
        }

        return nil
    }
}
