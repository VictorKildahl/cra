import AppIntents
import Foundation

/// What a shortcut, Siri, Spotlight, the Action button or a home-screen quick action asks the
/// browser to do once the app is in front.
enum LaunchAction: Equatable {
    case search(String?)
    case voiceSearch
    case changeIcon

    static let notification = Notification.Name("CraLaunchAction")
    /// Set before the browser exists; it picks it up when it appears.
    static var pending: LaunchAction?

    static func perform(_ action: LaunchAction) {
        pending = action
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// A home-screen quick action's type, as Info.plist names it.
    init?(shortcutType: String) {
        switch shortcutType {
        case "search": self = .search(nil)
        case "voice-search": self = .voiceSearch
        case "change-icon": self = .changeIcon
        default: return nil
        }
    }
}

struct SearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Search"
    static let description = IntentDescription("Opens Cra ready to search, or searches for what you give it.")
    static let openAppWhenRun = true

    @Parameter(title: "Search for")
    var query: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchAction.perform(.search(query))
        return .result()
    }
}

struct VoiceSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Voice Search"
    static let description = IntentDescription("Opens Cra listening for what to search for.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchAction.perform(.voiceSearch)
        return .result()
    }
}

struct CraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SearchIntent(), phrases: ["Search with \(.applicationName)"], shortTitle: "Search", systemImageName: "magnifyingglass")
        AppShortcut(intent: VoiceSearchIntent(), phrases: ["Voice Search with \(.applicationName)"], shortTitle: "Voice Search", systemImageName: "mic.fill")
    }
}
