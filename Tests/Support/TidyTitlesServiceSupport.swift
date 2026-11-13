import Foundation

/// Only the unused Tidy Tabs animation path needs this UI constant in the service harness.
enum SidebarTidyMetrics {
    static let minimumRun: TimeInterval = 0.9
}

@MainActor
enum SpaceListView {
    static func tidyTitleLayout(for id: UUID, window: UUID) -> TidyTitleLayout? { nil }
}
