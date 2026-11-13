import Foundation

/// The card on Settings' first tab (named after the user, as Arc's), in the place of Arc's membership card (Arc 1.172.2's Account tab: the member's
/// name, a nickname, anniversary stamps and the date they joined). Cra has no account and no server, so all of it
/// comes from this Mac: the name macOS has for the user, the day Cra's data folder was made, and a nickname picked
/// from that, the same every time the card is drawn.
public struct MemberCard: Equatable, Sendable {
    public let name: String
    public let nickname: String
    public let since: Date
    public let stamps: [Stamp]
    /// Which of the card's colour themes this member gets (0..<themeCount), from the same seed as the nickname, so
    /// cards differ from member to member as Arc's do.
    public let theme: Int

    public static let themeCount = 4

    public enum Stamp: Equatable, Sendable {
        /// Joined in Cra's first year (it came out in October 2026).
        case early(year: Int)
        /// One stamp through the first year that grows at 1, 3 and 6 months (Victor, 12 Nov 2026: one stamp,
        /// not one a month, so the early stamp stays and the card isn't empty until the first anniversary).
        case months(Int)
        /// Each full year since the user joined, as Arc's anniversary stamps.
        case anniversary(Int)
    }

    /// The last year a new user still gets the early stamp.
    public static let earlyUntilYear = 2026
    /// The months the first-year stamp marks.
    public static let monthMilestones = [1, 3, 6]

    public init(fullName: String, since: Date, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        name = Self.displayName(fullName)
        let seed = "\(name)|\(Int(since.timeIntervalSince1970))"
        nickname = Self.nickname(seed: seed)
        theme = Self.theme(seed: seed)
        self.since = since
        stamps = Self.stamps(since: since, now: now, calendar: calendar)
    }

    /// The name on the card: macOS's full name for the user, or "Cra Member" when it has none.
    public static func displayName(_ fullName: String) -> String {
        let trimmed = fullName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return trimmed.isEmpty ? "Cra Member" : trimmed
    }

    /// The early stamp first, then in the first year the months stamp (its latest milestone only), after it the
    /// anniversaries, the newest last; at most three, as the card has room for.
    public static func stamps(since: Date, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Stamp] {
        var stamps: [Stamp] = []
        let year = calendar.component(.year, from: since)
        if year <= earlyUntilYear { stamps.append(.early(year: year)) }
        let elapsed = calendar.dateComponents([.year, .month], from: since, to: now)
        let years = max(0, elapsed.year ?? 0)
        if years > 0 {
            stamps += (1...years).map { .anniversary($0) }
        } else if let reached = monthMilestones.last(where: { $0 <= max(0, elapsed.month ?? 0) }) {
            stamps.append(.months(reached))
        }
        return Array(stamps.suffix(3))
    }

    static let adjectives = [
        "Cosy", "Brave", "Sleepy", "Curious", "Swift", "Quiet", "Lucky", "Sunny", "Fuzzy", "Bold", "Gentle", "Witty",
        "Soggy", "Breezy", "Mellow", "Plucky", "Dapper", "Nimble", "Jolly", "Snappy", "Zesty", "Spry", "Tidy", "Wild",
    ]
    static let nouns = [
        "Crab", "Wanderer", "Navigator", "Explorer", "Voyager", "Pilot", "Tabkeeper", "Hermit", "Drifter", "Skipper",
        "Captain", "Scout", "Ranger", "Sailor", "Nomad", "Pioneer", "Lookout", "Beachcomber", "Diver", "Surfer",
    ]

    /// A nickname from the seed, as Arc gives each member one ("Soggy Warrior"). The hash is FNV-1a, not Swift's
    /// `hashValue`, which changes between launches.
    public static func nickname(seed: String) -> String {
        let h = hash(seed)
        let a = adjectives[Int(h % UInt64(adjectives.count))]
        let n = nouns[Int((h / UInt64(adjectives.count)) % UInt64(nouns.count))]
        return "\(a) \(n)"
    }

    /// The colour theme from the seed: the hash run through MurmurHash3's finaliser first, so it doesn't follow the
    /// nickname's words (FNV-1a's high bits barely move when only the seed's end differs).
    public static func theme(seed: String) -> Int {
        var h = hash(seed)
        h ^= h >> 33
        h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        h = h &* 0xc4ce_b9fe_1a85_ec53
        h ^= h >> 33
        return Int(h % UInt64(themeCount))
    }

    private static func hash(_ seed: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return h
    }
}

/// "Share Cra with a Friend" (Arc's "Gift Arc to a Friend"): the words and the link a user sends. Arc's link is the
/// member's own gift page on arc.net; Cra has no server to count gifts, so the link is the site's front page tagged
/// like every link the app opens (SiteLinks), and the site's analytics see it under the "share" campaign.
public enum ShareCra {
    public static let message = "Here’s a link to download Cra, the browser I was telling you about!"
    public static var link: String { SiteLinks.tagged("https://crabrowser.app/", from: .share) }
    /// What the system share menu and the member card's Share… send.
    public static var text: String { "\(message)\n\n\(link)" }
}
