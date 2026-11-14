import AppIntents
import Foundation

/// What a shortcut, Siri, Spotlight, the Action button or a home-screen quick action asks the
/// browser to do once the app is in front.
enum LaunchAction: Equatable {
    case search(String?)
    /// A Browse for Me page about the question (a search where the device can't make one).
    case browseForMe(String)
    case voiceSearch
    case changeIcon
    case spaces

    static let notification = Notification.Name("CraLaunchAction")
    /// Set before the browser exists; it picks it up when it appears.
    static var pending: LaunchAction?

    static func perform(_ action: LaunchAction) {
        pending = action
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// A widget's link: `cra://search`, `cra://voice`, `cra://spaces`. Nothing else in the `cra`
    /// scheme does anything, so a page or another app can't steer the browser through it.
    init?(link: URL) {
        guard link.scheme == "cra" else { return nil }
        switch link.host {
        case "search": self = .search(nil)
        case "voice": self = .voiceSearch
        case "spaces": self = .spaces
        default: return nil
        }
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

struct BrowseForMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Browse for Me"
    // App Store processing refuses "Apple" and "iPhone" in an intent's description (ITMS-90626).
    static let description = IntentDescription("Reads pages about your question and makes one page of the answer, on this device. Where it can't, it searches instead.")
    static let openAppWhenRun = true

    @Parameter(title: "Question")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchAction.perform(.browseForMe(query))
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
        AppShortcut(intent: BrowseForMeIntent(), phrases: ["Browse for Me with \(.applicationName)"], shortTitle: "Browse for Me", systemImageName: "sparkles")
        AppShortcut(intent: VoiceSearchIntent(), phrases: ["Voice Search with \(.applicationName)"], shortTitle: "Voice Search", systemImageName: "mic.fill")
    }
}
