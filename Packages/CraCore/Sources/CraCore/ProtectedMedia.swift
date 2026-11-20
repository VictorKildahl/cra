import Foundation

/// Which engine draws a page.
public enum PageEngine: String, Equatable, Sendable {
    /// Chromium (CEF): every page, unless a rule below says otherwise.
    case chromium
    /// The Mac's own WebKit (WKWebView), for sites whose DRM licence servers turn Cra's
    /// Chromium away.
    case webKit
}

/// A site that is mostly not protected media but has some: YouTube's bought and rented films
/// among its ordinary videos. Putting the whole site on the WebKit list would take extensions
/// away from every page of it, so only the page that plays a protected video moves, when it asks
/// for Widevine, and the user is asked first (`ProtectedVideoPages`, docs/protected-media.md).
public struct MixedMediaSite: Equatable, Sendable {
    /// Matches itself and its subdomains ("youtube.com").
    public var host: String
    /// What Cra calls it ("YouTube").
    public var name: String
    /// Hosts under `host` that are left alone ("music.youtube.com").
    public var excludedHosts: [String]
    /// The query items that name the video ("v" of /watch?v=…): with the path they are the page.
    /// Empty: the whole query is, unless `pathNamesVideo`.
    public var videoParameters: [String]
    /// The path alone names the video ("/content/browse/play/7236/PURCHASED_CONTENT"): no query
    /// item makes it another page.
    public var pathNamesVideo: Bool
    /// Where the site's videos play ("/content/browse/play"): only a page under one of these is
    /// asked about or moved. Empty: any page of the site. For a site whose other pages ask for
    /// Widevine too (Fandango at Home's front page does, twice, with nothing playing).
    public var videoPaths: [String]
    /// Where the site signs in ("google.com"): a switched page stays in WebKit there, so a sign-in
    /// made in WebKit comes back to the same cookies. Their cookies are not copied from Chromium:
    /// a whole Google account's sign-in would land in WebKit's store for one film.
    public var signInHosts: [String]
    /// The site's own sign-in addresses ("/signin", where Google's sign-in lands on YouTube).
    public var signInPaths: [String]
    /// Other hosts whose cookies hold the site's session (Fandango at Home keeps it on
    /// ".fandango.com"): copied with the site's own, but a switched page doesn't stay in WebKit
    /// for them as it does for `signInHosts`.
    public var cookieHosts: [String]
    /// The query item that starts the video at a time ("t" of &t=90s), nil when the site has none.
    public var timeParameter: String?

    public init(host: String, name: String? = nil, excludedHosts: [String] = [], videoParameters: [String] = [],
                pathNamesVideo: Bool = false, videoPaths: [String] = [], signInHosts: [String] = [], signInPaths: [String] = [],
                cookieHosts: [String] = [], timeParameter: String? = nil) {
        self.host = host
        self.name = name ?? host
        self.excludedHosts = excludedHosts
        self.videoParameters = videoParameters
        self.pathNamesVideo = pathNamesVideo
        self.videoPaths = videoPaths
        self.signInHosts = signInHosts
        self.signInPaths = signInPaths
        self.cookieHosts = cookieHosts
        self.timeParameter = timeParameter
    }

