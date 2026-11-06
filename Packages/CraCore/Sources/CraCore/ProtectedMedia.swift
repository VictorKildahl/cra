import Foundation

/// Which engine draws a page.
public enum PageEngine: String, Equatable, Sendable {
    /// Chromium (CEF): every page, unless a rule below says otherwise.
    case chromium
    /// The Mac's own WebKit (WKWebView), for sites whose DRM licence servers turn Cra's
    /// Chromium away.
    case webKit
}

/// Sites that play protected media (DRM) only in WebKit.
///
/// Chromium's Widevine CDM works in Cra, but the licence servers of these services also want
/// Widevine's Verified Media Path: `.sig` files for Cra's binaries, signed with a certificate
/// Google licenses through paid partners (docs/protected-media.md). Without it Spotify skips
/// track after track and Disney+ shows error 83 (GitHub #66). WebKit uses Apple's FairPlay,
/// which macOS gives any app: no certificate, no signing, no fee. So these sites open in a
/// WKWebView tab, which Safari's user agent makes look like Safari to them.
///
/// The rules, as a value so they can be tested without a page:
/// - A page Cra opens (a tab restored or created, a URL typed, a pinned tab reset) gets
///   `engine(for:)`: WebKit for a listed site, Chromium for anything else.
/// - A navigation a Chromium page starts itself (a link, a redirect, history) to a listed site
///   moves to WebKit before the request goes out (`handoff`), so a sign-in callback's one-time
///   code is spent in the engine that keeps the session. A POST stays: its body can't move.
/// - A WebKit page stays in WebKit wherever it navigates by itself: sign-in goes through
///   other sites (accounts.google.com, appleid.apple.com) and has to come back to the same
///   cookies. Cra's own navigations (the URL bar) pick the engine again.
public struct ProtectedMediaSites: Equatable, Sendable {
    /// The web players of services that need Verified Media Path in Chromium on a Mac and play
    /// in Safari. A host matches itself and its subdomains; "host/path" also needs the address's
    /// path to start with that path (Prime Video on Amazon). Players only, not whole domains:
    /// other sites send their "Sign in with Spotify/Tidal/Deezer" through accounts.spotify.com,
    /// login.tidal.com and connect.deezer.com, and those must finish in the engine they started in.
    public static let defaultHosts: [String] = [
        "open.spotify.com",
        "netflix.com",
        "disneyplus.com",
        // Max signs in on its own hosts and sends play.max.com on to www.hbomax.com; no other site
        // signs in with Max, so the whole domains.
        "max.com", "hbomax.com",
        "primevideo.com",
        "hulu.com",
        "paramountplus.com",
        "peacocktv.com",
        "tv.apple.com", "music.apple.com",
        "listen.tidal.com",
        "www.deezer.com",
        // Also on Ardia's list (another open-source browser that sends DRM sites to WebKit,
        // apps/browser/src/state/engines/engines.ts, 5 Nov 2026).
        "crunchyroll.com",
        "hotstar.com", "jiohotstar.com",
        "v.qq.com",
        // Seen refusing non-VMP Chromium ("Verified Media Path" errors for Joyn and Rakuten TV,
        // Nov 2024), and Sky's and Peacock's platforms, which fail as Peacock does (5 Nov 2026).
        "joyn.de", "joyn.at", "joyn.ch",
        "rakuten.tv",
        "skyshowtime.com", "nowtv.com", "wowtv.de", "showmax.com",
        // Prime Video where Amazon itself serves it (the US, and Amazon's stores that keep it under
        // /gp/video); the rest of Amazon (shopping, Login with Amazon) stays in Chromium.
    ] + amazonStores.map { "\($0)/gp/video" } + [
        // Amazon Music needs production VMP in Chromium (Parachord's tests, castlabs EVS, Nov 2026).
    ] + amazonStores.map { "music.\($0)" }

