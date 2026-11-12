import Foundation

@MainActor final class TidyTabsService {
    static let shared = TidyTabsService()
    static let fakeModel = false
    let modelAvailable = true
}
enum CraLog { static func note(_ message: String) {} }
