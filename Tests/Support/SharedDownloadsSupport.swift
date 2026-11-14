import Foundation

@MainActor final class SidebarStore {
    struct Settings {
        var tidyDownloads = true
        func downloadLocation(profileID: UUID?) -> DownloadLocation { DownloadLocation() }
    }
    struct Profile { var id: UUID; var directoryName: String }
    var settings = Settings()
    var profiles: [Profile] = []
}
@MainActor final class TidyTabsService {
    static let shared = TidyTabsService()
    static let fakeModel = false
    let modelAvailable = false
}
enum CraLog { static func note(_ message: String) {} }
// Persistence is outside this regression; all observed history mutations are production code.
final class JSONStore<Value: Codable> {
    init(_ name: String) {}
    func load(or fallback: () -> Value) -> Value { fallback() }
    func save(_ value: Value) {}
}
