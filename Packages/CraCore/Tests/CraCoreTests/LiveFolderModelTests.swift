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
}
