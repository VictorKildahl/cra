import Foundation

/// The page Cra offers to the user's other devices through Handoff (GitHub #745): the front window's page, which
/// an iPhone's app switcher shows as a suggestion to open in its browser, as Safari, Chrome and Firefox offer theirs.
/// Only web addresses go (http, https with a host): an iPhone can't open chrome://, cra://, file: or data: pages.
/// An incognito window offers nothing, as Chrome's doesn't.
public enum HandoffPage {
    public static func url(for address: String, offTheRecord: Bool) -> URL? {
        guard !offTheRecord, let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
