import Foundation

/// One page of a mixed site that moved to WebKit for the video it plays (`MixedMediaSite`). The
/// choice is the page's, not the site's: the tab's next video, or anything that isn't a video,
/// is Chromium's again (`ProtectedMediaSites.holds`).
public struct SwitchedPage: Equatable, Sendable {
    public enum How: String, Equatable, Sendable {
        /// The prompt's Once.
        case once
        /// The site's protected videos switch without asking (the prompt's Always).
        case always
    }

    /// `MixedMediaSite.host`.
    public var site: String
    /// `ProtectedMediaSites.pageKey`.
    public var key: String
    public var how: How
    /// Where the video was in Chromium, in seconds, for a site with no time in its address: the
    /// WebKit page seeks there once (`ProtectedVideoHandoff.seekScript`).
    public var resumeAt: Double?

    public init(site: String, key: String, how: How, resumeAt: Double? = nil) {
        self.site = site
        self.key = key
        self.how = how
        self.resumeAt = resumeAt
    }
}

/// What the prompt says and offers when a Chromium page of a mixed site asks for Widevine.
public struct ProtectedVideoPrompt: Equatable, Sendable {
    public enum Choice: String, Equatable, Sendable {
        case once = "Once"
        case always = "Always"
    }

    /// It names the cost with the gain: the page's extensions stop.
    public static let text = "Protected video: better quality with Safari's engine, no extensions"

    public var site: MixedMediaSite
    /// An incognito page offers Once only: Always would write the site to disk.
    public var choices: [Choice]

    public init(site: MixedMediaSite, incognito: Bool) {
        self.site = site
        choices = incognito ? [.once] : [.once, .always]
    }
}

/// The Site Control Center's Safari's Engine row: what is in force for the page, and with it what
/// a click does.
public enum SafariEngineRow: Equatable, Sendable {
    /// The whole site plays in WebKit. A click takes the site back to Chromium.
    case on
    /// A Chromium page that asked for Widevine, on a site that isn't mixed. A click moves the site.
    case off
    /// A mixed site whose protected videos switch without asking. A click stops that, and takes a
    /// switched page back to Chromium.
    case protectedVideos
    /// This page was switched Once. A click takes it back to Chromium.
    case thisVideo
    /// A Chromium page of a mixed site that asked for Widevine and stayed. A click switches the
    /// site's protected videos from now on, this one included.
    case videosOff

    public var state: String {
        switch self {
        case .on: "On"
        case .off, .videosOff: "Off"
        case .protectedVideos: "Protected Videos"
        case .thisVideo: "This Video"
        }
    }

    public var isOn: Bool { self != .off && self != .videosOff }
}

