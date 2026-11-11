import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Browse for Me" reads the web and writes the answer page. In Cra it runs on the device's own
/// Apple Intelligence model or not at all: nothing typed or read is sent to an AI service.
enum BrowseForMe {
    /// Whether this device can answer: Apple Intelligence present and switched on.
    static var isAvailable: Bool {
        if LaunchOptions.fakeModel { return true }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }
}
