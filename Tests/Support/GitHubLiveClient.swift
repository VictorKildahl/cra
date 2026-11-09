import Foundation

/// Reads pull requests from github.com with the browser's own GitHub session: no token, no
/// OAuth app. Arc and Dia do it this way (ARCClients/GitHubClient, shared by both): a request
/// made by Chromium with the profile's cookies for `github.com/pulls?q=<search>`, asking for
/// GitHub's JSON (headers GitHub-Verified-Fetch and X-Requested-With) and reading HTML when
/// that's what comes back. "Not signed in to GitHub" is a redirect to /login.
enum GitHubLiveClient {
    struct Page: Equatable {
        var pullRequests: [LivePullRequest] = []
        /// The signed-in user (meta user-login / the payload's viewer), when the page says.
        var viewer: String?
        var ssoOrganizations: [String] = []
    }

    enum Failure: Error, Equatable {
        case notSignedIn, rateLimited, unexpectedPage, network

        var asLiveFolderError: LiveFolderError {
            switch self {
            case .notSignedIn: return .notSignedIn
            case .rateLimited: return .rateLimited
            case .unexpectedPage: return .unexpectedPage
            case .network: return .network
            }
        }
    }

    /// Dia's search terms for its Pull Requests folder (GitHubClient: "is:pr is:open …").
    static func query(for attribute: GitHubLiveFilter.Attributes) -> String {
        let who: String
        switch attribute {
        case .authored: who = "author:@me"
        case .reviewRequests: who = "user-review-requested:@me"
        default: who = "review-requested:@me"
        }
        return "is:pr is:open archived:false \(who) sort:updated-desc"
    }

    static func pullsURL(query: String) -> String {
        var c = URLComponents(string: "https://github.com/pulls")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url!.absoluteString
    }