/// Which pages of mixed sites asked for Widevine, were switched to WebKit or were left in
/// Chromium, by tab. Kept for the session only: a switched page that is restored after a
/// relaunch opens in Chromium and asks again (or switches, with Always).
public struct ProtectedVideoPages: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Not a mixed site's page, or one the user left in Chromium.
        case nothing
        /// Show the prompt.
        case asks
        /// Always was chosen for the site: the page moves now.
        case switches
    }

    public private(set) var switched: [UUID: SwitchedPage] = [:]
    /// The page each tab's Chromium last saw ask for Widevine (its key).
    private var asked: [UUID: String] = [:]
    /// The asked page that still waits for an answer.
    private var waiting: [UUID: String] = [:]
    /// Pages the prompt's ✕ (or the row) left in Chromium: they aren't asked about again.
    private var declined: [UUID: Set<String>] = [:]

    public init() {}

    /// A Chromium page of `tab` at `url` asked for Widevine. Nothing happens on a page where its
    /// site plays no video (`MixedMediaSite.videoPaths`), with Always too.
    public mutating func widevineRequested(tab: UUID, url: String, sites: ProtectedMediaSites, choices: ProtectedMediaChoices) -> Step {
        guard let site = sites.mixedSite(for: url), sites.playsVideo(at: url), let key = sites.pageKey(for: url) else { return .nothing }
        asked[tab] = key
        if choices.switchesProtectedVideos(on: site) {
            waiting[tab] = nil
            return .switches
        }
        if declined[tab]?.contains(key) == true { return .nothing }
        waiting[tab] = key
        return .asks
    }

    /// The prompt `tab` should show while its Chromium page is at `url`, nil when none is due.
    public func prompt(tab: UUID, url: String, incognito: Bool, sites: ProtectedMediaSites) -> ProtectedVideoPrompt? {
        guard let key = waiting[tab], key == sites.pageKey(for: url), let site = sites.mixedSite(for: url) else { return nil }
        return ProtectedVideoPrompt(site: site, incognito: incognito)
    }

    /// Whether `tab`'s Chromium page at `url` asked for Widevine.
    public func asked(tab: UUID, url: String, sites: ProtectedMediaSites) -> Bool {
        asked[tab] != nil && asked[tab] == sites.pageKey(for: url)
    }

    /// `tab`'s Chromium page moved on to `url`: what it asked at another page no longer counts.
    public mutating func navigated(tab: UUID, to url: String, sites: ProtectedMediaSites) {
        let key = sites.pageKey(for: url)
        if asked[tab] != key { asked[tab] = nil }
        if waiting[tab] != key { waiting[tab] = nil }
    }

    /// Once or Always (or the row): the page at `url` is WebKit's from here. nil off a mixed site.
    @discardableResult
    public mutating func switching(tab: UUID, url: String, how: SwitchedPage.How, resumeAt: Double? = nil, sites: ProtectedMediaSites) -> SwitchedPage? {
        guard let site = sites.mixedSite(for: url), let key = sites.pageKey(for: url) else { return nil }
        let page = SwitchedPage(site: site.host, key: key, how: how, resumeAt: resumeAt)
        switched[tab] = page
        waiting[tab] = nil
        declined[tab]?.remove(key)
        return page
    }

    /// The WebKit page was made and told where to seek: a page made later (the tab waking from
    /// sleep) doesn't seek there again.
    public mutating func resumed(tab: UUID) { switched[tab]?.resumeAt = nil }

    /// The prompt's ✕: the page at `url` stays in Chromium and isn't asked about again.
    public mutating func declining(tab: UUID, url: String, sites: ProtectedMediaSites) {
        guard let key = sites.pageKey(for: url) else { return }
        declined[tab, default: []].insert(key)
        waiting[tab] = nil
    }

    /// A switched page's address changed to `url` (YouTube changes videos without a navigation).
    /// True when it is no longer the page that was switched: the tab goes back to Chromium.
    public mutating func leaves(tab: UUID, to url: String, sites: ProtectedMediaSites) -> Bool {
        guard let page = switched[tab], !sites.holds(page, at: url) else { return false }
        switched[tab] = nil
        return true
    }

    /// The Site Control Center took the switched page back to Chromium: it isn't asked about again.
    public mutating func returning(tab: UUID) {
        guard let page = switched.removeValue(forKey: tab) else { return }
        declined[tab, default: []].insert(page.key)
        waiting[tab] = nil
    }

    /// What the row's click on Off does to the page: Always, as the prompt's; an incognito page
    /// moves Once, so its site isn't written to disk.
    public static func rowSwitch(incognito: Bool) -> SwitchedPage.How { incognito ? .once : .always }

    /// The tab closed.
    public mutating func forget(tab: UUID) {
        switched[tab] = nil
        asked[tab] = nil
        waiting[tab] = nil
        declined[tab] = nil
    }

    /// The Safari's Engine row for `tab`'s page, nil for no row. `askedForWidevine`: what a
    /// Chromium page off the mixed sites answers when asked (PageScript's `drm`).
    public func row(tab: UUID, url: String, engine: PageEngine, askedForWidevine: Bool, sites: ProtectedMediaSites,
                    choices: ProtectedMediaChoices) -> SafariEngineRow? {
        switch engine {
        case .webKit:
            guard let page = switched[tab] else { return .on }
            return choices.protectedVideos.contains(page.site) ? .protectedVideos : .thisVideo
        case .chromium:
            guard let site = sites.mixedSite(for: url) else { return askedForWidevine ? .off : nil }
            if choices.switchesProtectedVideos(on: site) { return .protectedVideos }
            return asked(tab: tab, url: url, sites: sites) ? .videosOff : nil
        }
    }
}