    /// Amazon's storefronts with Prime Video and Amazon Music.
    static let amazonStores = ["amazon.com", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.it", "amazon.es", "amazon.ca",
                               "amazon.co.jp", "amazon.com.au", "amazon.in", "amazon.com.mx", "amazon.com.br"]

    /// What Cra calls each service when it tells the user why a page is WebKit's (the toast,
    /// the Site Control Center, the extension buttons' tooltips).
    public static let serviceNames: [String: String] = [
        "open.spotify.com": "Spotify", "netflix.com": "Netflix", "disneyplus.com": "Disney+",
        "max.com": "Max", "hbomax.com": "HBO Max", "primevideo.com": "Prime Video", "hulu.com": "Hulu",
        "paramountplus.com": "Paramount+", "peacocktv.com": "Peacock", "tv.apple.com": "Apple TV",
        "music.apple.com": "Apple Music", "listen.tidal.com": "Tidal", "www.deezer.com": "Deezer",
        "crunchyroll.com": "Crunchyroll", "hotstar.com": "Hotstar", "jiohotstar.com": "JioHotstar", "v.qq.com": "Tencent Video",
        "joyn.de": "Joyn", "joyn.at": "Joyn", "joyn.ch": "Joyn", "rakuten.tv": "Rakuten TV", "skyshowtime.com": "SkyShowtime",
        "nowtv.com": "NOW", "wowtv.de": "WOW", "showmax.com": "Showmax",
    ].merging(amazonStores.flatMap { [("\($0)/gp/video", "Prime Video"), ("music.\($0)", "Amazon Music")] }) { a, _ in a }

    /// Off: every page is Chromium's, as before.
    public var isEnabled: Bool
    /// Lower-cased hosts without a leading dot, some with a path ("amazon.com/gp/video").
    public private(set) var hosts: [String]

    /// `extraHosts` add to the list (tests, a user's own entries); `removedHosts` take sites
    /// off it.
    public init(isEnabled: Bool = true, extraHosts: [String] = [], removedHosts: [String] = []) {
        self.isEnabled = isEnabled
        let removed = Set(removedHosts.compactMap(Self.normalizedHost))
        var seen = Set<String>()
        hosts = (Self.defaultHosts + extraHosts).compactMap(Self.normalizedHost)
            .filter { !removed.contains($0) && seen.insert($0).inserted }
    }

    /// The engine a page Cra opens at `url` gets.
    public func engine(for url: String) -> PageEngine {
        listedHost(for: url) == nil ? .chromium : .webKit
    }

    /// The listed entry `url` falls under, or nil (also while off).
    public func listedHost(for url: String) -> String? {
        guard isEnabled, let host = Self.webHost(of: url) else { return nil }
        let path = URLComponents(string: url.trimmingCharacters(in: .whitespaces))?.path.lowercased() ?? ""
        return hosts.first { entry in
            let (h, p) = Self.split(entry)
            guard host == h || host.hasSuffix("." + h) else { return false }
            guard let p else { return true }
            return path == p || path.hasPrefix(p + "/")
        }
    }

    /// "amazon.com/gp/video" → ("amazon.com", "/gp/video"); "netflix.com" → ("netflix.com", nil).
    static func split(_ entry: String) -> (host: String, path: String?) {
        guard let slash = entry.firstIndex(of: "/") else { return (entry, nil) }
        return (String(entry[..<slash]), String(entry[slash...]))
    }

