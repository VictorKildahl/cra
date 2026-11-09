import Foundation
import CraCore
import Testing

/// The GitLab instance address rules that stay in Swift (the folder's identity and its migration).
/// What the GitLab plugin requests and reads: Tests/LiveFolderProviderTests.swift.
struct GitLabLiveClientTests {
    @Test func selfHostedURLsKeepPortsAndSubpaths() throws {
        let server = try #require(GitLabLiveClient.serverURL(" https://git.example.com:8443/gitlab/ "))
        #expect(server == "https://git.example.com:8443/gitlab")
        #expect(GitLabLiveClient.serverURL("git.example.com") == "https://git.example.com")
        for input in ["", "file:///etc/passwd", "https://user:token@git.example.com", "https://git.example.com?token=secret"] {
            #expect(GitLabLiveClient.serverURL(input) == nil)
        }
    }

    @Test func serverNamesDistinguishInstancesAndNormalizeEquivalentAddresses() {
        #expect(GitLabLiveClient.serverURL("HTTPS://GIT.Example.com:443/") == "https://git.example.com")
        #expect(GitLabLiveClient.serverURL("http://GIT.Example.com:80/gitlab/") == "http://git.example.com/gitlab")
        #expect(GitLabLiveClient.serverLabel("https://gitlab.com") == "gitlab.com")
        #expect(GitLabLiveClient.serverLabel("https://git.example.com:8443/gitlab/") == "git.example.com:8443/gitlab")
    }

    @Test func gitLabFolderSurvivesPersistence() throws {
        var folder = LiveFolderData()
        folder.source = .gitlab
        folder.serverURL = "https://git.example.com/gitlab"
        folder.hiddenItems = ["https://git.example.com/gitlab/team/app/-/merge_requests/17"]
        let restored = try JSONDecoder().decode(LiveFolderData.self, from: JSONEncoder().encode(folder))
        #expect(restored == folder)
        #expect(restored.signInURL == "https://git.example.com/gitlab/users/sign_in")
        let legacy = try JSONDecoder().decode(LiveFolderData.self, from: Data("{}".utf8))
        #expect(legacy.source == .github && legacy.serverURL == nil)
    }

    @Test func filtersMapToCategories() {
        var folder = LiveFolderData()
        folder.filter.attributes = [.reviewRequests, .assigned]
        #expect(folder.gitLabCategories == [.review, .assigned])
    }
}