/// How a page's request for Widevine reaches Cra (the scripts PageScript runs in every frame).
///
/// A wrapper in the page's world sees `navigator.requestMediaKeySystemAccess('com.widevine…')`
/// and tells Cra's isolated world of the same frame, through an event whose name (`channel`) is
/// random per launch. A request counts for the page, whichever frame made it: a player is often
/// a frame of its own (Fandango at Home's `player_frame.html`), so a frame's isolated world tells
/// the top frame's, which keeps the page's answer. A frame of the page's own origin raises the
/// same event on the top window; one of another origin can't touch that window, so it posts a
/// message instead, which the top frame stops at its own listener (a page that listened before
/// Cra's script was in, on a new tab's first page, can still see that one string).
///
/// A frame from another site runs in another process in Chromium, where Cra's scripts aren't
/// installed (they go in through the page's own protocol session): its request isn't seen.
/// WebKit runs them in every frame.
///
/// - `__cra.drm`: the page asked (the Site Control Center's Safari's Engine switch reads it).
/// - `__cra.drmNext()`: a promise that settles the next time the page asks, with the page's
///   address then, or with "" when a later call takes its place. Cra leaves one waiting in a
///   mixed site's page (`nextRequest`), so the page tells Cra and nothing polls.
///
/// Once a page has asked, each `encrypted` media event counts as asking again: a player that
/// changes videos without a navigation may keep the key system it got and not ask twice.
public enum WidevineSignal {
    /// The page's world, in every frame: the wrapper.
    public static func pageWorld(channel: String) -> String {
        """
        (() => {
          const proto = window.Navigator?.prototype, request = proto?.requestMediaKeySystemAccess;
          if (!request) return;
          Object.defineProperty(proto, 'requestMediaKeySystemAccess', { configurable: true, writable: true,
            value: { requestMediaKeySystemAccess(keySystem, configs) {
              if (String(keySystem).startsWith('com.widevine')) dispatchEvent(new CustomEvent('\(channel)d'));
              return request.call(this, keySystem, configs);
            } }.requestMediaKeySystemAccess });
        })();
        """
    }

    /// Cra's isolated world, in every frame: statements for the script that made `cra`
    /// (`window.__cra`).
    public static func isolatedWorld(channel: String) -> String {
        """
        cra.drmN = 0;
        cra.drmSeen = 0;
        const drmTop = window.top === window;
        const drmAsked = () => { cra.drm = true; cra.drmN++; cra.drmTell?.(); };
        const drmTold = () => {
          drmAsked();
          if (drmTop) return;
          try { window.top.dispatchEvent(new CustomEvent('\(channel)d')); } catch {
            try { window.top.postMessage('\(channel)f', '*'); } catch {}
          }
        };
        addEventListener('\(channel)d', drmTold);
        addEventListener('encrypted', () => { if (cra.drm) drmTold(); }, true);
        if (drmTop) addEventListener('message', e => {
          if (e.data !== '\(channel)f') return;
          e.stopImmediatePropagation();
          drmAsked();
        }, true);
        cra.drmNext = () => new Promise(done => {
          cra.drmStop?.();
          cra.drmStop = () => done('');
          cra.drmTell = () => {
            if (cra.drmN <= cra.drmSeen) return;
            cra.drmSeen = cra.drmN;
            cra.drmTell = cra.drmStop = null;
            done(location.href);
          };
          cra.drmTell();
        });
        """
    }

    /// Asked in Cra's isolated world of the top frame, and left waiting (`drmNext`). A page that
    /// navigates away ends it with an error.
    public static let nextRequest = "window.__cra?.drmNext?.() ?? ''"
}

/// What goes with a page when it moves to WebKit for a protected video: the place in the video
/// and the sign-in.
public enum ProtectedVideoHandoff {
    /// Below this the video starts over: nothing to keep.
    public static let leastTime: Double = 5

