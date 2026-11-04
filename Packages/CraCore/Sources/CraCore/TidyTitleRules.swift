import Foundation

/// Arc's tidy titles: the sidebar shows "Jupiter" for a tab whose page is "Jupiter - Wikipedia",
/// "Gmail" for the inbox, a Figma file without " – Figma". Per-site rules from Arc 1.171
/// (TidyTabTitles' TidyTitleConfiguration: siteName, rules of `match` + `title`), applied to every
/// tab's displayed title whatever Arc Max says (checked live 4 Nov 2026 with renamePinnedTabsEnabled
/// off), never to a name the user gave. The stored page title stays as it is.
public struct TidyTitleRules: Sendable {
    public struct Site: Decodable, Sendable {
        public var siteName: String
        public var rules: [Rule]
    }

    public struct Rule: Decodable, Sendable {
        public var match: Match?
        public var title: Title
    }

    /// Where on the site a rule applies; no match applies everywhere (Arc's PathMatchType).
    public struct Match: Decodable, Sendable {
        public var pathEquals: String?
        public var pathContainsRegex: String?
        public var fragmentEquals: String?
        public var fragmentContainsRegex: String?
    }

    /// What the title becomes (Arc's TitleModifier).
    public struct Title: Decodable, Sendable {
        public var always: String?
        public var removingPattern: String?
        public var removingPatterns: [String]?
    }

    public let sites: [String: Site]

    public init(sites: [String: Site]) { self.sites = sites }

    /// Arc's own rules.
    public static let arc: TidyTitleRules = {
        let sites = (try? JSONDecoder().decode([String: Site].self, from: Data(arcRulesJSON.utf8))) ?? [:]
        return TidyTitleRules(sites: sites)
    }()

    /// The rules' site for a host: an exact match, "www." ignored ("amazon.com" is not
    /// "aws.amazon.com", which has its own).
    public func site(forHost host: String) -> Site? {
        let h = host.lowercased()
        return sites[h] ?? (h.hasPrefix("www.") ? sites[String(h.dropFirst(4))] : nil)
    }

    /// The title the sidebar shows for a page: the first rule that fits the URL, or the page's own
    /// title. A rule that would leave nothing keeps the page's title.
    public func tidy(_ title: String, url: String) -> String {
        guard !title.isEmpty, let u = URLComponents(string: url), let host = u.host, let site = site(forHost: host) else { return title }
        let path = u.path.isEmpty ? "/" : u.path
        let fragment = u.fragment ?? ""
        for rule in site.rules where Self.fits(rule.match, path: path, fragment: fragment) {
            let out = Self.apply(rule.title, to: title)
            return out.isEmpty ? title : out
        }
        return title
    }

    static func fits(_ m: Match?, path: String, fragment: String) -> Bool {
        guard let m else { return true }
        if let p = m.pathEquals, path != p { return false }
        if let r = m.pathContainsRegex, !contains(path, r) { return false }
        if let f = m.fragmentEquals, fragment != f { return false }
        if let r = m.fragmentContainsRegex, !contains(fragment, r) { return false }
        return true
    }

    static func apply(_ t: Title, to title: String) -> String {
        if let a = t.always { return a }
        var out = title
        for p in (t.removingPattern.map { [$0] } ?? []) + (t.removingPatterns ?? []) {
            guard let re = regex(p) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contains(_ s: String, _ pattern: String) -> Bool {
        regex(pattern)?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static let cache = NSCache<NSString, NSRegularExpression>()

    static func regex(_ p: String) -> NSRegularExpression? {
        if let r = cache.object(forKey: p as NSString) { return r }
        guard let r = try? NSRegularExpression(pattern: p) else { return nil }
        cache.setObject(r, forKey: p as NSString)
        return r
    }
}
