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
        return ProtectedMediaSites(isEnabled: enabled, extraHosts: extra, removedHosts: choices.removed)
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

    /// The page is in WebKit's own fullscreen window, which covers Cra's (Chromium's fullscreen
    /// is Cra's window going fullscreen).
    static func isInOwnFullscreen(_ browser: CraBrowser) -> Bool { (browser as? WebKitBrowser)?.isContentFullscreen == true }

    /// A page browser for `url` in the engine the rules pick. A popup host (`url` nil) takes its
    /// opener's engine: WebKit can only hand a popup to a web view it made, CEF to a CraBrowser.
    /// `history`: the tab's saved back and forward list (PageHistory, #273); the page opens with
    /// it when it ends at `url` and that engine wrote it.
    static func makeBrowser(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool,
                            profilePath: String?, opener: CraBrowser? = nil, history: PageHistory? = nil) -> CraBrowser {
        // An easel's address (Arc's Easels): its canvas, not a page.
        if let url, let page = nativePage?(frame, url, delegate, incognito, profilePath) { return page }
        let engine = url.map { sites.engine(for: $0) } ?? opener.map(engine(of:)) ?? .chromium
        let restored = url.flatMap { u in history.flatMap { !incognito && $0.restores(into: engine, at: u) ? $0 : nil } }
        switch engine {
        case .webKit:
            let page = WebKitBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath,
                                     interactionState: restored?.state)
            page.serviceName = url.flatMap { sites.serviceName(for: $0) } ?? (opener as? WebKitBrowser)?.serviceName ?? ""
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
    static func spareFill(url: String, incognito: Bool, history: PageHistory?) -> (canTake: Bool, history: [String: Any]?) {
        let engine = sites.engine(for: url)
        guard SparePage.canTake(engine: engine, isEasel: isNativePage?(url) ?? false, incognito: incognito) else { return (false, nil) }
        let restored = history.flatMap { $0.restores(into: engine, at: url) ? $0 : nil }
        return (true, restored.map { ["history": $0.state.base64EncodedString(), "index": $0.index] })
    }

    /// Whether `browser` is one of the engines' pages (not an easel): only those have a history to save.
    static func savesHistory(_ browser: CraBrowser) -> Bool { !(browser is NativePage) }

    /// Whether a navigation `browser` is about to make has to happen in the other engine.
    /// Chromium asks for every main-frame request (CraCEF's OnBeforeBrowse); WebKit only for
    /// addresses Cra loads (-loadURL:), never for the page's own navigations.
    static func handoffTarget(from browser: CraBrowser, to url: String, method: String) -> PageEngine? {
        // An easel hands every other address to the engine that address gets.
        if let page = browser as? NativePage { return page.owns(url) ? nil : sites.engine(for: url) }
        let current = engine(of: browser)
        switch current {
        case .chromium: return sites.handoff(from: current, to: url, method: method)
        case .webKit:
            let wanted = sites.engine(for: url)
            return wanted == current ? nil : wanted
        }
    }
}

extension ExtensionStore {
    /// The tooltip of an extension button dimmed on a WebKit page ("Extensions don’t run on Spotify").
    nonisolated static func offOnProtectedMedia(_ service: String) -> String {
        "Extensions don’t run on \(service == "This site" ? "this site" : service)"
    }
}
