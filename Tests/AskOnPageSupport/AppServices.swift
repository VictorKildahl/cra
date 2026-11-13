import Foundation
import Observation

@MainActor @Observable final class TidyTabsService {
    static let shared = TidyTabsService()
    static let fakeModel = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] == "1"
    var modelAvailable = true
    var currentModelAvailable: Bool { modelAvailable }
}

@MainActor final class SidebarStore {}
