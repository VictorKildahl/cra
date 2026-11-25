import Foundation

public struct PullRequestChecks: Codable, Equatable {
    public var passed: Int
    public var failed: Int
    public var pending: Int
    public var skipped: Int
    public var failing: [String]

    public init(passed: Int = 0, failed: Int = 0, pending: Int = 0, skipped: Int = 0, failing: [String] = []) {
        self.passed = passed; self.failed = failed; self.pending = pending; self.skipped = skipped; self.failing = failing
    }
}

/// An empty or failed answer is finished too; only a new item version starts another request.
public struct PullRequestChecksCache {
    public struct Key: Hashable {
        public var url: String
        public var revision: String?
        public var updatedAt: Date?
        public init(_ item: LiveFolderPluginItem) {
            url = item.url; revision = item.revision; updatedAt = item.revision == nil ? item.updatedAt : nil
        }
    }
    private enum Entry { case fetching, finished(PullRequestChecks?) }
    private var entries: [Key: Entry] = [:]
    public init() {}
    public mutating func begin(_ key: Key) -> Bool {
        guard entries[key] == nil else { return false }
        entries[key] = .fetching
        return true
    }
    public mutating func finish(_ key: Key, checks: PullRequestChecks?) { entries[key] = .finished(checks) }
    public func checks(for key: Key) -> PullRequestChecks? {
        if case .finished(let checks) = entries[key] { return checks }
        return nil
    }
}

public enum PullRequestPreview {
    public struct Card: Equatable {
        public var header: String
        public var title: String
        public var checks: String?
        public var failing: [String]
        public var labels: String?
        public var activity: String?
        public var updated: String?
    }

    public static func identity(for url: String) -> String? {
        guard let u = URLComponents(string: url), u.scheme == "https", u.host?.lowercased() == "github.com",
              u.user == nil, u.password == nil, u.port == nil else { return nil }
        let parts = u.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 5, !parts[1].isEmpty, !parts[2].isEmpty, parts[3] == "pull",
              !parts[4].isEmpty, parts[4].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return "\(parts[1])/\(parts[2]) #\(parts[4])"
    }

    public static func card(item: LiveFolderPluginItem, checks: PullRequestChecks?, now: Date) -> Card {
        var card = Card(header: identity(for: item.url) ?? "", title: item.title, failing: [])
        if item.details?.draft == true { card.header += " · Draft" }
        if let checks {
            let total = checks.passed + checks.failed + checks.pending
            if checks.failed > 0 {
                card.checks = "\(checks.failed) failing check\(checks.failed == 1 ? "" : "s")"
                card.failing = Array(checks.failing.prefix(3))
            } else if checks.pending > 0 {
                card.checks = "\(checks.pending) pending check\(checks.pending == 1 ? "" : "s")"
            } else if checks.passed > 0 { card.checks = "All checks passed" }
            if card.checks != nil { card.checks! += " · \(checks.passed)/\(total) passed" }
        }
        if let labels = item.details?.labels, !labels.isEmpty {
            card.labels = labels.prefix(3).map(\.name).joined(separator: ", ") + (labels.count > 3 ? " +\(labels.count - 3)" : "")
        }
        var activity: [String] = []
        if let count = item.details?.commentCount, count > 0 { activity.append("\(count) comment\(count == 1 ? "" : "s")") }
        if let tasks = item.details?.tasks { activity.append("\(tasks.done) of \(tasks.total) tasks") }
        if !activity.isEmpty { card.activity = activity.joined(separator: " · ") }
        if let updated = item.updatedAt {
            let seconds = max(0, now.timeIntervalSince(updated))
            let age: String
            if seconds < 60 { age = "just now" }
            else if seconds < 3600 { age = "\(Int(seconds / 60)) min ago" }
            else if seconds < 86400 { age = "\(Int(seconds / 3600)) h ago" }
            else { age = "\(Int(seconds / 86400)) d ago" }
            card.updated = "Updated " + age
        }
        return card
    }
}
