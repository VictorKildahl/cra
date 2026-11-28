import Foundation

/// The command bar's Open Passwords (#905): Chromium's password manager for the space's profile, searched for the
/// site the window shows, so its logins are the first thing there. Settings ▸ Profiles ▸ Passwords opens the whole list.
public enum PasswordManagerPage {
    public static let list = "chrome://password-manager/passwords"

    /// The list, searched (its `q`) for `page`'s host without "www.". The whole list for no web page, and for an
    /// incognito window's page, whose site would otherwise show in the normal window the list opens in.
    public static func address(forPage page: String?, incognito: Bool) -> String {
        guard !incognito, let page, let url = URL(string: page), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = url.host?.lowercased(), !host.isEmpty else { return list }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var parts = URLComponents(string: list)
        parts?.queryItems = [URLQueryItem(name: "q", value: host)]
        return parts?.string ?? list
    }
}
