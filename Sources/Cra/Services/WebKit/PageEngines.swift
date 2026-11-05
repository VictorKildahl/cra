import AppKit
import CraCEF

/// Which engine draws a page, and the factory every page browser comes from
/// (ProtectedMediaSites has the rules; docs/protected-media.md the why).
@MainActor
enum PageEngines {
    /// Read once per launch. `defaults write dk.kildahl.cra webKitProtectedMedia -bool NO` turns
    /// it off (every page Chromium's again); `webKitProtectedMediaHosts` and
    /// `webKitProtectedMediaRemovedHosts` (string arrays) change the list. A test instance sets
    /// CRA_WEBKIT_DRM=0|1 and CRA_WEBKIT_HOSTS=<host,host> (the scenarios' 127.0.0.1).
    static let sites: ProtectedMediaSites = {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let enabled = env["CRA_WEBKIT_DRM"].map { $0 != "0" } ?? (defaults.object(forKey: "webKitProtectedMedia") as? Bool ?? true)
        let extra = (env["CRA_WEBKIT_HOSTS"] ?? "").split(separator: ",").map(String.init)
            + (defaults.stringArray(forKey: "webKitProtectedMediaHosts") ?? [])
        let removed = defaults.stringArray(forKey: "webKitProtectedMediaRemovedHosts") ?? []
        return ProtectedMediaSites(isEnabled: enabled, extraHosts: extra, removedHosts: removed)
    }()

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
    static func makeBrowser(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool,
                            profilePath: String?, opener: CraBrowser? = nil) -> CraBrowser {
        let engine = url.map { sites.engine(for: $0) } ?? opener.map(engine(of:)) ?? .chromium
        switch engine {
        case .webKit:
            let page = WebKitBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
            page.serviceName = url.flatMap { sites.serviceName(for: $0) } ?? (opener as? WebKitBrowser)?.serviceName ?? ""
            return page
        case .chromium:
            return CraBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        }
    }

    /// Whether a navigation `browser` is about to make has to happen in the other engine.
    /// Chromium asks for every main-frame request (CraCEF's OnBeforeBrowse); WebKit only for
    /// addresses Cra loads (-loadURL:), never for the page's own navigations.
    static func handoffTarget(from browser: CraBrowser, to url: String, method: String) -> PageEngine? {
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
