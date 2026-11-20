import AppKit
import CraCEF

/// Which engine draws a page, and the factory every page browser comes from
/// (ProtectedMediaSites has the rules; docs/protected-media.md the why).
/// A page Cra draws itself (an Easel) instead of a website. It keeps its own address and hands
/// any other one to the engine that address gets.
@MainActor
protocol NativePage: AnyObject {
    func owns(_ url: String) -> Bool
}

/// What only a WebKit page tells its delegate (CraBrowserDelegate is the engine bridge's).
@MainActor
protocol WebKitPageDelegate: AnyObject {
    /// The system Picture in Picture window's back-to-tab button was pressed for this page's
    /// video: WebKit is about to put the video back in the page.
    func webKitPageReturnsFromPictureInPicture(_ browser: CraBrowser)
}

@MainActor
enum PageEngines {
    /// The app's pages of its own (EaselBrowser), registered at launch: a browser for an address
    /// one of them owns, else nil.
    static var nativePage: ((_ frame: NSRect, _ url: String, _ delegate: CraBrowserDelegate?, _ incognito: Bool, _ profilePath: String?) -> CraBrowser?)?
    /// Whether `nativePage` would make the page for this address (an easel's), without making it.
    static var isNativePage: ((_ url: String) -> Bool)?

    /// The list, with the user's own choices (protected-media.json) on it. `defaults write
    /// dk.kildahl.cra webKitProtectedMedia -bool NO` turns it all off (every page Chromium's again).
    /// A test instance sets CRA_WEBKIT_DRM=0|1 and CRA_WEBKIT_HOSTS=<host,host> (the scenarios' localhost).
    private(set) static var sites: ProtectedMediaSites = load()

    /// The Safari's Engine choices and the closed toasts, in the data folder (CRA_DATA_DIR for a test).
    private static let file = JSONStore<ProtectedMediaChoices>("protected-media.json")
    private(set) static var choices: ProtectedMediaChoices = file.load(or: { ProtectedMediaChoices() })

    private static func load() -> ProtectedMediaSites {
        let env = ProcessInfo.processInfo.environment
        let enabled = env["CRA_WEBKIT_DRM"].map { $0 != "0" } ?? (UserDefaults.standard.object(forKey: "webKitProtectedMedia") as? Bool ?? true)
        let extra = (env["CRA_WEBKIT_HOSTS"] ?? "").split(separator: ",").map(String.init) + choices.added
        // CRA_MIXED_HOSTS=<host,host>: a test's own sites with protected videos among ordinary ones.
        let mixed = (env["CRA_MIXED_HOSTS"] ?? "").split(separator: ",").map(String.init)
        return ProtectedMediaSites(isEnabled: enabled, extraHosts: extra, removedHosts: choices.removed, mixedHosts: mixed)
    }

    /// The pages of mixed sites (YouTube) that asked for Widevine, moved to WebKit for one video
    /// or were left in Chromium, by tab (ProtectedVideoPages). BrowserManager moves the pages.
    static var videoPages = ProtectedVideoPages()

    /// The prompt's Always for a mixed site, or the Site Control Center taking it back: kept in
    /// protected-media.json as `protectedVideos`.
    static func switchProtectedVideos(_ on: Bool, on site: MixedMediaSite) {
        choices = choices.switchingProtectedVideos(on, on: site)
        file.saveNow(choices)
    }

    /// The engine a page Cra opens at `url` in `tab` gets: WebKit for a listed site, and for the
    /// one video the tab's page was switched for.
    static func engine(for url: String, tab: UUID?) -> PageEngine {
        sites.engine(for: url, switched: tab.flatMap { videoPages.switched[$0] })
    }

    /// The user's choice for `url`'s site (the Site Control Center's switch), kept and in force at once.
    static func choose(_ engine: PageEngine, for url: String) {
        choices = choices.choosing(engine, for: url)
        file.saveNow(choices)
        sites = load()
    }

    /// Whether `service`'s "plays with Safari's engine" toast was closed with its ✕.
    static func wasTold(_ service: String) -> Bool { choices.told.contains(service) }

    static func told(_ service: String) {
        guard !wasTold(service) else { return }
        choices = choices.telling(service)
        file.saveNow(choices)
    }

    static func engine(of browser: CraBrowser) -> PageEngine { browser is WebKitBrowser ? .webKit : .chromium }

    /// The service a WebKit page plays ("Spotify"), nil for a Chromium page: Cra tells the user why
    /// its extensions don't run there and it signs in on its own.
    static func protectedMediaService(of browser: CraBrowser) -> String? {
        guard let page = browser as? WebKitBrowser else { return nil }
        return page.serviceName.isEmpty ? "This site" : page.serviceName
    }

