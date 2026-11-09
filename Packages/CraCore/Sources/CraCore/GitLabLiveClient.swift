import Foundation

/// GitLab live folders: Arc's GitHub folder (LiveFolderModel) filled from GitLab's REST API, read with the
/// space's own browser session like Arc reads github.com (no token: GitLab accepts its session cookie on
/// GET /api/v4). Works for gitlab.com and self-managed instances, a port or a subpath included.
public enum GitLabLiveClient {

    /// The instance's base URL, normalized (lowercase scheme and host, no default port, no trailing slash),
    /// or nil for anything that isn't a plain http(s) address (credentials, a query or a fragment).
    public static func serverURL(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              var url = URLComponents(string: text.contains("://") ? text : "https://\(text)"),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        url.scheme = url.scheme?.lowercased()
        url.host = host.lowercased()
        if (url.scheme == "https" && url.port == 443) || (url.scheme == "http" && url.port == 80) { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        return url.url?.absoluteString
    }

    /// A new folder's name, as Arc names its GitHub folder "Pull Requests".
    public static let folderTitle = "Merge Requests"

    /// The instance as the Live Folders menu names it: "gitlab.com", "git.example.com:8443/gitlab".
    public static func serverLabel(_ server: String) -> String {
        let normalized = serverURL(server) ?? server
        return normalized.components(separatedBy: "://").last ?? normalized
    }

}
