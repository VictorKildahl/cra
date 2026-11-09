import AppKit
import SwiftUI

enum LiveFolderText {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func lastUpdate(_ live: LiveFolderData) -> String {
        if let error = live.lastError { return status(error, source: live.source) }
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
        switch live.lastError {
        case .notSignedIn?: return ("Sign back in to \(live.source.title).", live.signInURL)
        case let error?: return ("\(status(error, source: live.source)). Click to try again.", nil)
        case nil:
            guard let org = live.ssoOrganizations.first else { return nil }
            return ("Login with SSO to unlock this folder", "https://github.com/orgs/\(org)/sso")
        }
    }

    static func status(_ error: LiveFolderError, source: LiveFolderSource = .github) -> String {
        switch error {
        case .notSignedIn: return "Not signed in to \(source.title)"
        case .rateLimited: return "\(source.title) rate limit exceeded"
        case .unexpectedPage: return "Failed to update: unexpected \(source.title) response"
        case .network: return "Failed to update: \(source.title) can’t be reached"
        }
    }
}
