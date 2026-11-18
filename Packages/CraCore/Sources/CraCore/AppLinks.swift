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
    /// without one, a page asks once, then gets nothing until another page loads. One per tab.
    /// WebKit pages keep their own (`askedForAppOnThisPage`) and always arrive here as clicked.
    public struct RedirectGuard: Sendable {
        /// The page that has had its one question without a click.
        private var askedOn: String?

        public init() {}

        /// Whether a request from `page` (its address) may ask "Open <app>?".
        public mutating func mayAsk(userGesture: Bool, page: String) -> Bool {
            if userGesture { return true }
            if askedOn == page { return false }
            askedOn = page
            return true
        }
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
