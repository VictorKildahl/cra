import Foundation

/// Only the unused Tidy Tabs animation path needs this UI constant in the service harness.
enum SidebarTidyMetrics {
    static let minimumRun: TimeInterval = 0.9
}

@MainActor
final class SpaceListView {
    struct DropUI {
        var windowID: UUID
        var picked: [UUID] = []
        func group(for id: UUID, in store: SidebarStore) -> [UUID] { picked.isEmpty ? [id] : picked }
    }
    let store: SidebarStore
    var ui: DropUI
    init(store: SidebarStore, windowID: UUID, picked: [UUID] = []) {
        self.store = store
        ui = DropUI(windowID: windowID, picked: picked)
    }

    static func tidyTitleLayout(for id: UUID, window: UUID) -> TidyTitleLayout? { nil }
}