    /// Asked of the page that moves: the seconds its video is at, -1 without one. The video that
    /// plays, else the one furthest in; a live stream has no place to keep.
    public static let playbackTimeScript = """
    (() => {
      const all = [...document.querySelectorAll('video')].filter(v => v.currentTime > 0 && isFinite(v.duration));
      const v = all.find(v => !v.paused && !v.ended) || all.sort((a, b) => b.currentTime - a.currentTime)[0];
      return v ? v.currentTime : -1;
    })()
    """

    /// The address the page opens at in the other engine, and the time its video still has to be
    /// taken to there. A site with a time in its address (YouTube's `t`) gets it in the address;
    /// any other keeps its address and seeks (`seekScript`).
    public static func address(for url: String, at seconds: Double?, sites: ProtectedMediaSites) -> (url: String, seek: Double?) {
        guard let seconds, seconds.isFinite, seconds >= leastTime, let site = sites.mixedSite(for: url) else { return (url, nil) }
        guard let parameter = site.timeParameter else { return (url, seconds) }
        guard var c = URLComponents(string: url.trimmingCharacters(in: .whitespaces)) else { return (url, nil) }
        var items = (c.queryItems ?? []).filter { $0.name != parameter }
        items.append(URLQueryItem(name: parameter, value: "\(Int(seconds))s"))
        c.queryItems = items
        return (c.string ?? url, nil)
    }

    /// Runs at the start of the WebKit page's documents: the first video of the page at `url`
    /// that knows its length goes to `seconds`. Once, and only until `until` (ms since 1970), so
    /// a reload long after starts where the site puts it.
    public static func seekScript(url: String, seconds: Double, until: Double) -> String {
        let address = (try? JSONEncoder().encode(url)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (() => {
          if (window.top !== window || location.href !== \(address) || Date.now() > \(until)) return;
          let done = false;
          const seek = e => {
            const v = e.target;
            if (done || !(v instanceof HTMLVideoElement) || !(v.duration > \(seconds))) return;
            done = true;
            try { v.currentTime = \(seconds); } catch {}
          };
          addEventListener('loadedmetadata', seek, true);
          addEventListener('durationchange', seek, true);
        })();
        """
    }

    /// The cookie domains that go with a page of `site`: its own (YouTube's accounts. and consent.
    /// included) and any other that holds its session (`cookieHosts`). Not where it signs in
    /// (`signInHosts`, google.com): Victor, 20 Nov 2026, so one film doesn't put a whole Google
    /// account's sign-in in WebKit's store.
    public static func cookieDomains(for site: MixedMediaSite) -> [String] {
        var seen = Set<String>()
        return ([site.host] + site.cookieHosts).filter { seen.insert($0).inserted }
    }

    /// The cookies to copy from Chromium's answer to Network.getAllCookies (`json`): those of
    /// `cookieDomains`, subdomains included, that are still good at `now`. A
    /// partitioned cookie belongs to an embed on another site and stays. Nothing else in the
    /// profile is touched, and an answer that can't be read copies nothing.
    public static func cookies(fromProtocolAnswer json: String, for site: MixedMediaSite, now: Date = Date()) -> [HTTPCookie] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let list = root["cookies"] as? [[String: Any]] else { return [] }
        let domains = cookieDomains(for: site)
        return list.compactMap { c in
            guard let name = c["name"] as? String, !name.isEmpty, let value = c["value"] as? String,
                  let domain = (c["domain"] as? String)?.lowercased(), c["partitionKey"] == nil else { return nil }
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            guard domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
                  !site.excludedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
            var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: c["path"] as? String ?? "/"]
            if c["session"] as? Bool != true, let expires = c["expires"] as? Double, expires > 0 {
                let date = Date(timeIntervalSince1970: expires)
                guard date > now else { return nil }
                p[.expires] = date
            } else {
                p[.discard] = "TRUE"
            }
            if c["secure"] as? Bool == true { p[.secure] = "TRUE" }
            if c["httpOnly"] as? Bool == true { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            switch (c["sameSite"] as? String)?.lowercased() {
            case "strict": p[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
            case "lax": p[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
            default: break
            }
            return HTTPCookie(properties: p)
        }
    }
}
