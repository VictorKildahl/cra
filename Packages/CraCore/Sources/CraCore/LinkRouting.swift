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

    /// The space a URL typed in the ⌘T bar opens in (#421): Arc 1.173 runs it through the routes
    /// too, and when the first match is a route to a space the new tab opens there and the window
    /// switches to it. Nil keeps it in the space in use: no match (the default never applies, a
    /// typed URL that matches nothing stays put in Arc), Most Recent Space (the window's own) and
    /// a Little Window (not seen in Arc for typed URLs).
    public func space(forTypedURL url: String) -> UUID? {
        guard case .space(let id)? = linkRoutes.first(where: { $0.matches(url) })?.destination else { return nil }
        return id
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

// MARK: - Link tabs and redirects (#868)

/// Air Traffic Control for a tab a page's link, ⌘T or another app has just opened (#868, past Arc):
/// until its first page has loaded, and for `clientRedirectGrace` after that, an address that matches a
/// route to another space moves the tab there, once. The grace lets a redirector that answers 200 and
/// moves on by script or `<meta refresh>` (google.com/url?q=…) still land in the routed space.
/// Every other navigation stays in its tab and space, as in Arc, whose Air Traffic Control never
/// routes a navigation inside a tab.
public struct LinkRedirectState: Equatable, Sendable {
    /// How long after its first page loads a new tab may still be routed by a client-side redirect.
    public static let clientRedirectGrace: TimeInterval = 2.0

    /// False once the tab has moved, or its first page has loaded and the grace has passed.
    public private(set) var isTransient = true
    /// When its first page finished loading (`nil` while it loads).
    public private(set) var settledAt: Date?

    public init() {}

    /// Starts the grace once the first page has loaded.
    public mutating func noteLoadFinished(at now: Date) {
        if isTransient, settledAt == nil { settledAt = now }
    }

    /// True while the tab is still on its way to its first page, or inside the grace after it.
    public func isWithinTransientWindow(at now: Date) -> Bool {
        guard isTransient else { return false }
        guard let settledAt else { return true }
        return now.timeIntervalSince(settledAt) <= Self.clientRedirectGrace
    }

    /// The tab is done with Air Traffic Control: it moved, or the user took over its address (⌘L).
    public mutating func retireTransient() {
        isTransient = false
        settledAt = nil
    }
}

public enum LinkRedirectDecision: Equatable, Sendable {
    case none
    /// Move the new tab to `spaceID`; the window follows it when `follow` (the tab is the one in front).
    case moveTab(toSpace: UUID, follow: Bool)
}

public enum LinkRedirectRouting {
    /// The space an http(s) URL's first matching route sends it to, or nil: no match, Most Recent
    /// Space, a Little Window, a space that's gone or standalone, or the space it is already in.
    public static func targetSpace(for url: String,
                                   currentSpaceID: UUID?,
                                   isStandalone: Bool,
                                   routes: [LinkRoute],
                                   spaceAvailable: (UUID) -> Bool) -> UUID? {
        guard !isStandalone, normalizedHost(of: url) != nil else { return nil }
        guard case .space(let target)? = routes.first(where: { $0.matches(url) })?.destination else { return nil }
        guard target != currentSpaceID, spaceAvailable(target) else { return nil }
        return target
    }

    /// What a tab's address change (`didChangeURL`) does under Air Traffic Control. Only a new tab
    /// inside its window moves; pinned, favorite and split tabs never do. `isInFront`: the tab is the one
    /// the window shows, so the window follows it; otherwise it moves on its own, as one opened behind.
    public static func decision(for url: String,
                                currentSpaceID: UUID?,
                                isStandalone: Bool,
                                isPinnedOrFavorite: Bool,
                                inSplit: Bool,
                                isInFront: Bool,
                                state: inout LinkRedirectState,
                                routes: [LinkRoute],
                                spaceAvailable: (UUID) -> Bool,
                                now: Date) -> LinkRedirectDecision {
        guard state.isWithinTransientWindow(at: now) else {
            state.retireTransient()
            return .none
        }
        guard !isPinnedOrFavorite, !inSplit,
              let target = targetSpace(for: url, currentSpaceID: currentSpaceID, isStandalone: isStandalone,
                                       routes: routes, spaceAvailable: spaceAvailable) else { return .none }
        // One move per tab: a redirect back from the routed space doesn't bounce it again.
        state.retireTransient()
        return .moveTab(toSpace: target, follow: isInFront)
    }

    /// Lowercased host for http(s) URLs with leading `www.` stripped; `nil` for non-web schemes
    /// (`about:`, `data:`, `javascript:`, `blob:`, `cra:`, `chrome:`, `file:`, empty/invalid).
    public static func normalizedHost(of url: String) -> String? {
        guard let u = URL(string: url),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = u.host?.lowercased(),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}

extension AppSettings {
    /// The space an in-app link click should open in (#868), or `nil` to stay in `currentSpaceID`.
    public func space(forLinkURL url: String,
                      currentSpaceID: UUID?,
                      isStandalone: Bool,
                      spaceAvailable: (UUID) -> Bool) -> UUID? {
        LinkRedirectRouting.targetSpace(for: url,
                                        currentSpaceID: currentSpaceID,
                                        isStandalone: isStandalone,
                                        routes: linkRoutes,
                                        spaceAvailable: spaceAvailable)
    }
}
