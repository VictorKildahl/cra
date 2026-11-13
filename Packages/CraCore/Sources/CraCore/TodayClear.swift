import Foundation

/// Arc's Clear on Today (the button on the Today divider and ⇧⌘K, "Clear unselected Today
/// tabs" in Arc's strings): every Today row is archived except one holding a tab that a window
/// has on screen or that is playing sound. A split or tab group stays whole when one of its tabs
/// stays (GitHub #406).
public enum TodayClear {
    /// A Today row and its tabs: the tab itself, or every pane of a split or tab group.
    public struct Row: Equatable, Sendable {
        public let id: UUID
        public let tabs: [UUID]
        public init(id: UUID, tabs: [UUID]) {
            self.id = id
            self.tabs = tabs
        }
    }

    /// The tabs Clear archives, in sidebar order.
    public static func archived(_ rows: [Row], selected: Set<UUID>, playing: Set<UUID>) -> [UUID] {
        let kept = selected.union(playing)
        return rows.filter { $0.tabs.allSatisfy { !kept.contains($0) } }.flatMap(\.tabs)
    }
}
