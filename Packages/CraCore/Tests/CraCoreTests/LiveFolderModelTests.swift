import CraCore
import Testing

struct LiveFolderModelTests {
    @Test func signInGoesToTheEnterpriseWhenThereIsOne() {
        var folder = LiveFolderData()
        #expect(folder.signInURL == "https://github.com/login?return_to=%2Fpulls")
        folder.enterprise = "example-ent"
        #expect(folder.signInURL == "https://github.com/enterprises/example-ent/sso")
    }

    @Test func defaultsShowEveryPullRequest() {
        let folder = LiveFolderData()
        #expect(folder.source == .github && folder.filter == GitHubLiveFilter() && folder.filter.attributes == .all)
        #expect(GitHubLiveFilter.Attributes.all.rawValue == 7, "Arc's bit mask for all three")
        #expect(GitHubLiveFilter(attributes: [.authored, .teamReviewRequests]).attributes.rawValue == 5)
    }

    @Test func pullRequestIsKnownByItsURL() {
        let pr = LivePullRequest(owner: "example", repo: "app", number: 9, title: "Fix", author: "someone", state: .draft)
        #expect(pr.url == "https://github.com/example/app/pull/9" && pr.id == pr.url && pr.repository == "example/app")
        #expect(!pr.createdByMe && !pr.isAwaitingMyReview && pr.createdAt == nil && pr.updatedAt == nil)
    }

    @Test func repositoryExclusionsIgnoreCaseAndCanBeReenabled() {
        var filter = GitHubLiveFilter(hiddenRepositories: ["Company/App", "company/app", "company/other"])
        #expect(filter.isRepositoryHidden("COMPANY/APP"))
        filter.setRepository("COMPANY/APP", hidden: false)
        #expect(!filter.isRepositoryHidden("company/app"))
        #expect(filter.hiddenRepositories == ["company/other"])
        filter.setRepository("Company/App", hidden: true)
        filter.setRepository("company/app", hidden: true)
        #expect(filter.hiddenRepositories == ["company/other", "company/app"])
        #expect(filter.isRepositoryHidden("Company/App"))
    }

    @Test func repositoriesCanBeRecoveredFromGitHubLiveTabURLs() {
        let folder = LiveFolderData()
        #expect(folder.repository(for: "https://github.com/company/app/pull/12") == "company/app")
        #expect(folder.repository(for: "https://github.com/company/app/pull/12/files?diff=split") == "company/app")
        for url in ["https://other.test/company/app/pull/12", "https://github.com/company/app/issues/12",
                    "https://github.com/company/app/pull/invalid", "https://github.com/company/app/pull/0",
                    "file://github.com/company/app/pull/12", "not a URL"] {
            #expect(folder.repository(for: url) == nil)
        }
    }

    @Test func gitLabRepositoriesKeepNestedGroupsButNotTheServerSubpath() {
        var folder = LiveFolderData()
        folder.source = .gitlab
        folder.serverURL = "https://git.example.test:8443/gitlab/"
        #expect(folder.repository(for: "https://git.example.test:8443/gitlab/company/team/app/-/merge_requests/12") == "company/team/app")
        #expect(folder.repository(for: "https://git.example.test:8443/gitlab/company/other/app/-/merge_requests/12") == "company/other/app")
        for url in ["https://other.test:8443/gitlab/company/team/app/-/merge_requests/12",
                    "https://git.example.test/gitlab/company/team/app/-/merge_requests/12",
                    "https://git.example.test:8443/gitlab-other/company/team/app/-/merge_requests/12",
                    "https://git.example.test:8443/gitlab/app/-/merge_requests/12",
                    "https://git.example.test:8443/gitlab/company/team/app"] {
            #expect(folder.repository(for: url) == nil)
        }
        folder.serverURL = nil
        #expect(folder.repository(for: "https://git.example.test/company/app/-/merge_requests/12") == nil)
    }
}
