import Foundation

/// Links the app opens to crabrowser.app, tagged with the button that opened them.
///
/// A tab Cra opens by itself sends no referrer, so the site's analytics (Phantom) counted
/// these visits as "Direct / None", the same as a typed address. `utm_source=cra-app` plus a
/// campaign that names the button lets the site's stats tell the "Cra updated!" card's
/// What's new from Help → Release Notes. The tag names the button and nothing else: nothing
/// about the person or the Mac goes in it. The site removes it from the address bar once the
/// page view is counted (cra-website `CampaignTagCleanup`).
public enum SiteLinks {
    public static let source = "cra-app"

    /// The button a link was opened from: the `utm_campaign` value.
    public enum Origin: String, CaseIterable, Sendable {
        /// What's new on the "Cra updated!" card.
        case whatsNew = "whats-new"
        /// The Help menu's links.
        case helpMenu = "help-menu"
        /// "Learn more" on the site control center's protected-media card.
        case protectedMedia = "protected-media"
    }

    /// `url` with Cra's tag when it points at crabrowser.app; any other URL (GitHub, a typo)
    /// comes back unchanged. A tag already on the URL is replaced, other parameters and the
    /// fragment are kept.
    public static func tagged(_ url: String, from origin: Origin) -> String {
        guard var parts = URLComponents(string: url), parts.scheme == "https",
              let host = parts.host?.lowercased(), host == "crabrowser.app" || host == "www.crabrowser.app"
        else { return url }
        let kept = (parts.queryItems ?? []).filter { $0.name != "utm_source" && $0.name != "utm_campaign" }
        parts.queryItems = kept + [URLQueryItem(name: "utm_source", value: source), URLQueryItem(name: "utm_campaign", value: origin.rawValue)]
        return parts.string ?? url
    }
}
