import Foundation

/// Addresses the iPhone app's web view can't load itself: mailto:, tel:, sms:, maps:, the App
/// Store's itms-apps:, and every custom scheme an installed app registers. They go to the app that
/// handles them (`UIApplication.open`), decided before WebKit tries them, as Safari does. Left to
/// WebKit they failed with -1002 "unsupported URL", which #568's error page then showed in place
/// of the page (TestFlight 1086); before that page, the tap did nothing.
public enum MobileExternalLinks {
    public enum Answer: Equatable {
        /// The web view loads it.
        case load
        /// Straight to the app that handles it. With no app for it, nothing happens and the page
        /// stays (Safari shows an error page there; the page staying is what the app did before).
        case open
        /// Ask first, with Safari's question (`question(app:)`): a page sent itself there without a tap.
        case ask(app: String?)
        /// Not loaded and not handed on: the page stays as it is.
        case stay
    }

    /// What WebKit loads itself. The app's own cra-edit: and cra-browse: (a Browse for Me page's
    /// chips) are answered by the page before this; it registers no other scheme handler.
    public static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]

    /// The app's own addresses: `cra://` is what its widgets open, and a page never drives the app
    /// through it (Cra for Mac's rule for cra://, pages never).
    public static let ownSchemes: Set<String> = ["cra", "cra-edit", "cra-browse"]

    /// iOS asks before a call itself when one of these is opened, so the app adds no question.
    public static let systemAsks: Set<String> = ["tel", "telprompt", "facetime", "facetime-audio"]

    /// Apps that own a scheme on every iPhone, for the question. mailto: is left out: it goes to
    /// whichever mail app the user picked.
    public static let appNames: [String: String] = [
        "sms": "Messages", "maps": "Maps", "itms-apps": "App Store", "itms-appss": "App Store",
    ]

    public static let openButton = "Open"
    public static let cancelButton = "Cancel"

    /// The address's scheme, lowercased (RFC 3986: a letter, then letters, digits, "+", "-", ".").
    public static func scheme(of address: String) -> String? {
        guard let colon = address.firstIndex(of: ":") else { return nil }
        let scheme = address[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return nil }
        return scheme.lowercased()
    }

    /// The address has a scheme the web view can't load.
    public static func goesOut(_ address: String) -> Bool {
        guard let scheme = scheme(of: address) else { return false }
        return !webSchemes.contains(scheme)
    }

    /// What a navigation to `address` does. `isUserGesture`: the user tapped a link (or sent a
    /// form) for it, rather than a script or a redirect sending the page there.
    public static func answer(address: String, isMainFrame: Bool, isUserGesture: Bool) -> Answer {
        guard let scheme = scheme(of: address), !webSchemes.contains(scheme) else { return .load }
        if ownSchemes.contains(scheme) { return .stay }
        // A frame that goes there on its own (an ad's iframe): nothing, as in Safari.
        if !isMainFrame && !isUserGesture { return .stay }
        if isUserGesture || systemAsks.contains(scheme) { return .open }
        return .ask(app: appNames[scheme])
    }

    /// Safari's question for a page that sends itself to another app without a tap.
    public static func question(app: String?) -> String {
        app.map { "Open this page in “\($0)”?" } ?? "Open this page in another app?"
    }
}
