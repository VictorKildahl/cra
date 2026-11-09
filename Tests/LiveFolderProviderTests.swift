import Foundation

/// The bundled providers' JavaScript, run by the real CraPluginHost: the cases the Swift GitHub and
/// GitLab clients were tested on before they moved into `resources/live-folder-plugins`, plus each
/// plugin's migration from the folders those clients saved.
enum LiveFolderProviderTests {
    typealias Respond = (LiveFolderPluginRequest) -> LiveFolderPluginResponse

    static func run(executable: URL) throws {
        let github = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/github"))
        let gitlab = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/gitlab"))
        try gitHub(github, executable: executable)
        try gitLab(gitlab, executable: executable)
        print("Bundled providers: GitHub and GitLab cases passed")
    }

    // MARK: Helpers

    private static func invoke(_ package: LiveFolderPluginPackage, _ method: String, input: [String: Any], origins: [String],
                               executable: URL, respond: @escaping Respond = { _ in fatalError("Unexpected session request") }) throws -> Data {
        try LiveFolderPluginProcess.invoke(executable: executable, script: package.script, method: method,
            input: JSONSerialization.data(withJSONObject: input), origins: origins.map { try LiveFolderSessionOrigin($0) },
            fetch: { respond($0) })
    }

    /// A refresh's snapshot, or the error code it threw and the state it kept.
    private static func refresh(_ package: LiveFolderPluginPackage, executable: URL, origins: [String], filters: [String],
                                settings: [String: String] = [:], groups: [String] = [],
                                respond: @escaping Respond) throws -> Result<LiveFolderPluginSnapshot, Failure> {
        do {
            let data = try invoke(package, "refresh", input: ["settings": settings, "filters": filters, "state": [String: String](),
                                                             "groups": groups], origins: origins, executable: executable, respond: respond)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let snapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: data)
            try snapshot.validate()
            return .success(snapshot)
        } catch LiveFolderPluginError.pluginFailed(let message, let state) {
            return .failure(Failure(code: message.replacingOccurrences(of: "Error: ", with: ""), state: state))
        }
    }

    struct Failure: Error, Equatable { var code: String; var state: [String: String] = [:] }

    private static func code<T>(_ result: Result<T, Failure>) -> String? {
        if case .failure(let failure) = result { return failure.code }
        return nil
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: " + message) }
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: GitHub

    private static func gitHub(_ github: LiveFolderPluginPackage, executable: URL) throws {
        let origins = ["https://github.com"]
        func answer(status: Int = 200, finalURL: String? = nil, body: String) -> Respond {
            { LiveFolderPluginResponse(status: status, url: finalURL ?? $0.url, body: body) }
        }
        func read(status: Int = 200, finalURL: String? = nil, body: String, filters: [String] = ["authored"]) throws
            -> Result<LiveFolderPluginSnapshot, Failure> {
            try refresh(github, executable: executable, origins: origins, filters: filters,
                        respond: answer(status: status, finalURL: finalURL, body: body))
        }

        // GitHub's answers that mean "sign in" never read as an empty folder (6 Nov 2026: a lapsed
        // Enterprise Managed User session landed on the enterprise's SSO page and emptied the folder).
        let ssoPage = #"<html><meta name="user-login" content="vkp_jysk"><script type="application/json" id="client-env">{"locale":"en"}</script></html>"#
        let enterprise = try read(finalURL: "https://github.com/enterprises/jysk-emu/sso?return_to=%2Fpulls", body: ssoPage)
        check(enterprise == .failure(Failure(code: "notSignedIn", state: ["enterprise": "jysk-emu"])),
              "a fetch sent to the enterprise's single sign-on needs a sign-in, and the folder learns the enterprise")
        check(code(try read(finalURL: "https://github.com/orgs/jysk-dev/sso", body: ssoPage)) == "notSignedIn",
              "so does an organization's")
        let signIn = json(try invoke(github, "signIn", input: ["settings": [:], "state": ["enterprise": "jysk-emu"]],
                                     origins: [], executable: executable))
        check(signIn["url"] as? String == "https://github.com/enterprises/jysk-emu/sso", "the sign-in goes to the enterprise it learned")
        check(code(try read(finalURL: "https://github.com/dashboard", body: ssoPage)) == "unexpectedPage",
              "an empty page that isn't the pulls or search page is no answer")
        let empty = #"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":[],"pageInfo":{},"error":null}}}"#
        check((try? read(body: empty).get().items.isEmpty) == true, "the pulls page with no results is an empty folder")
        check(code(try read(status: 404, body: #"{"error":"Couldn’t authenticate you"}"#)) == "notSignedIn",
              "signed out, the pulls page can't authenticate you")
        check(code(try read(body: #"{"logged_in":false,"results":[]}"#)) == "notSignedIn", "the search route's logged_in false")
        check(code(try read(finalURL: "https://github.com/login?return_to=%2Fpulls", body: "<html></html>")) == "notSignedIn",
              "a redirect to the login page")
        check(code(try read(status: 429, body: "")) == "rateLimited", "429 is the rate limit")
        check(code(try read(status: 403, body: "API rate limit exceeded")) == "rateLimited", "so is a 403 that says so")
        check(code(try read(status: 0, body: "")) == "network", "no answer is the network")
        check(code(try read(status: 500, body: "{}")) == "unexpectedPage", "a server error is no answer")
        let presentation = try JSONDecoder().decode(LiveFolderPluginPresentation.self, from: invoke(github, "describe", input: [:],
                                                                                                   origins: [], executable: executable))
        check(presentation.statusMessages == ["notSignedIn": "Not signed in to GitHub", "rateLimited": "GitHub rate limit exceeded",
                                               "unexpectedPage": "Failed to update: unexpected GitHub response",
                                               "network": "Failed to update: GitHub can’t be reached"], "the folder menu's status lines")

        // Each filter is one search, with Dia's terms; the pulls page first, GitHub's search page when
        // that gives nothing it can read.
        for (filter, term) in [("authored", "author:@me"), ("review", "user-review-requested:@me"), ("teamReview", "review-requested:@me")] {
            var urls: [String] = []
            _ = try refresh(github, executable: executable, origins: origins, filters: [filter]) { request in
                urls.append(request.url)
                check(request.headers?["GitHub-Verified-Fetch"] == "true", "GitHub's JSON headers are sent")
                return LiveFolderPluginResponse(status: 200, url: request.url, body: empty)
            }
            let query = "is:pr is:open archived:false \(term) sort:updated-desc"
            check(urls.count == 2 && URLComponents(string: urls[0])?.path == "/pulls"
                  && URLComponents(string: urls[0])?.queryItems?.first?.value == query
                  && URLComponents(string: urls[1])?.path == "/search", "\(filter) searches \(query), then the search page")
        }

        // One list from the searches: newest first, each pull request once, your own named after you.
        let authored = #"{"viewer":{"login":"alice"},"results":[{"number":1,"title":"Old","repoNameWithOwner":"team/app","isDraft":false,"createdAt":"2026-11-01T12:00:00Z"},{"number":2,"title":"New","repoNameWithOwner":"team/app","isDraft":true,"createdAt":"2026-11-06T12:00:00Z"}]}"#
        let review = #"{"results":[{"number":2,"title":"New","repoNameWithOwner":"team/app","isDraft":true,"author":{"login":"bob"},"createdAt":"2026-11-06T12:00:00Z"},{"number":3,"title":"Middle","repository":{"nameWithOwner":"other/lib"},"isDraft":false,"author":{"login":"carol"},"createdAt":"2026-11-03T12:00:00Z"}]}"#
        let merged = try refresh(github, executable: executable, origins: origins, filters: ["authored", "review"]) { request in
            let isAuthored = request.url.contains("author%3A%40me")
            return LiveFolderPluginResponse(status: 200, url: request.url, body: isAuthored ? authored : review)
        }.get()
        check(merged.items.map(\.title) == ["New", "Middle", "Old"], "newest first, each pull request once")
        check(merged.items.map(\.subtitle) == ["alice", "carol", "alice"], "your own pull requests are named after you")
        check(merged.items.map(\.group) == ["team/app", "other/lib", "team/app"], "grouped by repository")
        check(merged.items.first?.url == "https://github.com/team/app/pull/2", "the pull request's address")

        // A partial update would empty the folder of whatever the failed search found.
        let partial = try refresh(github, executable: executable, origins: origins, filters: ["authored", "review"]) { request in
            request.url.contains("author%3A%40me")
                ? LiveFolderPluginResponse(status: 200, url: request.url, body: authored)
                : LiveFolderPluginResponse(status: 500, url: request.url, body: "")
        }
        check(code(partial) == "unexpectedPage", "one failed search fails the refresh")
        let signedOut = try refresh(github, executable: executable, origins: origins, filters: ["authored", "review", "teamReview"]) { request in
            request.url.contains("author%3A%40me")
                ? LiveFolderPluginResponse(status: 500, url: request.url, body: "")
                : LiveFolderPluginResponse(status: 401, url: request.url, body: "")
        }
        check(code(signedOut) == "notSignedIn", "a sign-in wins over another failure")

        // The classic list and GitHub's embedded React data, when the JSON route sends a page.
        let embedded = #"<meta name="user-login" content="alice"><script type="application/json" data-target="react-app.embeddedData">{"payload":{"results":[{"number":9,"title":"Embedded <em>fix</em>","repository":{"name":"app","owner":{"login":"team"}},"isDraft":false}]}}</script>"#
        check((try? read(body: embedded).get().items.map(\.title)) == ["Embedded fix"], "embedded React data")
        let classic = #"<meta name="user-login" content="alice"><div class="js-issue-row"><a href="/team/app/pull/7" class="markdown-title">Fix &amp; test &#39;it&#39;</a> opened by <a data-hovercard-type="user" href="/bob">bob</a><relative-time datetime="2026-11-05T10:00:00Z"></relative-time></div>"#
        let row = try read(body: classic).get().items.first
        check(row?.title == "Fix & test 'it'" && row?.subtitle == "bob" && row?.createdAt != nil, "the classic issue list")
        check(code(try read(body: #"<meta name="user-login" content=""><div>Sign in</div>"#)) == "notSignedIn",
              "a logged-out page has an empty user-login")

        // Organizations whose pull requests wait for SSO keep the ones already shown.
        let sso = try refresh(github, executable: executable, origins: origins, filters: ["authored"],
                              groups: ["protected/app", "other/app"]) { request in
            LiveFolderPluginResponse(status: 200, url: request.url,
                                     body: #"{"protected_org_logins":["protected"],"results":[],"x":"/orgs/second/sso"}"#)
        }.get()
        check(sso.preservedGroups == ["protected/app"] && sso.warning != nil, "SSO keeps the protected organization's rows")
        check(sso.actions.map(\.url) == ["https://github.com/orgs/protected/sso", "https://github.com/orgs/second/sso"],
              "one SSO sign-in per organization")

        // A pull request created or reviewed in a tab refreshes the folder (Dia's triggers), and an
        // enterprise SSO page teaches the folder where to sign in.
        func pageChanged(_ url: String, from previous: String) throws -> [String: Any] {
            json(try invoke(github, "pageChanged", input: ["url": url, "previousURL": previous, "state": [:], "settings": [:]],
                            origins: [], executable: executable))
        }
        check(try pageChanged("https://github.com/team/app/pull/4", from: "https://github.com/team/app/compare/main...fix")["refreshAfter"]
              as? [Double] == [5, 45], "creating a pull request refreshes")
        check(try pageChanged("https://github.com/team/app/pull/4#pullrequestreview-12", from: "https://github.com/team/app/pull/4")["refreshAfter"]
              as? [Double] == [5, 45], "submitting a review refreshes")
        check(try pageChanged("https://github.com/team/app/pull/4", from: "https://github.com/team/app/pull/3")["refreshAfter"]
              as? [Double] == [], "moving between pull requests doesn't")
        check(try pageChanged("https://github.com/enterprises/jysk-emu/sso", from: "")["state"] as? [String: String] == ["enterprise": "jysk-emu"],
              "the enterprise's SSO page is learned")

        // Folders saved by the Swift client become plugin folders with the same filters and enterprise.
        var legacy = LiveFolderData()
        legacy.filter.attributes = [.authored, .teamReviewRequests]
        legacy.enterprise = "jysk-emu"
        let migrated = json(try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "migrate",
            input: JSONEncoder().encode(legacy), origins: [], fetch: { _ in fatalError("Migration requested a session") }))
        check(migrated["filters"] as? [String] == ["authored", "teamReview"], "GitHub filters migrate")
        check(migrated["state"] as? [String: String] == ["enterprise": "jysk-emu"], "the enterprise migrates")
        let arcDefault = json(try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "migrate",
            input: JSONEncoder().encode(LiveFolderData()), origins: [], fetch: { _ in fatalError() }))
        check(arcDefault["filters"] as? [String] == ["authored", "review", "teamReview"], "Arc's default mask is all three")
    }

    // MARK: GitLab

    private static func gitLab(_ gitlab: LiveFolderPluginPackage, executable: URL) throws {
        let server = "https://git.example.com:8443/gitlab"
        let origins = ["https://git.example.com:8443"]
        let user = #"{"id":42}"#
        func mergeRequest(_ iid: Int, project: String = "company/team/app", host: String = server, state: String = "opened",
                     created: String = "2026-11-06T12:00:00.123Z") -> [String: Any] {
            ["iid": iid, "title": "MR \(iid)", "web_url": "\(host)/\(project)/-/merge_requests/\(iid)",
             "author": ["username": "alex"], "state": state, "draft": true, "created_at": created]
        }
        func body(_ rows: [[String: Any]]) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
        }
        func refresh(filters: [String] = ["authored"], respond: @escaping Respond) throws -> Result<LiveFolderPluginSnapshot, Failure> {
            try Self.refresh(gitlab, executable: executable, origins: origins, filters: filters, settings: ["server": server], respond: respond)
        }

        // A self-managed instance keeps its port and subpath; each filter is its own query.
        var queries: [String: [String: String]] = [:]
        let nested = try refresh(filters: ["authored", "review", "assigned"]) { request in
            let url = URLComponents(string: request.url)!
            if url.path == "/gitlab/api/v4/user" { return LiveFolderPluginResponse(status: 200, url: request.url, body: user) }
            check(url.path == "/gitlab/api/v4/merge_requests" && url.port == 8443, "merge requests come from the instance's API")
            let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            queries[query["scope"]!] = query
            return LiveFolderPluginResponse(status: 200, url: request.url, body: query["scope"] == "all" ? body([mergeRequest(17)]) : "[]")
        }.get()
        check(Set(queries.keys) == ["created_by_me", "all", "assigned_to_me"], "one query per filter")
        check(queries["all"]?["reviewer_id"] == "42" && queries["created_by_me"]?["reviewer_id"] == nil, "review requests ask for the signed-in user")
        check(queries.values.allSatisfy { $0["state"] == "opened" && $0["per_page"] == "100" && $0["page"] == "1" }, "open ones, a page at a time")
        check(nested.items.first?.group == "company/team/app" && nested.items.first?.subtitle == "alex", "nested groups and the author")
        check(nested.items.first?.url == server + "/company/team/app/-/merge_requests/17" && nested.items.first?.createdAt != nil,
              "the merge request's own address and date")

        // A full page asks for the next one; a merge request from another instance is no answer.
        var pages: [String] = []
        let paged = try refresh { request in
            if request.url.hasSuffix("/user") { return LiveFolderPluginResponse(status: 200, url: request.url, body: user) }
            let page = URLComponents(string: request.url)!.queryItems!.first { $0.name == "page" }!.value!
            pages.append(page)
            return LiveFolderPluginResponse(status: 200, url: request.url,
                body: body(page == "1" ? (1...100).map { mergeRequest($0) } : [mergeRequest(101)]))
        }.get()
        check(pages == ["1", "2"] && paged.items.count == 101, "paging continues after a full page")
        check(code(try refresh { request in
            LiveFolderPluginResponse(status: 200, url: request.url,
                body: request.url.hasSuffix("/user") ? user : body([mergeRequest(1, host: "https://other.example.com")]))
        }) == "unexpectedPage", "a merge request from another instance")

        // Failures never become an empty folder.
        for (status, expected) in [(0, "network"), (401, "notSignedIn"), (403, "unexpectedPage"), (429, "rateLimited"), (500, "unexpectedPage")] {
            check(code(try refresh { LiveFolderPluginResponse(status: status, url: $0.url, body: "") }) == expected, "status \(status)")
        }
        check(code(try refresh { _ in LiveFolderPluginResponse(status: 200, url: "https://git.example.com:8443/users/sign_in", body: user) })
              == "notSignedIn", "sent to the sign-in page")
        for wrong in ["<html>Sign in</html>", #"{"message":"403 Forbidden"}"#, #"[{"iid":1}]"#] {
            check(code(try refresh { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/user") ? user : wrong)
            }) == "unexpectedPage", "unreadable merge requests: \(wrong)")
        }
        check((try? refresh { request in
            LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/user") ? user : "[]")
        }.get().items.isEmpty) == true, "no merge requests is an empty folder")

        // A GitLab folder saved by the Swift client keeps its instance and filters.
        var legacy = LiveFolderData()
        legacy.source = .gitlab
        legacy.serverURL = server
        legacy.filter.attributes = [.reviewRequests, .assigned]
        let migrated = json(try LiveFolderPluginProcess.invoke(executable: executable, script: gitlab.script, method: "migrate",
            input: JSONEncoder().encode(legacy), origins: [], fetch: { _ in fatalError("Migration requested a session") }))
        check(migrated["settings"] as? [String: String] == ["server": server], "the instance migrates")
        check(migrated["filters"] as? [String] == ["review", "assigned"], "GitLab filters migrate")
        let signIn = json(try invoke(gitlab, "signIn", input: ["settings": ["server": server], "state": [:]], origins: [], executable: executable))
        check(signIn["url"] as? String == server + "/users/sign_in", "sign in on the instance")
    }
}
