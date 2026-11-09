import Foundation

// Arc's Air Traffic Control (Settings ▸ Links ▸ Air Traffic Control…, stored in
// StorableLinkRouting.json, see docs/arc-reverse-engineering.md): a link from another
// app is checked against the routes in order, the first match decides where it opens
// and anything else goes to the default destination.

/// Arc's LinkSourceTextMatchingStyle (`matches` / `contains`).
public enum LinkMatchStyle: String, Codable, CaseIterable, Identifiable {
    case equals, contains
    public var id: String { rawValue }
    public var label: String { self == .equals ? "Is equal to" : "Contains" }
}

/// Arc's LinkDestination is `space(ProfileDestination)` or `littleArc(ProfileDestination)`
/// with ProfileDestination `mostRecent | space(id) | profile(…)`. Its editor only offers
/// space(mostRecent), space(id) and littleArc(mostRecent); a hand-written littleArc(space)
/// only picked the page's profile and still said "Open in <most recent space>".
/// A space destination opens a new foreground tab in that space's Today list (also when
/// the URL is already open) and switches the window to the space.
/// A Little Window may name a space (#258, past Arc): the page loads in that space's
/// profile and "Open in" / ⌘O sends it there; nil is the space in use, as in Arc.
public enum LinkDestination: Codable, Hashable {
    case mostRecentSpace
    case space(UUID)
    /// Saved as `{"littleWindow": {}}` without a space, as before #258, and
    /// `{"littleWindow": {"space": "<id>"}}` with one, which older Cra reads as a plain
    /// Little Window rather than dropping the routes.
    case littleWindow(space: UUID?)

    /// A Little Window in the space in use.
    public static let littleWindowInUse = LinkDestination.littleWindow(space: nil)

    public var isLittleWindow: Bool {
        if case .littleWindow = self { return true }
        return false
    }
}

public struct LinkRoute: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var match: LinkMatchStyle = .contains
    public var text = ""
    public var destination: LinkDestination = .mostRecentSpace

    public init(id: UUID = UUID(), match: LinkMatchStyle = .contains, text: String = "", destination: LinkDestination = .mostRecentSpace) {
        self.id = id
        self.match = match
        self.text = text
        self.destination = destination
    }

    /// Matches like Arc 1.170 (observed by handing it links, see docs/arc-reverse-engineering.md):
    /// both sides lose case, the scheme and a leading `www.`; "Contains" then searches the
    /// rest including query and fragment, while "Is equal to" also drops the query, the
    /// fragment and trailing slashes, so `example.com/a` equals `http://www.example.com/a/?x#y`
    /// but not `example.com/a/b`. An empty route matches nothing.
    public func matches(_ url: String) -> Bool {
        let want = Self.normalized(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !want.isEmpty else { return false }
        let have = Self.normalized(url)
        switch match {
        case .contains: return have.contains(want)
        case .equals: return Self.page(have) == Self.page(want)
        }
    }

    private static func normalized(_ url: String) -> String {
        var s = Substring(url.lowercased())
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        if s.hasPrefix("www.") { s = s.dropFirst(4) }
        return String(s)
    }

    /// Host and path only.
    private static func page(_ s: String) -> Substring {
        var p = s[..<(s.firstIndex { $0 == "?" || $0 == "#" } ?? s.endIndex)]
        while p.hasSuffix("/") { p = p.dropLast() }
        return p
    }

    /// Arc seeds this route once (AppState+DefaultLinkRoutes, `didSetDefaultGoogleMeetRoute`)
    /// so calls open in a full window rather than in Little Arc.
    public static let googleMeet = LinkRoute(match: .contains, text: "meet.google.com", destination: .mostRecentSpace)
}

extension AppSettings {
    /// Where a link from another app opens: the first matching route, else the default.
    public func destination(forExternalURL url: String) -> LinkDestination {
        linkRoutes.first { $0.matches(url) }?.destination ?? defaultLinkDestination
    }
}

/// Arc's Peek opens links "to other sites": the registrable domain differs, so a link from
/// mail.google.com to accounts.google.com stays in the tab. Cra has no public suffix list;
/// a generic second-level label under a country code (co.uk, com.au) counts as suffix.
public enum SiteKey {
    private static let secondLevel: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gv"]

    public static func site(of url: String) -> String? {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host?.lowercased(), !host.isEmpty else { return nil }
        let labels = host.split(separator: ".")
        if labels.count <= 2 || host.allSatisfy({ $0.isNumber || $0 == "." }) || host.contains(":") { return host }
        let n = labels.count
        let keep = labels[n - 1].count == 2 && secondLevel.contains(labels[n - 2]) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
