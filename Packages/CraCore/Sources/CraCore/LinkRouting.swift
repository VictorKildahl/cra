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

// MARK: - In-app link & redirect routing (#868)

/// Per-tab redirect-routing state tracked while a tab is open in a session.
public struct LinkRedirectState: Equatable, Sendable {
    /// Time after the initial load finishes during which a client-side redirect
    /// (<meta refresh>, location.replace) may still move a freshly opened tab.
    public static let clientRedirectGrace: TimeInterval = 2.0

    /// True only for tabs created in-session (link click, ⌘T, external link) before settling.
    /// Restored, woken, pinned, favorite, and split tabs start non-transient.
    public private(set) var isTransient: Bool
    /// Spaces already visited in this tab's initial route chain (loop guard).
    public private(set) var visitedSpaces: Set<UUID>
    /// Number of ATC space moves applied to this tab's chain (max 1).
    public private(set) var hops: Int
    /// When the initial load finished (`nil` while loading).
    public private(set) var settledAt: Date?
    /// Whether a transient tab was opened in the background.
    public var openedInBackground: Bool
    /// Last stable URL on the tab, used to restore settled/pinned tabs
    /// or avoid re-triggering on same-host navigation.
    public var stableURL: String
    /// Recently loaded URL waiting out `clientRedirectGrace` before replacing `stableURL`,
    /// so a 200 OK JS/meta redirector doesn't overwrite `restoreURL` on a source tab.
    public private(set) var pendingURL: String?
    public private(set) var pendingAt: Date?
    /// Suppresses one navigation when an explicit in-tab load (⌘L) or restore runs.
    public var suppressNextRoute: Bool

    public init(isTransient: Bool = false,
                originSpaceID: UUID? = nil,
                routedToSpaceID: UUID? = nil,
                openedInBackground: Bool = false,
                stableURL: String = "",
                suppressNextRoute: Bool = false) {
        self.isTransient = isTransient && routedToSpaceID == nil
        var visited: Set<UUID> = []
        if let originSpaceID { visited.insert(originSpaceID) }
        if let routedToSpaceID { visited.insert(routedToSpaceID) }
        self.visitedSpaces = visited
        self.hops = routedToSpaceID == nil ? 0 : 1
        self.settledAt = nil
        self.openedInBackground = openedInBackground
        self.stableURL = stableURL
        self.pendingURL = nil
        self.pendingAt = nil
        self.suppressNextRoute = suppressNextRoute
    }

    /// Marks the tab settled once its initial load finishes (starting the brief grace window
    /// for `<meta refresh>` / `location.replace` redirects).
    public mutating func noteLoadFinished(at now: Date) {
        if isTransient, settledAt == nil { settledAt = now }
    }

    /// Records a committed/loaded HTTP(S) URL so normal browsing updates `stableURL` once settled
    /// without letting a short-lived JS/meta redirector overwrite the source tab's restore URL.
    public mutating func noteLoaded(url: String, at now: Date) {
        guard LinkRedirectRouting.normalizedHost(of: url) != nil else { return }
        if stableURL.isEmpty {
            stableURL = url
            pendingURL = nil
            pendingAt = nil
        } else if url != stableURL {
            pendingURL = url
            pendingAt = now
        }
    }

    /// Promotes `pendingURL` to `stableURL` once `clientRedirectGrace` has elapsed.
    public mutating func promotePendingIfSettled(at now: Date) {
        guard let pending = pendingURL, let at = pendingAt,
              now.timeIntervalSince(at) > Self.clientRedirectGrace else { return }
        stableURL = pending
        pendingURL = nil
        pendingAt = nil
    }

    /// True while a freshly opened tab has not yet settled past the client-redirect grace window.
    public func isWithinTransientWindow(at now: Date) -> Bool {
        guard isTransient else { return false }
        guard let settledAt else { return true }
        return now.timeIntervalSince(settledAt) <= Self.clientRedirectGrace
    }

