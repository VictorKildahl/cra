import Foundation

@main
struct LiveFolderPluginProcessTests {
    static func main() throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let origin = try LiveFolderSessionOrigin("https://example.test")
        func invoke(_ script: String, timeout: TimeInterval = 5,
                    fetch: (LiveFolderPluginRequest) throws -> LiveFolderPluginResponse = { _ in
                        throw LiveFolderPluginError.invalidManifest("Unexpected fetch")
                    }) throws -> Data {
            try LiveFolderPluginProcess.invoke(executable: executable, script: script, method: "run",
                                               input: Data("{}".utf8), origins: [origin], timeout: timeout, fetch: fetch)
        }
        let data = try invoke("return {run() { return cra.session.fetch('https://example.test/api'); }};") { request in
            precondition(request.url == "https://example.test/api")
            return LiveFolderPluginResponse(status: 200, url: request.url, body: "ok")
        }
        let response = try JSONDecoder().decode(LiveFolderPluginResponse.self, from: data)
        precondition(response.body == "ok")
        for script in ["throw new Error('failure')", "return {run() { throw new Error('failure'); }};",
                       "return {run() { return cra.session.fetch('https://evil.test/api'); }};",
                       "return {run() { return cra.session.fetch('https://example.test/api', {headers:{Cookie:'secret'}}); }};",
                       "return {run() { return Promise.resolve([]); }};"] {
            do { _ = try invoke(script); fatalError("Invalid plugin succeeded") }
            catch is LiveFolderPluginError {}
        }
        let start = Date()
        do { _ = try invoke("while(true) {}", timeout: 0.2); fatalError("Infinite loop succeeded") }
        catch is LiveFolderPluginError {}
        precondition(Date().timeIntervalSince(start) < 3)
        let gitlab = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/gitlab"))
        let description = try LiveFolderPluginProcess.invoke(executable: executable, script: gitlab.script, method: "describe",
            input: Data("{}".utf8), origins: [], fetch: { _ in fatalError("Description requested a session") })
        let presentation = try JSONDecoder().decode(LiveFolderPluginPresentation.self, from: description)
        try presentation.validate()
        precondition(presentation.filters.map(\.title) == ["My Merge Requests", "Review Requests", "Assigned to Me"])
        var requests = 0
        let snapshot = try LiveFolderPluginProcess.invoke(executable: executable, script: gitlab.script, method: "refresh",
            input: Data(#"{"settings":{"server":"https://example.test/gitlab"},"filters":["review"]}"#.utf8),
            origins: [origin]) { request in
                requests += 1
                let body: String
                if request.url.hasSuffix("/user") { body = #"{"id":42}"# }
                else {
                    precondition(request.url.contains("reviewer_id=42"))
                    body = #"[{"iid":17,"title":"Fix startup","web_url":"https://example.test/gitlab/company/team/app/-/merge_requests/17","author":{"username":"alex"},"state":"opened","created_at":"2026-11-06T12:00:00.123Z"}]"#
                }
                return LiveFolderPluginResponse(status: 200, url: request.url, body: body)
            }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let result = try decoder.decode(LiveFolderPluginSnapshot.self, from: snapshot)
        try result.validate()
        precondition(requests == 2 && result.items.count == 1)
        precondition(result.items[0].subtitle == "alex" && result.items[0].group == "company/team/app")
        let github = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/github"))
        let githubOrigin = try LiveFolderSessionOrigin("https://github.com")
        let migration = try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "migrate",
            input: Data(#"{"filter":{"attributes":{"rawValue":5}},"enterprise":"example"}"#.utf8), origins: [],
            fetch: { _ in fatalError("Migration requested a session") })
        let migrated = try JSONSerialization.jsonObject(with: migration) as! [String: Any]
        precondition(migrated["filters"] as? [String] == ["authored", "teamReview"])
        let githubResult = try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "refresh",
            input: Data(#"{"filters":["authored"],"groups":["protected/app","other/app"]}"#.utf8), origins: [githubOrigin]) { request in
                precondition(request.url.hasPrefix("https://github.com/pulls?q="))
                return LiveFolderPluginResponse(status: 200, url: request.url, body:
                    #"{"viewer":{"login":"alice"},"protected_org_logins":["protected"],"results":[{"number":5,"title":"Fix <em>startup</em>","repoNameWithOwner":"team/app","isDraft":false,"createdAt":"2026-11-06T12:00:00Z"}]}"#)
            }
        let githubSnapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: githubResult)
        try githubSnapshot.validate()
        precondition(githubSnapshot.items.first?.title == "Fix startup")
        precondition(githubSnapshot.items.first?.subtitle == "alice")
        precondition(githubSnapshot.preservedGroups == ["protected/app"])
        precondition(githubSnapshot.actions.first?.url == "https://github.com/orgs/protected/sso")
        let htmlResult = try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "refresh",
            input: Data(#"{"filters":["review"]}"#.utf8), origins: [githubOrigin]) { request in
                LiveFolderPluginResponse(status: 200, url: request.url, body:
                    #"<meta name="user-login" content="alice"><div class="js-issue-row"><a href="/team/app/pull/7" data-hovercard-type="pull_request">Fix &amp; test</a><a data-hovercard-type="user">bob</a></div>"#)
            }
        let htmlSnapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: htmlResult)
        precondition(htmlSnapshot.items.first?.title == "Fix & test" && htmlSnapshot.items.first?.subtitle == "bob")
        do {
            _ = try LiveFolderPluginProcess.invoke(executable: executable, script: github.script, method: "refresh",
                input: Data(#"{"filters":["authored"]}"#.utf8), origins: [githubOrigin]) { _ in
                    LiveFolderPluginResponse(status: 200, url: "https://github.com/enterprises/example/sso", body: "")
                }
            fatalError("SSO response succeeded")
        } catch LiveFolderPluginError.pluginFailed(let message, let state) {
            precondition(message.contains("notSignedIn") && state["enterprise"] == "example")
        }
        try jira(executable: executable)
        try LiveFolderProviderTests.run(executable: executable)
        try sandboxed(executable: executable)
        print("Plugin transport, permissions, timeout, bundled provider checks passed")
    }

    private static func jira(executable: URL) throws {
        let package = try LiveFolderPluginPackage(directory: URL(fileURLWithPath: "resources/live-folder-plugins/jira"))
        let server = "https://jira.example.test:8443/jira"
        let origin = try LiveFolderSessionOrigin("https://jira.example.test:8443")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        func invoke(_ method: String, filters: [String] = ["assigned", "todo", "inProgress"], extra: [String: Any] = [:],
                    fetch: (LiveFolderPluginRequest) throws -> LiveFolderPluginResponse = { _ in fatalError("Unexpected Jira request") }) throws -> Data {
            var input: [String: Any] = ["settings": ["server": server], "filters": filters, "state": [:]]
            input.merge(extra) { _, new in new }
            return try LiveFolderPluginProcess.invoke(executable: executable, script: package.script, method: method,
                input: JSONSerialization.data(withJSONObject: input), origins: [origin], fetch: fetch)
        }
        let presentation = try decoder.decode(LiveFolderPluginPresentation.self, from: invoke("describe"))
        try presentation.validate()
        precondition(presentation.setup?.key == package.manifest.sessionSetting && presentation.groups?.title == "Projects")
        precondition(presentation.filters.filter(\.enabledByDefault).map(\.id) == ["assigned", "todo", "inProgress"])
        let empty = try decoder.decode(LiveFolderPluginSnapshot.self, from: invoke("refresh", filters: []))
        precondition(empty.items.isEmpty)
        for (filter, clause) in [("assigned", "assignee"), ("reported", "reporter"), ("watching", "watcher")] {
            var calls = 0
            let result = try invoke("refresh", filters: [filter, "todo", "inProgress"]) { request in
                calls += 1
                precondition(request.headers?["Accept"] == "application/json")
                if request.url == server + "/rest/api/2/myself" {
                    return LiveFolderPluginResponse(status: 200, url: request.url, body: #"{"name":"alice","active":true}"#)
                }
                let url = URLComponents(string: request.url)!
                precondition(url.path == "/jira/rest/api/2/search" && url.port == 8443)
                let parameters = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
                precondition(parameters["jql"] == #"statusCategory IN ("To Do", "In Progress") AND ("# + clause + " = currentUser()) ORDER BY created DESC, key ASC")
                let start = Int(parameters["startAt"]!)!
                precondition(start < 2)
                let project = start == 0 ? "APP" : "OPS"
                let body: [String: Any] = ["startAt": start, "maxResults": 1, "total": 2, "issues": [
                    ["id": String(start + 10), "key": project + "-1", "fields": [
                        "summary": "Fix startup", "status": ["name": "In Progress"], "project": ["key": project],
                        "created": "2026-11-06T12:00:00.123+0300"]]
                ]]
                return LiveFolderPluginResponse(status: 200, url: request.url,
                    body: String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!)
            }
            let snapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: result)
            try snapshot.validate()
            precondition(calls == 3 && snapshot.items.map(\.group) == ["APP", "OPS"])
            precondition(snapshot.items.first?.url == server + "/browse/APP-1")
            precondition(snapshot.items.first?.title == "APP-1 · Fix startup")
            precondition(snapshot.items.first?.subtitle == "In Progress" && snapshot.items.first?.createdAt != nil)
        }
        _ = try invoke("refresh", filters: ["assigned", "reported", "watching", "todo", "inProgress"]) { request in
            if request.url.hasSuffix("/myself") {
                return LiveFolderPluginResponse(status: 200, url: request.url, body: #"{"name":"alice"}"#)
            }
            let query = URLComponents(string: request.url)!.queryItems!.first { $0.name == "jql" }!.value!
            precondition(query.contains("assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()"))
            return LiveFolderPluginResponse(status: 200, url: request.url, body: #"{"startAt":0,"maxResults":50,"total":0,"issues":[]}"#)
        }
        for filters in [["assigned"], ["todo", "inProgress"], []] {
            let snapshot = try decoder.decode(LiveFolderPluginSnapshot.self, from: invoke("refresh", filters: filters))
            precondition(snapshot.items.isEmpty)
        }
        for (filter, category) in [("todo", "To Do"), ("inProgress", "In Progress")] {
            _ = try invoke("refresh", filters: ["assigned", filter]) { request in
                if request.url.hasSuffix("/myself") {
                    return LiveFolderPluginResponse(status: 200, url: request.url, body: #"{"name":"alice"}"#)
                }
                let query = URLComponents(string: request.url)!.queryItems!.first { $0.name == "jql" }!.value!
                precondition(query == "statusCategory IN (\"" + category + "\") AND (assignee = currentUser()) ORDER BY created DESC, key ASC")
                precondition(!query.contains("Done") && !query.contains("resolution"))
                return LiveFolderPluginResponse(status: 200, url: request.url, body: #"{"startAt":0,"maxResults":50,"total":0,"issues":[]}"#)
            }
        }
        for (status, body, redirected, expected) in [
            (401, "", false, "notSignedIn"), (429, "", false, "rateLimited"),
            (0, "", false, "network"), (403, "", false, "unexpectedPage"),
            (200, "<html>Sign in</html>", false, "notSignedIn"),
            (200, "{}", true, "notSignedIn"), (200, "not json", false, "unexpectedPage")
        ] {
            do {
                _ = try invoke("refresh") { request in
                    LiveFolderPluginResponse(status: status, url: redirected ? server + "/login.jsp" : request.url, body: body)
                }
                fatalError("Invalid Jira response succeeded")
            } catch LiveFolderPluginError.pluginFailed(let message, _) { precondition(message.contains(expected)) }
        }
        for body in [#"{"startAt":1,"maxResults":50,"issues":[]}"#,
                     #"{"startAt":0,"maxResults":0,"issues":[]}"#,
                     #"{"startAt":0,"maxResults":50,"issues":[{"id":"1","key":"../evil","fields":{}}]}"#] {
            do {
                _ = try invoke("refresh") { request in
                    LiveFolderPluginResponse(status: 200, url: request.url,
                        body: request.url.hasSuffix("/myself") ? #"{"name":"alice"}"# : body)
                }
                fatalError("Invalid Jira search succeeded")
            } catch LiveFolderPluginError.pluginFailed(let message, _) { precondition(message.contains("unexpectedPage")) }
        }
        let signIn = try JSONSerialization.jsonObject(with: invoke("signIn")) as! [String: Any]
        precondition(signIn["url"] as? String == server + "/login.jsp")
        for (url, refreshes) in [(server + "/browse/APP-1", true), (server + "/login.jsp", false),
                                 ("https://jira.example.test:8443/jira-other/browse/APP-1", false),
                                 ("https://elsewhere.test/browse/APP-1", false)] {
            let result = try JSONSerialization.jsonObject(with: invoke("pageChanged", extra: ["url": url])) as! [String: Any]
            precondition((result["refreshAfter"] as! [Double]).isEmpty != refreshes)
            precondition(result["checkSignIn"] as? Bool == refreshes)
        }
    }


    /// <sandbox.h>: nonzero when the process is sandboxed, or when it is denied `operation`.
    @_silgen_name("sandbox_check")
    private static func sandbox_check(_ pid: pid_t, _ operation: UnsafePointer<CChar>?, _ type: Int32) -> Int32

    /// Plugin code runs only after the host gave up files and the network: checked on a live host,
    /// while it waits for the answer to its plugin's session request.
    private static func sandboxed(executable: URL) throws {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let invocation = try JSONSerialization.data(withJSONObject: [
            "script": "return {run() { return cra.session.fetch('https://example.test/'); }};", "method": "run", "input": [:]])
        try input.fileHandleForWriting.write(contentsOf: invocation + Data([10]))
        var line = Data()
        while !line.contains(10) {
            let chunk = output.fileHandleForReading.availableData
            precondition(!chunk.isEmpty, "the host asked for its session request")
            line += chunk
        }
        precondition(String(decoding: line, as: UTF8.self).contains("\"fetch\""), "the plugin is running")
        precondition(sandbox_check(process.processIdentifier, nil, 0) != 0, "the plugin host is sandboxed")
        // The profile is the host's own text now: an `allow` added to it has to fail here.
        for operation in ["file-read-data", "file-read-metadata", "file-write-data", "network-outbound", "network-inbound",
                          "process-exec", "process-fork", "mach-lookup", "mach-register", "sysctl-write"] {
            precondition(sandbox_check(process.processIdentifier, operation, 0) != 0, "the plugin host may not \(operation)")
        }
    }
}
