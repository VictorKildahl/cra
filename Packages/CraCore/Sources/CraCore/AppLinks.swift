import Foundation

/// Addresses a page hands to another app instead of loading (spotify:, zoommtg:, itms-apps:):
/// Chrome's external protocols. In Arc a link, target=_blank link or window.open to one opens no
/// tab: "Open Spotify?" comes up over the page and macOS opens the app (GitHub #207).
public enum AppLinks {
    public enum Kind: Equatable, Sendable {
        /// The engine loads it (http, about:blank, a page's own web+ handler, Chromium's pages).
        case page
        /// Another app's: "Open <app>?" first (Chrome's external protocol dialog).
        case asksFirst
        /// Another app's, opened without asking: Chrome's allowed schemes (mailto:).
        case opens
        /// Never handed to macOS: Chrome's denied schemes (afp: mounts a share) and cra:, Cra's
        /// own scripting scheme, which would reach the installed Cra.
        case refused
    }

    /// Schemes the engines handle themselves, allowed or not: Chromium opens View Page Source
    /// as a view-source: tab, runs a javascript: popup's script and refuses a web page's file: one.
    static let pageSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "filesystem", "ws", "wss", "file", "javascript",
        "view-source", "chrome", "chrome-extension", "chrome-untrusted", "chrome-search", "devtools",
    ]
    /// The rest of Chrome's kDeniedSchemes (external_protocol_handler.cc), plus cra:.
    static let refusedSchemes: Set<String> = [
        "afp", "disk", "disks", "hcp", "ie.http", "login", "mk", "ms-help", "nntp", "res", "shell",
        "vbscript", "vnd.ms.radio", "cra",
    ]
    /// Chrome's kAllowedSchemes.
    static let openedSchemes: Set<String> = ["mailto", "news", "snews"]

    /// Chrome's flood guard for a page's own redirect to another app (Slack's "Launching…" page
    /// after a sign-in, Spotify's "open in the app" on a first visit): a click asks every time;
    /// without one, a page asks once, then gets nothing until a page loads again (another page,
    /// or this one reloaded: Chrome's Reload button lets it ask again). history.pushState is not
    /// a load, so a page can't buy itself more questions with it. One per tab, in both engines.
    public struct RedirectGuard: Sendable {
        /// This load has had its one question without a click.
        private var asked = false

        public init() {}

        /// A page committed in the main frame (a new page, or a reload): it may ask once again.
        public mutating func pageLoaded() { asked = false }

        /// Whether a request to open another app may ask "Open <app>?".
        public mutating func mayAsk(userGesture: Bool) -> Bool {
            if userGesture { return true }
            if asked { return false }
            asked = true
            return true
        }
    }

    /// Whether a request to `url` with no click of its own may still go, once per page load (RedirectGuard):
    /// another app's address, asked about, and mail, opened. Chrome's flood guard lets either through once
    /// without a gesture; Cra let only the first through, so a new window a page sent to mailto: opened
    /// nothing (#684).
    public static func mayGoWithoutClick(_ url: String) -> Bool {
        let k = kind(of: url)
        return k == .asksFirst || k == .opens
    }

    /// Whether the page that asked for another app's address is a new tab or window that never showed a page
    /// (window.open(), then sent to mailto:): it closes once the address is handed to macOS, as Chrome closes
    /// a tab whose first navigation went to an app (external_protocol_handler.cc). It stayed as an empty
    /// about:blank window (#684).
    public static func closesRequester(currentURL: String, canGoBack: Bool) -> Bool {
        guard !canGoBack else { return false }
        return currentURL.isEmpty || currentURL == "about:blank" || currentURL.hasPrefix("about:blank#")
            || currentURL.hasPrefix("about:blank?")
    }

    /// What `url` is for a link or window.open that wants a new tab, or a WebKit page's own
    /// navigation to a scheme WebKit doesn't load.
    public static func kind(of url: String) -> Kind {
        guard let colon = url.firstIndex(of: ":") else { return .page }
        let scheme = url[..<colon].lowercased()
        // RFC 3986: a letter, then letters, digits, + - . (anything else is not a scheme).
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return .page }
        // navigator.registerProtocolHandler's own schemes go to the page that registered them.
        if scheme.hasPrefix("web+") || pageSchemes.contains(scheme) { return .page }
        if refusedSchemes.contains(scheme) { return .refused }
        return openedSchemes.contains(scheme) ? .opens : .asksFirst
    }
}

// MARK: Typed addresses (#604)

extension AppLinks {
    /// What Return does with an address typed in the command bar (⌘T, ⌘L, a Little Window's bar).
    public enum Typed: Equatable, Sendable {
        /// A page: the engine loads it.
        case load
        /// Another app's address with an app that opens it: macOS opens it, no tab. Typed by the person,
        /// it is their click, so no "Open <app>?" first (#604: todoist:// opened nothing, as Arc did).
        case openApp
        /// Another app's address no app here opens: it is searched for, as Chrome treats a scheme
        /// nothing is registered for.
        case search
        /// A scheme never handed to macOS (afp:, cra:): nothing happens.
        case refuse
    }

    public static func typed(_ url: String, hasApp: Bool) -> Typed {
        switch kind(of: url) {
        case .page: return .load
        case .refused: return .refuse
        case .asksFirst, .opens: return hasApp ? .openApp : .search
        }
    }
}