    /// Records a space visited during an unmatched redirect hop.
    public mutating func noteVisited(_ spaceID: UUID?) {
        if let spaceID { visitedSpaces.insert(spaceID) }
    }

    /// Records a space move on this transient tab, retiring future moves.
    public mutating func recordMove(to spaceID: UUID, from originSpaceID: UUID? = nil) {
        if let originSpaceID { visitedSpaces.insert(originSpaceID) }
        visitedSpaces.insert(spaceID)
        hops += 1
        isTransient = false
        settledAt = nil
        openedInBackground = false
        pendingURL = nil
        pendingAt = nil
    }

    /// Retires transient eligibility (e.g. after explicit navigation or window elapsed).
    public mutating func retireTransient() {
        isTransient = false
        settledAt = nil
    }

    /// Clears any unpromoted redirector URL when restoring `stableURL`.
    public mutating func clearPending() {
        pendingURL = nil
        pendingAt = nil
    }
}

public enum LinkRedirectDecision: Equatable, Sendable {
    case none
    /// Move the freshly opened transient tab to `spaceID`, switching the window if `follow` is true.
    case moveTab(toSpace: UUID, follow: Bool)
    /// Keep the settled/pinned/favorite/split source tab in place (restoring `restoreURL` if non-empty)
    /// and open a new Today tab for the navigated URL in `spaceID`.
    case openNewTab(inSpace: UUID, restoreURL: String)
}

public enum LinkRedirectRouting {
    /// Resolves an ATC space route for an http(s) URL.
    /// First match wins; `.mostRecentSpace`, `.littleWindow`, missing, standalone, or same-space return `nil`.
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

    /// Evaluates an in-tab URL change (`didChangeURL`) for ATC routing.
    public static func decision(for url: String,
                                currentSpaceID: UUID?,
                                isStandalone: Bool,
                                isPinnedOrFavorite: Bool,
                                inSplit: Bool,
                                state: inout LinkRedirectState,
                                routes: [LinkRoute],
                                spaceAvailable: (UUID) -> Bool,
                                now: Date) -> LinkRedirectDecision {
        if state.suppressNextRoute {
            state.suppressNextRoute = false
            return .none
        }
        state.promotePendingIfSettled(at: now)
        guard let nextHost = normalizedHost(of: url) else { return .none }
        guard !isStandalone else { return .none }

        guard let target = targetSpace(for: url,
                                       currentSpaceID: currentSpaceID,
                                       isStandalone: isStandalone,
                                       routes: routes,
                                       spaceAvailable: spaceAvailable) else {
            if state.isWithinTransientWindow(at: now) {
                state.noteVisited(currentSpaceID)
            }
            return .none
        }

        // Loop guard: never bounce back into an already-visited space or reroute more than once.
        guard state.hops == 0, !state.visitedSpaces.contains(target) else { return .none }

        // Transient new Today tab: move the tab itself.
        if !isPinnedOrFavorite, !inSplit, state.isWithinTransientWindow(at: now) {
            let follow = !state.openedInBackground
            state.recordMove(to: target, from: currentSpaceID)
            return .moveTab(toSpace: target, follow: follow)
        }

        // Settled, pinned, favorite, or split tab: never move it.
        // Guard against same-host browsing (`google.com -> google.com/search?q=scaler`) and
        // subdomains of a site intentionally kept in the current space (`a.scaler.com -> b.scaler.com`).
        if let pending = state.pendingURL, normalizedHost(of: pending) == nextHost {
            return .none
        }
        guard let stableHost = normalizedHost(of: state.stableURL), stableHost != nextHost else {
            return .none
        }
        let stableTarget = targetSpace(for: state.stableURL,
                                       currentSpaceID: currentSpaceID,
                                       isStandalone: isStandalone,
                                       routes: routes,
                                       spaceAvailable: spaceAvailable)
        guard stableTarget != target else { return .none }

        state.retireTransient()
        state.clearPending()
        return .openNewTab(inSpace: target, restoreURL: state.stableURL)
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