    static func searchURL(query: String) -> String {
        var c = URLComponents(string: "https://github.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "pullrequests")]
        return c.url!.absoluteString
    }

    static let jsonHeaders = [
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "GitHub-Verified-Fetch": "true",
    ]

    // MARK: Responses

    /// Turns one response into pull requests, or says why it can't.
    static func read(status: Int, finalURL: String, body: String) -> Result<Page, Failure> {
        if status == 0 { return .failure(.network) }
        let finalPath = URL(string: finalURL)?.path
        if let path = finalPath, path == "/login" || path.hasPrefix("/session") || isSSOPath(path) {
            return .failure(.notSignedIn)
        }
        if status == 429 || (status == 403 && body.localizedCaseInsensitiveContains("rate limit")) { return .failure(.rateLimited) }
        // Signed out, the pulls route answers 404 {"error":"Couldn’t authenticate you"} and the
        // search route an empty result with "logged_in": false (both seen 27 Oct 2026).
        if status == 401 || (body.count < 2000 && body.localizedCaseInsensitiveContains("authenticate you")) { return .failure(.notSignedIn) }
        if body.contains("\"logged_in\":false") { return .failure(.notSignedIn) }
        guard (200..<300).contains(status) else { return .failure(.unexpectedPage) }
        // Sent somewhere other than the pulls or search page: no pull requests there is no answer,
        // and reading it as one would empty the folder.
        let elsewhere = finalPath.map { !$0.isEmpty && !$0.hasPrefix("/pulls") && !$0.hasPrefix("/search") } ?? false

        var page = Page()
        page.ssoOrganizations = ssoOrganizations(in: body)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else { return .failure(.unexpectedPage) }
            page.viewer = viewer(inJSON: json)
            page.pullRequests = pullRequests(inJSON: json)
            if page.pullRequests.isEmpty && elsewhere { return .failure(.unexpectedPage) }
            return .success(page)
        }
        // An HTML page: logged out pages carry an empty user-login.
        page.viewer = metaContent("user-login", in: body) ?? metaContent("octolytics-actor-login", in: body)
        if page.viewer?.isEmpty ?? true, body.contains("name=\"user-login\"") { return .failure(.notSignedIn) }
        var found: [LivePullRequest] = []
        var sawPayload = false
        for blob in embeddedJSON(in: body) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(blob.utf8)) else { continue }
            sawPayload = true
            if page.viewer?.isEmpty ?? true { page.viewer = viewer(inJSON: json) }
            found += pullRequests(inJSON: json)
        }
        if found.isEmpty { found = pullRequests(inHTML: body) }
        page.pullRequests = unique(found)
        if page.pullRequests.isEmpty && (elsewhere || (!sawPayload && !body.contains("blankslate"))) { return .failure(.unexpectedPage) }
        return .success(page)
    }

    // MARK: JSON

    /// Finds pull request objects anywhere in a payload: GitHub's React routes (pulls dashboard,
    /// search) and GraphQL-shaped data name the same facts with different keys.
    static func pullRequests(inJSON root: Any) -> [LivePullRequest] {
        var out: [LivePullRequest] = []
        func walk(_ v: Any, depth: Int) {
            guard depth < 40 else { return }
            if let d = v as? [String: Any] {
                if let pr = pullRequest(from: d) { out.append(pr); return }
                for (_, child) in d { walk(child, depth: depth + 1) }
            } else if let a = v as? [Any] {
                for child in a { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return unique(out)
    }

    static func pullRequest(from d: [String: Any]) -> LivePullRequest? {
        let typename = (d["__typename"] as? String) ?? (d["type"] as? String) ?? ""
        if !typename.isEmpty, typename != "PullRequest", !typename.lowercased().contains("pull") { return nil }
        guard let number = int(d["number"]) ?? int(d["num"]) else { return nil }
        guard let rawTitle = (d["title"] as? String) ?? (d["hl_title"] as? String) ?? (d["titleHTML"] as? String) else { return nil }
        let link = ["url", "permalink", "html_url", "resourcePath", "path", "href"].lazy.compactMap { d[$0] as? String }.first
        var owner: String?, repo: String?
        if let link, let m = pullPath(link), m.number == number { owner = m.owner; repo = m.repo }
        if owner == nil, let r = repository(d["repository"] ?? d["repo"] ?? d["repoNameWithOwner"] ?? d["repository_nwo"]) {
            owner = r.owner; repo = r.repo
        }
        guard let owner, let repo else { return nil }
        // Search results carry no link: issue.issue.pull_request_id, merged and reviewable_state
        // say it's a pull request (blackbirdSearchRoute, 27 Oct 2026).
        let issue = (d["issue"] as? [String: Any])?["issue"] as? [String: Any]
        let isPull = link.map { $0.contains("/pull/") } ?? false || typename == "PullRequest"
            || d["isDraft"] != nil || d["is_draft"] != nil || d["reviewDecision"] != nil || d["pull_request"] != nil
            || issue?["pull_request_id"] != nil || d["reviewable_state"] != nil || d["merged"] != nil
        guard isPull || d["num"] != nil else { return nil }

        var pr = LivePullRequest(owner: owner, repo: repo, number: number, title: plainText(rawTitle))
        pr.author = login(d["author"]) ?? login(d["user"]) ?? (d["author_name"] as? String) ?? (d["authorLogin"] as? String)
        let state = ((d["state"] as? String) ?? "open").lowercased()
        if state == "merged" || (d["merged"] as? Bool) == true || (d["mergedAt"] as? String) != nil || (d["merged_at"] as? String) != nil {
            pr.state = .merged
        } else if state == "closed" {
            pr.state = .closed
        } else if state == "draft" || (d["isDraft"] as? Bool) == true || (d["is_draft"] as? Bool) == true || (d["draft"] as? Bool) == true {
            pr.state = .draft
        }
        pr.createdAt = date(d["createdAt"] ?? d["created_at"] ?? d["created"])
        pr.updatedAt = date(d["updatedAt"] ?? d["updated_at"] ?? d["updated"])
        return pr
    }

    static func viewer(inJSON root: Any) -> String? {
        var found: String?
        func walk(_ v: Any, depth: Int) {
            guard found == nil, depth < 12 else { return }
            if let d = v as? [String: Any] {
                for key in ["viewer", "currentUser", "current_user"] {
                    if let l = login(d[key]) { found = l; return }
                }
                if let l = (d["current_user_login"] as? String) ?? (d["viewerLogin"] as? String), !l.isEmpty { found = l; return }
                for (_, child) in d { walk(child, depth: depth + 1) }
            } else if let a = v as? [Any] {
                for child in a { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return found
    }

    // MARK: HTML

    /// The JSON GitHub's React pages embed (react-app / react-partial embeddedData).
    static func embeddedJSON(in html: String) -> [String] {
        matches(#"<script[^>]*type="application/json"[^>]*>([\s\S]*?)</script>"#, in: html).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    /// The classic issue list (`.js-issue-row`): a pull request link titled with the
    /// pull request, the author's hovercard link after "opened … by".
    static func pullRequests(inHTML html: String) -> [LivePullRequest] {
        let chunks = html.components(separatedBy: "js-issue-row")
        var out: [LivePullRequest] = []
        for chunk in chunks.count > 1 ? Array(chunks.dropFirst()) : chunks {
            for m in matches(#"<a\b([^>]*)>([\s\S]*?)</a>"#, in: chunk) where m.count > 2 {
                let attrs = m[1]
                guard let href = attribute("href", in: attrs), let p = pullPath(href), href.hasSuffix("/pull/\(p.number)") else { continue }
                let hovercard = attribute("data-hovercard-type", in: attrs)
                guard hovercard == "pull_request" || attrs.contains("markdown-title") || attrs.contains("js-navigation-open") else { continue }
                let title = plainText(m[2])
                guard !title.isEmpty else { continue }
                var pr = LivePullRequest(owner: p.owner, repo: p.repo, number: p.number, title: title)
                if let by = matches(#"<a\b[^>]*data-hovercard-type="user"[^>]*>([\s\S]*?)</a>"#, in: chunk).first, by.count > 1 {
                    pr.author = plainText(by[1])
                }
                if chunk.contains("octicon-git-pull-request-draft") { pr.state = .draft }
                if let t = matches(#"<relative-time[^>]*datetime="([^"]+)""#, in: chunk).first, t.count > 1 { pr.createdAt = date(t[1]) }
                out.append(pr)
                if chunks.count > 1 { break }
            }
        }
        return unique(out)
    }

    /// Orgs whose pull requests stay hidden until a SAML sign-in: links to /orgs/<org>/sso, and the
    /// search route's `protected_org_logins` (orgs it left out of the results).
    static func ssoOrganizations(in body: String) -> [String] {
        var seen: [String] = []
        var found = matches(#"/orgs/([A-Za-z0-9_.-]+)/sso"#, in: body).compactMap { $0.count > 1 ? $0[1] : nil }
        for list in matches(#""protected_org_logins"\s*:\s*\[([^\]]*)\]"#, in: body) where list.count > 1 {
            found += matches(#""([A-Za-z0-9_.-]+)""#, in: list[1]).compactMap { $0.count > 1 ? $0[1] : nil }
        }
        for org in found where !seen.contains(org) { seen.append(org) }
        return seen
    }

    // MARK: Helpers

    /// GitHub's single sign-on pages. A lapsed Enterprise Managed User session (Victor's JYSK
    /// account, 6 Nov 2026) is sent to /enterprises/<slug>/sso, a signed-in page with the user's
    /// login and React data, which read as "no pull requests" until this check.
    static func isSSOPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.count == 3 && (parts[0] == "enterprises" || parts[0] == "orgs") && parts[2] == "sso"
    }

    /// The enterprise a link to its single sign-on names (github.com/enterprises/<slug>/sso).
    static func enterprise(inSSO url: String) -> String? {
        guard let u = URL(string: url), u.host == "github.com", isSSOPath(u.path) else { return nil }
        let parts = u.path.split(separator: "/")
        return parts[0] == "enterprises" ? String(parts[1]) : nil
    }

    static func pullPath(_ link: String) -> (owner: String, repo: String, number: Int)? {
        guard let m = matches(#"(?:^|github\.com)/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/(\d+)"#, in: link).first, m.count > 3,
              let n = Int(m[3]) else { return nil }
        return (m[1], m[2], n)
    }

    private static func repository(_ v: Any?) -> (owner: String, repo: String)? {
        if let s = v as? String {
            let parts = s.split(separator: "/")
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
        guard let d = v as? [String: Any] else { return nil }
        if let inner = d["repository"] { return repository(inner) }
        if let nwo = d["nameWithOwner"] as? String ?? d["name_with_owner"] as? String ?? d["full_name"] as? String { return repository(nwo) }
        guard let name = d["name"] as? String else { return nil }
        let owner = login(d["owner"]) ?? (d["owner"] as? String) ?? (d["owner_login"] as? String) ?? (d["ownerLogin"] as? String)
        return owner.map { ($0, name) }
    }

    private static func login(_ v: Any?) -> String? {
        guard let d = v as? [String: Any] else { return nil }
        // The signed-in pulls dashboard sends author {displayLogin, displayName} (27 Oct 2026).
        let l = (d["login"] as? String) ?? (d["displayLogin"] as? String) ?? (d["display_login"] as? String)
        return l?.isEmpty == false ? l : nil
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(_ v: Any?) -> Date? {
        if let s = v as? String { return iso.date(from: s) ?? isoFull.date(from: s) }
        if let n = v as? Double { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        if let n = v as? Int { return Date(timeIntervalSince1970: Double(n) > 1e11 ? Double(n) / 1000 : Double(n)) }
        return nil
    }

    static func metaContent(_ name: String, in html: String) -> String? {
        for m in matches(#"<meta\b[^>]*>"#, in: html) {
            guard attribute("name", in: m[0]) == name else { continue }
            return attribute("content", in: m[0]).map(decodeEntities)
        }
        return nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        matches(#"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name) + #"="([^"]*)""#, in: tag).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    /// Text of a title that may hold markup (search highlights <em>, emoji spans) and entities.
    static func plainText(_ s: String) -> String {
        let stripped = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(stripped).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (k, v) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        for m in matches(#"&#(x?)([0-9a-fA-F]+);"#, in: out) where m.count > 2 {
            if let code = UInt32(m[2], radix: m[1].isEmpty ? 10 : 16), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func matches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        }
    }

    private static func unique(_ prs: [LivePullRequest]) -> [LivePullRequest] {
        var seen = Set<String>()
        return prs.filter { seen.insert($0.url.lowercased()).inserted }
    }
}
