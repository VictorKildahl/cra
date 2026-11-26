import Foundation

public struct PullRequestChecks: Codable, Equatable {
    public var passed: Int
    public var failed: Int
    public var pending: Int
    public var skipped: Int
    public var failing: [String]
    /// The most a count may be; GitHub's checks page lists far fewer jobs.
    public static let maxCount = 100_000

    public init(passed: Int = 0, failed: Int = 0, pending: Int = 0, skipped: Int = 0, failing: [String] = []) {
        self.passed = passed; self.failed = failed; self.pending = pending; self.skipped = skipped; self.failing = failing
    }

    private enum CodingKeys: String, CodingKey { case passed, failed, pending, skipped, failing }
    /// A plugin's answer: a count below zero or above `maxCount` is refused, so the card's sums can't overflow.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int {
            let value = try c.decode(Int.self, forKey: key)
            guard (0...Self.maxCount).contains(value) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Check count out of range")
            }
            return value
        }
        passed = try count(.passed); failed = try count(.failed); pending = try count(.pending); skipped = try count(.skipped)
        failing = try c.decode([String].self, forKey: .failing)
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
    public func reservesSlot(for key: Key) -> Bool {
        if case .finished(let checks) = entries[key] {
            guard let checks else { return false }
            return checks.passed + checks.failed + checks.pending + checks.skipped > 0
        }
        return true
    }
    public func checks(for key: Key) -> PullRequestChecks? {
        if case .finished(let checks) = entries[key] { return checks }
        return nil
    }
}

public enum PullRequestPreview {
    public struct Label: Equatable {
        public var name: String
        public var color: RGB?
        public var textColor: RGB? { color.map { PullRequestPreview.labelTextColor($0) } }
    }
    public struct Checks: Equatable {
        public enum State { case passed, failed, pending }
        public var state: State
        public var passed: Int
        public var total: Int
    }
    public struct Card: Equatable {
        public var repo: String
        public var number: String
        public var title: String
        public var author: String?
        public var draft: Bool
        public var age: String?
        public var checks: Checks?
        public var failing: [String]
        public var extraFailing: Int
        public var commentCount: Int?
        public var tasks: LiveFolderPluginItem.Details.Tasks?
        public var labels: [Label]
        public var extraLabels: Int
        public func showsStatusRow(reservingChecks: Bool) -> Bool {
            reservingChecks || draft || checks != nil || commentCount != nil || tasks != nil
        }
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
        let identity = identity(for: item.url)?.components(separatedBy: " #") ?? []
        let labels = item.details?.labels ?? []
        var card = Card(repo: identity.first ?? "", number: identity.last ?? "", title: item.title,
                        author: item.subtitle.flatMap { $0.isEmpty ? nil : $0 }, draft: item.details?.draft == true,
                        age: item.updatedAt.map { age(seconds: max(0, now.timeIntervalSince($0))) },
                        failing: [], extraFailing: 0,
                        commentCount: item.details?.commentCount.flatMap { $0 > 0 ? $0 : nil }, tasks: item.details?.tasks,
                        labels: labels.prefix(3).map { Label(name: $0.name, color: rgb($0.color)) },
                        extraLabels: max(0, labels.count - 3))
        if let checks {
            let done = checks.passed + checks.skipped
            let total = done + checks.failed + checks.pending
            if total > 0 {
                card.checks = Checks(state: checks.failed > 0 ? .failed : checks.pending > 0 ? .pending : .passed,
                                     passed: done, total: total)
            }
            if checks.failed > 0 {
                card.failing = Array(checks.failing.prefix(3))
                card.extraFailing = max(0, checks.failed - card.failing.count)
            }
        }
        return card
    }

    private static func rgb(_ hex: String?) -> RGB? {
        guard let hex else { return nil }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.allSatisfy(\.isHexDigit), let color = HexColor.components(digits) else { return nil }
        return RGB(color.r, color.g, color.b)
    }

    private static func labelTextColor(_ color: RGB) -> RGB {
        func luminance(_ c: RGB) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        let target = 4.5 * (luminance(RGB(25 / 255, 24 / 255, 23 / 255)) + 0.05) - 0.05
        guard luminance(color) < target else { return color }
        let (h, s, l) = SpaceTheme.hsl(color)
        let hue = SpaceTheme.rgb(h: h, s: 1, v: 1)
        func at(_ lightness: Double) -> RGB {
            let chroma = (1 - abs(2 * lightness - 1)) * s, m = lightness - chroma / 2
            return RGB(m + hue.0 * chroma, m + hue.1 * chroma, m + hue.2 * chroma)
        }
        var low = l, high = 1.0
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if luminance(at(middle)) < target { low = middle } else { high = middle }
        }
        return at(high)
    }

    private static func age(seconds: TimeInterval) -> String {
        if seconds < 60 { return "just now" }
        if seconds >= 86400 && seconds < 172800 { return "yesterday" }
        let units: [(TimeInterval, String)] = [(31536000, "year"), (2592000, "month"), (604800, "week"),
                                              (86400, "day"), (3600, "hour"), (60, "minute")]
        let (duration, unit) = units.first { seconds >= $0.0 }!
        let count = Int(seconds / duration)
        return "\(count) \(unit)\(count == 1 ? "" : "s") ago"
    }
}
