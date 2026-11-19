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
        try gitHubOpenOnly(github, executable: executable)
        try gitHubOpenOnlyEdges(github, executable: executable)
        try gitHubMergedSinceLastRefresh(github, executable: executable)
        try gitHubSSOKey(github, executable: executable)
        try gitHubSSOBesideOtherPullRequests(github, executable: executable)
        try gitLab(gitlab, executable: executable)
        let azure = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/azure-devops"))
        try azureDevOps(azure, executable: executable)
        print("Bundled providers: GitHub, GitLab and Azure DevOps cases passed")
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

    // promise: #523
    /// The folder holds open pull requests only, whatever GitHub's answer carries besides them: a merged
    /// or closed one in any of the shapes the reader accepts is left out, so it leaves the folder like a
    /// pull request that dropped out of the search (GitHub #523: merged pull requests showed in the folder).
    private static func gitHubOpenOnly(_ github: LiveFolderPluginPackage, executable: URL) throws {
        func titles(_ body: String) throws -> [String] {
            try refresh(github, executable: executable, origins: ["https://github.com"], filters: ["authored"]) { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: body)
            }.get().items.map(\.title)
        }
        // The signed-in pulls route: state OPEN, MERGED or CLOSED, and mergedAt.
        let pulls = #"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":["#
            + #"{"number":1,"title":"Open","repoNameWithOwner":"team/app","state":"OPEN","isDraft":false,"mergedAt":null,"createdAt":"2026-11-06T12:00:00Z"},"#
            + #"{"number":2,"title":"Draft","repoNameWithOwner":"team/app","state":"OPEN","isDraft":true,"mergedAt":null,"createdAt":"2026-11-05T12:00:00Z"},"#
            + #"{"number":3,"title":"Merged","repoNameWithOwner":"team/app","state":"MERGED","isDraft":false,"mergedAt":"2026-11-04T11:28:26+01:00","createdAt":"2026-11-04T10:00:00Z"},"#
            + #"{"number":4,"title":"Closed","repoNameWithOwner":"team/app","state":"CLOSED","isDraft":false,"mergedAt":null,"createdAt":"2026-11-03T12:00:00Z"},"#
            + #"{"number":5,"title":"Merged, no state","repoNameWithOwner":"team/app","isDraft":false,"mergedAt":"2026-11-02T12:00:00Z","createdAt":"2026-11-02T10:00:00Z"}"#
            + #"],"pageInfo":{},"error":null}}}"#
        check(try titles(pulls) == ["Open", "Draft"], "the pulls route keeps open and draft pull requests, not merged or closed ones")

        // The search route: state open, draft or closed, and merged.
        let search = #"{"payload":{"blackbirdSearchRoute":{"logged_in":true,"results":["#
            + #"{"number":6,"hl_title":"Searched open","state":"open","merged":false,"repo":{"repository":{"owner_login":"team","name":"app"}},"created":"2026-11-06T12:00:00Z"},"#
            + #"{"number":7,"hl_title":"Searched draft","state":"draft","merged":false,"repo":{"repository":{"owner_login":"team","name":"app"}},"created":"2026-11-05T12:00:00Z"},"#
            + #"{"number":8,"hl_title":"Searched merged","state":"closed","merged":true,"repo":{"repository":{"owner_login":"team","name":"app"}},"created":"2026-11-04T12:00:00Z"},"#
            + #"{"number":9,"hl_title":"Searched closed","state":"closed","merged":false,"repo":{"repository":{"owner_login":"team","name":"app"}},"created":"2026-11-03T12:00:00Z"}"#
            + #"]}}}"#
        check(try titles(search) == ["Searched open", "Searched draft"], "the search route keeps open and draft pull requests only")

        // GitHub's embedded React data (GraphQL's PullRequestState) and the classic list's state icons.
        let embedded = #"<meta name="user-login" content="alice"><script type="application/json" data-target="react-app.embeddedData">{"payload":{"results":["#
            + #"{"__typename":"PullRequest","number":11,"title":"Embedded open","state":"OPEN","repository":{"nameWithOwner":"team/app"}},"#
            + #"{"__typename":"PullRequest","number":12,"title":"Embedded merged","state":"MERGED","repository":{"nameWithOwner":"team/app"}},"#
            + #"{"__typename":"PullRequest","number":13,"title":"Embedded closed","closed":true,"repository":{"nameWithOwner":"team/app"}}"#
            + #"]}}</script>"#
        check(try titles(embedded) == ["Embedded open"], "embedded data keeps open pull requests only")
        func row(_ number: Int, _ icon: String, _ title: String) -> String {
            #"<div class="js-issue-row"><svg class="octicon \#(icon) color-fg-done"></svg><a href="/team/app/pull/\#(number)" class="markdown-title">\#(title)</a></div>"#
        }
        let classic = #"<meta name="user-login" content="alice">"# + row(14, "octicon-git-pull-request", "Row open")
            + row(15, "octicon-git-pull-request-draft", "Row draft") + row(16, "octicon-git-merge", "Row merged")
            + row(17, "octicon-git-pull-request-closed", "Row closed")
        check(try titles(classic) == ["Row open", "Row draft"], "the classic list leaves out merged and closed rows")
    }

    // promise: #523
    /// What still counts as open: a pull request in the merge queue (its icon starts like the merged one),
    /// open ones that spell out closedAt or merged as null or false; and what doesn't: GitHub's REST shape
    /// (state closed with merged_at), a closedAt alone, a lowercase "merged".
    private static func gitHubOpenOnlyEdges(_ github: LiveFolderPluginPackage, executable: URL) throws {
        func titles(_ body: String) throws -> [String] {
            try refresh(github, executable: executable, origins: ["https://github.com"], filters: ["authored"]) { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: body)
            }.get().items.map(\.title)
        }
        func row(_ number: Int, _ icon: String, _ title: String) -> String {
            #"<div class="js-issue-row"><svg class="octicon \#(icon)"></svg><a href="/team/app/pull/\#(number)" class="markdown-title">\#(title)</a></div>"#
        }
        let queue = #"<meta name="user-login" content="alice">"# + row(1, "octicon-git-merge-queue", "Queued")
            + row(2, "octicon-git-merge", "Merged")
        check(try titles(queue) == ["Queued"], "a pull request in the merge queue is still open")

        let shapes = #"{"results":["#
            + #"{"number":3,"title":"Spelled-out open","repoNameWithOwner":"team/app","state":"OPEN","isDraft":false,"merged":false,"closed":false,"mergedAt":null,"closedAt":null,"createdAt":"2026-11-06T12:00:00Z"},"#
            + #"{"number":4,"title":"REST merged","html_url":"https://github.com/team/app/pull/4","state":"closed","merged_at":"2026-11-05T12:00:00Z","pull_request":{},"created_at":"2026-11-05T10:00:00Z"},"#
            + #"{"number":5,"title":"REST closed","html_url":"https://github.com/team/app/pull/5","state":"closed","closed_at":"2026-11-04T12:00:00Z","pull_request":{},"created_at":"2026-11-04T10:00:00Z"},"#
            + #"{"number":6,"title":"REST open","html_url":"https://github.com/team/app/pull/6","state":"open","merged_at":null,"closed_at":null,"pull_request":{},"created_at":"2026-11-03T10:00:00Z"},"#
            + #"{"number":7,"title":"Closed at only","repoNameWithOwner":"team/app","isDraft":false,"closedAt":"2026-11-02T12:00:00Z","createdAt":"2026-11-02T10:00:00Z"},"#
            + #"{"number":8,"title":"Lowercase merged","repoNameWithOwner":"team/app","isDraft":false,"state":"merged","createdAt":"2026-11-01T10:00:00Z"}"#
            + #"]}"#
        check(try titles(shapes) == ["Spelled-out open", "REST open"], "every shape of merged or closed is left out, open ones stay")
    }

    // promise: #523
    /// The reporter's case over time: a pull request in the folder is merged on GitHub, and the next
    /// refresh no longer lists it while its open neighbour stays.
    private static func gitHubMergedSinceLastRefresh(_ github: LiveFolderPluginPackage, executable: URL) throws {
        func pulls(secondState: String, mergedAt: String) -> String {
            #"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":["#
                + #"{"number":1,"title":"Stays","repoNameWithOwner":"team/app","state":"OPEN","isDraft":false,"mergedAt":null,"createdAt":"2026-11-06T12:00:00Z"},"#
                + #"{"number":2,"title":"Gets merged","repoNameWithOwner":"team/app","state":"\#(secondState)","isDraft":false,"mergedAt":\#(mergedAt),"createdAt":"2026-11-05T12:00:00Z"}"#
                + #"],"pageInfo":{},"error":null}}}"#
        }
        func urls(_ body: String) throws -> [String] {
            try refresh(github, executable: executable, origins: ["https://github.com"], filters: ["authored", "review", "teamReview"]) { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: body)
            }.get().items.map(\.url)
        }
        check(try urls(pulls(secondState: "OPEN", mergedAt: "null")) == ["https://github.com/team/app/pull/1", "https://github.com/team/app/pull/2"],
              "both are in the folder while open")
        check(try urls(pulls(secondState: "MERGED", mergedAt: #""2026-11-07T09:00:00Z""#)) == ["https://github.com/team/app/pull/1"],
              "after the merge, every filter's answer leaves it out")
    }

    // promise: #521
    /// The GitHub plugin's answers carry what the folder row shows, as Arc words it: an organisation
    /// behind SAML single sign-on gives the key, "Login with SSO to unlock this folder" and a click to
    /// that organisation's SSO page; a healthy answer gives no warning at all (or every folder would
    /// show a key); signed out gives the triangle and "Sign back in to GitHub." (GitHub #521).
    private static func gitHubSSOKey(_ github: LiveFolderPluginPackage, executable: URL) throws {
        func folder(_ body: String) throws -> LiveFolderData {
            let snapshot = try refresh(github, executable: executable, origins: ["https://github.com"], filters: ["authored"]) { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: body)
            }.get()
            var live = LiveFolderData()
            var plugin = LiveFolderPluginConfiguration(id: "cra.github", settings: [:], filters: ["authored"], sessionOrigins: ["https://github.com"])
            plugin.snapshot = snapshot
            live.plugin = plugin
            return live
        }
        let sso = try folder(#"{"protected_org_logins":["acme"],"results":[]}"#)
        check(sso.plugin?.snapshot?.warning == "Login with SSO to unlock this folder", "Arc's SSO tip")
        check(sso.plugin?.snapshot?.actionMessage == "SSO ensures all of your organizations’ PRs appear", "Arc's SSO menu note")
        check(sso.plugin?.snapshot?.actions == [.init(title: "Sign In to acme with SSO…", url: "https://github.com/orgs/acme/sso")],
              "the organisation's SSO sign-in")
        check(sso.alert == .singleSignOn(help: "Login with SSO to unlock this folder", url: "https://github.com/orgs/acme/sso")
              && sso.alert?.symbol == "key", "an organisation behind SSO puts the key on the folder, and a click goes to its SSO page")

        let healthy = try folder(#"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":[],"pageInfo":{},"error":null}}}"#)
        check(healthy.plugin?.snapshot?.warning == nil && healthy.alert == nil, "a folder nothing holds back shows no key")

        var signedOut = sso
        let signIn = json(try invoke(github, "signIn", input: ["settings": [:], "state": [:]], origins: [], executable: executable))
        signedOut.plugin?.signIn = .init(title: signIn["title"] as? String ?? "", url: signIn["url"] as? String ?? "")
        signedOut.plugin?.signInWarning = signIn["warning"] as? String
        signedOut.lastError = .notSignedIn
        check(signedOut.alert == .signIn(help: "Sign back in to GitHub.", url: "https://github.com/login?return_to=%2Fpulls")
              && signedOut.alert?.symbol == "exclamationmark.triangle", "signed out shows the triangle, even with an organisation behind SSO")
    }

    // promise: #521
    /// The pulls page's JSON lists pull requests but never which organisations wait for SSO; GitHub
    /// says that in the page itself (pullsDashboardSurfaceLayoutRoute's `sso_organizations`, which Arc
    /// reads) and in its search's `protected_org_logins`. With pull requests from elsewhere in the folder
    /// the search never ran, so a lapsed organisation SSO showed no key while its pull requests asked
    /// for a sign-in when opened (GitHub #521, 0.1.49). Answers shaped like GitHub's on 19 Nov 2026.
    private static func gitHubSSOBesideOtherPullRequests(_ github: LiveFolderPluginPackage, executable: URL) throws {
        let pulls = #"{"meta":{"title":"Pull requests"},"payload":{"pullsDashboardSurfaceContentRoute":{"results":["#
            + #"{"number":7,"title":"Elsewhere","permalink":"https://github.com/me/tool/pull/7","repoNameWithOwner":"me/tool","#
            + #""author":{"displayLogin":"me"},"state":"OPEN","isDraft":false,"mergedAt":null,"createdAt":"2026-11-18T12:00:00Z"}],"#
            + #""pageInfo":{"currentPage":1,"totalPages":1,"totalCount":1},"error":null}}}"#
        func page(_ organisations: String) -> String {
            #"<html><meta name="user-login" content="me"><script type="application/json" data-target="react-app.embeddedData">"#
                + #"{"payload":{"pullsDashboardSurfaceLayoutRoute":{"sso":{"sso_organizations":"# + organisations
                + #","current_sso_orgs_match_dismissed_cookie":false}}},"appPayload":{"sso_organizations":"# + organisations + "}}</script></html>"
        }
        let acme = #"[{"id":"1","login":"acme","name":"Acme","avatar_url":"https://avatars.githubusercontent.com/u/1?s=60&v=4"}]"#
        func read(_ organisations: String) throws -> (LiveFolderPluginSnapshot, [LiveFolderPluginRequest]) {
            var requests: [LiveFolderPluginRequest] = []
            let snapshot = try refresh(github, executable: executable, origins: ["https://github.com"], filters: ["authored"],
                                       groups: ["acme/app", "me/tool"]) { request in
                requests.append(request)
                let json = request.headers?["Accept"] == "application/json"
                return LiveFolderPluginResponse(status: 200, url: request.url, body: json ? pulls : page(organisations))
            }.get()
            return (snapshot, requests)
        }

        let (lapsed, requests) = try read(acme)
        check(lapsed.items.map(\.title) == ["Elsewhere"], "the pull requests that do load stay in the folder")
        check(lapsed.warning == "Login with SSO to unlock this folder", "an organisation waiting for SSO puts the key on the folder")
        check(lapsed.actions == [.init(title: "Sign In to acme with SSO…", url: "https://github.com/orgs/acme/sso")],
              "and a click goes to its SSO page")
        check(lapsed.preservedGroups == ["acme/app"], "its pull requests already in the folder are kept")
        check(requests.count == 2 && requests[1].url == "https://github.com/pulls" && requests[1].headers?["Accept"] != "application/json",
              "one read of the pulls page itself, after the search")

        let (healthy, _) = try read("[]")
        check(healthy.warning == nil && healthy.actions.isEmpty, "no organisation waiting, no key")
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

    // MARK: Azure DevOps

    /// Azure DevOps pull requests through the space's own session (#542): yours and the ones still
    /// waiting for your vote, across the organization, never an empty folder on a sign-in page.
    // promise: #542
    private static func azureDevOps(_ azure: LiveFolderPluginPackage, executable: URL) throws {
        let org = "https://dev.azure.com/acme"
        let origins = ["https://dev.azure.com"]
        let me = "11111111-1111-1111-1111-111111111111", other = "22222222-2222-2222-2222-222222222222"
        let connection = #"{"authenticatedUser":{"id":"\#(me)","descriptor":"Microsoft.IdentityModel.Claims.ClaimsIdentity;acme\\alex"}}"#
        func pull(_ id: Int, project: String = "Web Shop", repo: String = "checkout", by author: String = other,
                  votes: [(String, Int)] = [], status: String = "active", created: String = "2026-11-06T12:00:00.1234567Z") -> [String: Any] {
            ["pullRequestId": id, "title": "PR \(id)", "status": status, "creationDate": created,
             "createdBy": ["id": author, "displayName": author == me ? "Alex" : "Sam"],
             "repository": ["name": repo, "project": ["name": project]],
             "reviewers": votes.map { ["id": $0.0, "vote": $0.1] }]
        }
        func body(_ rows: [[String: Any]]) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: ["count": rows.count, "value": rows]), encoding: .utf8)!
        }
        func refresh(server: String = org, filters: [String] = ["authored", "review"],
                     respond: @escaping Respond) throws -> Result<LiveFolderPluginSnapshot, Failure> {
            try Self.refresh(azure, executable: executable, origins: origins, filters: filters, settings: ["server": server], respond: respond)
        }
        func query(_ request: LiveFolderPluginRequest) -> [String: String] {
            Dictionary(uniqueKeysWithValues: (URLComponents(string: request.url)!.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }

        let presentation = try JSONDecoder().decode(LiveFolderPluginPresentation.self,
            from: invoke(azure, "describe", input: [:], origins: [], executable: executable))
        try presentation.validate()
        check(presentation.setup?.key == azure.manifest.sessionSetting && presentation.groups?.title == "Repositories", "address setup and repository groups")
        check(presentation.filters.filter(\.enabledByDefault).map(\.id) == ["authored", "review"], "both filters start on")

        // One query per filter with the signed-in user's id; the address of any page in the org is the org.
        var asked: [String: [String: String]] = [:]
        let snapshot = try refresh(server: org + "/Web%20Shop/_git/checkout/pullrequest/7") { request in
            check(request.headers?["X-TFS-FedAuthRedirect"] == "Suppress", "signed out answers 401 instead of a sign-in page")
            if request.url == org + "/_apis/connectionData" { return LiveFolderPluginResponse(status: 200, url: request.url, body: connection) }
            check(request.url.hasPrefix(org + "/_apis/git/pullrequests?"), "pull requests come from the organization's API")
            let q = query(request)
            check(q["searchCriteria.status"] == "active" && q["$top"] == "100" && q["$skip"] == "0", "active ones, a page at a time")
            if q["searchCriteria.creatorId"] == me {
                asked["authored"] = q
                return LiveFolderPluginResponse(status: 200, url: request.url, body: body([pull(3, by: me, created: "2026-11-05T09:00:00Z")]))
            }
            asked["review"] = q
            check(q["searchCriteria.reviewerId"] == me, "review requests ask for the signed-in user")
            return LiveFolderPluginResponse(status: 200, url: request.url, body: body([
                pull(7, votes: [(me, 0)]),
                pull(8, repo: "Web Shop", votes: [(me, 10)]),
                pull(9, votes: [(me, -5)]),
                pull(3, by: me, created: "2026-11-05T09:00:00Z"),
            ]))
        }.get()
        check(Set(asked.keys) == ["authored", "review"], "one query per filter")
        check(snapshot.items.map(\.url) == [org + "/Web%20Shop/_git/checkout/pullrequest/7", org + "/Web%20Shop/_git/checkout/pullrequest/3"],
              "reviewed ones leave, your own are listed once, newest first: \(snapshot.items.map(\.url))")
        check(snapshot.items.first?.group == "Web Shop/checkout" && snapshot.items.first?.subtitle == "Sam" && snapshot.items.first?.createdAt != nil,
              "repository group, author and date")
        check(snapshot.items.first?.title == "PR 7", "the pull request's title")

        // With Review Requests alone, a pull request you opened yourself stays out even when you're on it.
        let reviewOnly = try refresh(filters: ["review"]) { request in
            LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/connectionData") ? connection
                : body([pull(3, by: me, votes: [(me, 0)]), pull(4), pull(5, votes: [(other, 10), (me, 0)])]))
        }.get()
        check(reviewOnly.items.map(\.url) == [org + "/Web%20Shop/_git/checkout/pullrequest/4", org + "/Web%20Shop/_git/checkout/pullrequest/5"],
              "review requests leave out your own: \(reviewOnly.items.map(\.url))")

        // A project's default repository has the project's name: the group is that name once.
        let named = try refresh(filters: ["authored"]) { request in
            LiveFolderPluginResponse(status: 200, url: request.url,
                body: request.url.hasSuffix("/connectionData") ? connection : body([pull(1, project: "Shop", repo: "Shop", by: me)]))
        }.get()
        check(named.items.first?.group == "Shop", "a project's own repository groups under the project")

        // A visualstudio.com organization and a Server collection keep their own address.
        for (server, expected) in [("https://acme.visualstudio.com/Shop/_git", "https://acme.visualstudio.com"),
                                   ("https://tfs.example.com/tfs/DefaultCollection", "https://tfs.example.com/tfs/DefaultCollection")] {
            var first = ""
            let host = URL(string: expected)!
            _ = try Self.refresh(azure, executable: executable, origins: ["https://\(host.host!)"], filters: ["authored"],
                                 settings: ["server": server]) { request in
                if first.isEmpty { first = request.url }
                return LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/connectionData") ? connection : body([]))
            }.get()
            check(first == expected + "/_apis/connectionData", "\(server) is read at \(expected)")
        }

        // A full page asks for the next one.
        var skips: [String] = []
        let paged = try refresh(filters: ["authored"]) { request in
            if request.url.hasSuffix("/connectionData") { return LiveFolderPluginResponse(status: 200, url: request.url, body: connection) }
            let skip = query(request)["$skip"]!
            skips.append(skip)
            return LiveFolderPluginResponse(status: 200, url: request.url,
                body: body(skip == "0" ? (1...100).map { pull($0, by: me) } : [pull(101, by: me)]))
        }.get()
        check(skips == ["0", "100"] && paged.items.count == 101, "paging continues after a full page")

        // Failures never become an empty folder.
        for (status, expected) in [(0, "network"), (401, "notSignedIn"), (403, "unexpectedPage"), (429, "rateLimited"), (500, "unexpectedPage")] {
            check(code(try refresh { LiveFolderPluginResponse(status: status, url: $0.url, body: "") }) == expected, "status \(status)")
        }
        check(code(try refresh { _ in LiveFolderPluginResponse(status: 200, url: "https://dev.azure.com/_signin?realm=dev.azure.com", body: connection) })
              == "notSignedIn", "sent to the sign-in page")
        check(code(try refresh { LiveFolderPluginResponse(status: 203, url: $0.url, body: "<html>Sign in</html>") }) == "notSignedIn",
              "an expired session's sign-in page")
        check(code(try refresh { LiveFolderPluginResponse(status: 200, url: $0.url,
            body: #"{"authenticatedUser":{"id":"00000000-0000-0000-0000-000000000000","descriptor":"System:PublicAccess;Anonymous"}}"#) })
              == "notSignedIn", "an anonymous connection")
        for wrong in [#"{"message":"TF400813"}"#, #"{"value":[{"pullRequestId":1}]}"#, body([pull(1, status: "completed")]),
                      body([pull(1, repo: "")])] {
            check(code(try refresh { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/connectionData") ? connection : wrong)
            }) == "unexpectedPage", "unreadable pull requests: \(wrong)")
        }
        check((try? refresh { request in
            LiveFolderPluginResponse(status: 200, url: request.url, body: request.url.hasSuffix("/connectionData") ? connection : body([]))
        }.get().items.isEmpty) == true, "no pull requests is an empty folder")
        check((try? refresh(filters: []) { _ in fatalError("No filter asked anything") }.get().items.isEmpty) == true, "no filter, no requests")

        // Sign-in and the pages that refresh the folder.
        let signIn = json(try invoke(azure, "signIn", input: ["settings": ["server": org + "/Shop"], "state": [:]], origins: [], executable: executable))
        check(signIn["url"] as? String == org && signIn["failureURL"] as? String == org + "/_pulls", "sign in at the organization")
        check(signIn["instanceLabel"] as? String == "Azure DevOps (dev.azure.com/acme)", "the instance label")
        for (url, refreshes) in [(org + "/Shop/_git/checkout/pullrequest/7", true), ("https://dev.azure.com/ACME/Shop/_pulls", true),
                                 ("https://dev.azure.com/acme-other/x", false),
                                 ("https://example.com/", false)] {
            let changed = json(try invoke(azure, "pageChanged", input: ["url": url, "previousURL": "", "settings": ["server": org], "state": [:]],
                                          origins: [], executable: executable))
            check((changed["refreshAfter"] as? [Int] ?? []).isEmpty != refreshes && (changed["checkSignIn"] as? Bool) == refreshes, "page \(url)")
        }
    }
}