    func covers(_ h: String) -> Bool {
        (h == host || h.hasSuffix("." + host)) && !excludedHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    func playsVideo(path: String) -> Bool {
        videoPaths.isEmpty || videoPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    func signsIn(host h: String, path: String) -> Bool {
        if signInHosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return true }
        return covers(h) && signInPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
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

    /// Sites with protected videos among ordinary ones. YouTube: films bought or rented there play
    /// at 480p in a Chromium without Verified Media Path. YouTube Music is left out: its player
    /// isn't known to need it. Sign-in goes through Google and lands on accounts.youtube.com and
    /// /signin; consent.youtube.com is the cookie question.
    ///
    /// Fandango at Home (Vudu): a shop whose films ask for Widevine in a player frame of the play
    /// page (/content/browse/play/<id>/<kind>, which is the video; its returnUrl isn't). Its
    /// session is in cookies on ".fandango.com", which is also Fandango's ticket shop, so those
    /// are copied without the page staying in WebKit there. It has to arrive signed in: signed
    /// out, the play page in WebKit sends itself to /content/account/login and reloads, twice a
    /// second without end (19 Nov 2026, also in a plain WKWebView), where Chromium lands on the
    /// sign-in page. A signed-out Chromium page is sent to sign in before it plays, so it isn't
    /// asked about. Its routes for a video are play/<id>/<kind> and live/…; other pages ask for
    /// Widevine too (the front page, signed out, with nothing playing), hence `videoPaths`.
    public static let defaultMixedSites: [MixedMediaSite] = [
        MixedMediaSite(host: "youtube.com", name: "YouTube", excludedHosts: ["music.youtube.com"], videoParameters: ["v"],
                       signInHosts: ["google.com", "accounts.youtube.com", "consent.youtube.com"], signInPaths: ["/signin"],
                       timeParameter: "t"),
        MixedMediaSite(host: "athome.fandango.com", name: "Fandango at Home", pathNamesVideo: true,
                       videoPaths: ["/content/browse/play", "/content/browse/live"],
                       signInPaths: ["/content/account"], cookieHosts: ["fandango.com"]),
    ]

    /// Off: every page is Chromium's, as before.
    public var isEnabled: Bool
    /// Lower-cased hosts without a leading dot, some with a path ("amazon.com/gp/video").
    public private(set) var hosts: [String]
    /// The sites whose protected videos move one page at a time.
    public private(set) var mixedSites: [MixedMediaSite]

    /// `extraHosts` add to the list (tests, a user's own entries); `removedHosts` take sites
    /// off it. `mixedHosts` add plain mixed sites (tests: the scenarios' 127.0.0.1).
    public init(isEnabled: Bool = true, extraHosts: [String] = [], removedHosts: [String] = [], mixedHosts: [String] = []) {
        self.isEnabled = isEnabled
        var mixed = Self.defaultMixedSites
        for host in mixedHosts.compactMap(Self.normalizedHost) where !mixed.contains(where: { $0.host == host }) {
            mixed.append(MixedMediaSite(host: host))
        }
        mixedSites = mixed
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

    /// The mixed site a page at `url` is on: nil while off, on a left-out host, and for a site
    /// that plays in WebKit as a whole (listed, or added with the Safari's Engine switch).
    public func mixedSite(for url: String) -> MixedMediaSite? {
        guard isEnabled, let host = Self.webHost(of: url), listedHost(for: url) == nil else { return nil }
        return mixedSites.first { $0.covers(host) }
    }

    /// Whether the page at `url` is one its mixed site plays videos on (`videoPaths`): the only
    /// pages whose request for Widevine is acted on. False off a mixed site.
    public func playsVideo(at url: String) -> Bool {
        guard let site = mixedSite(for: url) else { return false }
        return site.playsVideo(path: URLComponents(string: url.trimmingCharacters(in: .whitespaces))?.path ?? "")
    }

    /// What makes a page of a mixed site that page and no other: the site, the path and the query
    /// items that name the video ("youtube.com/watch?v=abc"; a time, a playlist or a fragment don't
    /// make it another page). nil off a mixed site.
    public func pageKey(for url: String) -> String? {
        guard let site = mixedSite(for: url), let c = URLComponents(string: url.trimmingCharacters(in: .whitespaces)) else { return nil }
        var path = c.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let items = (site.pathNamesVideo ? [] : c.queryItems ?? [])
            .filter { site.videoParameters.isEmpty || site.videoParameters.contains($0.name) }
            .map { "\($0.name)=\($0.value ?? "")" }.sorted()
        return site.host + path + (items.isEmpty ? "" : "?" + items.joined(separator: "&"))
    }

    /// Whether a page switched to WebKit for one video is still that page at `url`: the same
    /// video, or the site signing in (Google's pages and where they land), which has to come back
    /// to the same cookies. Anything else, another video included, goes back to Chromium.
    public func holds(_ page: SwitchedPage, at url: String) -> Bool {
        guard isEnabled, let host = Self.webHost(of: url), let site = mixedSites.first(where: { $0.host == page.site }) else { return false }
        let path = URLComponents(string: url.trimmingCharacters(in: .whitespaces))?.path ?? ""
        return site.signsIn(host: host, path: path) || pageKey(for: url) == page.key
    }

    /// The engine a page Cra opens at `url` gets in a tab whose page was switched for one video.
    public func engine(for url: String, switched: SwitchedPage?) -> PageEngine {
        if let switched, holds(switched, at: url) { return .webKit }
        return engine(for: url)
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
/// site (the Site Control Center's Safari's Engine switch, `ProtectedMediaSites.choosing`), the
/// mixed sites whose protected videos switch without asking, and the services whose "plays with
/// Safari's engine" toast was closed. In the data folder, not the defaults, so each profile
/// folder and test instance (CRA_DATA_DIR) keeps its own.
public struct ProtectedMediaChoices: Codable, Equatable, Sendable {
    /// Sites the user sent to WebKit.
    public var added: [String]
    /// Listed entries the user took back to Chromium.
    public var removed: [String]
    /// Services whose toast was closed with its ✕.
    public var told: [String]
    /// Mixed sites (`MixedMediaSite.host`) whose protected videos move to WebKit without asking:
    /// the prompt's Always. Not `added`, which is the whole site.
    public var protectedVideos: [String]

    public init(added: [String] = [], removed: [String] = [], told: [String] = [], protectedVideos: [String] = []) {
        self.added = added
        self.removed = removed
        self.told = told
        self.protectedVideos = protectedVideos
    }

    private enum CodingKeys: String, CodingKey { case added, removed, told, protectedVideos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try c.decodeIfPresent([String].self, forKey: .added) ?? []
        removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? []
        told = try c.decodeIfPresent([String].self, forKey: .told) ?? []
        protectedVideos = try c.decodeIfPresent([String].self, forKey: .protectedVideos) ?? []
    }

    /// `protectedVideos` is written only once it has an entry, so a file without one stays as it was.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(added, forKey: .added)
        try c.encode(removed, forKey: .removed)
        try c.encode(told, forKey: .told)
        if !protectedVideos.isEmpty { try c.encode(protectedVideos, forKey: .protectedVideos) }
    }

    /// After choosing `engine` for `url`'s site.
    public func choosing(_ engine: PageEngine, for url: String) -> ProtectedMediaChoices {
        let r = ProtectedMediaSites.choosing(engine, for: url, added: added, removed: removed)
        return ProtectedMediaChoices(added: r.added, removed: r.removed, told: told, protectedVideos: protectedVideos)
    }

    /// After the user closed `service`'s toast.
    public func telling(_ service: String) -> ProtectedMediaChoices {
        var next = self
        if !told.contains(service) { next.told.append(service) }
        return next
    }

    /// After the prompt's Always for a mixed site (`on`), or the Site Control Center taking it back.
    public func switchingProtectedVideos(_ on: Bool, on site: MixedMediaSite) -> ProtectedMediaChoices {
        var next = self
        next.protectedVideos.removeAll { $0 == site.host }
        if on { next.protectedVideos.append(site.host) }
        return next
    }

    public func switchesProtectedVideos(on site: MixedMediaSite) -> Bool { protectedVideos.contains(site.host) }
}