    /// What the Site Control Center's card and the dimmed extension buttons call a page that moved
    /// to WebKit for one protected video of a mixed site (the rest of YouTube is Chromium's).
    static let switchedVideoName = "This video"

    /// The page is in WebKit's own fullscreen window, which covers Cra's (Chromium's fullscreen
    /// is Cra's window going fullscreen).
    static func isInOwnFullscreen(_ browser: CraBrowser) -> Bool { (browser as? WebKitBrowser)?.isContentFullscreen == true }

    /// A page browser for `url` in the engine the rules pick. A popup host (`url` nil) takes its
    /// opener's engine: WebKit can only hand a popup to a web view it made, CEF to a CraBrowser.
    /// `history`: the tab's saved back and forward list (PageHistory, #273); the page opens with
    /// it when it ends at `url` and that engine wrote it.
    /// `tab`: the tab the page is for, whose page may have been switched to WebKit for one video
    /// (`videoPages`); such a page seeks to where the video was once, when its address has no time.
    static func makeBrowser(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool,
                            profilePath: String?, opener: CraBrowser? = nil, history: PageHistory? = nil, tab: UUID? = nil) -> CraBrowser {
        // An easel's address (Arc's Easels): its canvas, not a page.
        if let url, let page = nativePage?(frame, url, delegate, incognito, profilePath) { return page }
        let engine = url.map { self.engine(for: $0, tab: tab) } ?? opener.map(engine(of:)) ?? .chromium
        let restored = url.flatMap { u in history.flatMap { !incognito && $0.restores(into: engine, at: u) ? $0 : nil } }
        switch engine {
        case .webKit:
            let switched = url.flatMap { u in tab.flatMap { videoPages.switched[$0] }.flatMap { sites.holds($0, at: u) ? $0 : nil } }
            let resume = url.flatMap { u in switched?.resumeAt.map { (url: u, seconds: $0) } }
            let page = WebKitBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath,
                                     interactionState: restored?.state, resume: resume)
            if let tab, resume != nil { videoPages.resumed(tab: tab) }
            // A page switched for one video is that video's, not its site's: "This video plays with Safari's engine".
            page.serviceName = url.flatMap { sites.serviceName(for: $0) } ?? (switched != nil ? switchedVideoName : nil)
                ?? (opener as? WebKitBrowser)?.serviceName ?? ""
            return page
        case .chromium:
            guard let url, let restored else {
                return CraBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
            }
            return CraBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath,
                              history: ["history": restored.state.base64EncodedString(), "index": restored.index])
        }
    }

    /// Whether a tab at `url` can take a spare page (SparePage), and the saved history it then gets,
    /// as makeBrowser would hand it in.
    static func spareFill(url: String, incognito: Bool, history: PageHistory?, tab: UUID? = nil) -> (canTake: Bool, history: [String: Any]?) {
        let engine = engine(for: url, tab: tab)
        guard SparePage.canTake(engine: engine, isEasel: isNativePage?(url) ?? false, incognito: incognito) else { return (false, nil) }
        let restored = history.flatMap { $0.restores(into: engine, at: url) ? $0 : nil }
        return (true, restored.map { ["history": $0.state.base64EncodedString(), "index": $0.index] })
    }

    /// Whether `browser` is one of the engines' pages (not an easel): only those have a history to save.
    static func savesHistory(_ browser: CraBrowser) -> Bool { !(browser is NativePage) }

    /// Whether a navigation `browser` is about to make has to happen in the other engine.
    /// Chromium asks for every main-frame request (CraCEF's OnBeforeBrowse); WebKit only for
    /// addresses Cra loads (-loadURL:), never for the page's own navigations.
    /// `tab`: the page's tab; a page switched to WebKit for one video stays for that video's address.
    static func handoffTarget(from browser: CraBrowser, to url: String, method: String, tab: UUID? = nil) -> PageEngine? {
        // An easel hands every other address to the engine that address gets.
        if let page = browser as? NativePage { return page.owns(url) ? nil : sites.engine(for: url) }
        let current = engine(of: browser)
        switch current {
        case .chromium: return sites.handoff(from: current, to: url, method: method)
        case .webKit:
            let wanted = engine(for: url, tab: tab)
            return wanted == current ? nil : wanted
        }
    }
}

extension ExtensionStore {
    /// The tooltip of an extension button dimmed on a WebKit page ("Extensions don’t run on Spotify").
    nonisolated static func offOnProtectedMedia(_ service: String) -> String {
        "Extensions don’t run on \(service == "This site" || service == PageEngines.switchedVideoName ? service.lowercased() : service)"
    }
}
