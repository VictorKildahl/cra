import Foundation

/// Chrome's own pages that never load in incognito (Chromium's `IsURLAllowedInIncognito`,
/// chrome/browser/ui/incognito_allowed_url.cc in 158): Settings, History, Extensions, the
/// password manager, Help, Apps and sign-in work on the normal profile, so Chrome opens them in a
/// normal window. Cra built the incognito page for them instead and quit (GitHub #412).
public enum IncognitoPages {
    static let blockedHosts: Set<String> = [
        "apps", "settings", "help", "history", "extensions", "password-manager", "chrome-signin",
    ]

    /// Whether `url` may open in an incognito window. Every web page and most chrome:// pages may.
    /// `about:settings` is Chrome's alias of `chrome://settings`, and a `view-source:` page is
    /// allowed when its page is.
    public static func allows(_ url: String) -> Bool {
        var rest = Substring(url.trimmingCharacters(in: .whitespaces))
        while rest.lowercased().hasPrefix("view-source:") { rest = rest.dropFirst("view-source:".count) }
        let lower = rest.lowercased()
        let host: Substring
        if lower.hasPrefix("chrome://") {
            host = lower.dropFirst("chrome://".count)
        } else if lower.hasPrefix("about:") {
            host = lower.dropFirst("about:".count)
        } else {
            return true
        }
        let name = host.prefix { !"/?#:".contains($0) }
        return !blockedHosts.contains(String(name))
    }
}
