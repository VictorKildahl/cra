import AppKit
import SwiftUI

// Shared by the live folder's rows and menu (SidebarRowViews, SidebarMenus): GitHub's mark and
// the folder's status lines.

/// GitHub's mark (Primer Octicons mark-github, MIT) for the live folder and its tabs (Arc: the
/// GithubFavicon asset and customInfo.iconType "github"). github.com's own favicon is no stand-in:
/// Cra caches favicons per host and GitHub swaps in a red ✕ while a pull request's checks fail.
enum GitHubMark {
    static let image: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>"#
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

/// GitLab's tanuki in one colour, tinted like GitHubMark: Arc draws its GitHub folder's mark in the
/// folder's ink, so the GitLab folder does the same rather than show the full-colour logo.
enum GitLabMark {
    static let image: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 25 24" width="16" height="16"><path d="m24.507 9.5-.034-.09L21.082.562a.896.896 0 0 0-1.694.091l-2.29 7.01H7.825L5.535.653a.898.898 0 0 0-1.694-.09L.451 9.411.416 9.5a6.297 6.297 0 0 0 2.09 7.278l.012.01.03.022 5.16 3.867 2.56 1.935 1.554 1.176a1.051 1.051 0 0 0 1.268 0l1.555-1.176 2.56-1.935 5.197-3.89.014-.01A6.297 6.297 0 0 0 24.507 9.5Z"/></svg>"#
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

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
