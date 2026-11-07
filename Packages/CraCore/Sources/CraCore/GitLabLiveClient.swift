import Foundation

/// GitLab live folders: Arc's GitHub folder (LiveFolderModel) filled from GitLab's REST API, read with the
/// space's own browser session like Arc reads github.com (no token: GitLab accepts its session cookie on
/// GET /api/v4). Works for gitlab.com and self-managed instances, a port or a subpath included.
public enum GitLabLiveClient {
    public static let pageSize = 100

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

    public static func userURL(server: String) -> String { "\(server)/api/v4/user" }

    public static func mergeRequestsURL(server: String, category: GitLabLiveCategory, userID: Int, page: Int) -> String {
        let scope: String
        switch category {
        case .authored: scope = "created_by_me"
        case .review: scope = "all"
        case .assigned: scope = "assigned_to_me"
        }
        var url = URLComponents(string: "\(server)/api/v4/merge_requests")!
        url.queryItems = [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "order_by", value: "created_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(pageSize)"),
            URLQueryItem(name: "page", value: "\(page)"),
        ]
        if category == .review { url.queryItems?.append(URLQueryItem(name: "reviewer_id", value: "\(userID)")) }
        return url.url!.absoluteString
    }

    public static func validate(status: Int, finalURL: String, requestedURL: String) throws {
        if status == 0 { throw LiveFolderError.network }
        if status == 401 { throw LiveFolderError.notSignedIn }
        if status == 429 { throw LiveFolderError.rateLimited }
        guard (200..<300).contains(status) else { throw LiveFolderError.unexpectedPage }
        guard let final = URL(string: finalURL), let requested = URL(string: requestedURL),
              final.scheme == requested.scheme, final.host == requested.host,
              final.port == requested.port, final.path == requested.path else { throw LiveFolderError.notSignedIn }
    }

    public static func userID(in body: String) throws -> Int {
        struct User: Decodable { var id: Int }
        return try decode(User.self, body: body).id
    }

    public static func mergeRequests(in body: String, server: String, category: GitLabLiveCategory) throws -> [LivePullRequest] {
        struct Author: Decodable { var username: String }
        struct MergeRequest: Decodable {
            var iid: Int
            var title: String
            var webUrl: String
            var author: Author?
            var state: String
            var draft: Bool?
            var createdAt: String?
            var updatedAt: String?
        }
        let requests = try decode([MergeRequest].self, body: body)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ text: String?) -> Date? { text.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) } }
        return try requests.map { request in
            guard request.webUrl.hasPrefix(server + "/"),
                  let boundary = request.webUrl.range(of: "/-/merge_requests/", options: .backwards) else {
                throw LiveFolderError.unexpectedPage
            }
            let project = String(request.webUrl[..<boundary.lowerBound].dropFirst(server.count + 1))
            guard let slash = project.lastIndex(of: "/"), request.iid > 0 else { throw LiveFolderError.unexpectedPage }
            var pr = LivePullRequest(owner: String(project[..<slash]), repo: String(project[project.index(after: slash)...]),
                                     number: request.iid, title: request.title, author: request.author?.username,
                                     createdByMe: category == .authored, isAwaitingMyReview: category == .review,
                                     createdAt: date(request.createdAt), updatedAt: date(request.updatedAt))
            pr.webURL = request.webUrl
            switch request.state {
            case "opened": pr.state = request.draft == true ? .draft : .open
            case "merged": pr.state = .merged
            case "closed": pr.state = .closed
            default: throw LiveFolderError.unexpectedPage
            }
            return pr
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, body: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(type, from: Data(body.utf8)) }
        catch { throw LiveFolderError.unexpectedPage }
    }
}
