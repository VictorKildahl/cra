import Foundation

/// The model and native list registry are the only unavailable app dependencies in this harness.
@MainActor
final class TidyTabsService {
    static let shared = TidyTabsService()
    var modelAvailable: Bool { true }
    static var fakeModel: Bool { false }
}

@MainActor
enum SpaceListView {
    static func tidyTitleLayout(for id: UUID, window: UUID) -> TidyTitleLayout? { nil }
}
