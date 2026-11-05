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
    /// in Safari. A host matches itself and its subdomains. Players only, not whole domains:
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
    ]

    /// What Cra calls each service when it tells the user why a page is WebKit's (the toast,
    /// the Site Control Center, the extension buttons' tooltips).
    public static let serviceNames: [String: String] = [
        "open.spotify.com": "Spotify", "netflix.com": "Netflix", "disneyplus.com": "Disney+",
        "max.com": "Max", "hbomax.com": "HBO Max", "primevideo.com": "Prime Video", "hulu.com": "Hulu",
        "paramountplus.com": "Paramount+", "peacocktv.com": "Peacock", "tv.apple.com": "Apple TV",
        "music.apple.com": "Apple Music", "listen.tidal.com": "Tidal", "www.deezer.com": "Deezer",
        "crunchyroll.com": "Crunchyroll", "hotstar.com": "Hotstar", "jiohotstar.com": "JioHotstar", "v.qq.com": "Tencent Video",
    ]

    /// Off: every page is Chromium's, as before.
    public var isEnabled: Bool
    /// Lower-cased hosts without a leading dot.
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

    /// The listed host `url` falls under, or nil (also while off).
    public func listedHost(for url: String) -> String? {
        guard isEnabled, let host = Self.webHost(of: url) else { return nil }
        return hosts.first { host == $0 || host.hasSuffix("." + $0) }
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

    /// "Open.Spotify.com", " spotify.com ", ".spotify.com" → "spotify.com"; a URL gives its host.
    static func normalizedHost(_ entry: String) -> String? {
        var s = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("://"), let host = webHost(of: s) { s = host }
        while s.hasPrefix(".") { s.removeFirst() }
        while s.hasSuffix(".") { s.removeLast() }
        guard !s.isEmpty, !s.contains("/"), !s.contains(" ") else { return nil }
        return s
    }
}
