import Foundation

// Live folders: folders that fill themselves from a service and empty as items close.
// Shape follows Arc's AutomaticLiveFolderData (StorableSidebar.json `list.automaticLiveFolderData`:
// dataSource github, filter.github {attributes, hiddenRepositories}, hiddenItems, lastFetch) and the
// cached LiveItem.github.pullRequest in StorableLiveData.json. Dia 1.54 keeps the same GitHub client
// (ARCClients/GitHubClient). Findings and what was verified: docs/live-folders.md.

/// What a live folder is filled from. Arc and Dia also have Bitbucket, Notion, Drive and calendar sources.
public enum LiveFolderSource: String, Codable {
    case github
    case gitlab

    public var title: String { self == .github ? "GitHub" : "GitLab" }
}

/// Which pull requests a GitHub live folder shows. Arc saves `attributes` as a bit mask (7 = all three).
public struct GitHubLiveFilter: Codable, Equatable {
    public struct Attributes: OptionSet, Codable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// author:@me
        public static let authored = Attributes(rawValue: 1)
        /// user-review-requested:@me (asked of you by name)
        public static let reviewRequests = Attributes(rawValue: 2)
        /// review-requested:@me, which also covers teams you are on (Arc: "Team Review Requests")
        public static let teamReviewRequests = Attributes(rawValue: 4)
        public static let assigned = Attributes(rawValue: 8)
        public static let all: Attributes = [.authored, .reviewRequests, .teamReviewRequests]
    }

    public var attributes: Attributes = .all
    /// "owner/name" of repositories switched off in the folder's menu.
    public var hiddenRepositories: [String] = []

    public init(attributes: Attributes = .all, hiddenRepositories: [String] = []) {
        self.attributes = attributes
        self.hiddenRepositories = hiddenRepositories
    }
}

public enum LiveFolderError: String, Codable, Equatable, Error {
    case notSignedIn, rateLimited, unexpectedPage, network
}

public enum GitLabLiveCategory: String, Codable, CaseIterable {
    case authored, review, assigned

    public var title: String {
        switch self {
        case .authored: return "My Merge Requests"
        case .review: return "Review Requests"
        case .assigned: return "Assigned to Me"
        }
    }

    public var attribute: GitHubLiveFilter.Attributes {
        switch self {
        case .authored: return .authored
        case .review: return .reviewRequests
        case .assigned: return .assigned
        }
    }
}

public struct LiveFolderData: Codable, Equatable {
    public var source: LiveFolderSource = .github
    public var serverURL: String?
    public var filter = GitHubLiveFilter()
    /// Items closed out of the folder; they don't come back (Arc: hiddenItems).
    public var hiddenItems: [String] = []
    public var separateByCategory: Bool?
    public var cachedResults: [LivePullRequest]?
    public var lastFetch: Date?
    /// Why the last refresh failed; nil once one succeeds.
    public var lastError: LiveFolderError?
    /// Organizations that want a SAML sign-in before their pull requests show up (Arc: needsSSO).
    public var ssoOrganizations: [String] = []
    /// The enterprise whose single sign-on GitHub sent a tab to (Enterprise Managed Users sign in
    /// there, not at github.com/login): the folder's sign-in button goes there too.
    public var enterprise: String?

    /// Where to sign in again.
    public var signInURL: String {
        if source == .gitlab { return "\(serverURL ?? "https://gitlab.com")/users/sign_in" }
        if let enterprise { return "https://github.com/enterprises/\(enterprise)/sso" }
        return "https://github.com/login?return_to=%2Fpulls"
    }

    public init() {}

    public var gitLabCategories: [GitLabLiveCategory] {
        GitLabLiveCategory.allCases.filter { filter.attributes.contains($0.attribute) }
    }

    public func category(for request: LivePullRequest) -> GitLabLiveCategory? {
        gitLabCategories.first { request.categories.contains($0) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(LiveFolderSource.self, forKey: .source) ?? .github
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
        filter = try c.decodeIfPresent(GitHubLiveFilter.self, forKey: .filter) ?? GitHubLiveFilter()
        hiddenItems = try c.decodeIfPresent([String].self, forKey: .hiddenItems) ?? []
        separateByCategory = try c.decodeIfPresent(Bool.self, forKey: .separateByCategory)
        cachedResults = try c.decodeIfPresent([LivePullRequest].self, forKey: .cachedResults)
        lastFetch = try c.decodeIfPresent(Date.self, forKey: .lastFetch)
        lastError = try? c.decodeIfPresent(LiveFolderError.self, forKey: .lastError)
        ssoOrganizations = try c.decodeIfPresent([String].self, forKey: .ssoOrganizations) ?? []
        enterprise = try c.decodeIfPresent(String.self, forKey: .enterprise)
    }
}

/// One pull request as the GitHub client reads it (Arc: LiveItem.Data.github.pullRequest).
public struct LivePullRequest: Codable, Equatable, Identifiable {
    public enum State: String, Codable { case open, draft, merged, closed }

    public var owner: String
    public var repo: String
    public var number: Int
    public var title: String
    public var author: String?
    public var state: State = .open
    public var createdByMe = false
    public var isAwaitingMyReview = false
    public var createdAt: Date?
    public var updatedAt: Date?
    public var webURL: String?
    public var gitLabCategories: Set<GitLabLiveCategory>?

    public var categories: Set<GitLabLiveCategory> {
        if let gitLabCategories { return gitLabCategories }
        var result: Set<GitLabLiveCategory> = []
        if createdByMe { result.insert(.authored) }
        if isAwaitingMyReview { result.insert(.review) }
        return result
    }

    public init(owner: String, repo: String, number: Int, title: String, author: String? = nil, state: State = .open,
                createdByMe: Bool = false, isAwaitingMyReview: Bool = false, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.owner = owner
        self.repo = repo
        self.number = number
        self.title = title
        self.author = author
        self.state = state
        self.createdByMe = createdByMe
        self.isAwaitingMyReview = isAwaitingMyReview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var id: String { url }
    public var url: String { webURL ?? "https://github.com/\(owner)/\(repo)/pull/\(number)" }
    public var repository: String { "\(owner)/\(repo)" }
}
