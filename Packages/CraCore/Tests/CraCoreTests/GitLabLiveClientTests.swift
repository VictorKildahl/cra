import Foundation
import CraCore
import Testing

struct GitLabLiveClientTests {
    @Test func selfHostedURLsKeepPortsAndSubpaths() throws {
        let server = try #require(GitLabLiveClient.serverURL(" https://git.example.com:8443/gitlab/ "))
        #expect(server == "https://git.example.com:8443/gitlab")
        #expect(GitLabLiveClient.userURL(server: server) == server + "/api/v4/user")
        let url = try #require(URLComponents(string: GitLabLiveClient.mergeRequestsURL(server: server, category: .review, userID: 42, page: 2)))
        #expect(url.path == "/gitlab/api/v4/merge_requests")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["reviewer_id"] == "42" && query["scope"] == "all" && query["page"] == "2")
        #expect(GitLabLiveClient.serverURL("git.example.com") == "https://git.example.com")
        for input in ["", "file:///etc/passwd", "https://user:token@git.example.com", "https://git.example.com?token=secret"] {
            #expect(GitLabLiveClient.serverURL(input) == nil)
        }
    }

    @Test func mergeRequestsKeepNestedGroupsAndServerIdentity() throws {
        let server = "https://git.example.com/gitlab"
        let body = #"[{"iid":17,"title":"Fix startup","web_url":"https://git.example.com/gitlab/company/team/app/-/merge_requests/17","author":{"username":"alex"},"state":"opened","draft":true,"created_at":"2026-11-06T12:00:00.123Z"}]"#
        let request = try #require(GitLabLiveClient.mergeRequests(in: body, server: server, category: .review).first)
        #expect(request.repository == "company/team/app")
        #expect(request.url == server + "/company/team/app/-/merge_requests/17")
        #expect(request.author == "alex" && request.state == .draft && request.createdAt != nil)
        #expect(request.isAwaitingMyReview && !request.createdByMe)
        let restored = try JSONDecoder().decode(LivePullRequest.self, from: JSONEncoder().encode(request))
        #expect(restored == request)
        #expect(throws: LiveFolderError.unexpectedPage) {
            try GitLabLiveClient.mergeRequests(in: body, server: "https://other.example.com", category: .review)
        }
    }

    @Test func serverNamesDistinguishInstancesAndNormalizeEquivalentAddresses() {
        #expect(GitLabLiveClient.serverURL("HTTPS://GIT.Example.com:443/") == "https://git.example.com")
        #expect(GitLabLiveClient.serverURL("http://GIT.Example.com:80/gitlab/") == "http://git.example.com/gitlab")
        #expect(GitLabLiveClient.folderTitle(server: "https://gitlab.com") == "GitLab · gitlab.com")
        #expect(GitLabLiveClient.folderTitle(server: "https://git.example.com:8443/gitlab/") == "GitLab · git.example.com:8443/gitlab")
    }

    @Test func failuresCannotBecomeEmptySuccesses() throws {
        let url = "https://git.example.com/api/v4/merge_requests"
        for (status, error) in [(0, LiveFolderError.network), (401, .notSignedIn), (403, .unexpectedPage), (429, .rateLimited), (500, .unexpectedPage)] {
            #expect(throws: error) { try GitLabLiveClient.validate(status: status, finalURL: url, requestedURL: url) }
        }
        #expect(throws: LiveFolderError.notSignedIn) {
            try GitLabLiveClient.validate(status: 200, finalURL: "https://sso.example.com/login", requestedURL: url)
        }
        for body in ["<html>Sign in</html>", #"{"message":"403 Forbidden"}"#, #"[{"iid":1}]"#] {
            #expect(throws: LiveFolderError.unexpectedPage) {
                try GitLabLiveClient.mergeRequests(in: body, server: "https://git.example.com", category: .authored)
            }
        }
        #expect(try GitLabLiveClient.mergeRequests(in: "[]", server: "https://git.example.com", category: .authored).isEmpty)
    }

    @Test func gitLabFolderSurvivesPersistence() throws {
        var folder = LiveFolderData()
        folder.source = .gitlab
        folder.serverURL = "https://git.example.com/gitlab"
        folder.separateByCategory = true
        folder.hiddenItems = ["https://git.example.com/gitlab/team/app/-/merge_requests/17"]
        let restored = try JSONDecoder().decode(LiveFolderData.self, from: JSONEncoder().encode(folder))
        #expect(restored == folder)
        #expect(restored.signInURL == "https://git.example.com/gitlab/users/sign_in")
        let legacy = try JSONDecoder().decode(LiveFolderData.self, from: Data("{}".utf8))
        #expect(legacy.source == .github && legacy.serverURL == nil)
        #expect(legacy.separateByCategory == nil && legacy.cachedResults == nil)
    }

    @Test func categoriesUseDistinctFiltersAndDeduplicateByPriority() throws {
        let expected: [(GitLabLiveCategory, String)] = [(.authored, "created_by_me"), (.review, "all"), (.assigned, "assigned_to_me")]
        for (category, scope) in expected {
            let url = try #require(URLComponents(string: GitLabLiveClient.mergeRequestsURL(server: "https://git.example.com", category: category, userID: 42, page: 1)))
            let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(query["scope"] == scope)
            #expect((query["reviewer_id"] != nil) == (category == .review))
        }
        var folder = LiveFolderData()
        folder.filter.attributes = [.authored, .reviewRequests, .assigned]
        var request = LivePullRequest(owner: "team", repo: "app", number: 17, title: "Fix")
        request.gitLabCategories = [.authored, .review, .assigned]
        #expect(folder.category(for: request) == .authored)
        folder.filter.attributes.remove(.authored)
        #expect(folder.category(for: request) == .review)
        folder.filter.attributes.remove(.reviewRequests)
        #expect(folder.category(for: request) == .assigned)
        folder.filter.attributes = []
        #expect(folder.category(for: request) == nil)
    }
}
