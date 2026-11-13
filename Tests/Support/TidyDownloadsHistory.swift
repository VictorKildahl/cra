import Foundation

/// CEF and Quick Look belong to the app; lifecycle checks assert real files and the service card.
@MainActor
final class DownloadHistory {
    static let shared = DownloadHistory()
    func move(from: String, to: String) {}
}

/// Only the unused Tidy Tabs animation path needs this UI constant in the service harness.
enum SidebarTidyMetrics {
    static let minimumRun: TimeInterval = 0.9
}
