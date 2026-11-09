import AppKit
import SwiftUI

@MainActor
enum LiveFolderText {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func lastUpdate(_ live: LiveFolderData) -> String {
        if let error = live.lastError { return status(error, live: live) }
        guard let last = live.lastFetch else { return "Not updated yet" }
        if Date().timeIntervalSince(last) < 60 { return "Updated just now" }
        return "Updated \(relative.localizedString(for: last, relativeTo: Date()))"
    }

    static func refreshHelp(_ live: LiveFolderData?) -> String {
        guard let live, live.lastFetch != nil else { return "Refresh" }
        return "Refresh · \(lastUpdate(live))"
    }

    /// The folder's warning button: Arc's tip, and where a click signs in (nil: it tries again).
    static func warning(_ live: LiveFolderData) -> (help: String, signInURL: String?)? {
        if live.lastError == .notSignedIn, let plugin = live.plugin, let warning = plugin.signInWarning {
            return (warning, plugin.signIn?.url)
        }
        if let error = live.lastError { return ("\(status(error, live: live)). Click to try again.", nil) }
        if let warning = live.plugin?.snapshot?.warning { return (warning, live.plugin?.snapshot?.actions.first?.url) }
        return nil
    }

    static func status(_ error: LiveFolderError, live: LiveFolderData) -> String {
        LiveFolderPluginStore.shared.entry(for: live)?.presentation.statusMessages[error.rawValue] ?? "Failed to update"
    }
}