    /// The user's own choice for a site (the Site Control Center's Safari's Engine switch): the
    /// lists Cra keeps of sites added to WebKit and listed ones taken off, after choosing `engine`
    /// for `url`'s host. Choosing WebKit lifts a removal (else adds the host); choosing Chromium
    /// drops an added host, and takes off the listed entry the address falls under.
    public static func choosing(_ engine: PageEngine, for url: String, added: [String], removed: [String])
        -> (added: [String], removed: [String]) {
        guard let host = webHost(of: url) else { return (added, removed) }
        var added = added.compactMap(normalizedHost), removed = removed.compactMap(normalizedHost)
        let defaults = ProtectedMediaSites(removedHosts: removed)
        switch engine {
        case .webKit:
            // A listed entry this site falls under, taken off earlier, comes back.
            let all = ProtectedMediaSites()
            if let entry = all.listedHost(for: url) { removed.removeAll { $0 == entry } }
            if ProtectedMediaSites(extraHosts: added, removedHosts: removed).engine(for: url) == .chromium, !added.contains(host) {
                added.append(host)
            }
        case .chromium:
            added.removeAll { entry in host == split(entry).host || host.hasSuffix("." + split(entry).host) }
            if let entry = defaults.listedHost(for: url), !removed.contains(entry) { removed.append(entry) }
        }
        return (added, removed)
    }

    /// The service's name for a page at `url` ("Spotify"); a host someone added names itself.
    public func serviceName(for url: String) -> String? {
        listedHost(for: url).map { Self.serviceNames[$0] ?? $0 }
    }

    /// A navigation a page started itself: the engine it has to move to, or nil to stay.
    /// `method` is the request's HTTP method.
    public func handoff(from current: PageEngine, to url: String, method: String) -> PageEngine? {
        guard current == .chromium, method.uppercased() == "GET", engine(for: url) == .webKit else { return nil }
        return .webKit
    }

    /// The host of an http(s) URL, lower-cased; nil for any other scheme (about:, chrome:,
    /// file:, data:, view-source:), which only Chromium shows.
    static func webHost(of url: String) -> String? {
        guard let c = URLComponents(string: url.trimmingCharacters(in: .whitespaces)),
              let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = c.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    /// "Open.Spotify.com", " spotify.com ", ".spotify.com" → "spotify.com"; a URL gives its host;
    /// "amazon.com/gp/video/" keeps its path, without the last slash.
    static func normalizedHost(_ entry: String) -> String? {
        var s = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("://"), let host = webHost(of: s) { s = host }
        var (host, path) = split(s)
        while host.hasPrefix(".") { host.removeFirst() }
        while host.hasSuffix(".") { host.removeLast() }
        while path?.hasSuffix("/") == true { path?.removeLast() }
        guard !host.isEmpty, !host.contains(" "), path?.contains(" ") != true, path?.contains("?") != true else { return nil }
        return path.map { $0.isEmpty ? host : host + $0 } ?? host
    }
}

/// protected-media.json in the data folder: the user's own choices about which engine plays a
/// site (the Site Control Center's Safari's Engine switch, `ProtectedMediaSites.choosing`) and the
/// services whose "plays with Safari's engine" toast was closed. In the data folder, not the
/// defaults, so each profile folder and test instance (CRA_DATA_DIR) keeps its own.
public struct ProtectedMediaChoices: Codable, Equatable, Sendable {
    /// Sites the user sent to WebKit.
    public var added: [String]
    /// Listed entries the user took back to Chromium.
    public var removed: [String]
    /// Services whose toast was closed with its ✕.
    public var told: [String]

    public init(added: [String] = [], removed: [String] = [], told: [String] = []) {
        self.added = added
        self.removed = removed
        self.told = told
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try c.decodeIfPresent([String].self, forKey: .added) ?? []
        removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? []
        told = try c.decodeIfPresent([String].self, forKey: .told) ?? []
    }

    /// After choosing `engine` for `url`'s site.
    public func choosing(_ engine: PageEngine, for url: String) -> ProtectedMediaChoices {
        let r = ProtectedMediaSites.choosing(engine, for: url, added: added, removed: removed)
        return ProtectedMediaChoices(added: r.added, removed: r.removed, told: told)
    }

    /// After the user closed `service`'s toast.
    public func telling(_ service: String) -> ProtectedMediaChoices {
        told.contains(service) ? self : ProtectedMediaChoices(added: added, removed: removed, told: told + [service])
    }
}
